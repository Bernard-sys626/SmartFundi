const router = require('express').Router();
const { q, q1 } = require('../db');
const { asyncH, fail, auth, role, mainAdmin, getSetting, setSetting } = require('../util');
const { numberRows, totalOf, buildPdf, buildXlsx } = require('../boq_export');

router.use(auth);

const KINDS = ['section', 'group', 'item', 'sub'];
const n = (v) => { const x = Number(v); return Number.isFinite(x) && x >= 0 ? Math.round(x * 100) / 100 : 0; };
const priced = (k) => k === 'item' || k === 'sub';

async function masterRows() {
  return q('select id,kind,description,unit,rate::float rate,sort from boq_items where active order by sort,id');
}

// ---------- master list (Admin edits it for everybody; each Fundi sees own prices on top) ----------
router.get('/master', role('fundi', 'admin'), asyncH(async (req, res) => {
  const rows = await masterRows();
  const mine = req.user.role === 'fundi'
    ? new Map((await q('select item_id, rate::float rate from boq_user_rates where user_id=$1', [req.user.id])).map((r) => [r.item_id, r.rate])) : new Map();
  const items = numberRows(rows.map((r) => ({ ...r, master_rate: r.rate, rate: mine.has(r.id) ? mine.get(r.id) : r.rate, own_rate: mine.has(r.id) })));
  res.json({ title: await getSetting('boq_title', 'BILLS OF QUANTITIES'), items });
}));

router.put('/master/title', mainAdmin, asyncH(async (req, res) => {
  const t = String(req.body.title || '').trim().slice(0, 200);
  if (!t) return fail(res, 400, 'name_required');
  await setSetting('boq_title', t);
  res.json({ ok: true });
}));
router.post('/master/items', mainAdmin, asyncH(async (req, res) => {
  const b = req.body;
  const kind = KINDS.includes(b.kind) ? b.kind : 'item';
  const desc = String(b.description || '').trim().slice(0, 600);
  if (!desc) return fail(res, 400, 'name_required');
  // placed at the end of the section given by after_id (or at the very end)
  let sort;
  if (b.after_id) {
    const a = await q1('select sort from boq_items where id=$1', [b.after_id]).catch(() => null);
    if (a) {
      const nx = await q1('select min(sort) s from boq_items where sort > $1', [a.sort]);
      sort = nx && nx.s ? (Number(a.sort) + Number(nx.s)) / 2 : Number(a.sort) + 10;
    }
  }
  if (sort === undefined) sort = Number((await q1('select coalesce(max(sort),0)+10 s from boq_items')).s);
  const r = await q1('insert into boq_items(kind,description,unit,rate,sort) values($1,$2,$3,$4,$5) returning id',
    [kind, desc, priced(kind) ? String(b.unit || '').trim().slice(0, 20) || null : null, priced(kind) ? n(b.rate) : null, sort]);
  res.json({ ok: true, id: r.id });
}));
router.put('/master/items/:id', mainAdmin, asyncH(async (req, res) => {
  const b = req.body;
  const r = await q1(
    `update boq_items set description=coalesce($2,description), unit=coalesce($3,unit), rate=coalesce($4,rate), kind=coalesce($5,kind) where id=$1 returning id`,
    [req.params.id, b.description ? String(b.description).trim().slice(0, 600) : null, b.unit != null ? String(b.unit).trim().slice(0, 20) : null,
      b.rate != null && b.rate !== '' ? n(b.rate) : null, KINDS.includes(b.kind) ? b.kind : null]).catch(() => null);
  if (!r) return fail(res, 404, 'not_found');
  res.json({ ok: true });
}));
router.delete('/master/items/:id', mainAdmin, asyncH(async (req, res) => {
  await q('update boq_items set active=false where id=$1', [req.params.id]).catch(() => {});
  res.json({ ok: true });
}));

