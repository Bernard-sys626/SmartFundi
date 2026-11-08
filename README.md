# SmartFundi

Mobile app that connects customers with verified electricians (Fundi) and companies in Tanzania.
Electrical services at launch; the data model already supports other trades (plumbing, car mechanics, ...)
because services, areas and commission are all managed by the Admin, not hard coded.

```
app/        Flutter code for TWO apps built from one code base:
              SmartFundi        (Client + Fundi/Company)  lib/main.dart
              SmartFundi Admin  (administrators only)     lib/main_admin.dart
backend/    Node.js API (Express + Postgres/Neon), tested end to end
brand/      Logo files (SVG, PNG)
tools/      Android patch script used by the APK workflow
.github/    GitHub Actions: APK build + backend tests
```

## What is built

* Language choice on first launch (Kiswahili, English, Francais), animated splash with the logo, light and night mode.
* Login with phone or email + verification code. The server decides the role. Admin phones cannot sign in to the
  Client/Fundi app, and the Admin app refuses any number that is not an Admin (it never creates accounts).
  The Google button is in place but disabled (see "Not done yet").
* **Client**: Home, My Requests, Alerts, Messages, Settings. Report a problem in 4 popup-style steps
  (service, description + photos, area + GPS, review with the mandatory nauli message). Track the job
  (timeline), chat with the Fundi, call / WhatsApp / SMS, see the quotation, pay in full or in parts,
  receipts, rate the Fundi, cancel (nauli rule applied when the Fundi has already arrived).
