const router = require('express').Router();
const { q, q1 } = require('../db');
const { asyncH, fail, auth, role, getSetting, notify, money } = require('../util');

const SVC = { sw: 'name_sw', en: 'name_en', fr: 'name_fr' };

async function fundiRating(fundiId) {
  const r = await q1('select round(avg(r.rating)::numeric,1) avg, count(*)::int n from ratings r join jobs j on j.id=r.job_id where j.fundi_id=$1', [fundiId]);
  return { avg: r.avg ? Number(r.avg) : null, count: r.n };
}
async function fundiMatches(fundiId, j) {
  const r = await q1(
    `select 1 x from users u where u.id=$1 and u.role='fundi' and u.fundi_status='approved' and u.fundi_type=$2
     and exists(select 1 from fundi_areas a where a.user_id=u.id and a.district_id=$3 and (a.ward_id is null or a.ward_id=$4))
     and exists(select 1 from fundi_services s where s.user_id=u.id and s.service_id=$5)`,
    [fundiId, j.preference, j.district_id, j.ward_id, j.service_id]
  );
  return !!r;
}
async function canView(j, u) {
  if (u.role === 'admin') return true;
  if (j.client_id === u.id || j.fundi_id === u.id) return true;
  if (u.role === 'fundi' && j.status === 'pending' && !j.fundi_id) return fundiMatches(u.id, j);
  return false;
}
async function jobView(id, viewer) {
  const j = await q1(
    `select j.*, s.name_sw, s.name_en, s.name_fr, r.name region_name, d.name district_name, w.name ward_name
     from jobs j left join services s on s.id=j.service_id left join regions r on r.id=j.region_id
     left join districts d on d.id=j.district_id left join wards w on w.id=j.ward_id where j.id=$1`, [id]);
  if (!j) return null;
  const lang = viewer.language || 'sw';
  const quotation = await q1('select amount,includes_transport,note,file_ids,updated_at from quotations where job_id=$1', [id]);
  const pays = await q('select id,amount,method,status,created_at from payments where job_id=$1 order by created_at', [id]);
  const paid = pays.filter((p) => p.status === 'success').reduce((a, p) => a + Number(p.amount), 0);
  const pending = pays.filter((p) => p.status === 'pending').reduce((a, p) => a + Number(p.amount), 0);
  const total = quotation ? Number(quotation.amount) : 0;
  const photos = (await q('select file_id from job_photos where job_id=$1', [id])).map((x) => x.file_id);
  const rating = await q1('select rating,comment from ratings where job_id=$1', [id]);
  const out = {
    id: j.id, code: j.code, status: j.status, preference: j.preference, description: j.description, notes: j.notes,
    service_id: j.service_id, service_name: j[SVC[lang] || 'name_sw'],
    region_name: j.region_name, district_name: j.district_name, ward_name: j.ward_name,
    lat: j.lat, lng: j.lng, address: j.address, nauli_due: j.nauli_due, cancel_reason: j.cancel_reason, cancelled_by: j.cancelled_by,
    created_at: j.created_at, accepted_at: j.accepted_at, on_the_way_at: j.on_the_way_at, arrived_at: j.arrived_at,
    started_at: j.started_at, completed_at: j.completed_at, cancelled_at: j.cancelled_at,
    photos, rating,
    quotation: quotation ? { amount: total, includes_transport: quotation.includes_transport, note: quotation.note, file_ids: quotation.file_ids } : null,
    payments: pays,
    paid, pending, balance: Math.max(total - paid, 0),
    payment_status: !quotation ? 'no_quotation' : paid >= total ? 'paid' : paid > 0 ? 'partial' : 'unpaid',
    can_contact: !!j.fundi_id && j.status !== 'cancelled',
  };
  if (j.fundi_id) {
    const f = await q1('select id,name,phone,fundi_type,company_name,photo_file_id from users where id=$1', [j.fundi_id]);
    out.fundi = { ...f, rating: await fundiRating(j.fundi_id) };
  }
  if (j.fundi_id || viewer.role === 'admin') {
    out.client = await q1('select id,name,phone from users where id=$1', [j.client_id]);
  }
  return out;
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

// ---------- create / list ----------
router.post('/', auth, role('client'), asyncH(async (req, res) => {
  const b = req.body, u = req.user;
  const svc = await q1('select * from services where id=$1 and active', [b.service_id]);
  if (!svc) return fail(res, 400, 'invalid_service');
  if (!b.description || !String(b.description).trim()) return fail(res, 400, 'description_required');
  if (typeof b.lat !== 'number' || typeof b.lng !== 'number') return fail(res, 400, 'location_required');
  const region_id = b.region_id || u.region_id, district_id = b.district_id || u.district_id, ward_id = b.ward_id || u.ward_id || null;
  if (!district_id) return fail(res, 400, 'area_required');
  const d = await q1('select active from districts where id=$1', [district_id]);
  const rg = await q1('select active from regions where id=$1', [region_id]);
  if (!d || !d.active || !rg || !rg.active) return fail(res, 400, 'area_not_available');
  const pref = b.preference === 'company' ? 'company' : 'technician';
  const j = await q1(
    `insert into jobs(client_id,service_id,preference,description,notes,region_id,district_id,ward_id,lat,lng,address)
     values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) returning *`,
    [u.id, svc.id, pref, String(b.description).trim(), b.notes || null, region_id, district_id, ward_id, b.lat, b.lng, b.address || null]);
  for (const f of (b.photo_ids || []).slice(0, 8)) await q('insert into job_photos(job_id,file_id) values($1,$2) on conflict do nothing', [j.id, f]);
  const fundis = await q(
    `select distinct u.id from users u join fundi_areas a on a.user_id=u.id join fundi_services s on s.user_id=u.id
     where u.role='fundi' and u.fundi_status='approved' and u.fundi_type=$1 and a.district_id=$2 and (a.ward_id is null or a.ward_id=$3) and s.service_id=$4`,
    [pref, district_id, ward_id, svc.id]);
  for (const f of fundis) await notify(f.id, 'new_job', { service: svc.name_en }, j.id).catch(() => {});
  res.json(await jobView(j.id, u));
}));

router.get('/', auth, role('client'), asyncH(async (req, res) => {
  const rows = await q('select id from jobs where client_id=$1 order by created_at desc limit 100', [req.user.id]);
  const out = [];
  for (const r of rows) out.push(await jobView(r.id, req.user));
  res.json(out);
}));

router.get('/chats', auth, asyncH(async (req, res) => {
  const u = req.user;
  const rows = await q(
    `select j.id, j.code, j.status, j.client_id, j.fundi_id,
       (select body from messages m where m.job_id=j.id order by id desc limit 1) last_message,
       (select created_at from messages m where m.job_id=j.id order by id desc limit 1) last_at
     from jobs j where j.fundi_id is not null and (j.client_id=$1 or j.fundi_id=$1) order by coalesce((select max(created_at) from messages m where m.job_id=j.id), j.accepted_at) desc limit 100`, [u.id]);
  for (const r of rows) {
    const other = await q1('select name,company_name,phone from users where id=$1', [r.client_id === u.id ? r.fundi_id : r.client_id]);
    r.other_name = other.company_name || other.name || other.phone;
  }
  res.json(rows);
}));

router.get('/:id', auth, asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1', [req.params.id]).catch(() => null);
  if (!j || !(await canView(j, req.user))) return fail(res, 404, 'not_found');
  const v = await jobView(j.id, req.user);
  if (req.user.role === 'fundi' && j.fundi_id !== req.user.id) { delete v.client; v.address = null; v.lat = null; v.lng = null; }
  res.json(v);
}));

