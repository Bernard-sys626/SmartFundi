const router = require('express').Router();
const { q, q1 } = require('../db');
const { asyncH, fail, auth, role, getSetting, notify, money } = require('../util');

const SVC = { sw: 'name_sw', en: 'name_en', fr: 'name_fr' };

// A Fundi/Company matches a job when it is approved, offers the job's category, covers the area and has the right type.
// A job without a ward (the client typed a place that is not in the list) matches every Fundi of the district.
const MATCH_SQL = `u.role='fundi' and u.fundi_status='approved' and ($1::text='any' or u.fundi_type=$1::text)
  and exists(select 1 from fundi_categories fc where fc.user_id=u.id and fc.category_id=$4)
  and exists(select 1 from fundi_areas a where a.user_id=u.id and a.district_id=$2 and (a.ward_id is null or $3::int is null or a.ward_id=$3))`;

async function matchingFundiIds(j) {
  const rows = await q(`select u.id from users u where ${MATCH_SQL}`, [j.preference || 'any', j.district_id, j.ward_id || null, j.category_id]);
  return rows.map((r) => r.id);
}
async function fundiMatches(fundiId, j) {
  const r = await q1(`select 1 x from users u where u.id=$5 and ${MATCH_SQL}`, [j.preference || 'any', j.district_id, j.ward_id || null, j.category_id, fundiId]);
  return !!r;
}
async function adminIdsFor(regionId) {
  const rows = await q(
    `select u.id from users u where u.role='admin' and (u.is_main_admin or exists(select 1 from admin_regions ar where ar.user_id=u.id and ar.region_id=$1))`,
    [regionId || 0]);
  return rows.map((r) => r.id);
}

async function canView(j, u) {
  if (u.role === 'admin') return true;
  if (j.client_id === u.id || j.fundi_id === u.id) return true;
  if (u.role === 'fundi') {
    if (j.target_fundi_id && j.target_fundi_id !== u.id) return false;
    return fundiMatches(u.id, j);
  }
  return false;
}

const uniq = (a) => [...new Set(a.filter(Boolean))];

