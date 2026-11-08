const jwt = require('jsonwebtoken');
const { q, q1 } = require('./db');
const SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';

const asyncH = (fn) => (req, res, next) =>
  Promise.resolve(fn(req, res, next)).catch((e) => {
    console.error(e);
    if (!res.headersSent) res.status(500).json({ error: 'server' });
  });
const fail = (res, status, error, extra = {}) => res.status(status).json({ error, ...extra });
const sign = (id) => jwt.sign({ id }, SECRET, { expiresIn: '60d' });

async function auth(req, res, next) {
  try {
    let t = (req.headers.authorization || '').replace('Bearer ', '');
    if (!t && req.query.token) t = req.query.token;
    if (!t) return fail(res, 401, 'unauthorized');
    const { id } = jwt.verify(t, SECRET);
    const u = await q1('select * from users where id=$1', [id]);
    if (!u) return fail(res, 401, 'unauthorized');
    if (u.blocked) return fail(res, 403, 'blocked');
    req.user = u;
    next();
  } catch (e) {
    fail(res, 401, 'unauthorized');
  }
}
const role = (...rs) => (req, res, next) => (rs.includes(req.user.role) ? next() : fail(res, 403, 'forbidden'));
const mainAdmin = (req, res, next) =>
  req.user.role === 'admin' && req.user.is_main_admin ? next() : fail(res, 403, 'forbidden');

