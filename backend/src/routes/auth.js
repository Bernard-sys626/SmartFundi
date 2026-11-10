const router = require('express').Router();
const rateLimit = require('express-rate-limit');
const { q, q1 } = require('../db');
const { asyncH, fail, sign, auth, notify, normId, normUsername, validUsername, validPassword, hashPassword, checkPassword } = require('../util');

const MAXR = Number(process.env.RATE_LIMIT_MAX || 10);
const limiter = rateLimit({ windowMs: 60 * 1000, max: MAXR, standardHeaders: true, legacyHeaders: false });
const LANGS = ['sw', 'en', 'fr'];

// There are no verification codes any more:
//  * Client  : name + phone number (+ area), straight from the "Client" button.
//  * Fundi / Company: sets a username and password the first time, then signs in with them on any phone.
//  * Admin   : signs in with username and password in the Admin app (default created at startup, see seed.js).

// Client: one tap, fill in the details and go. The phone number identifies the client, so the same
// number on another phone opens the same account.
router.post('/client-start', limiter, asyncH(async (req, res) => {
  if (req.body.app === 'admin') return fail(res, 403, 'not_admin');
  const b = req.body;
  const id = normId(b.phone);
  if (!id || id.type !== 'phone') return fail(res, 400, 'invalid_phone');
  const name = String(b.name || '').trim();
  if (!name) return fail(res, 400, 'name_required');
  const lang = LANGS.includes(b.language) ? b.language : 'sw';
  let u = await q1('select * from users where phone=$1', [id.value]);
  let isNew = false;
  if (u) {
    if (u.role === 'admin') return fail(res, 403, 'use_admin_app');
    if (u.role !== 'client') return fail(res, 409, 'phone_in_use');
    if (u.blocked) return fail(res, 403, 'blocked');
    u = await q1(
      `update users set name=$2, language=$3, region_id=coalesce($4,region_id), district_id=coalesce($5,district_id), ward_id=coalesce($6,ward_id) where id=$1 returning *`,
      [u.id, name, lang, b.region_id ?? null, b.district_id ?? null, b.ward_id ?? null]
    );
  } else {
    isNew = true;
    u = await q1(
      `insert into users(role,phone,name,language,region_id,district_id,ward_id) values('client',$1,$2,$3,$4,$5,$6) returning *`,
      [id.value, name, lang, b.region_id ?? null, b.district_id ?? null, b.ward_id ?? null]
    );
  }
  res.json({ token: sign(u.id), is_new: isNew, user: await userOut(u) });
}));

// Fundi / Company: first time only. Chooses a username and password.
router.post('/register', limiter, asyncH(async (req, res) => {
  if (req.body.app === 'admin') return fail(res, 403, 'not_admin');
  const username = normUsername(req.body.username);
  if (!validUsername(username)) return fail(res, 400, 'invalid_username');
  if (!validPassword(req.body.password)) return fail(res, 400, 'weak_password');
  const lang = LANGS.includes(req.body.language) ? req.body.language : 'sw';
  // The phone number is needed to recognise the Fundi when the password is forgotten.
  const ph = normId(req.body.phone);
  if (!ph || ph.type !== 'phone') return fail(res, 400, 'invalid_phone');
  if (await q1('select 1 x from users where lower(username)=$1', [username])) return fail(res, 409, 'username_taken');
  if (await q1('select 1 x from users where phone=$1', [ph.value])) return fail(res, 409, 'phone_in_use');
  let u;
  try {
    u = await q1(
      `insert into users(role,username,password_hash,phone,language,fundi_status) values('fundi',$1,$2,$3,$4,'incomplete') returning *`,
      [username, hashPassword(req.body.password), ph.value, lang]
    );
  } catch (e) {
    if (e.code === '23505') return fail(res, 409, e.constraint && e.constraint.includes('phone') ? 'phone_in_use' : 'username_taken');
    throw e;
  }
  res.json({ token: sign(u.id), is_new: true, user: await userOut(u) });
}));