/// Builds the full view of several jobs with a fixed number of queries (not 8 per job).
async function jobViews(ids, viewer) {
  if (!ids.length) return [];
  const lang = viewer.language || 'sw';
  const nameCol = SVC[lang] || 'name_sw';
  const jobs = await q(
    `select j.*, c.name_sw cat_sw, c.name_en cat_en, c.name_fr cat_fr, r.name region_name, d.name district_name, w.name ward_name
     from jobs j left join categories c on c.id=j.category_id left join regions r on r.id=j.region_id
     left join districts d on d.id=j.district_id left join wards w on w.id=j.ward_id where j.id = any($1::uuid[])`, [ids]);
  const svcs = await q(
    `select js.job_id, s.id, s.name_sw, s.name_en, s.name_fr from job_services js join services s on s.id=js.service_id
     where js.job_id = any($1::uuid[]) order by s.sort, s.id`, [ids]);
  const quotes = await q('select job_id,amount,includes_transport,note,file_ids from quotations where job_id = any($1::uuid[])', [ids]);
  const pays = await q('select id,job_id,amount,method,status,created_at from payments where job_id = any($1::uuid[]) order by created_at', [ids]);
  const photos = await q('select job_id,file_id from job_photos where job_id = any($1::uuid[])', [ids]);
  const ratings = await q('select job_id,rating,comment from ratings where job_id = any($1::uuid[])', [ids]);
  const boqs = viewer.role === 'client' || viewer.role === 'admin' || viewer.role === 'fundi'
    ? await q('select id,job_id,owner_id,title,total,updated_at from boqs where job_id = any($1::uuid[]) order by updated_at desc', [ids]) : [];
  const fundiIds = uniq(jobs.flatMap((j) => [j.fundi_id, j.target_fundi_id]));
  const userIds = uniq([...fundiIds, ...jobs.map((j) => j.client_id)]);
  const users = userIds.length
    ? await q('select id,name,phone,fundi_type,company_name,photo_file_id,admin_rating,experience from users where id = any($1::uuid[])', [userIds]) : [];
  const rats = fundiIds.length
    ? await q(`select j.fundi_id id, round(avg(r.rating)::numeric,1) avg, count(*)::int n from ratings r join jobs j on j.id=r.job_id
               where j.fundi_id = any($1::uuid[]) group by j.fundi_id`, [fundiIds]) : [];
  const U = new Map(users.map((u) => [u.id, u]));
  const RT = new Map(rats.map((r) => [r.id, r]));
  const fundiOut = (id) => {
    const f = U.get(id);
    if (!f) return null;
    const rt = RT.get(id);
    const avg = f.admin_rating != null ? Number(f.admin_rating) : rt && rt.avg ? Number(rt.avg) : null;
    return { id: f.id, name: f.name, phone: f.phone, fundi_type: f.fundi_type, company_name: f.company_name, photo_file_id: f.photo_file_id, experience: f.experience, rating: { avg, count: rt ? rt.n : 0 } };
  };
  const by = (arr, key) => {
    const m = new Map();
    for (const x of arr) { if (!m.has(x[key])) m.set(x[key], []); m.get(x[key]).push(x); }
    return m;
  };
  const SV = by(svcs, 'job_id'), QT = new Map(quotes.map((x) => [x.job_id, x])), PY = by(pays, 'job_id'), PH = by(photos, 'job_id'),
    RA = new Map(ratings.map((x) => [x.job_id, x])), BQ = by(boqs, 'job_id');
  const out = new Map();
  for (const j of jobs) {
    const quotation = QT.get(j.id);
    const pl = PY.get(j.id) || [];
    const paid = pl.filter((p) => p.status === 'success').reduce((a, p) => a + Number(p.amount), 0);
    const pending = pl.filter((p) => p.status === 'pending').reduce((a, p) => a + Number(p.amount), 0);
    const total = quotation ? Number(quotation.amount) : 0;
    const sl = (SV.get(j.id) || []).map((s) => ({ id: s.id, name: s[nameCol] || s.name_en }));
    const names = [...sl.map((s) => s.name), ...(j.other_service ? [j.other_service] : [])];
    const rating = RA.get(j.id);
    const v = {
      id: j.id, code: j.code, status: j.status, preference: j.preference, description: j.description || '', notes: j.notes,
      service_id: j.service_id, service_name: names.join(', '), services: sl, other_service: j.other_service,
      category_id: j.category_id, category_name: j['cat_' + lang] || j.cat_en,
      region_name: j.region_name, district_name: j.district_name, ward_name: j.ward_name || j.ward_text, ward_text: j.ward_text,
      lat: j.lat, lng: j.lng, address: j.address, nauli_due: j.nauli_due, cancel_reason: j.cancel_reason, cancelled_by: j.cancelled_by,
      created_at: j.created_at, accepted_at: j.accepted_at, on_the_way_at: j.on_the_way_at, arrived_at: j.arrived_at,
      started_at: j.started_at, completed_at: j.completed_at, cancelled_at: j.cancelled_at, resent_at: j.resent_at,
      photos: (PH.get(j.id) || []).map((x) => x.file_id),
      rating: rating ? { rating: rating.rating, comment: rating.comment } : null,
      quotation: quotation ? { amount: total, includes_transport: quotation.includes_transport, note: quotation.note, file_ids: quotation.file_ids } : null,
      payments: pl.map((p) => ({ id: p.id, amount: p.amount, method: p.method, status: p.status, created_at: p.created_at })),
      paid, pending, balance: Math.max(total - paid, 0),
      payment_status: !quotation ? 'no_quotation' : paid >= total ? 'paid' : paid > 0 ? 'partial' : 'unpaid',
      can_contact: !!j.fundi_id && j.status !== 'cancelled',
      boqs: (BQ.get(j.id) || [])
        .filter((b) => viewer.role !== 'fundi' || b.owner_id === viewer.id)
        .map((b) => ({ id: b.id, title: b.title, total: Number(b.total), updated_at: b.updated_at })),
    };
    if (j.fundi_id) v.fundi = fundiOut(j.fundi_id);
    // A Fundi chosen by the client who has not accepted yet: the client sees all of that Fundi's details.
    if (!j.fundi_id && j.target_fundi_id) v.target_fundi = fundiOut(j.target_fundi_id);
    if (j.fundi_id || viewer.role === 'admin') {
      const c = U.get(j.client_id);
      if (c) v.client = { id: c.id, name: c.name, phone: c.phone };
    }
    out.set(j.id, v);
  }
  return ids.map((id) => out.get(id)).filter(Boolean);
}
async function jobView(id, viewer) {
  return (await jobViews([id], viewer))[0] || null;
}
/// What a Fundi who has not (or not yet) been given the job may see: no client, no exact location.
function stripForOthers(v) {
  delete v.client;
  v.address = null; v.lat = null; v.lng = null;
  delete v.boqs;
  return v;
}

