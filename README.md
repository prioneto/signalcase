# Signalcase

Signalcase is a native macOS prototype that turns logs from Supabase, Stripe, Render, RevenueCat, and Sentry into compact, evidence-backed bug cases.

The prototype uses realistic demo events so the product direction can be tested without connecting production credentials. It deliberately uses deterministic grouping and findings; there is no required AI account.

## Native app

```bash
cd macOS
./scripts/build-app.sh --open
```

The packaged app is created at `macOS/.build/Signalcase.app`.

Try these flows:

- Select the seeded cases to compare cross-service timelines.
- Click **Capture recent logs**, choose a time window, and build a new case.
- Open **Integrations** to see how service connections fit into the product.
- Advance a case from New → Triaged → Fixing → Verified.

## Website

```bash
cd website
npm install
npm run dev
```

Open [http://localhost:3002](http://localhost:3002).

## Prototype boundary

The UI and case-building workflow are functional. Service connections currently use demo data and do not make production API calls. The intended MVP would begin with read-only Stripe Events, Supabase log queries, and Render deploy data, then add a small hosted webhook collector for always-on ingestion.

