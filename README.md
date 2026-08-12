# Signalcase

Signalcase is a native macOS app that turns logs from Supabase, Render, and your application into compact, evidence-backed bug cases.

Signalcase only uses connected or imported live data. Grouping and findings are deterministic, so no AI account is required.

## Native app

```bash
cd macOS
./scripts/build-app.sh --open
```

The packaged app is created at `macOS/.build/Signalcase.app`.

Try these flows:

- In onboarding or Settings, sign in with GitHub and create or select a Signalcase project. Every project keeps its own connections, cases, and activity history.
- Open **Connections** and click **Connect Supabase**. Authorization opens in the user's default browser and returns through the app's secure callback. Signalcase then retrieves the accessible Supabase projects and lets the user choose one; no project reference or access token is pasted into the app. Provider tokens are encrypted on the server.
- Render credentials currently use macOS Keychain. Prefer the narrowest read-only permissions available.
- Click **Sync recent logs**, choose connected sources and a window, then let Signalcase detect cases. Provider pages and temporary rate limits are handled automatically.
- Enable **Automatic sync** in Settings to incrementally check connected pull-based sources every 5, 15, 30, or 60 minutes while Signalcase is open.
- Import a JSON, JSONL, or plain-text log file from the sync sheet.
- Advance a case from New → Reviewed → Fixing → Verified.

### Sources

- **Supabase:** Management OAuth with `projects:read` and `analytics:read`. Signalcase lists accessible projects, saves the user's selection, and queries the current Management API unified `logs` endpoint through its server.
- **Render:** workspace owner ID, service IDs, and an API key. Service logs and deploys are read.
- **Application Logs:** a local authenticated endpoint accepts structured errors while Signalcase is open, so your own request IDs and error context can be matched to provider logs.

## Website

```bash
cd website
npm install
npm run dev
```

Open [http://localhost:3002](http://localhost:3002).

The server needs the values listed in `website/.env.example` before account linking or Supabase OAuth can work. See [Production setup](docs/PRODUCTION_SETUP.md) for the exact Supabase, Vercel, and native build steps.

## Current boundary

Supabase pull-based sync uses the hosted authenticated server. Render currently uses local Keychain credentials. The Application Logs receiver runs while Signalcase is open. Provider retention and API limits still apply.
