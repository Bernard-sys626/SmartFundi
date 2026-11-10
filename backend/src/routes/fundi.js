const router = require('express').Router();
const { q, q1 } = require('../db');
const { asyncH, fail, auth, role, haversine, notify, money } = require('../util');
const { jobView } = require('./jobs');

router.use(auth, role('fundi'));

async function profile(u) {
  const user = await q1('select * from users where id=$1', [u.id]);
  return {
    user: {
      id: user.id, name: user.name, username: user.username, reset_requested_at: user.reset_requested_at, phone: user.phone, email: user.email, fundi_type: user.fundi_type, company_name: user.company_name,
      fundi_status: user.fundi_status, reject_reason: user.reject_reason, photo_file_id: user.photo_file_id, language: user.language,
    },
    areas: await q(
      `select a.id,a.region_id,a.district_id,a.ward_id,r.name region_name,d.name district_name,w.name ward_name from fundi_areas a
       left join regions r on r.id=a.region_id left join districts d on d.id=a.district_id left join wards w on w.id=a.ward_id where a.user_id=$1 order by a.id`, [u.id]),
    service_ids: (await q('select service_id from fundi_services where user_id=$1', [u.id])).map((x) => x.service_id),
    documents: await q('select id,kind,name,file_id,created_at from fundi_documents where user_id=$1 order by id desc', [u.id]),
  };
}
router.get('/profile', asyncH(async (req, res) => res.json(await profile(req.user))));

async function saveProfile(userId, b) {
  await q(`update users set fundi_type=coalesce($2,fundi_type), company_name=coalesce($3,company_name), name=coalesce($4,name),
           photo_file_id=coalesce($5,photo_file_id) where id=$1`,
    [userId, ['technician', 'company'].includes(b.fundi_type) ? b.fundi_type : null, b.company_name || null, b.name || null, b.photo_file_id || null]);
  if (Array.isArray(b.areas)) {
    await q('delete from fundi_areas where user_id=$1', [userId]);
    for (const a of b.areas) if (a.district_id) await q('insert into fundi_areas(user_id,region_id,district_id,ward_id) values($1,$2,$3,$4)', [userId, a.region_id || null, a.district_id, a.ward_id || null]);
  }
  if (Array.isArray(b.service_ids)) {
    await q('delete from fundi_services where user_id=$1', [userId]);
    for (const s of b.service_ids) await q('insert into fundi_services(user_id,service_id) values($1,$2) on conflict do nothing', [userId, s]);
  }
}
router.put('/profile', asyncH(async (req, res) => {
  if (req.user.fundi_status === 'approved' && req.body.fundi_type && req.body.fundi_type !== req.user.fundi_type) return fail(res, 400, 'cannot_change_type');
  await saveProfile(req.user.id, req.body);
  res.json(await profile(req.user));
}));

router.post('/documents', asyncH(async (req, res) => {
  const { kind, file_id, name } = req.body;
  if (!file_id) return fail(res, 400, 'no_file');
  const allowed = ['education', 'professional', 'national_id', 'company_reg', 'quotation', 'invoice', 'other'];
  await q('insert into fundi_documents(user_id,kind,name,file_id) values($1,$2,$3,$4)', [req.user.id, allowed.includes(kind) ? kind : 'other', name || null, file_id]);
  res.json(await profile(req.user));
}));
router.delete('/documents/:id', asyncH(async (req, res) => {
  await q('delete from fundi_documents where id=$1 and user_id=$2', [req.params.id, req.user.id]);
  res.json(await profile(req.user));
}));

