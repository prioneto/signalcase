# Signalcase

Signalcase is a native macOS app that turns logs from Supabase, Stripe, Render, RevenueCat, Sentry, and your application into compact, evidence-backed bug cases.

Signalcase only uses connected or imported live data. Grouping and findings are deterministic, so no AI account is required.

## Native app

```bash
cd macOS
./scripts/build-app.sh --open
```

The packaged app is created at `macOS/.build/Signalcase.app`.

Try these flows:

- In onboarding or Settings, sign in with GitHub and select the local project folder. This links the Mac folder to the team's Signalcase project.
- Open **Connections**, enter the Supabase project reference, and click **Connect Supabase**. Authorization opens in the user's default browser and returns through the app's secure callback. The resulting provider tokens are encrypted on the server and are never saved in the app.
- Other provider credentials currently use macOS Keychain. Prefer the narrowest read-only permissions available.
- Click **Sync recent logs**, choose connected sources and a window, then let Signalcase detect cases. Provider pages and temporary rate limits are handled automatically.
- Enable **Automatic sync** in Settings to incrementally check connected pull-based sources every 5, 15, 30, or 60 minutes while Signalcase is open.
- Import a JSON, JSONL, or plain-text log file from the sync sheet.
- Advance a case from New → Reviewed → Fixing → Verified.

### Sources

- **Supabase:** Management OAuth with the `analytics:read` scope. Signalcase queries the current Management API unified `logs` endpoint through its server.
- **Stripe:** a restricted key with Events read access. Events and unsuccessful webhook deliveries from the selected window are read.
- **Render:** workspace owner ID, service IDs, and an API key. Service logs and deploys are read.
- **Sentry:** organization/project slugs and an `event:read` token. Recent issues and their latest event are read.
- **RevenueCat:** configure its webhook to send to `POST /revenuecat` on the receiver shown in the app. Configure the same required Authorization header on both sides; HMAC signing is also supported with a five-minute replay window.
- **Application:** send structured JSON to `POST /events` on the same receiver with the required Authorization header.

Example local application event:

```bash
curl -X POST http://localhost:9782/events \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer replace-with-your-receiver-secret' \
  -d '{"timestamp":"2026-08-05T00:25:42Z","level":"error","title":"ProfileBootstrapError","message":"permission denied for table profiles","request_id":"req_17","user_id":"usr_42","release":"28cc04","route":"GET /profiles"}'
```

Use the same `request_id` or trace ID in your app logs and downstream service metadata when possible. Exact IDs are shown as proven links; nearby events are visibly labeled as time-based context.

## Website

```bash
cd website
npm install
npm run dev
```

Open [http://localhost:3002](http://localhost:3002).

The server needs the values listed in `website/.env.example` before account linking or Supabase OAuth can work. See [Production setup](docs/PRODUCTION_SETUP.md) for the exact Supabase, Vercel, and native build steps.

## Current boundary

The macOS receiver works while Signalcase is open. Supabase pull-based sync now uses the hosted authenticated server, but an always-on hosted collector is still needed for reliable RevenueCat and application webhook ingestion. Render, Stripe, and Sentry still use local Keychain credentials. Provider retention and API limits still apply, and RevenueCat history is collected from new webhooks rather than fetched retroactively.
