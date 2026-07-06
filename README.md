# Field Tracker

Location tracking for field staff / delivery - internal testing version (2-5 users).

```
Phone app (Flutter)  --every 30s-5min-->  Backend (FastAPI + SQLite)  <--  Dashboard (browser, Leaflet map)
```

- `backend/` - API + live dashboard (Python / FastAPI, SQLite database)
- `app/` - Android app (Flutter): foreground service, on/off toggle, offline buffer

Note: this project uses **port 8090** (8000 is used by the Glimmora dev
server on this PC, 8080 by PostgreSQL/pgAdmin).

---

## 1. Run the backend (this PC)

```powershell
cd backend
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
Copy-Item .env.example .env      # then edit .env and change API_KEY
.venv\Scripts\uvicorn app.main:app --host 0.0.0.0 --port 8090
```

Open http://localhost:8090 -> dashboard (enter the same API_KEY).

For phones to reach it on the same Wi-Fi, find this PC's IP with `ipconfig`
(e.g. `192.168.1.10`) - the app's Server URL is then `http://192.168.1.10:8090`.

Allow port 8090 through Windows Firewall (run once in an **admin** PowerShell):

```powershell
New-NetFirewallRule -DisplayName "Field Tracker Backend (port 8090)" -Direction Inbound -Protocol TCP -LocalPort 8090 -Action Allow -Profile Any
```

To reach phones on mobile data, deploy the backend to a free host
(Render / Railway): deploy the `backend/` folder, set the `API_KEY`
environment variable, start command:
`uvicorn app.main:app --host 0.0.0.0 --port $PORT`

## 2. Build the app (one-time PC setup)

Already done on this PC: Flutter 3.44.4 (`C:\dev\flutter`), JDK 17
(`C:\dev\jdk17`), Android SDK (`C:\Android`) - all on PATH.

```powershell
cd app
.\setup.ps1                      # generates the android/ project (one time - already done)
flutter build apk --release
```

APK: `app\build\app\outputs\flutter-apk\app-release.apk` - share it via
WhatsApp (send as document) or pendrive.

> **Always build updates on this same PC.** The APK is signed with this PC's
> debug keystore (`%USERPROFILE%\.android\debug.keystore`) - updates only
> install over the old version if signed with the same key. Back that file up.

## 3. Admin (dashboard) login

The dashboard is behind an email/password admin login. Set these two
environment variables on the Render service (Environment tab), then it
redeploys and creates the admin account:

- `ADMIN_EMAIL` - your email (use a real domain; `.local`/`.test` are rejected)
- `ADMIN_PASSWORD` - password you choose

The `API_KEY` still works as a master key for scripts/verification.

## 4. Install checklist for each tester phone

1. Install the APK (allow "install from unknown sources" when asked)
2. Open the app -> **Create account** with name, email, and a password the
   person chooses and remembers (the server URL is already filled in).
3. Tap the "Fix" buttons until every permission shows a green tick:
   - Location -> **"Allow all the time"** (not "only while using")
   - Notifications -> allow
   - Battery -> no restrictions
   - Uninstall protection -> enable (Device Admin; blocks one-tap uninstall)
4. **Xiaomi / Redmi / Oppo / Vivo / Realme:** also enable **Autostart** for
   Field Tracker in phone settings (Security app -> Autostart), or the phone
   will kill tracking after a while.
5. Switch tracking ON - a permanent, silent notification appears (required by
   Android, cannot be hidden - it is what keeps tracking legal and honest).
6. Check the dashboard - the person appears within a minute.

- **Turning tracking OFF requires the account password.**
- Removing the app requires first disabling Device Admin (several steps in
  Settings); doing so sends a "removed app protection" alert to the dashboard.

## 5. Daily use

- Each person has a fixed colour. Tick people in the sidebar to draw their
  route (last 12 h) on the map.
- Status badge: **live** (< 5 min), **delayed** (< 15 min), **offline**
  (older - phone off / killed / no signal), **tracking off** (turned off by
  the person). The marker stays at the last known position when offline.
- "Recent activity" panel lists tamper events: who turned tracking off/on and
  who removed app protection, with timestamps.
- If a phone shows offline while the person is on duty, it is almost always the
  battery-optimization / autostart settings from step 4.

## Tamper protection - what it does and does not do

- **Does:** password to turn off in-app; app can't be uninstalled with one tap
  (Device Admin); dashboard is alerted when someone turns tracking off or
  removes protection.
- **Does not:** it is a *deterrent*, not a hard lock. A determined person can
  still deactivate Device Admin via phone Settings, or factory-reset the phone.
  A true hard lock needs "Device Owner" enrolment (factory reset + QR setup per
  phone) - only worth it later with company-owned devices. The system GPS
  switch also cannot be locked without Device Owner.

## Later, when you scale

- Google Play closed-testing track ($25 one-time) -> automatic updates
- Postgres instead of SQLite -> set `DATABASE_URL` in `.env`
- Transistor `flutter_background_geolocation` plugin (~$400 one-time) ->
  smarter battery use (motion-based tracking), better survival on aggressive phones