async function confirmPayment(id) {
  const p = await q1('select * from payments where id=$1', [id]);
  if (!p || p.status === 'success') return p;
  const pct = Number(await getSetting('commission_percent', 20));
  const platform = Math.round(Number(p.amount) * pct) / 100;
  const fundiAmt = Number(p.amount) - platform;
  const r = await q1(
    `update payments set status='success', commission_percent=$2, platform_amount=$3, fundi_amount=$4, confirmed_at=now() where id=$1 returning *`,
    [id, pct, platform, fundiAmt]);
  const j = await q1('select id,code,fundi_id,client_id from jobs where id=$1', [r.job_id]);
  await notify(j.client_id, 'payment_ok', { amount: money(r.amount), code: j.code }, j.id);
  if (j.fundi_id) await notify(j.fundi_id, 'payment_fundi', { amount: money(r.amount), share: money(fundiAmt), code: j.code }, j.id);
  return r;
}

async function areaLabel(j) {
  const r = await q1(
    `select r.name rn, d.name dn, w.name wn from (select 1) x left join regions r on r.id=$1 left join districts d on d.id=$2 left join wards w on w.id=$3`,
    [j.region_id || 0, j.district_id || 0, j.ward_id || 0]);
  return [j.ward_text || (r && r.wn), r && r.dn, r && r.rn].filter(Boolean).join(', ');
}

/// Tells the Fundis who can take the job (or only the chosen Fundi), and the Admins.
async function announce(j, svcNames, { resend = false } = {}) {
  const client = await q1('select name,phone from users where id=$1', [j.client_id]);
  const who = (client && (client.name || client.phone)) || '';
  if (j.target_fundi_id) {
    await notify(j.target_fundi_id, resend ? 'job_resent' : 'job_for_you', { client: who, code: j.code, service: svcNames }, j.id).catch(() => {});
  } else {
    for (const id of await matchingFundiIds(j)) {
      await notify(id, resend ? 'job_resent' : 'new_job', { service: svcNames, code: j.code }, j.id).catch(() => {});
    }
  }
  const area = await areaLabel(j);
  for (const id of await adminIdsFor(j.region_id)) {
    await notify(id, resend ? 'job_resent' : 'new_job_admin', { client: who, service: svcNames, area, code: j.code }, j.id).catch(() => {});
  }
}

