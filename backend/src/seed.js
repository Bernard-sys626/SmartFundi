const { q, q1 } = require('./db');
const { normId, getSetting, setSetting } = require('./util');

const REGIONS = ['Arusha','Dar es Salaam','Dodoma','Geita','Iringa','Kagera','Katavi','Kigoma','Kilimanjaro','Lindi','Manyara','Mara','Mbeya','Morogoro','Mtwara','Mwanza','Njombe','Pemba Kaskazini','Pemba Kusini','Pwani','Rukwa','Ruvuma','Shinyanga','Simiyu','Singida','Songwe','Tabora','Tanga','Unguja Kaskazini','Unguja Kusini','Unguja Mjini Magharibi'];
// SAMPLE location data. The full official list of districts and wards must be imported
// by the Admin (More > Locations > Import) or through POST /api/admin/locations/import.
const SAMPLE = {
  Mbeya: { 'Mbeya Jiji': ['Iyela','Isanga','Itezi','Ilemi','Ruanda','Forest','Maanga','Iganzo','Nsalaga','Mwakibete'], 'Mbeya Vijijini': [], Rungwe: [], Kyela: [], Chunya: [], Mbarali: [], Busokelo: [] },
  Mwanza: { Nyamagana: ['Igogo','Mirongo','Pamba','Mkuyuni','Mahina','Butimba','Isamilo'], Ilemela: ['Buswelu','Pasiansi','Nyamanoro','Bugogwa','Kirumba','Kitangiri'], Magu: ['Kisesa'], Kwimba: [], Misungwi: [], Sengerema: [], Ukerewe: [], Buchosa: [] },
  'Dar es Salaam': { Ilala: [], Kinondoni: [], Temeke: [], Kigamboni: [], Ubungo: [] },
  Dodoma: { 'Dodoma Jiji': [] },
  Arusha: { 'Arusha Jiji': [] },
};
const ACTIVE = new Set(['Mbeya', 'Mwanza']);
const SERVICES = [
  ['fault_repair', 'Ukarabati wa hitilafu za umeme', 'Electrical fault diagnosis and repair', 'Diagnostic et réparation de pannes électriques'],
  ['wiring', 'Wiring wa nyumba na majengo', 'House and building wiring installation', 'Câblage de maisons et de bâtiments'],
  ['cctv', 'Kamera za CCTV (ufungaji na matengenezo)', 'CCTV camera installation and maintenance', 'Installation et maintenance de caméras CCTV'],
  ['electric_fence', 'Uzio wa umeme', 'Electric fence installation', 'Installation de clôture électrique'],
  ['gate_motor', 'Ufungaji wa motor ya geti', 'Gate motor installation', 'Installation de moteur de portail'],
  ['motor', 'Ufungaji na rewinding wa motor', 'Motor installation and rewinding', 'Installation et rebobinage de moteurs'],
  ['other', 'Huduma nyingine za umeme', 'Other related electrical services', 'Autres services électriques'],
];

async function importRows(rows) {
  let n = 0;
  for (const r of rows) {
    if (!r.region || !r.district) continue;
    const reg = await q1('insert into regions(name) values($1) on conflict(name) do update set name=excluded.name returning id', [r.region.trim()]);
    const dis = await q1('insert into districts(region_id,name) values($1,$2) on conflict(region_id,name) do update set name=excluded.name returning id', [reg.id, r.district.trim()]);
    if (r.ward) await q('insert into wards(district_id,name) values($1,$2) on conflict do nothing', [dis.id, r.ward.trim()]);
    n++;
  }
  return n;
}

async function seed() {
  for (const r of REGIONS) await q('insert into regions(name,active) values($1,$2) on conflict(name) do nothing', [r, ACTIVE.has(r)]);
  const hasDistricts = await q1('select count(*)::int c from districts');
  if (!hasDistricts.c) {
    for (const [reg, ds] of Object.entries(SAMPLE)) {
      const r = await q1('select id from regions where name=$1', [reg]);
      for (const [d, wards] of Object.entries(ds)) {
        const dr = await q1('insert into districts(region_id,name,active) values($1,$2,$3) on conflict do nothing returning id', [r.id, d, ACTIVE.has(reg)]);
        if (!dr) continue;
        for (const w of wards) await q('insert into wards(district_id,name) values($1,$2) on conflict do nothing', [dr.id, w]);
      }
    }
  }
  let i = 0;
  for (const [key, sw, en, fr] of SERVICES) {
    await q('insert into services(key,name_sw,name_en,name_fr,sort) values($1,$2,$3,$4,$5) on conflict(key) do nothing', [key, sw, en, fr, i++]);
  }
  if ((await getSetting('commission_percent', null)) === null) await setSetting('commission_percent', 20);
  if ((await getSetting('payment_methods', null)) === null) await setSetting('payment_methods', { mobile_money: true, bank: true, lipa_namba: true });
  if ((await getSetting('about', null)) === null) {
    await setSetting('about', {
      app_name: 'SmartFundi',
      partner: 'G TECH ELECTRICAL SERVICES',
      location: 'Mbeya',
      po_box: '131, Mbeya',
      phones: ['+255 740 586 160', '+255 613 936 160'],
    });
  }
  if ((await getSetting('landing_url', null)) === null) await setSetting('landing_url', process.env.LANDING_URL || '');

  const phones = (process.env.ADMIN_PHONES || '+255740586160,+255613936160').split(',').map((s) => normId(s)).filter(Boolean);
  let first = true;
  for (const p of phones) {
    await q(
      `insert into users(role,is_main_admin,name,phone,language) values('admin',$2,'Admin',$1,'sw')
       on conflict(phone) do update set role='admin', is_main_admin = users.is_main_admin OR $2`,
      [p.value, first]
    );
    first = false;
  }
}
module.exports = { seed, importRows };