* **Fundi / Company**: registration wizard (type, name, work areas by Region > District > Ward, services,
  documents), Admin approval, then: new jobs for their areas and services, accept (first one wins),
  on my way, "I have arrived" (checked against the client's GPS), quotation with attachments,
  start / complete, earnings (80% share), documents, profile.
* **SmartFundi Admin (separate app)**: business dashboard, customers (search, history, block/unblock),
  approve / reject / suspend Fundis, companies, register a Fundi manually, all jobs (reassign or cancel),
  payments (confirm or reject manual payments, commission totals), services (add new trades), commission %
  and payment methods, locations (switch regions and districts on or off, add districts and wards, bulk import),
  other Admins with regional scope (main admin only), statistics and reports (revenue, commission, requests per
  day / service / region, top fundis, completion rate for 7, 30, 90 or 365 days).
* Commission is read from the server for every new payment (default 20% platform / 80% Fundi).
  Changing it in the Admin app updates the Fundi earnings text and all new payments immediately.
* Notifications are stored in the database and shown in the app; Firebase push is sent as well when configured.
* Images are converted to WebP (max 1600 px) on upload. Documents: PDF, Word, Excel, images.

## Deploy in 4 steps

1. **Database (Neon)**: create a project at https://neon.tech and copy the connection string.
   Tables are created automatically on the first start.
2. **Backend**: deploy `backend/` (for example on Render using `render.yaml`, or any Node 18+ host) and set the
   environment variables below. Test: open `https://YOUR-API/health`.
3. **GitHub secrets**: repository Settings > Secrets and variables > Actions > New repository secret.
4. **Build the APKs**: Actions > "Build Android APKs" > Run workflow. Two files are produced:
   `SmartFundi-apk` (Client + Fundi/Company) and `SmartFundi-Admin-apk` (administrators only).
   Tags like `v1.0.0` also attach both APKs to a GitHub release. The Admin app has its own icon
   (charcoal background) and package name `tz.smartfundi.admin`; it uses in-app alerts, push is for the main app.

### GitHub Actions secrets (for the APK)

| Secret | Required | Value |
|---|---|---|
| `API_BASE_URL` | yes | Your backend URL ending in `/api`, e.g. `https://smartfundi-api.onrender.com/api` (must be https) |
| `FIREBASE_API_KEY` | for push | `current_key` in google-services.json |
| `FIREBASE_APP_ID` | for push | `mobilesdk_app_id` in google-services.json |
| `FIREBASE_SENDER_ID` | for push | `project_number` in google-services.json |
| `FIREBASE_PROJECT_ID` | for push | `project_id` in google-services.json |

Firebase: create a project, add an Android app with package name **tz.smartfundi.smartfundi**, download
google-services.json and copy the four values above. Without them the app still works, only push is off.

### Backend environment variables

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | Neon connection string |
| `JWT_SECRET` | yes | Long random string |
| `ADMIN_PHONES` | yes | Comma separated. The first number is the Main Admin (default `+255740586160,+255613936160`) |
| `PAYMENT_MODE` | yes | `manual` (Admin confirms payments) or `simulated` (auto success, testing only) |
| `BEEM_API_KEY`, `BEEM_SECRET`, `BEEM_SENDER` | for SMS | Beem Africa SMS for verification codes. Without it codes are only written to the server log |
| `SMTP_URL`, `MAIL_FROM` | for email codes | e.g. `smtps://user:pass@smtp.host` |
| `FIREBASE_SERVICE_ACCOUNT` | for push | Base64 of the Firebase service account JSON (`base64 -w0 key.json`) |
| `PAYMENT_WEBHOOK_SECRET` | with a payment provider | Header `x-webhook-secret` for `POST /api/payments/webhook` |
| `ARRIVAL_RADIUS_M` | no | GPS distance accepted for "I have arrived" (default 300) |
| `LANDING_URL` | no | Website opened from "Read more" in Privacy and Terms |
| `DEV_OTP` | testing only | `true` returns the code in the API response. Keep `false` in production |

## Verification codes (important)

The app asks the server to send a code by SMS (phone) or email. **The server only sends codes after you configure a provider**,
otherwise it answers with a clear error ("verification code service is not switched on") instead of pretending it was sent.

* **Email codes (quickest, free):** set `SMTP_URL` on the backend. Examples:
  Gmail with an app password: `smtps://yourname%40gmail.com:APP_PASSWORD@smtp.gmail.com:465`
  (Google account > Security > 2-Step Verification > App passwords), or Brevo / Resend / any SMTP host.
  Also set `MAIL_FROM`.
* **SMS codes:** create a Beem Africa account, register a sender ID, then set `BEEM_API_KEY`, `BEEM_SECRET`, `BEEM_SENDER`.
  Check the delivery log on the server if a phone does not receive anything.
* **Only while testing:** `DEV_OTP=true` makes the server return the code and the app fills it in automatically.
  Never leave this on in production, anyone could log in as anyone.
* The Admin phones in `ADMIN_PHONES` also need working delivery to sign in the first time.

## What was tested, and what was not

* **Tested (62 checks, all passing):** `backend/test/smoke.js` runs the whole flow against a real Postgres:
  OTP login and role detection, location data, fundi registration and approval, uploads and WebP conversion,
  job creation rules, matching and notifications, accept race, GPS arrival check, quotation, partial and full
  payment with the 80/20 split, commission change, receipts, earnings, rating, nauli rule, admin controls,
  regional admin permissions, Admin/Client app separation, customers, companies filter and reports. It also runs in GitHub Actions (`backend-test.yml`).
* **Not tested here:** the Flutter app. The build environment used to write it cannot download the Flutter SDK,
  so the code was syntax-checked only. The first GitHub Actions run is the real compile. If it reports errors,
  send me the log and I will fix them.

## Not done yet (needs your accounts or decisions)

* **Real payments.** Mobile Money, Bank and Lipa Namba need a payment provider (aggregator) account.
  The app already records payments, splits commission and issues receipts. In `manual` mode the Admin confirms
  each payment. When you choose a provider, connect it to `POST /api/payments/webhook` (and add the
  request-to-pay call in `backend/src/routes/jobs.js`, route `/:id/pay`).
* **SMS delivery** uses the Beem Africa API format and has not been tried against a live account.
* **Google Sign-In** is shown as a button only (it needs a Google Cloud OAuth client).
* **Tanzania locations.** All 31 regions are loaded, but only a small sample of districts and wards
  (Mbeya, Mwanza and a few others). Import the full official list: Admin app > More > Locations > import icon
  (lines `Region, District, Ward`) or `POST /api/admin/locations/import`.
* **Release signing and Play Store.** The workflow builds a debug-signed release APK (installs fine, not for
  the Play Store). Add your own keystore before publishing.
* **Cloud storage.** Files are stored in Postgres for now (as agreed). Move to Cloudflare R2 later in `routes/common.js`.
* The service called "Get motor installation" in the requirements was read as **Gate motor installation**.
