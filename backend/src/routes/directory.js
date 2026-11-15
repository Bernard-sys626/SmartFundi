const router = require('express').Router();
const { q, q1 } = require('../db');
const { asyncH, fail, auth, role } = require('../util');

router.use(auth);

const SVC = { sw: 'name_sw', en: 'name_en', fr: 'name_fr' };

// Fundis and Companies a client can choose from. Filter by region, district and ward (each one optional),
// by category and by type. Approved accounts only. Phone numbers are not listed here: the client gets
// the full details of the chosen Fundi once the request is sent.
async function listFundis(req) {
  const b = req.query;
  const lang = SVC[req.user.language] || 'name_sw';
  const region = Number(b.region_id) || null, district = Number(b.district_id) || null, ward = Number(b.ward_id) || null;
  const category = Number(b.category_id) || null;
  const type = ['technician', 'company'].includes(b.type) ? b.type : null;
  const term = b.q ? '%' + String(b.q).trim() + '%' : null;
  const rows = await q(
    `select u.id, u.name, u.company_name, u.fundi_type, u.photo_file_id, u.experience, u.admin_rating,
       (select round(avg(r.rating)::numeric,1) from ratings r join jobs j on j.id=r.job_id where j.fundi_id=u.id) avg_rating,
       (select count(*)::int from jobs j where j.fundi_id=u.id and j.status='completed') completed,
       (select string_agg(distinct s.${lang}, ', ') from fundi_services fs join services s on s.id=fs.service_id where fs.user_id=u.id) services,
       (select string_agg(distinct c.${lang}, ', ') from fundi_categories fc join categories c on c.id=fc.category_id where fc.user_id=u.id) categories,
       (select string_agg(distinct coalesce(w.name || ', ', '') || d.name, ' | ') from fundi_areas a join districts d on d.id=a.district_id left join wards w on w.id=a.ward_id where a.user_id=u.id) areas
     from users u
     where u.role='fundi' and u.fundi_status='approved' and not coalesce(u.blocked,false)
       and ($1::int is null or exists(select 1 from fundi_areas a where a.user_id=u.id and a.region_id=$1))
       and ($2::int is null or exists(select 1 from fundi_areas a where a.user_id=u.id and a.district_id=$2))
       and ($3::int is null or exists(select 1 from fundi_areas a where a.user_id=u.id and (a.ward_id=$3 or (a.ward_id is null and a.district_id=(select district_id from wards where id=$3)))))
       and ($4::int is null or exists(select 1 from fundi_categories fc where fc.user_id=u.id and fc.category_id=$4))
       and ($5::text is null or u.fundi_type=$5)
       and ($6::text is null or u.name ilike $6 or u.company_name ilike $6)
     order by coalesce(u.admin_rating, 0) desc, u.created_at limit 80`,
    [region, district, ward, category, type, term]);
  return rows.map((r) => ({
    id: r.id, name: r.name, company_name: r.company_name, fundi_type: r.fundi_type, photo_file_id: r.photo_file_id, experience: r.experience,
    rating: { avg: r.admin_rating != null ? Number(r.admin_rating) : r.avg_rating ? Number(r.avg_rating) : null },
    completed: r.completed, services: r.services, categories: r.categories, areas: r.areas,
  }));
}

router.get('/fundis', role('client', 'admin'), asyncH(async (req, res) => res.json(await listFundis(req))));

router.get('/fundis/:id', role('client', 'admin'), asyncH(async (req, res) => {
  const f = (await listFundisOne(req, req.params.id));
  if (!f) return fail(res, 404, 'not_found');
  res.json(f);
}));

async function listFundisOne(req, id) {
  const lang = SVC[req.user.language] || 'name_sw';
  const u = await q1(
    `select u.id, u.name, u.company_name, u.fundi_type, u.photo_file_id, u.experience, u.admin_rating,
       (select round(avg(r.rating)::numeric,1) from ratings r join jobs j on j.id=r.job_id where j.fundi_id=u.id) avg_rating,
       (select count(*)::int from jobs j where j.fundi_id=u.id and j.status='completed') completed
     from users u where u.id=$1 and u.role='fundi' and u.fundi_status='approved'`, [id]).catch(() => null);
  if (!u) return null;
  const services = await q(`select s.id, s.${lang} name from fundi_services fs join services s on s.id=fs.service_id where fs.user_id=$1 order by s.sort`, [id]);
  const categories = await q(`select c.id, c.${lang} name from fundi_categories fc join categories c on c.id=fc.category_id where fc.user_id=$1 order by c.sort`, [id]);
  const areas = await q(
    `select r.name region_name, d.name district_name, w.name ward_name from fundi_areas a left join regions r on r.id=a.region_id
     left join districts d on d.id=a.district_id left join wards w on w.id=a.ward_id where a.user_id=$1`, [id]);
  return {
    id: u.id, name: u.name, company_name: u.company_name, fundi_type: u.fundi_type, photo_file_id: u.photo_file_id, experience: u.experience,
    rating: { avg: u.admin_rating != null ? Number(u.admin_rating) : u.avg_rating ? Number(u.avg_rating) : null },
    completed: u.completed, services, categories, areas,
  };
}

module.exports = router;
