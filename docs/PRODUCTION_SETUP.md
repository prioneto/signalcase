# Signalcase production setup

The code is ready for the native account and Supabase Management OAuth flow. The following steps require access to your Supabase organization and Vercel project.

## 1. Apply the database migration

From the repository root, the simplest option is:

```bash
supabase login
supabase link --project-ref aaowyafijolazrrwlwob
supabase db push
```

Review the migration list when prompted. The server-owned integration migrations include:

```text
20260807224113_provider_oauth_foundation.sql
20260813000935_production_application_ingest.sql
20260814064812_add_github_integration.sql
```

If you prefer the dashboard:

1. Open the Signalcase project in Supabase.
2. In the left sidebar, click **SQL Editor**.
3. Click **New query**.
4. Run the unapplied migration files in filename order.
5. Open **Table Editor** and confirm `provider_oauth_states`, `provider_credentials`, and `application_ingest_keys` exist.

Do not add client RLS policies for these credential tables. They are intentionally server-only.

## 2. Collect the Signalcase Supabase keys

1. In the Signalcase Supabase project, click **Project Settings** in the sidebar.
2. Open **API Keys**.
3. Copy the **Project URL**.
4. Copy the **Publishable key** (`sb_publishable_…`). This is safe to compile into the Mac app.
5. Create or copy a **Secret key** (`sb_secret_…`). This is server-only and must only be placed in Vercel.

Do not use the secret key in the Mac app, any `NEXT_PUBLIC_` variable, or source control.

## 3. Configure GitHub sign-in for the Mac app

The existing GitHub provider can be shared by the website and native app.

1. In the Signalcase Supabase project, open **Authentication** → **URL Configuration**.
2. Set **Site URL** to your final production website, for example `https://signalcase.app`.
3. Add all of these under **Redirect URLs**:

```text
https://YOUR_DOMAIN/auth/callback
http://localhost:3002/auth/callback
signalcase://auth/callback
```

4. Open **Authentication** → **Providers** → **GitHub** and confirm it is enabled.

The GitHub OAuth application's callback remains the Supabase callback shown on that provider page. Do not replace it with the custom `signalcase://` URL.

## 4. Create the Supabase Management OAuth app

This is separate from GitHub sign-in. It gives Signalcase permission to read a user's selected Supabase project's logs.

1. Return to the Supabase organization level using the project switcher in the upper-left.
2. Open **Organization Settings**.
3. Open **OAuth Apps**.
4. Click **Add application**.
5. Name it `Signalcase`.
6. Set its redirect URL to exactly:

```text
https://YOUR_DOMAIN/api/integrations/supabase/callback
```

7. Enable **Projects · Read** (`projects:read`) and **Analytics · Read** (`analytics:read`). No write scopes are needed. Existing users must reconnect after adding `projects:read`.
8. Save the application.
9. Copy its **Client ID** and **Client Secret**. The secret may only be shown once.

For localhost testing, create a second OAuth application with this redirect URL and use its credentials in `website/.env.local`:

```text
http://localhost:3002/api/integrations/supabase/callback
```

The redirect URL must exactly match `NEXT_PUBLIC_SITE_URL` plus `/api/integrations/supabase/callback`.

## 5. Create the Signalcase GitHub App

This is separate from the GitHub OAuth provider used for Signalcase sign-in. It gives each team a GitHub-owned screen where they choose exactly which repositories Signalcase may read.

