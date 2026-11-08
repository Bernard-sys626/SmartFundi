// End-to-end smoke test. Run with DEV_OTP=true PAYMENT_MODE=simulated while the server is running.
const sharp = require('sharp');
const B = process.env.API || 'http://localhost:8080/api';
let pass = 0, failN = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  ok  ', m); } else { failN++; console.log('  FAIL', m); } };
async function call(method, path, body, token, form) {
  const r = await fetch(B + path, {
    method, headers: { ...(form ? {} : body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: form || (body ? JSON.stringify(body) : undefined),
  });
  let j = null; try { j = await r.json(); } catch (e) {}
  return { s: r.status, j };
}
async function login(identifier, extra = {}) {
  const a = await call('POST', '/auth/request-otp', { identifier, app: extra.app });
  const r = await call('POST', '/auth/verify-otp', { identifier, code: a.j.dev_code, ...extra });
  return { token: r.j.token, user: r.j.user };
}
async function upload(token, name, buf, type) {
  const f = new FormData(); f.append('file', new Blob([buf], { type }), name);
  return (await call('POST', '/files', null, token, f)).j;
}
(async () => {
  const sfx = String(Date.now()).slice(-6);
  console.log('Auth and roles');
  const admin = await login('0740586160', { app: 'admin' });
  ok(admin.user.role === 'admin' && admin.user.is_main_admin, 'admin phone is detected automatically as main admin');
  const client = await login('07' + sfx + '11', { name: 'Asha Mteja' });
  ok(client.user.role === 'client', 'new user becomes client');
  const adminInMain = await call('POST', '/auth/request-otp', { identifier: '0740586160' });
  ok(adminInMain.s === 403 && adminInMain.j.error === 'use_admin_app', 'admin number is refused in the Client/Fundi app');
  const strangerInAdmin = await call('POST', '/auth/request-otp', { identifier: '0799' + sfx, app: 'admin' });
  ok(strangerInAdmin.s === 403 && strangerInAdmin.j.error === 'not_admin', 'unknown number is refused in the Admin app and no account is created');
  const bad = await call('POST', '/auth/verify-otp', { identifier: '0711000000', code: '000000' });
  ok(bad.s === 400, 'wrong OTP rejected');

  console.log('Config and locations');
  const cfg = await call('GET', '/config');
  ok(cfg.j.commission_percent === 20 && cfg.j.about.partner === 'G TECH ELECTRICAL SERVICES', 'config: 20% commission, About details');
  const regions = (await call('GET', '/locations/regions')).j;
  const mbeya = regions.find((r) => r.name === 'Mbeya');
  ok(regions.length === 31 && mbeya.active, '31 regions, Mbeya active');
  const districts = (await call('GET', `/locations/districts?region_id=${mbeya.id}`)).j;
  const dist = districts.find((d) => d.name === 'Mbeya Jiji');
  const wards = (await call('GET', `/locations/wards?district_id=${dist.id}`)).j;
  const services = (await call('GET', '/services')).j;
  ok(services.length >= 7, 'services seeded');
  const wiring = services.find((s) => s.key === 'wiring');
  const nonActive = regions.find((r) => r.name === 'Arusha');

  console.log('Fundi registration and approval');
  const fundi = await login('07' + sfx + '22', { intent: 'fundi', name: 'Juma Fundi' });
  ok(fundi.user.role === 'fundi' && fundi.user.fundi_status === 'incomplete', 'fundi account starts incomplete');
  const early = await call('GET', '/fundi/jobs/available', null, fundi.token);
  ok(early.s === 403, 'unapproved fundi cannot see jobs');
  const sub0 = await call('POST', '/fundi/submit', null, fundi.token);
  ok(sub0.s === 400 && sub0.j.missing.includes('photo') && sub0.j.missing.includes('services'), 'submit blocked until profile is complete');
  const png = await sharp({ create: { width: 3000, height: 2000, channels: 3, background: '#335' } }).png().toBuffer();
  const photo = await upload(fundi.token, 'me.png', png, 'image/png');
  ok(photo.mime === 'image/webp', 'images are converted to WebP');
  const idDoc = await upload(fundi.token, 'id.pdf', Buffer.from('%PDF-1.4 test'), 'application/pdf');
  const cert = await upload(fundi.token, 'cert.docx', Buffer.from('docx'), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
  const exe = await call('POST', '/files', null, fundi.token, (() => { const f = new FormData(); f.append('file', new Blob(['x']), 'a.exe'); return f; })());
  ok(exe.s === 400, 'unsupported file type rejected');
  await call('PUT', '/fundi/profile', { fundi_type: 'technician', name: 'Juma Fundi', photo_file_id: photo.id,
    areas: [{ region_id: mbeya.id, district_id: dist.id, ward_id: wards[0].id }, { region_id: mbeya.id, district_id: dist.id, ward_id: wards[1].id }],
    service_ids: [wiring.id] }, fundi.token);
  await call('POST', '/fundi/documents', { kind: 'national_id', file_id: idDoc.id, name: 'NIDA' }, fundi.token);
  await call('POST', '/fundi/documents', { kind: 'professional', file_id: cert.id, name: 'VETA' }, fundi.token);
  const sub = await call('POST', '/fundi/submit', null, fundi.token);
  ok(sub.j.user.fundi_status === 'pending', 'registration submitted, waiting for Admin');
  const pendingList = await call('GET', '/admin/fundis?status=pending', null, admin.token);
  ok(pendingList.j.some((f) => f.id === fundi.user.id), 'admin sees the application');
  const appr = await call('POST', `/admin/fundis/${fundi.user.id}/approve`, {}, admin.token);
  ok(appr.j.user.fundi_status === 'approved', 'admin approved the fundi');
  const manual = await call('POST', '/admin/fundis', { identifier: '07' + sfx + '33', name: 'Manual Fundi', fundi_type: 'technician',
    areas: [{ region_id: mbeya.id, district_id: dist.id }], service_ids: [wiring.id] }, admin.token);
  ok(manual.j.user.fundi_status === 'approved', 'admin can register a fundi manually');

  console.log('Client reports a problem');
  await call('PUT', '/auth/me', { region_id: mbeya.id, district_id: dist.id, ward_id: wards[0].id, language: 'sw' }, client.token);
  const jobPhoto = await upload(client.token, 'fault.png', png, 'image/png');
  const noGps = await call('POST', '/jobs', { service_id: wiring.id, preference: 'technician', description: 'Waya zimeungua' }, client.token);
  ok(noGps.s === 400 && noGps.j.error === 'location_required', 'GPS location is required');
  const arushaD = (await call('GET', `/locations/districts?region_id=${nonActive.id}`)).j[0];
  const bad2 = await call('POST', '/jobs', { service_id: wiring.id, description: 'x', lat: -8.9, lng: 33.45, region_id: nonActive.id, district_id: arushaD.id }, client.token);
  ok(bad2.j.error === 'area_not_available', 'area not yet available is blocked');
  const LAT = -8.9094, LNG = 33.4608;
  const job = (await call('POST', '/jobs', { service_id: wiring.id, preference: 'technician', description: 'Wiring ya nyumba mpya', notes: 'Karibu na soko',
    lat: LAT, lng: LNG, photo_ids: [jobPhoto.id] }, client.token)).j;
  if (!job.status) console.log(job);
  ok(job.status === 'pending' && job.code.startsWith('SF-') && job.photos.length === 1, 'job created as pending with photo');
  const fn1 = (await call('GET', '/notifications', null, fundi.token)).j;
  ok(fn1.items.some((n) => n.job_id === job.id), 'matching fundi was notified of the new job');
  const avail = (await call('GET', '/fundi/jobs/available', null, fundi.token)).j;
  ok(avail.length === 1 && !avail[0].client, 'fundi sees the job without client contact');
  const chatEarly = await call('GET', `/jobs/${job.id}/messages`, null, client.token);
  ok(chatEarly.s === 404, 'chat locked before a fundi accepts');

  console.log('Fundi works the job');
  const acc = await call('POST', `/fundi/jobs/${job.id}/accept`, null, fundi.token);
  ok(acc.j.status === 'accepted' && acc.j.client.phone, 'fundi accepted, client contact unlocked');
  const mf = await login('07' + sfx + '33');
  const acc2 = await call('POST', `/fundi/jobs/${job.id}/accept`, null, mf.token);
  ok(acc2.s === 409 || acc2.s === 403, 'other fundis cannot take an accepted job');
  const cn = (await call('GET', '/notifications', null, client.token)).j;
  ok(cn.items.some((n) => n.title.includes('Kazi imekubaliwa')), 'client notified: job accepted');
  await call('POST', `/jobs/${job.id}/messages`, { body: 'Habari, ninakuja' }, fundi.token);
  const msgs = (await call('GET', `/jobs/${job.id}/messages`, null, client.token)).j;
  ok(msgs.length === 1, 'in-app chat works');
  const otw = await call('POST', `/fundi/jobs/${job.id}/on-the-way`, null, fundi.token);
  ok(otw.j.status === 'on_the_way', 'status: on the way');
  const far = await call('POST', `/fundi/jobs/${job.id}/arrived`, { lat: LAT + 0.05, lng: LNG }, fundi.token);
  ok(far.s === 400 && far.j.error === 'too_far', 'GPS check rejects arrival from far away');
  const near = await call('POST', `/fundi/jobs/${job.id}/arrived`, { lat: LAT + 0.0005, lng: LNG }, fundi.token);
  ok(near.j.status === 'arrived', 'GPS check accepts arrival at the site');
  const early2 = await call('POST', `/fundi/jobs/${job.id}/complete`, null, fundi.token);
  ok(early2.s === 400, 'cannot complete before starting');
  const qt = await call('PUT', `/fundi/jobs/${job.id}/quotation`, { amount: 100000, includes_transport: true, note: 'Waya na kazi' }, fundi.token);
  ok(qt.j.quotation.amount === 100000 && qt.j.balance === 100000, 'quotation saved, balance equals quote');
  await call('POST', `/fundi/jobs/${job.id}/start`, null, fundi.token);
  const done = await call('POST', `/fundi/jobs/${job.id}/complete`, null, fundi.token);
  ok(done.j.status === 'completed', 'job completed');

  console.log('Payments, commission, receipt');
  const over = await call('POST', `/jobs/${job.id}/pay`, { amount: 200000, method: 'mobile_money' }, client.token);
  ok(over.j.error === 'amount_too_high', 'cannot overpay');
  const p1 = await call('POST', `/jobs/${job.id}/pay`, { amount: 40000, method: 'mobile_money', phone: '0700000000' }, client.token);
  ok(p1.j.job.payment_status === 'partial' && p1.j.job.balance === 60000, 'partial payment: balance still demanded (60,000)');
  ok(Number(p1.j.payment.platform_amount) === 8000 && Number(p1.j.payment.fundi_amount) === 32000, '20% / 80% split applied');
  await call('PUT', '/admin/settings', { commission_percent: 25 }, admin.token);
  const cfg2 = await call('GET', '/config');
  ok(cfg2.j.commission_percent === 25, 'admin changed commission, config reflects it');
  const p2 = await call('POST', `/jobs/${job.id}/pay`, { amount: 60000, method: 'bank' }, client.token);
  ok(p2.j.job.payment_status === 'paid' && Number(p2.j.payment.platform_amount) === 15000, 'full payment, new 25% rate applied');
  await call('PUT', '/admin/settings', { payment_methods: { mobile_money: true, bank: false, lipa_namba: true } }, admin.token);
  const dis = await call('POST', `/jobs/${job.id}/pay`, { amount: 1, method: 'bank' }, client.token);
  ok(dis.s === 400, 'disabled payment method is refused');
  const rc = (await call('GET', `/payments/${p2.j.payment.id}/receipt`, null, client.token)).j;
  ok(rc.client_name === 'Asha Mteja' && rc.fundi_name === 'Juma Fundi' && rc.fundi_phone && rc.service_name && rc.job_code === job.code && rc.balance === 0, 'receipt has all required details');
  const earn = (await call('GET', '/fundi/earnings', null, fundi.token)).j;
  ok(earn.total_earned === 32000 + 45000 && earn.history.length === 2, 'fundi earnings: 32,000 + 45,000');
  const rate = await call('POST', `/jobs/${job.id}/rate`, { rating: 5, comment: 'Safi' }, client.token);
  ok(rate.j.rating.rating === 5 && rate.j.fundi.rating.avg === 5, 'client rated the fundi');
  const cn2 = (await call('GET', '/notifications', null, client.token)).j;
  ok(['Kazi imekamilika', 'Malipo yamepokelewa'].every((t) => cn2.items.some((n) => n.title.includes(t))), 'completion thanks and payment notifications sent');

  console.log('Nauli rule and admin control');
  const job2 = (await call('POST', '/jobs', { service_id: wiring.id, description: 'Test 2', lat: LAT, lng: LNG }, client.token)).j;
  await call('POST', `/fundi/jobs/${job2.id}/accept`, null, fundi.token);
  await call('POST', `/fundi/jobs/${job2.id}/arrived`, { lat: LAT, lng: LNG }, fundi.token);
  const cx = await call('POST', `/jobs/${job2.id}/cancel`, { reason: 'Nimebadili mawazo' }, client.token);
  ok(cx.j.status === 'cancelled' && cx.j.nauli_due === true, 'cancel after arrival marks nauli as due');
  const job3 = (await call('POST', '/jobs', { service_id: wiring.id, description: 'Test 3', lat: LAT, lng: LNG }, client.token)).j;
  await call('POST', `/fundi/jobs/${job3.id}/accept`, null, fundi.token);
  const re = await call('POST', `/admin/jobs/${job3.id}/reassign`, { fundi_id: manual.j.user.id }, admin.token);
  ok(re.j.fundi.id === manual.j.user.id, 'admin reassigned the job');
  const ac = await call('POST', `/admin/jobs/${job3.id}/cancel`, { reason: 'test' }, admin.token);
  ok(ac.j.status === 'cancelled', 'admin cancelled a job');
  const dash = (await call('GET', '/admin/dashboard', null, admin.token)).j;
  ok(dash.payments.platform > 0 && dash.clients >= 1, 'admin dashboard has totals');
  const cov = (await call('GET', '/admin/coverage', null, admin.token)).j;
  ok(cov.find((r) => r.name === 'Mbeya').fundis >= 1, 'coverage shows fundis per region');
  const svc = await call('POST', '/admin/services', { name_sw: 'Mabomba', name_en: 'Plumbing', trade: 'plumbing' }, admin.token);
  ok(svc.j.trade === 'plumbing', 'admin can add a new service (future trades)');
  const reg = await call('POST', '/admin/admins', { identifier: '07' + sfx + '44', name: 'Msaidizi Mbeya', region_ids: [mbeya.id] }, admin.token);
  const sub1 = await login('07' + sfx + '44', { app: 'admin' });
  ok(sub1.user.role === 'admin' && !sub1.user.is_main_admin, 'regional admin is auto-detected at login');
  const noMain = await call('PUT', '/admin/settings', { commission_percent: 50 }, sub1.token);
  ok(noMain.s === 403, 'regional admin cannot change commission');
  const forbid = await call('GET', '/admin/fundis', null, client.token);
  ok(forbid.s === 403, 'client cannot reach admin API');
  const imp = await call('POST', '/admin/locations/import', { rows: [{ region: 'Mbeya', district: 'Mbeya Jiji', ward: 'Kiwanja Mpaka' }] }, admin.token);
  ok(imp.j.imported === 1, 'location import works');

  console.log('Admin app: customers, companies, reports');
  const cl = (await call('GET', '/admin/clients?q=Asha', null, admin.token)).j;
  const ashaRow = cl.find((c) => c.id === client.user.id);
  ok(ashaRow && ashaRow.jobs_total >= 3 && ashaRow.spent === 100000, 'admin lists customers with job counts and amount spent');
  const cd = (await call('GET', `/admin/clients/${client.user.id}`, null, admin.token)).j;
  ok(cd.jobs.length >= 3, 'admin opens a customer with their jobs');
  const blk = await call('POST', `/admin/clients/${client.user.id}/block`, { blocked: true }, admin.token);
  const blocked = await call('GET', '/jobs', null, client.token);
  ok(blk.j.blocked === true && blocked.s === 403 && blocked.j.error === 'blocked', 'blocked customer is locked out');
  await call('POST', `/admin/clients/${client.user.id}/block`, { blocked: false }, admin.token);
  const back = await call('GET', '/jobs', null, client.token);
  ok(back.s === 200, 'customer can be unblocked');
  const co = await call('POST', '/admin/fundis', { identifier: '07' + sfx + '55', name: 'Umeme Co', company_name: 'Umeme Co Ltd', fundi_type: 'company', areas: [{ region_id: mbeya.id, district_id: dist.id }], service_ids: [wiring.id] }, admin.token);
  const companies = (await call('GET', '/admin/fundis?type=company', null, admin.token)).j;
  ok(companies.length >= 1 && companies.every((f) => f.fundi_type === 'company') && companies.some((f) => f.id === co.j.user.id), 'admin filters companies');
  const rep = (await call('GET', '/admin/reports?days=7', null, admin.token)).j;
  ok(rep.jobs.total >= 3 && rep.jobs.completed >= 1 && rep.money.revenue === 100000, 'report totals: jobs and revenue');
  ok(rep.money.platform === 23000 && rep.money.fundis === 77000, 'report commission split (8,000 + 15,000 platform)');
  ok(rep.by_day.length === 7 && rep.by_service.length >= 1 && rep.top_fundis[0].completed === 1, 'report by day, by service and top fundis');
  const repReg = (await call('GET', '/admin/reports?days=7', null, sub1.token)).j;
  ok(repReg.jobs.total >= 3, 'regional admin report is limited to assigned regions');

  console.log(`\n${pass} passed, ${failN} failed`);
  process.exit(failN ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
