const router = require('express').Router();
const { q, q1 } = require('../db');
const { asyncH, fail, auth, role, mainAdmin, normId, getSetting, setSetting, notify } = require('../util');
const { jobView, confirmPayment } = require('./jobs');
const { saveProfile, profile } = require('./fundi');
const { importRows } = require('../seed');

router.use(auth, role('admin'));

async function scope(u) {
  if (u.is_main_admin) return null;
  return (await q('select region_id from admin_regions where user_id=$1', [u.id])).map((r) => r.region_id);
}

router.get('/dashboard', asyncH(async (req, res) => {
  const sc = await scope(req.user);
  const byStatus = await q('select status, count(*)::int n from jobs where ($1::int[] is null or region_id = any($1)) group by status', [sc]);
  const f = await q('select fundi_status s, count(*)::int n from users where role=$1 group by fundi_status', ['fundi']);
  const c = await q1(`select count(*)::int n from users where role='client'`);
  const pay = await q1(`select coalesce(sum(amount),0) total, coalesce(sum(platform_amount),0) platform, coalesce(sum(fundi_amount),0) fundi from payments where status='success'`);
  const pend = await q1(`select count(*)::int n from payments where status='pending'`);
  res.json({ jobs_by_status: byStatus, fundis_by_status: f, clients: c.n, payments: pay, pending_payments: pend.n });
}));

// ---------- fundis ----------
router.get('/fundis', asyncH(async (req, res) => {
  const sc = await scope(req.user);
  const rows = await q(
    `select u.id,u.name,u.phone,u.email,u.fundi_type,u.company_name,u.fundi_status,u.created_at,
       (select string_agg(distinct d.name, ', ') from fundi_areas a join districts d on d.id=a.district_id where a.user_id=u.id) districts
     from users u where u.role='fundi' and ($1::text is null or u.fundi_status=$1)
     and ($2::int[] is null or exists(select 1 from fundi_areas a where a.user_id=u.id and a.region_id = any($2)))
     order by case u.fundi_status when 'pending' then 0 else 1 end, u.created_at desc limit 300`,
    [req.query.status || null, sc]);
  res.json(rows);
}));
router.get('/fundis/:id', asyncH(async (req, res) => {
  const u = await q1(`select id from users where id=$1 and role='fundi'`, [req.params.id]).catch(() => null);
  if (!u) return fail(res, 404, 'not_found');
  res.json(await profile(u));
}));
async function setStatus(req, res, status, key) {
  const u = await q1(`update users set fundi_status=$2, reject_reason=$3 where id=$1 and role='fundi' returning id`, [req.params.id, status, status === 'rejected' ? req.body.reason || null : null]);
  if (!u) return fail(res, 404, 'not_found');
  if (key) await notify(u.id, key, { reason: req.body.reason || '' });
  res.json(await profile(u));
}
router.post('/fundis/:id/approve', asyncH((req, res) => setStatus(req, res, 'approved', 'approved')));
router.post('/fundis/:id/reject', asyncH((req, res) => setStatus(req, res, 'rejected', 'rejected')));
router.post('/fundis/:id/suspend', asyncH((req, res) => setStatus(req, res, 'suspended', null)));
router.post('/fundis', asyncH(async (req, res) => {
  const b = req.body, id = normId(b.identifier);
  if (!id) return fail(res, 400, 'invalid_identifier');
  const col = id.type === 'email' ? 'email' : 'phone';
  if (await q1(`select 1 x from users where ${col}=$1`, [id.value])) return fail(res, 409, 'already_exists');
  const u = await q1(
    `insert into users(role,${col},name,fundi_type,company_name,fundi_status,language) values('fundi',$1,$2,$3,$4,$5,'sw') returning id`,
    [id.value, b.name || null, b.fundi_type === 'company' ? 'company' : 'technician', b.company_name || null, b.approve === false ? 'pending' : 'approved']);
  await saveProfile(u.id, b);
  res.json(await profile(u));
}));
router.put('/fundis/:id', asyncH(async (req, res) => {
  const b = req.body;
  const u = await q1(`update users set name=coalesce($2,name), company_name=coalesce($3,company_name), fundi_type=coalesce($4,fundi_type) where id=$1 and role='fundi' returning id`,
    [req.params.id, b.name || null, b.company_name || null, ['technician', 'company'].includes(b.fundi_type) ? b.fundi_type : null]);
  if (!u) return fail(res, 404, 'not_found');
  await saveProfile(u.id, { areas: b.areas, service_ids: b.service_ids });
  res.json(await profile(u));
}));
router.post('/fundis/:id/documents', asyncH(async (req, res) => {
  await q('insert into fundi_documents(user_id,kind,name,file_id) values($1,$2,$3,$4)', [req.params.id, req.body.kind || 'other', req.body.name || null, req.body.file_id]);
  res.json(await profile({ id: req.params.id }));
}));