1. Open [GitHub Developer Settings](https://github.com/settings/apps).
2. Click **New GitHub App**.
3. Enter a globally unique app name, such as `Signalcase` or `Signalcase Dev`.
4. Set **Homepage URL** to `https://YOUR_DOMAIN`.
5. Leave **Callback URL** empty. This flow uses the installation setup callback, not user OAuth.
6. Turn off **Request user authorization (OAuth) during installation**.
7. Set **Setup URL** to exactly:

```text
https://YOUR_DOMAIN/api/integrations/github/callback
```

8. Enable **Redirect on update**.
9. Turn off **Active** under Webhook. This version polls recent Actions evidence and does not need webhooks.
10. Under **Repository permissions**, set **Actions** to **Read-only**. Leave **Metadata** at its required read-only setting and every other permission at **No access**.
11. Under **Where can this GitHub App be installed?**, choose **Any account** for production.
12. Click **Create GitHub App**.
13. Copy the numeric **App ID** and the **App slug**.
14. At the bottom of the app settings, click **Generate a private key**. GitHub downloads a `.pem` file; keep it server-only.

For localhost, create a second GitHub App with this Setup URL:

```text
http://localhost:3002/api/integrations/github/callback
```

## 6. Configure and deploy Vercel

1. Open Vercel and select the Signalcase project.
2. Click **Settings** → **Build and Deployment**.
3. Set **Root Directory** to `website` if it is not already set.
4. Click **Settings** → **Environment Variables**.
5. Add these variables for **Production**:

| Variable | Value |
| --- | --- |
| `NEXT_PUBLIC_SITE_URL` | `https://YOUR_DOMAIN` |
| `NEXT_PUBLIC_SUPABASE_URL` | Signalcase Supabase Project URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Signalcase `sb_publishable_…` key |
| `SUPABASE_SECRET_KEY` | Signalcase `sb_secret_…` key |
| `SUPABASE_MANAGEMENT_CLIENT_ID` | Management OAuth application client ID |
| `SUPABASE_MANAGEMENT_CLIENT_SECRET` | Management OAuth application client secret |
| `CREDENTIAL_ENCRYPTION_KEY` | A stable base64-encoded 32-byte random key |
| `GITHUB_APP_ID` | Numeric App ID from GitHub App settings |
| `GITHUB_APP_SLUG` | App slug, such as `signalcase` |
| `GITHUB_APP_PRIVATE_KEY` | Entire downloaded `.pem` file, including BEGIN/END lines |
| `GITHUB_API_VERSION` | `2022-11-28` |

Generate the encryption key locally with:

```bash
openssl rand -base64 32
```

Keep that encryption key stable. Changing it makes previously connected provider tokens unreadable, so users would need to reconnect.

6. Save the variables.
7. Open **Deployments**, open the latest deployment's menu, and click **Redeploy**. Environment variable changes do not alter old deployments.
8. Visit `https://YOUR_DOMAIN/api/health`. It should return `"ok": true`; it reports missing variable names but never returns their values.
9. Visit `https://YOUR_DOMAIN/sign-in` and verify GitHub sign-in reaches `/dashboard`.

For local development, copy `website/.env.example` to `website/.env.local`, fill in the development OAuth app credentials, then run:

```bash
cd website
npm run dev
```

## 7. Configure Stripe subscriptions

1. In Stripe, switch to **Test mode**.
2. Open **Product catalog** and create `Signalcase Team`.
3. Add one recurring monthly price matching the public price on the Signalcase website.
4. Copy the `price_…` identifier.
5. Open **Developers** → **Webhooks** and add:

```text
https://YOUR_DOMAIN/api/billing/webhook
```

6. Subscribe the endpoint to `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid`, and `invoice.payment_failed`.
7. Copy the webhook signing secret (`whsec_…`).
8. Add the following Vercel Production variables and redeploy:

| Variable | Value |
| --- | --- |
| `STRIPE_SECRET_KEY` | Stripe secret key (`sk_test_…` while testing) |
| `STRIPE_WEBHOOK_SECRET` | Endpoint signing secret (`whsec_…`) |
| `STRIPE_TEAM_PRICE_ID` | Recurring Team price (`price_…`) |
| `NEXT_PUBLIC_TEAM_PRICE_LABEL` | Public display text, for example `$19 / month` |
| `BILLING_ENFORCEMENT_ENABLED` | Keep `false` until the full test succeeds |

9. In **Settings** → **Billing** → **Customer portal**, enable payment-method updates and subscription cancellation.
10. Start Checkout from the native app or `/dashboard`, complete it with a Stripe test card, and confirm the workspace changes to `active`.
11. Test a failed renewal and cancellation in Stripe. Confirm the webhook updates Signalcase.
12. Only after those tests pass, use live Stripe keys, create the live webhook, and change `BILLING_ENFORCEMENT_ENABLED` to `true`.

The server verifies Stripe's raw webhook body and signature and records event IDs for idempotency. Never place a Stripe secret or webhook signing secret in a `NEXT_PUBLIC_` variable or the Mac app.

### Error monitoring

The server and the Mac app report errors into the `error_reports` table automatically; no third-party account is required:

- Every API route funnels 5xx failures through `jsonError`, which logs to Vercel and stores a redacted report (message, short stack, path, request ID).
- The native app batches crash reports and non-fatal errors locally in `DiagnosticsReporter` and uploads them to `/api/client/errors` (rate limited to 20 per hour per user or IP). Reports contain versions and messages only—never logs or credentials.
- Review recent issues with SQL in the Supabase dashboard:

```sql
select source, count(*) as reports, max(message)
from error_reports
where occurred_at > now() - interval '7 days'
group by source
order by reports desc;
```

Reports are deleted after 90 days by the nightly cleanup cron. The customer-facing Terms, Privacy, Refunds, and Support pages are published at `/terms`, `/privacy`, `/refunds`, and `/support`; update the entity details in `website/lib/site.ts` (legal entity name, support email addresses) before launch.

## 8. Build the production Mac app

Save the public production configuration once:

```bash
cd macOS
cp .env.build.example .env.build
```

Open `macOS/.env.build`, replace its three placeholder values, and save it. The file is ignored by Git. From then on, build and open the app with only:

```bash
./scripts/build-app.sh --open
```

The app is created at `macOS/.build/Signalcase.app`. The build script registers the `signalcase://` callback scheme. It never embeds the Supabase secret key, Management OAuth client secret, provider access tokens, or encryption key.

The build checks `macOS/.env.build` first. If that file does not exist, it reads the three public values from `website/.env.local`, which keeps the existing localhost workflow working.

### Versioning and the update channel

- The marketing version lives in `macOS/VERSION`. Bump it for each release; the build number is derived from the commit count (override with `SIGNALCASE_APP_VERSION` / `SIGNALCASE_APP_BUILD`).
- After publishing a notarized build, set `MAC_RELEASE_VERSION` and `MAC_RELEASE_BUILD` in Vercel to match. The app polls `/api/releases/latest` once per day and on manual **Settings → General → Check for Updates**; when the manifest is newer, Settings shows a **Download** button that opens `NEXT_PUBLIC_MAC_DOWNLOAD_URL`.
- This is an update notification channel, not silent auto-update: users still download and replace the app. Sparkle remains an option later if fully automatic updates become necessary.

## 9. Verify the real end-to-end flow

1. Start or deploy the website server.
2. Open the newly built Signalcase app.
3. Complete onboarding and create or select a Signalcase project.
4. Click **Sign in with GitHub**. Your default browser should open, then return to Signalcase and show your email.
5. Open **Settings** → **Connections** → **Supabase**.
6. Click **Connect Supabase** and approve the `projects:read` and `analytics:read` request in the browser.
7. The browser returns to Signalcase. If the account has multiple Supabase projects, choose the correct project in the native picker; a single accessible project is selected automatically.
8. In the monitored Supabase project's **SQL Editor**, run this harmless failing read to create a real error log:

```sql
select * from public.signalcase_connection_test_table_that_does_not_exist;
```

9. Wait about one minute for log ingestion.
10. In Signalcase, click **Sync logs**, select Supabase, choose the last 15 minutes, and sync.
11. Confirm a database-error case appears. Open it and verify its source is Supabase rather than demo data.

To verify GitHub:

1. Open **Settings** → **Connections** → **GitHub**.
2. Click **Connect GitHub**. The default browser opens GitHub's installation screen.
3. Choose an account, approve only the repository Signalcase should read, and click **Install**.
4. The browser returns to the existing Signalcase window. One approved repository is selected automatically; otherwise choose one in the app.
5. Run a GitHub Actions workflow that fails, or select a recent time window containing an existing failure.
6. In Signalcase, click **Sync logs**, include GitHub, and sync.
7. Confirm the failed workflow appears as a GitHub case with its branch, run number, actor, commit SHA, and link back to the Actions run.

To verify production Application Logs:

1. Open **Settings** → **Connections** → **Application Logs**.
2. Click **Create production endpoint** and copy both generated environment variables.
3. Add them to a server-side test project. Do not expose the authorization value in browser JavaScript.
4. Send the JSON example shown in Signalcase while the Mac app is closed.
5. Reopen Signalcase, click **Sync logs**, select Application Logs, and sync the matching time window.
6. Confirm the application error appears and that its request ID can correlate with Render or Supabase evidence.

If authorization succeeds but project selection or sync returns `403`, confirm the Management OAuth app has **Projects · Read** and **Analytics · Read**, then disconnect and reconnect so both scopes are granted. If the app reports missing cloud configuration, rebuild the app with the three public values in step 8.

## 10. Verify collaboration and data controls

1. In the first Mac, open **Settings** → **Team**, invite a second email, and copy the invitation link.
2. Open the link in a private browser, sign in with the invited email, and accept it.
3. Sign in on a second Mac and select the shared project.
4. Sync a real failure on the first Mac and confirm it appears on the second.
5. Move the case to **Active** on one Mac and confirm the other receives the same status after switching projects or reopening the app.
6. Resolve it, generate a newer matching event, and confirm it reopens.
7. Delete and restore a case. Confirm the shared list follows the change.
8. Change the member between Member and Owner, then remove the account and confirm access is revoked.
9. Test project deletion and account deletion with disposable accounts.
10. Confirm `/api/cron/cleanup` returns `401` without the Vercel cron bearer token.

## 11. Distribute outside the Mac App Store

The current build script creates the `.app`, but public distribution also requires an Apple Developer ID certificate, hardened-runtime signing, notarization, stapling, and a hosted `.dmg` or `.zip`. After hosting the notarized artifact:

1. Set `NEXT_PUBLIC_MAC_DOWNLOAD_URL` in Vercel and redeploy so the authenticated dashboard shows the download button.
2. Set `MAC_RELEASE_VERSION` and `MAC_RELEASE_BUILD` to the published version from `macOS/VERSION` and the build number printed by `build-app.sh`. Existing installs then surface the update through **Settings → General → Check for Updates** within a day.
3. Verify `https://YOUR_DOMAIN/api/releases/latest` returns the new values with `"configured": true`.
