# Updating a repository that already has the first version

You do NOT need to redo Neon, the Render service or the `API_BASE_URL` secret.

## What changed in the folder layout
| Old | New |
|---|---|
| `app/` | `client_app/`, `admin_app/` and `packages/smartfundi_core/` |
| `.github/workflows/build-apk.yml` | `build-client-apk.yml` and `build-admin-apk.yml` |
| `backend/`, `render.yaml` | same place (render.yaml keeps `plan: free`) |

## Steps (git on a computer or Termux)
```
git pull
git rm -r app .github/workflows/build-apk.yml
# unzip SmartFundi-Project.zip, then copy the CONTENTS of the "smartfundi" folder into your repo root
# (client_app, admin_app, packages, backend, brand, tools, docs, .github, README.md, render.yaml, .gitignore)
git add -A
git commit -m "Split into Client and Admin apps"
git push
```
## Steps (GitHub website)
1. Open the folder `app` > the three dots > **Delete directory** > commit.
2. Open `.github/workflows/build-apk.yml` > the trash icon > commit.
3. **Add file > Upload files**: upload the contents of the unzipped `smartfundi` folder (not the folder itself).

## Checks that avoid most errors
* `.github/workflows` must be at the repository ROOT (not inside a `smartfundi/` sub folder).
* After the push, Render redeploys the API by itself. Open `https://smartfundi-api.onrender.com/health` and wait for `{"ok":true}`.
* On Render > Environment, add a verification-code provider (`SMTP_URL` or the Beem variables) or, for testing only, `DEV_OTP=true`.
* Uninstall the old SmartFundi APK from the phone before installing a new one (debug-signed builds from different runs cannot update each other). Your data is on the server and is not lost.
* Red failed steps matter; yellow deprecation notices in the log are normal and harmless.