function normId(raw) {
  if (!raw) return null;
  const s = String(raw).trim();
  if (s.includes('@')) {
    const v = s.toLowerCase();
    return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v) ? { type: 'email', value: v } : null;
  }
  let d = s.replace(/[^\d+]/g, '');
  if (d.startsWith('+')) d = d.slice(1);
  if (d.startsWith('0')) d = '255' + d.slice(1);
  if (/^255\d{9}$/.test(d)) return { type: 'phone', value: '+' + d };
  if (/^\d{8,15}$/.test(d)) return { type: 'phone', value: '+' + d };
  return null;
}
function haversine(lat1, lon1, lat2, lon2) {
  const R = 6371000, rad = (x) => (x * Math.PI) / 180;
  const dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
async function getSetting(key, dflt) {
  const r = await q1('select value from settings where key=$1', [key]);
  return r ? r.value : dflt;
}
async function setSetting(key, value) {
  await q('insert into settings(key,value) values($1,$2) on conflict(key) do update set value=$2', [key, JSON.stringify(value)]);
}

// ---------- notifications ----------
const TXT = {
  sw: {
    job_accepted: ['Kazi imekubaliwa', '{name} amekubali kazi yako {code}.'],
    on_the_way: ['Fundi yuko njiani', '{name} yuko njiani kuja kwako (kazi {code}).'],
    arrived: ['Fundi amefika', '{name} amefika kwenye site yako. GPS imethibitisha.'],
    completed: ['Kazi imekamilika', 'Asante kwa kutumia SmartFundi. Kazi {code} imekamilika. Tafadhali kamilisha malipo kupitia app na utoe ukadiriaji.'],
    payment_ok: ['Malipo yamepokelewa', 'Tumepokea TSh {amount} kwa kazi {code}.'],
    payment_fundi: ['Malipo yamepokelewa', 'Mteja amelipa TSh {amount} kwa kazi {code}. Sehemu yako ni TSh {share}.'],
    new_job: ['Kazi mpya karibu nawe', 'Kuna kazi mpya ya {service} kwenye eneo lako.'],
    quotation: ['Gharama ya kazi imewekwa', 'Kiasi cha kulipa kwa kazi {code} ni TSh {amount}.'],
    cancelled: ['Kazi imeghairiwa', 'Kazi {code} imeghairiwa.'],
    cancelled_nauli: ['Kazi imeghairiwa', 'Kazi {code} imeghairiwa baada ya Fundi kufika. Mteja anatakiwa kulipa nauli (usafiri).'],
    reassigned: ['Umepangiwa kazi', 'Umepangiwa kazi {code} na Admin.'],
    approved: ['Usajili umekubaliwa', 'Akaunti yako imeidhinishwa. Sasa unaweza kupokea kazi.'],
    rejected: ['Usajili umekataliwa', 'Maombi yako hayakukubaliwa. {reason}'],
  },
  en: {
    job_accepted: ['Job accepted', '{name} accepted your job {code}.'],
    on_the_way: ['Fundi is on the way', '{name} is on the way to you (job {code}).'],
    arrived: ['Fundi has arrived', '{name} has arrived at your site. GPS confirmed.'],
    completed: ['Job completed', 'Thank you for using SmartFundi. Job {code} is completed. Please complete payment in the app and leave a rating.'],
    payment_ok: ['Payment received', 'We received TSh {amount} for job {code}.'],
    payment_fundi: ['Payment received', 'The client paid TSh {amount} for job {code}. Your share is TSh {share}.'],
    new_job: ['New job near you', 'There is a new {service} job in your area.'],
    quotation: ['Quotation added', 'The amount to pay for job {code} is TSh {amount}.'],
    cancelled: ['Job cancelled', 'Job {code} has been cancelled.'],
    cancelled_nauli: ['Job cancelled', 'Job {code} was cancelled after the Fundi arrived. The client must pay the transport fee (nauli).'],
    reassigned: ['Job assigned to you', 'Admin assigned job {code} to you.'],
    approved: ['Registration approved', 'Your account is approved. You can now receive jobs.'],
    rejected: ['Registration rejected', 'Your application was not approved. {reason}'],
  },
  fr: {
    job_accepted: ['Travail accepté', '{name} a accepté votre demande {code}.'],
    on_the_way: ['Le Fundi est en route', '{name} est en route vers vous (travail {code}).'],
    arrived: ['Le Fundi est arrivé', '{name} est arrivé sur votre site. GPS confirmé.'],
    completed: ['Travail terminé', 'Merci d\'utiliser SmartFundi. Le travail {code} est terminé. Veuillez payer dans l\'application et laisser une note.'],
    payment_ok: ['Paiement reçu', 'Nous avons reçu TSh {amount} pour le travail {code}.'],
    payment_fundi: ['Paiement reçu', 'Le client a payé TSh {amount} pour le travail {code}. Votre part est TSh {share}.'],
    new_job: ['Nouveau travail près de vous', 'Il y a un nouveau travail {service} dans votre zone.'],
    quotation: ['Devis ajouté', 'Le montant à payer pour le travail {code} est TSh {amount}.'],
    cancelled: ['Travail annulé', 'Le travail {code} a été annulé.'],
    cancelled_nauli: ['Travail annulé', 'Le travail {code} a été annulé après l\'arrivée du Fundi. Le client doit payer le transport (nauli).'],
    reassigned: ['Travail attribué', 'L\'admin vous a attribué le travail {code}.'],
    approved: ['Inscription approuvée', 'Votre compte est approuvé. Vous pouvez recevoir des travaux.'],
    rejected: ['Inscription refusée', 'Votre demande n\'a pas été acceptée. {reason}'],
  },
};
function render(lang, key, vars) {
  const set = TXT[lang] || TXT.sw;
  const [t, b] = set[key] || TXT.sw[key];
  const f = (s) => s.replace(/\{(\w+)\}/g, (_, k) => (vars[k] == null ? '' : vars[k]));
  return { title: f(t), body: f(b) };
}
let fcm = null;
function initFcm() {
  if (!process.env.FIREBASE_SERVICE_ACCOUNT) return;
  try {
    const admin = require('firebase-admin');
    const cred = JSON.parse(Buffer.from(process.env.FIREBASE_SERVICE_ACCOUNT, 'base64').toString());
    admin.initializeApp({ credential: admin.credential.cert(cred) });
    fcm = admin.messaging();
    console.log('FCM enabled');
  } catch (e) {
    console.error('FCM init failed:', e.message);
  }
}
async function notify(userId, key, vars = {}, jobId = null) {
  const u = await q1('select language,fcm_token from users where id=$1', [userId]);
  if (!u) return;
  const { title, body } = render(u.language, key, vars);
  await q('insert into notifications(user_id,title,body,job_id) values($1,$2,$3,$4)', [userId, title, body, jobId]);
  if (fcm && u.fcm_token) {
    fcm.send({ token: u.fcm_token, notification: { title, body }, data: { jobId: jobId || '' } }).catch(() => {});
  }
}
const money = (n) => Number(n).toLocaleString('en-US', { maximumFractionDigits: 0 });

module.exports = { asyncH, fail, sign, auth, role, mainAdmin, normId, haversine, getSetting, setSetting, notify, initFcm, money };