// ---------- jobs ----------
router.get('/jobs', asyncH(async (req, res) => {
  const sc = await scope(req.user);
  const rows = await q(
    `select id from jobs where ($1::text is null or status=$1) and ($2::int[] is null or region_id = any($2)) order by created_at desc limit 200`,
    [req.query.status || null, sc]);
  const out = [];
  for (const r of rows) out.push(await jobView(r.id, req.user));
  res.json(out);
}));
router.get('/jobs/:id', asyncH(async (req, res) => {
  const v = await jobView(req.params.id, req.user).catch(() => null);
  if (!v) return fail(res, 404, 'not_found');
  res.json(v);
}));
router.post('/jobs/:id/reassign', asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1', [req.params.id]).catch(() => null);
  if (!j || ['completed', 'cancelled'].includes(j.status)) return fail(res, 400, 'invalid_status');
  const f = await q1(`select id from users where id=$1 and role='fundi' and fundi_status='approved'`, [req.body.fundi_id]).catch(() => null);
  if (!f) return fail(res, 400, 'invalid_fundi');
  const old = j.fundi_id;
  await q(`update jobs set fundi_id=$2, status='accepted', accepted_at=now(), on_the_way_at=null, arrived_at=null, started_at=null where id=$1`, [j.id, f.id]);
  await notify(f.id, 'reassigned', { code: j.code }, j.id);
  if (old && old !== f.id) await notify(old, 'cancelled', { code: j.code }, j.id);
  await notify(j.client_id, 'job_accepted', { name: (await q1('select coalesce(company_name,name,phone) n from users where id=$1', [f.id])).n, code: j.code }, j.id);
  res.json(await jobView(j.id, req.user));
}));
router.post('/jobs/:id/cancel', asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1', [req.params.id]).catch(() => null);
  if (!j || ['completed', 'cancelled'].includes(j.status)) return fail(res, 400, 'invalid_status');
  await q(`update jobs set status='cancelled', cancelled_at=now(), cancelled_by='admin', cancel_reason=$2 where id=$1`, [j.id, req.body.reason || null]);
  await notify(j.client_id, 'cancelled', { code: j.code }, j.id);
  if (j.fundi_id) await notify(j.fundi_id, 'cancelled', { code: j.code }, j.id);
  res.json(await jobView(j.id, req.user));
}));
router.get('/available-fundis', asyncH(async (req, res) => {
  const j = await q1('select * from jobs where id=$1', [req.query.job_id]).catch(() => null);
  if (!j) return fail(res, 404, 'not_found');
  res.json(await q(
    `select u.id,u.name,u.phone,u.company_name,u.fundi_type from users u where u.role='fundi' and u.fundi_status='approved'
     and exists(select 1 from fundi_areas a where a.user_id=u.id and a.district_id=$1) and exists(select 1 from fundi_services s where s.user_id=u.id and s.service_id=$2)`,
    [j.district_id, j.service_id]));
}));

// ---------- services ----------
router.get('/services', asyncH(async (req, res) => res.json(await q('select * from services order by sort,id'))));
router.post('/services', mainAdmin, asyncH(async (req, res) => {
  const b = req.body;
  if (!b.name_sw && !b.name_en) return fail(res, 400, 'name_required');
  const key = (b.key || b.name_en || b.name_sw).toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '') + '_' + Date.now().toString(36);
  res.json(await q1(`insert into services(trade,key,name_sw,name_en,name_fr,sort) values($1,$2,$3,$4,$5,(select coalesce(max(sort),0)+1 from services)) returning *`,
    [b.trade || 'electrical', key, b.name_sw || b.name_en, b.name_en || b.name_sw, b.name_fr || b.name_en || b.name_sw]));
}));
router.put('/services/:id', mainAdmin, asyncH(async (req, res) => {
  const b = req.body;
  res.json(await q1(`update services set name_sw=coalesce($2,name_sw), name_en=coalesce($3,name_en), name_fr=coalesce($4,name_fr), active=coalesce($5,active) where id=$1 returning *`,
    [req.params.id, b.name_sw ?? null, b.name_en ?? null, b.name_fr ?? null, typeof b.active === 'boolean' ? b.active : null]));
}));
router.delete('/services/:id', mainAdmin, asyncH(async (req, res) => {
  const used = await q1('select (select count(*) from jobs where service_id=$1)+(select count(*) from fundi_services where service_id=$1) n', [req.params.id]);
  if (Number(used.n) > 0) await q('update services set active=false where id=$1', [req.params.id]);
  else await q('delete from services where id=$1', [req.params.id]);
  res.json({ ok: true, deactivated: Number(used.n) > 0 });
}));

// ---------- settings / commission ----------
router.get('/settings', asyncH(async (req, res) => res.json({
  commission_percent: Number(await getSetting('commission_percent', 20)),
  payment_methods: await getSetting('payment_methods', {}),
  about: await getSetting('about', {}),
  landing_url: await getSetting('landing_url', ''),
  is_main_admin: req.user.is_main_admin,
})));
router.put('/settings', mainAdmin, asyncH(async (req, res) => {
  const b = req.body;
  if (b.commission_percent !== undefined) {
    const c = Number(b.commission_percent);
    if (!(c >= 0 && c <= 100)) return fail(res, 400, 'invalid_commission');
    await setSetting('commission_percent', c);
  }
  if (b.payment_methods) await setSetting('payment_methods', { mobile_money: !!b.payment_methods.mobile_money, bank: !!b.payment_methods.bank, lipa_namba: !!b.payment_methods.lipa_namba });
  if (b.about) await setSetting('about', b.about);
  if (typeof b.landing_url === 'string') await setSetting('landing_url', b.landing_url);
  res.json({ ok: true });
}));