// ---------- BOQ documents ----------
function out(b, full = true) {
  const lines = numberRows(Array.isArray(b.lines) ? b.lines : []);
  const o = {
    id: b.id, title: b.title, job_id: b.job_id, owner_id: b.owner_id, total: Number(b.total), created_at: b.created_at, updated_at: b.updated_at,
    client_name: b.client_name, client_contact: b.client_contact, location: b.location, tin: b.tin, installer_name: b.installer_name, installer_phone: b.installer_phone,
    owner_name: b.owner_name,
  };
  if (full) o.lines = lines;
  return o;
}
async function canSee(b, u) {
  if (u.role === 'admin') return true;
  if (b.owner_id === u.id) return true;
  if (u.role === 'client' && b.job_id) return !!(await q1('select 1 x from jobs where id=$1 and client_id=$2', [b.job_id, u.id]));
  return false;
}
async function getBoq(req, res) {
  const b = await q1(`select b.*, coalesce(u.company_name,u.name,u.phone) owner_name from boqs b left join users u on u.id=b.owner_id where b.id=$1`, [req.params.id]).catch(() => null);
  if (!b || !(await canSee(b, req.user))) { fail(res, 404, 'not_found'); return null; }
  return b;
}

router.get('/mine', role('fundi'), asyncH(async (req, res) => {
  const rows = await q(
    `select b.id,b.title,b.total,b.created_at,b.updated_at,b.job_id,b.client_name,j.code job_code from boqs b left join jobs j on j.id=b.job_id
     where b.owner_id=$1 order by b.updated_at desc limit 100`, [req.user.id]);
  res.json(rows.map((r) => ({ ...r, total: Number(r.total) })));
}));
router.get('/all', role('admin'), asyncH(async (req, res) => {
  const rows = await q(
    `select b.id,b.title,b.total,b.created_at,b.updated_at,b.job_id,b.client_name,j.code job_code, coalesce(u.company_name,u.name,u.phone) owner_name
     from boqs b left join jobs j on j.id=b.job_id left join users u on u.id=b.owner_id order by b.updated_at desc limit 200`);
  res.json(rows.map((r) => ({ ...r, total: Number(r.total) })));
}));

// New BOQ: all items of the master list with this Fundi's own prices and quantity 0.
router.post('/', role('fundi'), asyncH(async (req, res) => {
  const u = req.user;
  if (u.fundi_status !== 'approved') return fail(res, 403, 'not_approved');
  let job = null;
  if (req.body.job_id) {
    job = await q1(
      `select j.id, j.code, c.name client_name, c.phone client_phone, w.name ward_name, j.ward_text, d.name district_name, r.name region_name
       from jobs j join users c on c.id=j.client_id left join wards w on w.id=j.ward_id left join districts d on d.id=j.district_id left join regions r on r.id=j.region_id
       where j.id=$1 and j.fundi_id=$2`, [req.body.job_id, u.id]).catch(() => null);
    if (!job) return fail(res, 404, 'not_found');
  }
  const rows = await masterRows();
  const mine = new Map((await q('select item_id, rate::float rate from boq_user_rates where user_id=$1', [u.id])).map((r) => [r.item_id, r.rate]));
  const lines = rows.map((r) => ({ item_id: r.id, kind: r.kind, desc: r.description, unit: r.unit, rate: mine.has(r.id) ? mine.get(r.id) : r.rate, qty: 0 }));
  const b = await q1(
    `insert into boqs(owner_id,job_id,title,client_name,client_contact,location,installer_name,installer_phone,lines,total)
     values($1,$2,$3,$4,$5,$6,$7,$8,$9,0) returning *`,
    [u.id, job ? job.id : null, await getSetting('boq_title', 'BILLS OF QUANTITIES'), job ? job.client_name : null, job ? job.client_phone : null,
      job ? [job.ward_name || job.ward_text, job.district_name, job.region_name].filter(Boolean).join(', ') : null,
      u.company_name || u.name, u.phone, JSON.stringify(lines)]);
  res.json(out(b));
}));