// ---------- create / list ----------
router.post('/', auth, role('client'), asyncH(async (req, res) => {
  const b = req.body, u = req.user;
  // one or more services chosen from the list, and/or another service described by the client
  const wanted = [...new Set((Array.isArray(b.service_ids) ? b.service_ids : b.service_id ? [b.service_id] : []).map(Number).filter(Boolean))].slice(0, 12);
  const svcs = wanted.length ? await q('select * from services where id = any($1::int[]) and active order by sort,id', [wanted]) : [];
  const other = b.other_service && String(b.other_service).trim() ? String(b.other_service).trim().slice(0, 300) : null;
  if (!svcs.length && !other) return fail(res, 400, 'invalid_service');
  let categoryId = Number(b.category_id) || (svcs[0] && svcs[0].category_id) || null;
  if (!categoryId) return fail(res, 400, 'invalid_service');
  if (typeof b.lat !== 'number' || typeof b.lng !== 'number') return fail(res, 400, 'location_required');
  const region_id = b.region_id || u.region_id, district_id = b.district_id || u.district_id, ward_id = b.ward_id || null;
  if (!district_id) return fail(res, 400, 'area_required');
  const d = await q1('select active from districts where id=$1', [district_id]);
  const rg = await q1('select active from regions where id=$1', [region_id]);
  if (!d || !d.active || !rg || !rg.active) return fail(res, 400, 'area_not_available');
  let pref = ['technician', 'company'].includes(b.preference) ? b.preference : 'any';
  let target = null;
  if (b.fundi_id) {
    target = await q1(`select id,fundi_type from users where id=$1 and role='fundi' and fundi_status='approved'`, [b.fundi_id]).catch(() => null);
    if (!target) return fail(res, 400, 'invalid_fundi');
    pref = target.fundi_type;
  }
  const wardText = !ward_id && b.ward_text && String(b.ward_text).trim() ? String(b.ward_text).trim().slice(0, 120) : null;
  const j = await q1(
    `insert into jobs(client_id,service_id,category_id,other_service,preference,description,notes,region_id,district_id,ward_id,ward_text,lat,lng,address,target_fundi_id)
     values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) returning *`,
    [u.id, svcs[0] ? svcs[0].id : null, categoryId, other, pref, String(b.description || '').trim(), b.notes || null,
      region_id, district_id, ward_id, wardText, b.lat, b.lng, b.address || null, target ? target.id : null]);
  for (const s of svcs) await q('insert into job_services(job_id,service_id) values($1,$2) on conflict do nothing', [j.id, s.id]);
  for (const f of (b.photo_ids || []).slice(0, 8)) await q('insert into job_photos(job_id,file_id) values($1,$2) on conflict do nothing', [j.id, f]);
  await announce(j, [...svcs.map((s) => s.name_en), ...(other ? [other] : [])].join(', '));
  res.json(await jobView(j.id, u));
}));

router.get('/', auth, role('client'), asyncH(async (req, res) => {
  const rows = await q('select id from jobs where client_id=$1 and not coalesce(client_hidden,false) order by created_at desc limit 60', [req.user.id]);
  res.json(await jobViews(rows.map((r) => r.id), req.user));
}));

router.get('/chats', auth, asyncH(async (req, res) => {
  const u = req.user;
  const rows = await q(
    `select j.id, j.code, j.status, j.client_id, j.fundi_id,
       (select body from messages m where m.job_id=j.id order by id desc limit 1) last_message,
       (select created_at from messages m where m.job_id=j.id order by id desc limit 1) last_at
     from jobs j where j.fundi_id is not null and (j.client_id=$1 or j.fundi_id=$1) and not (j.client_id=$1 and coalesce(j.client_hidden,false))
     order by coalesce((select max(created_at) from messages m where m.job_id=j.id), j.accepted_at) desc limit 100`, [u.id]);
  const ids = uniq(rows.map((r) => (r.client_id === u.id ? r.fundi_id : r.client_id)));
  const others = ids.length ? await q('select id,name,company_name,phone from users where id = any($1::uuid[])', [ids]) : [];
  const O = new Map(others.map((o) => [o.id, o]));
  for (const r of rows) {
    const other = O.get(r.client_id === u.id ? r.fundi_id : r.client_id) || {};
    r.other_name = other.company_name || other.name || other.phone;
  }
  res.json(rows);
}));

