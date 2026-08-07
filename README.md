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

- Open **Integrations** and save a provider credential. Signalcase only makes read requests, and tokens are stored in macOS Keychain rather than the workspace file. Prefer the narrowest provider permissions available.
- Click **Sync recent logs**, choose connected sources and a window, then let Signalcase detect cases. Provider pages and temporary rate limits are handled automatically.
- Enable **Automatic sync** in Settings to incrementally check connected pull-based sources every 5, 15, 30, or 60 minutes while Signalcase is open.
- Import a JSON, JSONL, or plain-text log file from the sync sheet.
- Advance a case from New → Reviewed → Fixing → Verified.

### Sources

- **Supabase:** project reference plus a Personal Access Token. Signalcase queries the current Management API unified `logs` endpoint.
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

## Current boundary

The macOS receiver works while Signalcase is open. It is suitable for local testing; a hosted, authenticated collector is still needed for reliable always-on RevenueCat and application ingestion. Provider retention and API limits still apply, and RevenueCat history is collected from new webhooks rather than fetched retroactively.
