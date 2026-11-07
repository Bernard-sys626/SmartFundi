const router = require('express').Router();
const { q1 } = require('../db');
const { asyncH, fail, auth } = require('../util');
const { confirmPayment } = require('./jobs');

const SVC = { sw: 'name_sw', en: 'name_en', fr: 'name_fr' };

router.get('/:id/receipt', auth, asyncH(async (req, res) => {
  const p = await q1('select * from payments where id=$1', [req.params.id]).catch(() => null);
  if (!p) return fail(res, 404, 'not_found');
  const j = await q1(
    `select j.*, s.name_sw,s.name_en,s.name_fr, r.name region_name, d.name district_name, w.name ward_name
     from jobs j left join services s on s.id=j.service_id left join regions r on r.id=j.region_id
     left join districts d on d.id=j.district_id left join wards w on w.id=j.ward_id where j.id=$1`, [p.job_id]);
  const u = req.user;
  if (!(u.role === 'admin' || j.client_id === u.id || j.fundi_id === u.id)) return fail(res, 404, 'not_found');
  const client = await q1('select name,phone from users where id=$1', [j.client_id]);
  const fundi = j.fundi_id ? await q1('select name,phone,company_name from users where id=$1', [j.fundi_id]) : null;
  const qt = await q1('select amount from quotations where job_id=$1', [j.id]);
  const sums = await q1(`select coalesce(sum(amount),0) s from payments where job_id=$1 and status='success'`, [j.id]);
  res.json({
    receipt_no: p.reference, payment_id: p.id, status: p.status, method: p.method,
    client_name: client.name || client.phone, client_phone: client.phone,
    amount_paid: Number(p.amount), total_paid: Number(sums.s), quoted: qt ? Number(qt.amount) : null,
    balance: qt ? Math.max(Number(qt.amount) - Number(sums.s), 0) : null,
    fundi_name: fundi ? fundi.company_name || fundi.name : null, fundi_phone: fundi ? fundi.phone : null,
    service_name: j[SVC[u.language] || 'name_sw'], job_code: j.code,
    location: [j.ward_name, j.district_name, j.region_name].filter(Boolean).join(', '),
    paid_at: p.confirmed_at || p.created_at,
  });
}));

// Generic webhook for a payment aggregator (Mobile Money / Lipa Namba / Bank gateway).
// Configure PAYMENT_WEBHOOK_SECRET and make your provider call this endpoint.
router.post('/webhook', asyncH(async (req, res) => {
  const secret = process.env.PAYMENT_WEBHOOK_SECRET;
  if (!secret || req.headers['x-webhook-secret'] !== secret) return fail(res, 401, 'unauthorized');
  const p = await q1('select * from payments where reference=$1', [req.body.reference]);
  if (!p) return fail(res, 404, 'not_found');
  if (req.body.status === 'success') await confirmPayment(p.id);
  else if (req.body.status === 'failed') await require('../db').q("update payments set status='failed' where id=$1 and status='pending'", [p.id]);
  res.json({ ok: true });
}));

module.exports = router;