// The Fundis/Companies a client has worked with ("My Fundi"), with their full details.
router.get('/my-fundis', auth, role('client'), asyncH(async (req, res) => {
  const rows = await q(
    `select u.id,u.name,u.phone,u.fundi_type,u.company_name,u.photo_file_id,u.experience,u.admin_rating,
       count(j.id)::int jobs, max(j.created_at) last_job,
       (select round(avg(r.rating)::numeric,1) from ratings r join jobs jj on jj.id=r.job_id where jj.fundi_id=u.id) avg_rating,
       (select string_agg(distinct s.${SVC[req.user.language] || 'name_sw'}, ', ') from fundi_services fs join services s on s.id=fs.service_id where fs.user_id=u.id) services
     from jobs j join users u on u.id=j.fundi_id
     where j.client_id=$1 and j.status <> 'cancelled' group by u.id order by max(j.created_at) desc`, [req.user.id]);
  res.json(rows.map((r) => ({
    id: r.id, name: r.name, phone: r.phone, fundi_type: r.fundi_type, company_name: r.company_name, photo_file_id: r.photo_file_id,
    experience: r.experience, jobs: r.jobs, last_job: r.last_job, services: r.services,
    rating: { avg: r.admin_rating != null ? Number(r.admin_rating) : r.avg_rating ? Number(r.avg_rating) : null },
  })));
}));
router.get('/my-fundis/:id', auth, role('client'), asyncH(async (req, res) => {
  const ok = await q1('select 1 x from jobs where client_id=$1 and fundi_id=$2', [req.user.id, req.params.id]).catch(() => null);
  if (!ok) return fail(res, 404, 'not_found');
  const rows = await q(`select id from jobs where client_id=$1 and fundi_id=$2 order by created_at desc limit 30`, [req.user.id, req.params.id]);
  const jobs = await jobViews(rows.map((r) => r.id), req.user);
  const boqs = await q(`select b.id,b.title,b.total,b.updated_at,b.job_id from boqs b join jobs j on j.id=b.job_id where j.client_id=$1 and b.owner_id=$2 order by b.updated_at desc`, [req.user.id, req.params.id]);
  res.json({ jobs, boqs });
}));

router.get('/:id', auth, asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1', [req.params.id]).catch(() => null);
  if (!j || !(await canView(j, req.user))) return fail(res, 404, 'not_found');
  const v = await jobView(j.id, req.user);
  if (req.user.role === 'fundi' && j.fundi_id !== req.user.id) {
    stripForOthers(v);
    v.taken = !!j.fundi_id; // somebody else already took it: visible, but it cannot be accepted
    if (v.taken) { delete v.fundi; delete v.payments; delete v.quotation; }
  }
  res.json(v);
}));

router.post('/:id/cancel', auth, role('client'), asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1 and client_id=$2', [req.params.id, req.user.id]).catch(() => null);
  if (!j) return fail(res, 404, 'not_found');
  if (['completed', 'cancelled'].includes(j.status)) return fail(res, 400, 'cannot_cancel');
  const nauli = ['arrived', 'in_progress'].includes(j.status);
  // A cancelled request disappears from the client's list (the Admin still sees it, marked cancelled).
  // It stays visible only when nauli (transport) is still owed.
  await q(`update jobs set status='cancelled', cancelled_at=now(), cancelled_by='client', cancel_reason=$2, nauli_due=$3, client_hidden=$4 where id=$1`,
    [j.id, req.body.reason || null, nauli, !nauli]);
  if (j.fundi_id) await notify(j.fundi_id, nauli ? 'cancelled_nauli' : 'cancelled', { code: j.code }, j.id);
  if (nauli) await notify(j.client_id, 'cancelled_nauli', { code: j.code }, j.id);
  for (const id of await adminIdsFor(j.region_id)) await notify(id, 'cancelled', { code: j.code }, j.id).catch(() => {});
  res.json({ ...(await jobView(j.id, req.user)), ok: true, hidden: !nauli });
}));

// Send the request again (nobody accepted yet). With open_to_all the request is opened to every matching Fundi.
router.post('/:id/resend', auth, role('client'), asyncH(async (req, res) => {
  const j0 = await q1('select * from jobs where id=$1 and client_id=$2', [req.params.id, req.user.id]).catch(() => null);
  if (!j0) return fail(res, 404, 'not_found');
  if (j0.status !== 'pending' || j0.fundi_id) return fail(res, 400, 'cannot_resend');
  if (j0.resent_at && Date.now() - new Date(j0.resent_at).getTime() < 2 * 60 * 1000) return fail(res, 429, 'resend_too_soon');
  const j = await q1(`update jobs set resent_at=now(), target_fundi_id = case when $2 then null else target_fundi_id end where id=$1 returning *`, [j0.id, !!req.body.open_to_all]);
  const names = (await q('select s.name_en from job_services js join services s on s.id=js.service_id where js.job_id=$1', [j.id])).map((s) => s.name_en);
  if (j.other_service) names.push(j.other_service);
  await announce(j, names.join(', '), { resend: true });
  res.json(await jobView(j.id, req.user));
}));

