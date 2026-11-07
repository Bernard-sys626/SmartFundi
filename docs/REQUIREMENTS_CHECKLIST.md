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
| Admin: fundis, jobs, payments, services, areas, regional admins | Done, Tested |
| Languages Kiswahili / English / Francais | Done (French admin texts fall back to English where missing) |
| Mobile Money / Bank / Lipa Namba real payments | Needs a provider account (see README) |
| Google Sign-In | Button only |
| Full Tanzania wards list | Sample data + import tool |
| APK via GitHub Actions | Workflow written, not yet run |