// Submit registration for Admin approval
router.post('/submit', asyncH(async (req, res) => {
  const p = await profile(req.user);
  const kinds = new Set(p.documents.map((d) => d.kind));
  const missing = [];
  if (!p.user.fundi_type) missing.push('type');
  if (!p.user.name && p.user.fundi_type === 'technician') missing.push('name');
  if (p.user.fundi_type === 'company' && !p.user.company_name) missing.push('company_name');
  if (!p.areas.length) missing.push('areas');
  if (!p.service_ids.length) missing.push('services');
  if (!p.user.photo_file_id) missing.push('photo');
  if (p.user.fundi_type === 'technician') {
    if (!kinds.has('national_id')) missing.push('national_id');
    if (!kinds.has('education') && !kinds.has('professional')) missing.push('certificates');
  } else if (p.user.fundi_type === 'company') {
    if (!kinds.has('company_reg')) missing.push('company_reg');
  }
  if (missing.length) return fail(res, 400, 'missing_info', { missing });
  await q(`update users set fundi_status='pending', reject_reason=null where id=$1 and fundi_status in ('incomplete','rejected')`, [req.user.id]);
  res.json(await profile(req.user));
}));

function approved(req, res, next) {
  if (req.user.fundi_status !== 'approved') return fail(res, 403, 'not_approved');
  next();
}

router.get('/jobs/available', approved, asyncH(async (req, res) => {
  const rows = await q(
    `select j.id from jobs j where j.status='pending' and j.fundi_id is null and j.preference=$2
     and exists(select 1 from fundi_areas a where a.user_id=$1 and a.district_id=j.district_id and (a.ward_id is null or a.ward_id=j.ward_id))
     and exists(select 1 from fundi_services s where s.user_id=$1 and s.service_id=j.service_id)
     order by j.created_at desc limit 100`, [req.user.id, req.user.fundi_type]);
  const out = [];
  for (const r of rows) { const v = await jobView(r.id, req.user); delete v.client; v.address = null; v.lat = null; v.lng = null; out.push(v); }
  res.json(out);
}));
router.get('/jobs/mine', approved, asyncH(async (req, res) => {
  const rows = await q('select id from jobs where fundi_id=$1 order by created_at desc limit 100', [req.user.id]);
  const out = [];
  for (const r of rows) out.push(await jobView(r.id, req.user));
  res.json(out);
}));

async function myJob(req, res, statuses) {
  const j = await q1('select * from jobs where id=$1 and fundi_id=$2', [req.params.id, req.user.id]).catch(() => null);
  if (!j) { fail(res, 404, 'not_found'); return null; }
  if (statuses && !statuses.includes(j.status)) { fail(res, 400, 'invalid_status'); return null; }
  return j;
}
const who = (u) => u.company_name || u.name || u.phone;