router.post('/:id/cancel', auth, role('client'), asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1 and client_id=$2', [req.params.id, req.user.id]);
  if (!j) return fail(res, 404, 'not_found');
  if (['completed', 'cancelled'].includes(j.status)) return fail(res, 400, 'cannot_cancel');
  const nauli = ['arrived', 'in_progress'].includes(j.status);
  await q(`update jobs set status='cancelled', cancelled_at=now(), cancelled_by='client', cancel_reason=$2, nauli_due=$3 where id=$1`, [j.id, req.body.reason || null, nauli]);
  if (j.fundi_id) await notify(j.fundi_id, nauli ? 'cancelled_nauli' : 'cancelled', { code: j.code }, j.id);
  if (nauli) await notify(j.client_id, 'cancelled_nauli', { code: j.code }, j.id);
  res.json(await jobView(j.id, req.user));
}));

router.post('/:id/rate', auth, role('client'), asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1 and client_id=$2', [req.params.id, req.user.id]);
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
router.post('/:id/pay', auth, role('client'), asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1 and client_id=$2', [req.params.id, req.user.id]);
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
    `insert into payments(job_id,client_id,amount,method,phone,reference) values($1,$2,$3,$4,$5,$6) returning *`,
    [j.id, req.user.id, amount, method, req.body.phone || null, 'SF' + Date.now().toString(36).toUpperCase()]);
  if ((process.env.PAYMENT_MODE || 'manual') === 'simulated') p = await confirmPayment(p.id);
  res.json({ payment: p, job: await jobView(j.id, req.user) });
}));

module.exports = { router, jobView, confirmPayment, fundiMatches, fundiRating };
