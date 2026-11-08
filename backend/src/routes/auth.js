const router = require('express').Router();
const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const { q, q1 } = require('../db');
const { asyncH, fail, sign, auth, normId } = require('../util');

const SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';
const hash = (c) => crypto.createHash('sha256').update(c + SECRET).digest('hex');
const MAXR = Number(process.env.RATE_LIMIT_MAX || 10);
const limiter = rateLimit({ windowMs: 60 * 1000, max: MAXR, standardHeaders: true, legacyHeaders: false });
const verifyLimiter = rateLimit({ windowMs: 60 * 1000, max: MAXR * 2, standardHeaders: true, legacyHeaders: false });

// Returns true when the code was handed to a provider. Throws when delivery fails.
async function sendOtp(id, code) {
  const text = `SmartFundi: code yako ni ${code}. Your code is ${code}. Valid for 10 minutes.`;
  if (id.type === 'email') {
    if (!process.env.SMTP_URL) return false;
    const mailer = require('nodemailer').createTransport(process.env.SMTP_URL);
    await mailer.sendMail({ from: process.env.MAIL_FROM || 'SmartFundi <no-reply@smartfundi.app>', to: id.value, subject: 'SmartFundi verification code', text });
    return true;
  }
  if (!process.env.BEEM_API_KEY) return false;
  const r = await fetch('https://apisms.beem.africa/v1/send', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Basic ' + Buffer.from(`${process.env.BEEM_API_KEY}:${process.env.BEEM_SECRET}`).toString('base64'),
    },
    body: JSON.stringify({
      source_addr: process.env.BEEM_SENDER || 'SmartFundi',
      schedule_time: '',
      encoding: 0,
      message: text,
      recipients: [{ recipient_id: 1, dest_addr: id.value.replace('+', '') }],
    }),
  });
  if (!r.ok) throw new Error('sms provider replied ' + r.status);
  return true;
}

// The Client/Fundi app and the Admin app are separate apps. Admin phones must not log in to the
// main app, and the Admin app must never create accounts.
async function gate(res, id, app) {
  const col = id.type === 'email' ? 'email' : 'phone';
  const u = await q1(`select role from users where ${col}=$1`, [id.value]);
  if (app === 'admin' && (!u || u.role !== 'admin')) { fail(res, 403, 'not_admin'); return false; }
  if (app !== 'admin' && u && u.role === 'admin') { fail(res, 403, 'use_admin_app'); return false; }
  return true;
}

router.post('/request-otp', limiter, asyncH(async (req, res) => {
  const id = normId(req.body.identifier);
  if (!id) return fail(res, 400, 'invalid_identifier');
  if (!(await gate(res, id, req.body.app))) return;
  const code = String(crypto.randomInt(100000, 1000000));
  await q(
    `insert into otps(identifier,code_hash,expires_at,attempts) values($1,$2,now()+interval '10 minutes',0)
     on conflict(identifier) do update set code_hash=$2, expires_at=now()+interval '10 minutes', attempts=0`,
    [id.value, hash(code)]
  );
  const dev = process.env.DEV_OTP === 'true';
  let delivered = false;
  try {
    delivered = await sendOtp(id, code);
  } catch (e) {
    console.error('[OTP] delivery failed:', e.message);
    if (!dev) return fail(res, 502, 'otp_send_failed');
  }
  if (!delivered && !dev) {
    console.error(`[OTP] no SMS/email provider configured, code for ${id.value} was NOT delivered`);
    return fail(res, 503, 'otp_unavailable');
  }
  res.json({ ok: true, ...(dev ? { dev_code: code } : {}) });
}));

router.post('/verify-otp', verifyLimiter, asyncH(async (req, res) => {
  const id = normId(req.body.identifier);
  const code = String(req.body.code || '');
  if (!id) return fail(res, 400, 'invalid_identifier');
  if (!(await gate(res, id, req.body.app))) return;
  const o = await q1('select * from otps where identifier=$1', [id.value]);
  if (!o || new Date(o.expires_at) < new Date()) return fail(res, 400, 'code_expired');
  if (o.attempts >= 5) return fail(res, 429, 'too_many_attempts');
  if (o.code_hash !== hash(code)) {
    await q('update otps set attempts=attempts+1 where identifier=$1', [id.value]);
    return fail(res, 400, 'invalid_code');
  }
  await q('delete from otps where identifier=$1', [id.value]);
  const col = id.type === 'email' ? 'email' : 'phone';
  let u = await q1(`select * from users where ${col}=$1`, [id.value]);
  let isNew = false;
  if (!u) {
    isNew = true;
    const intent = req.body.intent === 'fundi' ? 'fundi' : 'client';
    const lang = ['sw', 'en', 'fr'].includes(req.body.language) ? req.body.language : 'sw';
    u = await q1(
      `insert into users(role,${col},name,language,fundi_status) values($1,$2,$3,$4,$5) returning *`,
      [intent, id.value, (req.body.name || '').trim() || null, lang, intent === 'fundi' ? 'incomplete' : null]
    );
  }
  res.json({ token: sign(u.id), is_new: isNew, user: await userOut(u) });
}));

async function userOut(u) {
  return {
    id: u.id, role: u.role, is_main_admin: u.is_main_admin, name: u.name, phone: u.phone, email: u.email,
    language: u.language, region_id: u.region_id, district_id: u.district_id, ward_id: u.ward_id,
    photo_file_id: u.photo_file_id, fundi_type: u.fundi_type, company_name: u.company_name,
    fundi_status: u.fundi_status, reject_reason: u.reject_reason,
  };
}

router.get('/me', auth, asyncH(async (req, res) => res.json({ user: await userOut(req.user) })));
router.put('/me', auth, asyncH(async (req, res) => {
  const b = req.body, u = req.user;
  const lang = ['sw', 'en', 'fr'].includes(b.language) ? b.language : u.language;
  const r = await q1(
    `update users set name=coalesce($2,name), language=$3, region_id=coalesce($4,region_id), district_id=coalesce($5,district_id),
     ward_id=coalesce($6,ward_id), fcm_token=coalesce($7,fcm_token), photo_file_id=coalesce($8,photo_file_id) where id=$1 returning *`,
    [u.id, b.name ? String(b.name).trim() : null, lang, b.region_id ?? null, b.district_id ?? null, b.ward_id ?? null, b.fcm_token ?? null, b.photo_file_id ?? null]
  );
  res.json({ user: await userOut(r) });
}));

module.exports = { router, userOut };
