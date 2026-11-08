# Requirements checklist (from SmartFundi_Full_Requirements_v4)

Done = implemented. Tested = covered by backend/test/smoke.js. App screens are untested until the first APK build.

| Area | Status |
|---|---|
| Splash with animated logo, language choice, light/night mode | Done (app) |
| Client: home, my requests, alerts, messages, settings (5 tabs, bell icon top right) | Done (app) |
| Report a problem: service, photos, area, GPS, nauli message | Done (app), rules Tested (server) |
| Fundi or Company preference, first accept wins | Done, Tested |
| Fundi registration with documents, Admin approval | Done, Tested |
| Matching by region/district/ward and service | Done, Tested |
| Accept, on the way, GPS arrival, start, complete | Done, Tested |
| Quotation with attachments, partial payments, balance | Done, Tested |
| Commission 20/80 editable by Admin, shown to Fundis | Done, Tested |
| Receipts, rating | Done, Tested |
| Nauli rule when cancelled after arrival | Done, Tested |
| In-app chat, call, WhatsApp, SMS | Done (chat Tested) |
| Notifications (in-app + Firebase push) | In-app Tested; push needs Firebase setup |
| SmartFundi Admin as a separate app (dashboard, customers, fundis, companies, jobs, payments + commission, add admins, statistics and reports) | Done, Tested (server) |
| Languages Kiswahili / English / Francais | Done (French admin texts fall back to English where missing) |
| Mobile Money / Bank / Lipa Namba real payments | Needs a provider account (see README) |
| Google Sign-In | Button only |
| Full Tanzania wards list | Sample data + import tool |
| APKs via GitHub Actions (SmartFundi + SmartFundi Admin) | Workflow written, not yet run |

## Admin panel (section 7) after the latest round

| Item | Status |
|---|---|
| 7.1 View applications, approve/reject with documents, register manually (with documents), edit every detail (name, phone, email, type, areas, services) | Done, Tested (server) |
| 7.1 See which regions, districts and wards have Fundis/Companies | Done: region, district and ward level, Tested (server) |
| 7.2 Requests (near real time, refreshed every 20 s), who accepted, reassign, cancel, history | Done, Tested |
| 7.3 Add, edit, remove services | Done, Tested (Main Admin only) |
| 7.4 Commission 20/80, edit %, shown on Fundi earnings (refreshed every 30 s without restart), payments and commission reports, payment methods | Done, Tested (edit: Main Admin only) |
| 7.5 All regions, switch service on/off per region and district, other Admins with regions (editable) | Done, Tested |
| Regional Admins limited to their own regions (dashboard, payments, jobs, fundis) | Done, Tested |
| Full official list of districts and wards | Only sample data + import tool (data must come from you) |