// ---------- payments ----------
router.get('/payments', asyncH(async (req, res) => {
  const rows = await q(
    `select p.id,p.reference,p.amount,p.method,p.phone,p.status,p.commission_percent,p.platform_amount,p.fundi_amount,p.created_at,j.code,
       cu.name client_name, coalesce(fu.company_name,fu.name) fundi_name
     from payments p join jobs j on j.id=p.job_id join users cu on cu.id=p.client_id left join users fu on fu.id=j.fundi_id
     where ($1::text is null or p.status=$1) order by p.created_at desc limit 300`, [req.query.status || null]);
  const t = await q1(`select coalesce(sum(amount),0) total, coalesce(sum(platform_amount),0) platform, coalesce(sum(fundi_amount),0) fundi from payments where status='success'`);
  res.json({ totals: t, items: rows });
}));
router.post('/payments/:id/confirm', asyncH(async (req, res) => res.json(await confirmPayment(req.params.id))));
router.post('/payments/:id/reject', asyncH(async (req, res) => {
  res.json(await q1(`update payments set status='failed' where id=$1 and status='pending' returning *`, [req.params.id]));
}));

// ---------- locations ----------
router.get('/coverage', asyncH(async (req, res) => {
  const regions = await q(`select r.id,r.name,r.active,(select count(*)::int from districts d where d.region_id=r.id) districts,
    (select count(distinct a.user_id)::int from fundi_areas a join users u on u.id=a.user_id and u.fundi_status='approved' where a.region_id=r.id) fundis from regions r order by r.name`);
  res.json(regions);
}));
router.get('/coverage/:regionId', asyncH(async (req, res) => {
  res.json(await q(`select d.id,d.name,d.active,(select count(*)::int from wards w where w.district_id=d.id) wards,
    (select count(distinct a.user_id)::int from fundi_areas a join users u on u.id=a.user_id and u.fundi_status='approved' where a.district_id=d.id) fundis
    from districts d where d.region_id=$1 order by d.name`, [req.params.regionId]));
}));
router.put('/regions/:id', asyncH(async (req, res) => res.json(await q1('update regions set active=$2 where id=$1 returning *', [req.params.id, !!req.body.active]))));
router.put('/districts/:id', asyncH(async (req, res) => res.json(await q1('update districts set active=$2 where id=$1 returning *', [req.params.id, !!req.body.active]))));
router.post('/districts', asyncH(async (req, res) => {
  if (!req.body.name) return fail(res, 400, 'name_required');
  res.json(await q1('insert into districts(region_id,name) values($1,$2) on conflict(region_id,name) do update set name=excluded.name returning *', [req.body.region_id, req.body.name.trim()]));
}));
router.post('/wards', asyncH(async (req, res) => {
  if (!req.body.name) return fail(res, 400, 'name_required');
  res.json(await q1('insert into wards(district_id,name) values($1,$2) on conflict(district_id,name) do update set name=excluded.name returning *', [req.body.district_id, req.body.name.trim()]));
}));
router.post('/locations/import', mainAdmin, asyncH(async (req, res) => {
  const rows = Array.isArray(req.body.rows) ? req.body.rows : [];
  res.json({ imported: await importRows(rows.slice(0, 20000)) });
}));

// ---------- other admins ----------
router.get('/admins', mainAdmin, asyncH(async (req, res) => res.json(await q(
  `select u.id,u.name,u.phone,u.email,u.is_main_admin,
   coalesce((select json_agg(json_build_object('id',r.id,'name',r.name)) from admin_regions ar join regions r on r.id=ar.region_id where ar.user_id=u.id),'[]') regions
   from users u where u.role='admin' order by u.is_main_admin desc, u.created_at`))));
router.post('/admins', mainAdmin, asyncH(async (req, res) => {
  const id = normId(req.body.identifier);
  if (!id) return fail(res, 400, 'invalid_identifier');
  const col = id.type === 'email' ? 'email' : 'phone';
  const u = await q1(`insert into users(role,${col},name) values('admin',$1,$2) on conflict(${col}) do update set role='admin', name=coalesce($2,users.name) returning id`, [id.value, req.body.name || null]);
  await q('delete from admin_regions where user_id=$1', [u.id]);
  for (const r of req.body.region_ids || []) await q('insert into admin_regions(user_id,region_id) values($1,$2) on conflict do nothing', [u.id, r]);
  res.json({ ok: true, id: u.id });
}));
router.delete('/admins/:id', mainAdmin, asyncH(async (req, res) => {
  if (req.params.id === req.user.id) return fail(res, 400, 'cannot_remove_self');
  await q(`update users set role='client', is_main_admin=false where id=$1 and role='admin'`, [req.params.id]);
  await q('delete from admin_regions where user_id=$1', [req.params.id]);
  res.json({ ok: true });
}));

module.exports = router;