// Fundi / Company / Admin: sign in with the saved username and password (any phone).
router.post('/login', limiter, asyncH(async (req, res) => {
  const username = normUsername(req.body.username);
  const u = username ? await q1('select * from users where lower(username)=$1', [username]) : null;
  if (!u || !checkPassword(req.body.password, u.password_hash)) return fail(res, 401, 'invalid_credentials');
  if (req.body.app === 'admin' && u.role !== 'admin') return fail(res, 403, 'not_admin');
  if (req.body.app !== 'admin' && u.role === 'admin') return fail(res, 403, 'use_admin_app');
  if (u.blocked) return fail(res, 403, 'blocked');
  res.json({ token: sign(u.id), is_new: false, user: await userOut(u) });
}));

// Fundi forgot the password: the registered phone number files a request that every Admin sees.
// An Admin then sets a temporary password (Admin app > Fundi > "Set new password") and the Fundi
// must choose their own at the next sign-in. Always answers ok so numbers cannot be probed.
router.post('/forgot', limiter, asyncH(async (req, res) => {
  const ph = normId(req.body.phone);
  if (ph && ph.type === 'phone') {
    const u = await q1(`select id,name,company_name,phone from users where phone=$1 and role='fundi'`, [ph.value]);
    if (u) {
      await q('update users set reset_requested_at=now() where id=$1', [u.id]);
      for (const a of await q(`select id from users where role='admin'`)) {
        await notify(a.id, 'reset_request', { name: u.company_name || u.name || u.phone, phone: u.phone }).catch(() => {});
      }
    }
  }
  res.json({ ok: true });
}));

// After an Admin reset the Fundi must replace the temporary password straight away.
router.post('/set-password', auth, limiter, asyncH(async (req, res) => {
  if (!req.user.must_change_password) return fail(res, 400, 'bad_request');
  if (!validPassword(req.body.password)) return fail(res, 400, 'weak_password');
  const u = await q1('update users set password_hash=$2, must_change_password=false, reset_requested_at=null where id=$1 returning *', [req.user.id, hashPassword(req.body.password)]);
  res.json({ user: await userOut(u) });
}));

// Change own username / password (used by the admin in Settings). Needs the current password.
router.put('/credentials', auth, limiter, asyncH(async (req, res) => {
  const u = req.user, b = req.body;
  if (!checkPassword(b.current_password, u.password_hash)) return fail(res, 403, 'wrong_password');
  const username = b.username != null && String(b.username).trim() ? normUsername(b.username) : u.username;
  if (!validUsername(username)) return fail(res, 400, 'invalid_username');
  const hash = b.password ? (validPassword(b.password) ? hashPassword(b.password) : null) : u.password_hash;
  if (!hash) return fail(res, 400, 'weak_password');
  try {
    await q('update users set username=$2, password_hash=$3, must_change_password=false where id=$1', [u.id, username, hash]);
  } catch (e) {
    if (e.code === '23505') return fail(res, 409, 'username_taken');
    throw e;
  }
  res.json({ ok: true, username });
}));

async function userOut(u) {
  return {
    id: u.id, role: u.role, is_main_admin: u.is_main_admin, name: u.name, username: u.username, phone: u.phone, email: u.email,
    language: u.language, region_id: u.region_id, district_id: u.district_id, ward_id: u.ward_id,
    photo_file_id: u.photo_file_id, fundi_type: u.fundi_type, company_name: u.company_name,
    fundi_status: u.fundi_status, reject_reason: u.reject_reason, must_change_password: !!u.must_change_password,
  };
}

router.get('/me', auth, asyncH(async (req, res) => res.json({ user: await userOut(req.user) })));
router.put('/me', auth, asyncH(async (req, res) => {
  const b = req.body, u = req.user;
  const lang = LANGS.includes(b.language) ? b.language : u.language;
  const r = await q1(
    `update users set name=coalesce($2,name), language=$3, region_id=coalesce($4,region_id), district_id=coalesce($5,district_id),
     ward_id=coalesce($6,ward_id), fcm_token=coalesce($7,fcm_token), photo_file_id=coalesce($8,photo_file_id) where id=$1 returning *`,
    [u.id, b.name ? String(b.name).trim() : null, lang, b.region_id ?? null, b.district_id ?? null, b.ward_id ?? null, b.fcm_token ?? null, b.photo_file_id ?? null]
  );
  res.json({ user: await userOut(r) });
}));

module.exports = { router, userOut };
