const router = require('express').Router();
const multer = require('multer');
const sharp = require('sharp');
const { q, q1 } = require('../db');
const { asyncH, fail, auth, getSetting } = require('../util');

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 12 * 1024 * 1024 } });
const DOC_EXT = ['pdf', 'doc', 'docx', 'xls', 'xlsx'];

router.get('/config', asyncH(async (req, res) => {
  res.json({
    commission_percent: Number(await getSetting('commission_percent', 20)),
    payment_methods: await getSetting('payment_methods', {}),
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
  res.json(await q('select id,trade,key,name_sw,name_en,name_fr,active from services where active order by sort,id'))));

router.post('/files', auth, upload.single('file'), asyncH(async (req, res) => {
  const f = req.file;
  if (!f) return fail(res, 400, 'no_file');
  const ext = (f.originalname.split('.').pop() || '').toLowerCase();
  let data = f.buffer, mime = f.mimetype, name = f.originalname;
  if (mime.startsWith('image/')) {
    try {
      data = await sharp(f.buffer).rotate().resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true }).webp({ quality: 85 }).toBuffer();
      mime = 'image/webp';
      name = name.replace(/\.[^.]+$/, '') + '.webp';
    } catch (e) {
      return fail(res, 400, 'bad_image');
    }
  } else if (!DOC_EXT.includes(ext)) {
    return fail(res, 400, 'bad_file_type');
  }
  const r = await q1('insert into files(owner_id,name,mime,data) values($1,$2,$3,$4) returning id,name,mime', [req.user.id, name, mime, data]);
  res.json(r);
}));

router.get('/files/:id', auth, asyncH(async (req, res) => {
  const f = await q1('select name,mime,data from files where id=$1', [req.params.id]).catch(() => null);
  if (!f) return fail(res, 404, 'not_found');
  res.set('Content-Type', f.mime);
  res.set('Content-Disposition', `inline; filename="${encodeURIComponent(f.name || 'file')}"`);
  res.set('Cache-Control', 'private, max-age=86400');
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