router.get('/:id', asyncH(async (req, res) => {
  const b = await getBoq(req, res); if (!b) return;
  res.json(out(b));
}));

router.put('/:id', role('fundi'), asyncH(async (req, res) => {
  const old = await q1('select * from boqs where id=$1 and owner_id=$2', [req.params.id, req.user.id]).catch(() => null);
  if (!old) return fail(res, 404, 'not_found');
  const b = req.body;
  const s = (v, max) => (v == null ? null : String(v).trim().slice(0, max) || null);
  const lines = (Array.isArray(b.lines) ? b.lines : []).slice(0, 500).map((l) => {
    const kind = KINDS.includes(l.kind) ? l.kind : 'item';
    return { item_id: Number(l.item_id) || null, kind, desc: String(l.desc || '').trim().slice(0, 600), unit: priced(kind) ? s(l.unit, 20) : null, rate: priced(kind) ? n(l.rate) : null, qty: priced(kind) ? n(l.qty) : 0 };
  }).filter((l) => l.desc);
  const total = totalOf(lines);
  const r = await q1(
    `update boqs set title=coalesce($2,title), client_name=$3, client_contact=$4, location=$5, tin=$6, installer_name=$7, installer_phone=$8,
       job_id=coalesce($9,job_id), lines=$10, total=$11, updated_at=now() where id=$1 returning *`,
    [old.id, s(b.title, 200), s(b.client_name, 120), s(b.client_contact, 80), s(b.location, 200), s(b.tin, 40), s(b.installer_name, 160), s(b.installer_phone, 40),
      b.job_id || null, JSON.stringify(lines), total]).catch(() => null);
  if (!r) return fail(res, 400, 'bad_request');
  // Prices this Fundi changed stay private to them: they become their own default prices for new BOQs.
  const master = new Map((await masterRows()).map((m) => [m.id, m.rate]));
  for (const l of lines) {
    if (!l.item_id || !master.has(l.item_id) || !priced(l.kind)) continue;
    if (Math.abs(Number(l.rate) - Number(master.get(l.item_id))) > 0.001) {
      await q('insert into boq_user_rates(user_id,item_id,rate) values($1,$2,$3) on conflict(user_id,item_id) do update set rate=$3', [req.user.id, l.item_id, l.rate]);
    } else {
      await q('delete from boq_user_rates where user_id=$1 and item_id=$2', [req.user.id, l.item_id]);
    }
  }
  res.json(out(r));
}));

router.delete('/:id', asyncH(async (req, res) => {
  const b = await q1('select * from boqs where id=$1', [req.params.id]).catch(() => null);
  if (!b || !(b.owner_id === req.user.id || req.user.role === 'admin')) return fail(res, 404, 'not_found');
  await q('delete from boqs where id=$1', [b.id]);
  res.json({ ok: true });
}));

// Download as PDF or Excel (with the SmartFundi logo and watermark). The app opens this link with the sign-in token.
router.get('/:id/export', asyncH(async (req, res) => {
  const b = await getBoq(req, res); if (!b) return;
  const fmt = req.query.format === 'xlsx' ? 'xlsx' : 'pdf';
  const safe = String(b.title || 'BOQ').replace(/[^A-Za-z0-9]+/g, '_').slice(0, 40) || 'BOQ';
  const name = `SmartFundi_${safe}_${String(b.id).slice(0, 6)}.${fmt}`;
  const doc = { ...b, lines: Array.isArray(b.lines) ? b.lines : [] };
  const buf = fmt === 'xlsx' ? await buildXlsx(doc) : await buildPdf(doc);
  res.set('Content-Type', fmt === 'xlsx' ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' : 'application/pdf');
  res.set('Content-Disposition', `attachment; filename="${name}"`);
  res.send(buf);
}));

module.exports = router;
