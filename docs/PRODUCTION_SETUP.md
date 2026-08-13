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

## 5. Configure and deploy Vercel

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

## 6. Build the production Mac app

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

## 7. Verify the real end-to-end flow

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

To verify production Application Logs:

1. Open **Settings** → **Connections** → **Application Logs**.
2. Click **Create production endpoint** and copy both generated environment variables.
3. Add them to a server-side test project. Do not expose the authorization value in browser JavaScript.
4. Send the JSON example shown in Signalcase while the Mac app is closed.
5. Reopen Signalcase, click **Sync logs**, select Application Logs, and sync the matching time window.
6. Confirm the application error appears and that its request ID can correlate with Render or Supabase evidence.

If authorization succeeds but project selection or sync returns `403`, confirm the Management OAuth app has **Projects · Read** and **Analytics · Read**, then disconnect and reconnect so both scopes are granted. If the app reports missing cloud configuration, rebuild the app with the three public values in step 6.