router.post('/jobs/:id/accept', approved, asyncH(async (req, res) => {
  const j0 = await q1('select * from jobs where id=$1', [req.params.id]).catch(() => null);
  if (!j0) return fail(res, 404, 'not_found');
  const ok = await q1(
    `select 1 x from users u where u.id=$1 and u.fundi_type=$2
     and exists(select 1 from fundi_areas a where a.user_id=u.id and a.district_id=$3 and (a.ward_id is null or a.ward_id=$4))
     and exists(select 1 from fundi_services s where s.user_id=u.id and s.service_id=$5)`, [req.user.id, j0.preference, j0.district_id, j0.ward_id, j0.service_id]);
  if (!ok) return fail(res, 403, 'forbidden');
  const j = await q1(`update jobs set fundi_id=$1, status='accepted', accepted_at=now() where id=$2 and status='pending' and fundi_id is null returning *`, [req.user.id, j0.id]);
  if (!j) return fail(res, 409, 'already_taken');
  await notify(j.client_id, 'job_accepted', { name: who(req.user), code: j.code }, j.id);
  res.json(await jobView(j.id, req.user));
}));
router.post('/jobs/:id/on-the-way', approved, asyncH(async (req, res) => {
  const j = await myJob(req, res, ['accepted']); if (!j) return;
  await q(`update jobs set status='on_the_way', on_the_way_at=now() where id=$1`, [j.id]);
  await notify(j.client_id, 'on_the_way', { name: who(req.user), code: j.code }, j.id);
  res.json(await jobView(j.id, req.user));
}));
router.post('/jobs/:id/arrived', approved, asyncH(async (req, res) => {
  const j = await myJob(req, res, ['accepted', 'on_the_way']); if (!j) return;
  const { lat, lng } = req.body;
  if (typeof lat !== 'number' || typeof lng !== 'number') return fail(res, 400, 'gps_required');
  const radius = Number(process.env.ARRIVAL_RADIUS_M || 300);
  const dist = haversine(j.lat, j.lng, lat, lng);
  if (dist > radius) return fail(res, 400, 'too_far', { distance_m: Math.round(dist), radius_m: radius });
  await q(`update jobs set status='arrived', arrived_at=now(), arrived_lat=$2, arrived_lng=$3 where id=$1`, [j.id, lat, lng]);
  await notify(j.client_id, 'arrived', { name: who(req.user), code: j.code }, j.id);
  res.json(await jobView(j.id, req.user));
}));
router.put('/jobs/:id/quotation', approved, asyncH(async (req, res) => {
  const j = await myJob(req, res, ['accepted', 'on_the_way', 'arrived', 'in_progress']); if (!j) return;
  const amount = Math.round(Number(req.body.amount) * 100) / 100;
  if (!(amount > 0)) return fail(res, 400, 'invalid_amount');
  const paid = await q1(`select coalesce(sum(amount),0) s from payments where job_id=$1 and status in ('success','pending')`, [j.id]);
  if (amount < Number(paid.s)) return fail(res, 400, 'amount_below_paid');
  await q(
    `insert into quotations(job_id,amount,includes_transport,note,file_ids) values($1,$2,$3,$4,$5)
     on conflict(job_id) do update set amount=$2, includes_transport=$3, note=$4, file_ids=$5, updated_at=now()`,
    [j.id, amount, !!req.body.includes_transport, req.body.note || null, Array.isArray(req.body.file_ids) ? req.body.file_ids : []]);
  await notify(j.client_id, 'quotation', { amount: money(amount), code: j.code }, j.id);
  res.json(await jobView(j.id, req.user));
}));
router.post('/jobs/:id/start', approved, asyncH(async (req, res) => {
  const j = await myJob(req, res, ['arrived']); if (!j) return;
  await q(`update jobs set status='in_progress', started_at=now() where id=$1`, [j.id]);
  res.json(await jobView(j.id, req.user));
}));
router.post('/jobs/:id/complete', approved, asyncH(async (req, res) => {
  const j = await myJob(req, res, ['in_progress']); if (!j) return;
  const qt = await q1('select 1 x from quotations where job_id=$1', [j.id]);
  if (!qt) return fail(res, 400, 'quotation_required');
  await q(`update jobs set status='completed', completed_at=now() where id=$1`, [j.id]);
  await notify(j.client_id, 'completed', { code: j.code }, j.id);
  res.json(await jobView(j.id, req.user));
}));

router.get('/earnings', asyncH(async (req, res) => {
  const hist = await q(
    `select p.id,p.amount,p.fundi_amount,p.platform_amount,p.commission_percent,p.status,p.method,p.created_at,p.confirmed_at,j.code
     from payments p join jobs j on j.id=p.job_id where j.fundi_id=$1 order by p.created_at desc limit 200`, [req.user.id]);
  const sum = (arr, f) => arr.reduce((a, x) => a + Number(x[f] || 0), 0);
  const ok = hist.filter((h) => h.status === 'success');
  const outstanding = await q1(
    `select coalesce(sum(greatest(qt.amount - coalesce((select sum(amount) from payments p where p.job_id=j.id and p.status='success'),0),0)),0) s
     from jobs j join quotations qt on qt.job_id=j.id where j.fundi_id=$1 and j.status<>'cancelled'`, [req.user.id]);
  res.json({
    total_earned: sum(ok, 'fundi_amount'), total_paid_by_clients: sum(ok, 'amount'), platform_fees: sum(ok, 'platform_amount'),
    pending_confirmation: sum(hist.filter((h) => h.status === 'pending'), 'amount'), outstanding_from_clients: Number(outstanding.s), history: hist,
  });
}));

module.exports = { router, saveProfile, profile };
