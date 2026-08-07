# Signalcase production setup

The code is ready for the native account and Supabase Management OAuth flow. The following steps require access to your Supabase organization and Vercel project.

## 1. Apply the database migration

From the repository root, the simplest option is:

```bash
supabase login
supabase link --project-ref aaowyafijolazrrwlwob
supabase db push
```

Review the migration list when prompted. The new migration is:

```text
20260807224113_provider_oauth_foundation.sql
```

If you prefer the dashboard:

1. Open the Signalcase project in Supabase.
2. In the left sidebar, click **SQL Editor**.
3. Click **New query**.
4. Copy the complete contents of `supabase/migrations/20260807224113_provider_oauth_foundation.sql` into the editor.
5. Click **Run** once.
6. Open **Table Editor** and confirm `provider_oauth_states` and `provider_credentials` exist.

Do not add RLS policies for either of those two tables. They are intentionally server-only.

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

7. Enable only **Analytics · Read** (`analytics:read`). No write scopes are needed.
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

Only public configuration is compiled into the app:

```bash
cd macOS
SIGNALCASE_CLOUD_URL=https://YOUR_DOMAIN \
SIGNALCASE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
SIGNALCASE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME \
./scripts/build-app.sh --open
```

The app is created at `macOS/.build/Signalcase.app`. The build script registers the `signalcase://` callback scheme. It never embeds the Supabase secret key, Management OAuth client secret, provider access tokens, or encryption key.

For local testing, the build script can read the three public values from `website/.env.local`; with its current local site URL it points the app at `http://localhost:3002`.

## 7. Verify the real end-to-end flow

1. Start or deploy the website server.
2. Open the newly built Signalcase app.
3. Complete onboarding and select a local project folder.
4. Click **Sign in with GitHub**. The macOS authentication sheet should close and show your email.
5. Open **Settings** → **Connections** → **Supabase**.
6. Find the monitored project's reference in its Supabase dashboard URL or **Project Settings**, paste it, and click **Connect Supabase**.
7. Approve the `analytics:read` request. The sheet should close and the connection should show **Connected**.
8. In the monitored Supabase project's **SQL Editor**, run this harmless failing read to create a real error log:

```sql
select * from public.signalcase_connection_test_table_that_does_not_exist;
```

9. Wait about one minute for log ingestion.
10. In Signalcase, click **Sync logs**, select Supabase, choose the last 15 minutes, and sync.
11. Confirm a database-error case appears. Open it and verify its source is Supabase rather than demo data.

If authorization succeeds but sync returns `403`, confirm the Management OAuth app has **Analytics · Read**, then disconnect and reconnect so the new scope is granted. If the app reports missing cloud configuration, rebuild the app with the three public values in step 6.
