const router = require('express').Router();
const multer = require('multer');
const sharp = require('sharp');
const { q, q1 } = require('../db');
const { asyncH, fail, auth, getSetting } = require('../util');

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 12 * 1024 * 1024 } });
const DOC_EXT = ['pdf', 'doc', 'docx', 'xls', 'xlsx'];
const DOC_MIME = {
  pdf: 'application/pdf', doc: 'application/msword', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xls: 'application/vnd.ms-excel', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

/// Converts any picture (JPG, PNG, HEIC, a file without extension...) to a WebP of at most 1600 px.
/// Returns null when the data is not a picture.
async function toWebp(buf) {
  try {
    return await sharp(buf).rotate().resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true }).webp({ quality: 82 }).toBuffer();
  } catch (e) {
    return null;
  }
}

router.get('/config', asyncH(async (req, res) => {
  res.json({
    commission_percent: Number(await getSetting('commission_percent', 20)),
    payment_methods: await getSetting('payment_methods', {}),
    payment_accounts: await getSetting('payment_accounts', []),
    about: await getSetting('about', {}),
    landing_url: await getSetting('landing_url', ''),
  });
}));

router.get('/locations/regions', asyncH(async (req, res) => res.json(await q('select id,name,active from regions order by name'))));
router.get('/locations/districts', asyncH(async (req, res) =>
  res.json(await q('select id,region_id,name,active from districts where region_id=$1 order by name', [req.query.region_id || 0]))));
router.get('/locations/wards', asyncH(async (req, res) =>
  res.json(await q('select id,district_id,name from wards where district_id=$1 order by name', [req.query.district_id || 0]))));
router.get('/services', asyncH(async (req, res) =>
  res.json(await q('select id,trade,key,category_id,name_sw,name_en,name_fr,active from services where active order by sort,id'))));
router.get('/categories', asyncH(async (req, res) =>
  res.json(await q('select id,key,icon,name_sw,name_en,name_fr,active from categories where active order by sort,id'))));

// Pictures and short videos shown on the Home page and in the Help pages (uploaded by the Admin).
router.get('/media', auth, asyncH(async (req, res) => {
  const placement = ['home', 'help_client', 'help_fundi'].includes(req.query.placement) ? req.query.placement : 'home';
  res.json(await q('select id,kind,file_id,title from media where active and placement=$1 order by sort,id', [placement]));
}));

router.post('/files', auth, upload.single('file'), asyncH(async (req, res) => {
  const f = req.file;
  if (!f) return fail(res, 400, 'no_file');
  const ext = (f.originalname.split('.').pop() || '').toLowerCase();
  let data = f.buffer, mime = f.mimetype, name = f.originalname;
  if (DOC_EXT.includes(ext)) {
    mime = DOC_MIME[ext];
  } else {
    // Anything else must be a picture. The content is checked, not only the name or the type the phone
    // reports (camera and gallery files often have no extension or a generic type).
    const out = await toWebp(f.buffer);
    if (!out) return fail(res, 400, mime && mime.startsWith('image/') ? 'bad_image' : 'bad_file_type');
    data = out;
    mime = 'image/webp';
    name = (name.replace(/\.[^.]+$/, '') || 'photo') + '.webp';
  }
  const r = await q1('insert into files(owner_id,name,mime,data) values($1,$2,$3,$4) returning id,name,mime', [req.user.id, name, mime, data]);
  res.json(r);
}));

// Small cache of resized pictures so list screens do not download full size photos.
const thumbs = new Map();
router.get('/files/:id', auth, asyncH(async (req, res) => {
  const f = await q1('select name,mime,data from files where id=$1', [req.params.id]).catch(() => null);
  if (!f) return fail(res, 404, 'not_found');
  res.set('Cache-Control', 'private, max-age=604800');
  res.set('Content-Disposition', `inline; filename="${encodeURIComponent(f.name || 'file')}"`);
  const w = Math.min(Number(req.query.w) || 0, 1200);
  if (w > 0 && f.mime.startsWith('image/')) {
    const key = req.params.id + ':' + w;
    let t = thumbs.get(key);
    if (!t) {
      try {
        t = await sharp(f.data).resize({ width: w, height: w, fit: 'inside', withoutEnlargement: true }).webp({ quality: 75 }).toBuffer();
      } catch (e) {
        t = f.data;
      }
      if (thumbs.size > 300) thumbs.delete(thumbs.keys().next().value);
      thumbs.set(key, t);
    }
    res.set('Content-Type', 'image/webp');
    return res.send(t);
  }
  res.set('Content-Type', f.mime);
  res.set('Accept-Ranges', 'bytes');
  // Range requests, so that phones can play and seek short videos.
  const m = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
  if (m && (m[1] || m[2])) {
    const size = f.data.length;
    let start = m[1] ? parseInt(m[1], 10) : size - parseInt(m[2], 10);
    let end = m[1] && m[2] ? parseInt(m[2], 10) : size - 1;
    if (start < 0) start = 0;
    if (end >= size) end = size - 1;
    if (start > end) {
      res.status(416).set('Content-Range', `bytes */${size}`);
      return res.end();
    }
    res.status(206).set('Content-Range', `bytes ${start}-${end}/${size}`).set('Content-Length', String(end - start + 1));
    return res.end(f.data.subarray(start, end + 1));
  }
  res.send(f.data);
}));

router.get('/notifications', auth, asyncH(async (req, res) => {
  const items = await q('select id,title,body,job_id,read,created_at from notifications where user_id=$1 order by id desc limit 100', [req.user.id]);
  res.json({ items, unread: items.filter((n) => !n.read).length });
}));
router.get('/notifications/unread-count', auth, asyncH(async (req, res) => {
  const r = await q1('select count(*)::int c from notifications where user_id=$1 and not read', [req.user.id]);
  res.json({ unread: r.c });
}));
router.post('/notifications/read-all', auth, asyncH(async (req, res) => {
  await q('update notifications set read=true where user_id=$1', [req.user.id]);
  res.json({ ok: true });
}));

module.exports = router;
module.exports.toWebp = toWebp;
