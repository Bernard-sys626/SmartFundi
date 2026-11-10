// End-to-end smoke test. Run with PAYMENT_MODE=simulated while the server is running.
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
// Client: name + phone, no code. Fundi: register with username/password. Admin: username/password.
async function login(identifier, extra = {}) {
  let r;
  if (extra.app === 'admin') r = await call('POST', '/auth/login', { username: identifier, password: extra.password, app: 'admin' });
  else if (extra.intent === 'fundi') r = await call('POST', '/auth/register', { username: 'fundi' + identifier, password: 'secret123', phone: '07' + identifier, language: 'sw' });
  else r = await call('POST', '/auth/client-start', { phone: identifier, name: extra.name || 'Test Client', language: 'sw' });
  return { token: r.j.token, user: r.j.user };
}
async function upload(token, name, buf, type) {
  const f = new FormData(); f.append('file', new Blob([buf], { type }), name);
  return (await call('POST', '/files', null, token, f)).j;
}
(async () => {
  const sfx = String(Date.now()).slice(-6);
  console.log('Auth and roles');
  const admin = await login('0613936160', { app: 'admin', password: '*Bernard2001' });
  ok(admin.user.role === 'admin' && admin.user.is_main_admin, 'default admin signs in with username and password and is main admin');
  const client = await login('07' + sfx + '11', { name: 'Asha Mteja' });
  ok(client.user.role === 'client', 'new user becomes client');
  const adminInMain = await call('POST', '/auth/login', { username: '0613936160', password: '*Bernard2001' });
  ok(adminInMain.s === 403 && adminInMain.j.error === 'use_admin_app', 'admin account is refused in the Client/Fundi app');
  const badPw = await call('POST', '/auth/login', { username: '0613936160', password: 'wrong', app: 'admin' });
  ok(badPw.s === 401 && badPw.j.error === 'invalid_credentials', 'wrong admin password rejected');
  const strangerInAdmin = await call('POST', '/auth/login', { username: 'nobody' + sfx, password: 'secret123', app: 'admin' });
  ok(strangerInAdmin.s === 401, 'unknown username is refused in the Admin app');
  const clientAgain = await call('POST', '/auth/client-start', { phone: '07' + sfx + '11', name: 'Asha Mteja', language: 'sw' });
  ok(clientAgain.s === 200 && clientAgain.j.user.id === client.user.id && !clientAgain.j.is_new, 'same phone number opens the same client account');
  const noPhone = await call('POST', '/auth/client-start', { name: 'X' });
  ok(noPhone.s === 400, 'client needs a valid phone number');
  const adminAsClient = await call('POST', '/auth/client-start', { phone: '0613936160', name: 'X' });
  ok(adminAsClient.s === 403, 'admin phone cannot be used as a client');
  const f1 = await call('POST', '/auth/register', { username: 'Juma' + sfx, password: 'secret123', phone: '0788' + sfx });
  ok(f1.s === 200 && f1.j.user.role === 'fundi' && f1.j.user.fundi_status === 'incomplete', 'fundi sets username and password the first time');
  const f2 = await call('POST', '/auth/register', { username: 'juma' + sfx, password: 'other123', phone: '0789' + sfx });
  ok(f2.s === 409 && f2.j.error === 'username_taken', 'username is unique (case-insensitive)');
  const f3 = await call('POST', '/auth/register', { username: 'abc' + sfx, password: '123', phone: '0787' + sfx });
  ok(f3.s === 400 && f3.j.error === 'weak_password', 'short password rejected');
  const f4 = await call('POST', '/auth/login', { username: 'JUMA' + sfx, password: 'secret123' });
  ok(f4.s === 200 && f4.j.user.id === f1.j.user.id, 'fundi signs in again with the saved username and password (another phone)');
  const f5 = await call('POST', '/auth/login', { username: 'juma' + sfx, password: 'nope1234' });
  ok(f5.s === 401, 'fundi wrong password rejected');
  const noPh = await call('POST', '/auth/register', { username: 'nophone' + sfx, password: 'secret123' });
  ok(noPh.s === 400 && noPh.j.error === 'invalid_phone', 'fundi must give a phone number');
  const dupPh = await call('POST', '/auth/register', { username: 'dup' + sfx, password: 'secret123', phone: '0788' + sfx });
  ok(dupPh.s === 409 && dupPh.j.error === 'phone_in_use', 'phone number cannot be reused');
  // forgot password: request by registered phone, Admin sets a temporary one, Fundi must replace it
  ok((await call('POST', '/auth/forgot', { phone: '0788' + sfx })).s === 200 && (await call('POST', '/auth/forgot', { phone: '0700000000' })).s === 200, 'forgot request always answers ok');
  const fl = (await call('GET', '/admin/fundis', null, admin.token)).j.find((x) => x.id === f1.j.user.id);
  ok(fl && fl.reset_requested_at, 'Admin sees the reset request');
  const rp = await call('POST', `/admin/fundis/${f1.j.user.id}/reset-password`, {}, admin.token);
  ok(rp.s === 200 && rp.j.temp_password.length === 8, 'Admin sets a temporary password');
  const tl = await call('POST', '/auth/login', { username: 'juma' + sfx, password: rp.j.temp_password });
  ok(tl.s === 200 && tl.j.user.must_change_password === true, 'Fundi signs in with it and must change it');
  const sp = await call('POST', '/auth/set-password', { password: 'brandnew1' }, tl.j.token);
  ok(sp.s === 200 && sp.j.user.must_change_password === false, 'Fundi sets own password');
  ok((await call('POST', '/auth/login', { username: 'juma' + sfx, password: rp.j.temp_password })).s === 401 && (await call('POST', '/auth/login', { username: 'juma' + sfx, password: 'brandnew1' })).s === 200, 'temporary password stops working');
  const ch = await call('PUT', '/auth/credentials', { current_password: 'wrong', password: 'newpass123' }, f1.j.token);
  ok(ch.s === 403 && ch.j.error === 'wrong_password', 'changing credentials needs the current password');

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
  const fundi = await login(sfx + '22', { intent: 'fundi' });
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
  const reg = await call('POST', '/admin/admins', { identifier: '07' + sfx + '44', name: 'Msaidizi Mbeya', username: 'sub' + sfx, password: 'subpass123', region_ids: [mbeya.id] }, admin.token);
  const sub1 = await login('sub' + sfx, { app: 'admin', password: 'subpass123' });
  ok(sub1.user.role === 'admin' && !sub1.user.is_main_admin, 'regional admin signs in with the username and password set by the main admin');
  const chA = await call('PUT', '/auth/credentials', { current_password: 'subpass123', username: 'sub' + sfx, password: 'subpass456' }, sub1.token);
  ok(chA.s === 200, 'admin changes own password in Settings');
  ok((await call('POST', '/auth/login', { username: 'sub' + sfx, password: 'subpass123', app: 'admin' })).s === 401 && (await call('POST', '/auth/login', { username: 'sub' + sfx, password: 'subpass456', app: 'admin' })).s === 200, 'old admin password stops working, new one works');
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

  console.log('Completeness fixes');
  const wardCov = (await call('GET', `/admin/coverage/district/${dist.id}/wards`, null, admin.token)).j;
  ok(wardCov.length >= 10 && wardCov.find((w) => w.id === wards[0].id).fundis >= 2, 'ward list with fundi availability per ward');
  const ed = await call('PUT', `/admin/fundis/${manual.j.user.id}`, { name: 'Manual Edited', phone: '07' + sfx + '66', fundi_type: 'company', company_name: 'Edited Co',
    areas: [{ region_id: mbeya.id, district_id: dist.id, ward_id: wards[2].id }], service_ids: [wiring.id, services[0].id] }, admin.token);
  ok(ed.j.user.name === 'Manual Edited' && ed.j.user.phone.endsWith(sfx + '66') && ed.j.areas.length === 1 && ed.j.service_ids.length === 2 && ed.j.user.fundi_type === 'company', 'admin edits name, phone, type, areas and services');
  const dup = await call('PUT', `/admin/fundis/${manual.j.user.id}`, { phone: '07' + sfx + '22' }, admin.token);
  ok(dup.s === 409, 'duplicate phone is refused');
  const doc = await upload(admin.token, 'lic.pdf', Buffer.from('%PDF-1.4 x'), 'application/pdf');
  const ad = await call('POST', `/admin/fundis/${manual.j.user.id}/documents`, { kind: 'company_reg', file_id: doc.id, name: 'Licence' }, admin.token);
  ok(ad.j.documents.some((d) => d.kind === 'company_reg'), 'admin attaches a document to a manually registered fundi');
  const mwanza = regions.find((r) => r.name === 'Mwanza');
  await call('POST', '/admin/admins', { identifier: '07' + sfx + '77', name: 'Msaidizi Mwanza', username: 'mw' + sfx, password: 'mwpass123', region_ids: [mwanza.id] }, admin.token);
  const mw = await login('mw' + sfx, { app: 'admin', password: 'mwpass123' });
  const mwPay = (await call('GET', '/admin/payments', null, mw.token)).j;
  ok(Number(mwPay.totals.total) === 0 && mwPay.items.length === 0, 'regional admin sees only payments of own regions');
  const mwDash = (await call('GET', '/admin/dashboard', null, mw.token)).j;
  ok(Number(mwDash.payments.total) === 0 && mwDash.clients === 0, 'regional admin dashboard is limited to own regions');
  const mwFundi = await call('POST', `/admin/fundis/${fundi.user.id}/suspend`, {}, mw.token);
  ok(mwFundi.s === 403, 'regional admin cannot change a fundi of another region');
  const mwJob = await call('POST', `/admin/jobs/${job.id}/cancel`, {}, mw.token);
  ok(mwJob.s === 403, 'regional admin cannot touch a job of another region');
  const upd = await call('POST', '/admin/admins', { identifier: '07' + sfx + '77', name: 'Msaidizi Mwanza', region_ids: [mwanza.id, mbeya.id] }, admin.token);
  const mw2 = (await call('GET', '/admin/payments', null, mw.token)).j;
  ok(upd.s === 200 && Number(mw2.totals.total) === 100000, 'changing the regions of an admin takes effect');

  console.log(`\n${pass} passed, ${failN} failed`);
  process.exit(failN ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