router.post('/:id/rate', auth, role('client'), asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1 and client_id=$2', [req.params.id, req.user.id]).catch(() => null);
  if (!j) return fail(res, 404, 'not_found');
  if (j.status !== 'completed') return fail(res, 400, 'not_completed');
  const n = Math.round(Number(req.body.rating));
  if (!(n >= 1 && n <= 5)) return fail(res, 400, 'invalid_rating');
  await q('insert into ratings(job_id,rating,comment) values($1,$2,$3) on conflict(job_id) do update set rating=$2, comment=$3', [j.id, n, req.body.comment || null]);
  res.json(await jobView(j.id, req.user));
}));

// ---------- chat ----------
async function chatJob(req, res) {
  const j = await q1('select * from jobs where id=$1', [req.params.id]).catch(() => null);
  if (!j || !j.fundi_id || (j.client_id !== req.user.id && j.fundi_id !== req.user.id)) { fail(res, 404, 'not_found'); return null; }
  return j;
}
router.get('/:id/messages', auth, asyncH(async (req, res) => {
  const j = await chatJob(req, res); if (!j) return;
  const after = Number(req.query.after || 0);
  res.json(await q('select id,sender_id,body,created_at from messages where job_id=$1 and id>$2 order by id limit 200', [j.id, after]));
}));
router.post('/:id/messages', auth, asyncH(async (req, res) => {
  const j = await chatJob(req, res); if (!j) return;
  const body = String(req.body.body || '').trim().slice(0, 2000);
  if (!body) return fail(res, 400, 'empty');
  res.json(await q1('insert into messages(job_id,sender_id,body) values($1,$2,$3) returning id,sender_id,body,created_at', [j.id, req.user.id, body]));
}));

// ---------- payment ----------
// The client pays through the payment details shown in the app, enters the amount (and the transaction
// reference, if any) and confirms. The app issues the receipt, which is the proof of payment.
router.post('/:id/pay', auth, role('client'), asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1 and client_id=$2', [req.params.id, req.user.id]).catch(() => null);
  if (!j) return fail(res, 404, 'not_found');
  if (j.status === 'cancelled') return fail(res, 400, 'cannot_pay');
  const qt = await q1('select amount from quotations where job_id=$1', [j.id]);
  if (!qt) return fail(res, 400, 'no_quotation');
  const methods = await getSetting('payment_methods', {});
  const method = req.body.method;
  if (!methods[method]) return fail(res, 400, 'method_disabled');
  const amount = Math.round(Number(req.body.amount) * 100) / 100;
  const sums = await q1(`select coalesce(sum(amount),0) s from payments where job_id=$1 and status in ('success','pending')`, [j.id]);
  const balance = Number(qt.amount) - Number(sums.s);
  if (!(amount > 0)) return fail(res, 400, 'invalid_amount');
  if (amount > balance + 0.001) return fail(res, 400, 'amount_too_high', { balance });
  let p = await q1(
    `insert into payments(job_id,client_id,amount,method,phone,reference,txn_ref) values($1,$2,$3,$4,$5,$6,$7) returning *`,
    [j.id, req.user.id, amount, method, req.body.phone || null, 'SF' + Date.now().toString(36).toUpperCase(), req.body.txn_ref ? String(req.body.txn_ref).trim().slice(0, 60) : null]);
  if ((process.env.PAYMENT_MODE || 'manual') === 'simulated') p = await confirmPayment(p.id);
  res.json({ payment: p, job: await jobView(j.id, req.user) });
}));

module.exports = { router, jobView, jobViews, stripForOthers, confirmPayment, fundiMatches, matchingFundiIds, adminIdsFor, announce };
