# Self-hosting Signalcase

Signalcase is free software (AGPL-3.0) with no official hosted service — running your own instance is the way to use it. This guide gives you a completely independent deployment: your own Supabase project, your own OAuth applications, and zero connection to anyone else's infrastructure.

## What you need

| Component | Purpose | Free tier works? |
| --- | --- | --- |
| Supabase project | Database, auth, storage | Yes |
| Vercel project | Hosts the website and API routes | Yes |
| GitHub account | Sign-in provider + a GitHub App for repository evidence | Yes |
| Apple Developer Program ($99/yr) | Only if you distribute a signed, notarized Mac app to other people | Local `swift build` needs nothing |
| A domain | Redirect URLs must match exactly | Any hostname works, including Vercel's default |

No payment or billing configuration is required anywhere — Signalcase has no payment code.

## 1. Create the database

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

This applies every migration in `supabase/migrations/` in order. Verify that `provider_oauth_states`, `provider_credentials`, `application_ingest_keys`, and `error_reports` exist.

Credential tables intentionally have no client RLS policies — they are server-only (`service_role`).

## 2. Configure GitHub sign-in

1. In your Supabase project: **Authentication → URL Configuration**.
2. Set **Site URL** to your domain.
3. Add these **Redirect URLs**, replacing the domain:

```text
https://YOUR_DOMAIN/auth/callback
http://localhost:3002/auth/callback
signalcase://auth/callback
```

4. Enable **Authentication → Providers → GitHub** using your own GitHub OAuth application. Its callback stays the Supabase-provided URL shown on the provider page.

## 3. Create a Supabase Management OAuth app

This is separate from sign-in; it grants read-only access to a user's chosen Supabase project logs.

1. Supabase organization settings → **OAuth Apps → Add application**.
2. Redirect URL: exactly `https://YOUR_DOMAIN/api/integrations/supabase/callback`.
3. Scopes: **Projects · Read** and **Analytics · Read** — no write scopes.
4. Save, then copy the client ID and client secret (shown once).

For local development create a second app with `http://localhost:3002/api/integrations/supabase/callback` as its redirect.

## 4. Create a GitHub App

Also separate from sign-in; it lets users approve specific repositories for Actions evidence.

1. GitHub → Settings → **Developer settings → GitHub Apps → New GitHub App**.
2. Homepage URL: your domain. Leave **Callback URL** empty.
3. Disable **Request user authorization (OAuth) during installation**.
4. Setup URL: exactly `https://YOUR_DOMAIN/api/integrations/github/callback`, enable **Redirect on update**.
5. Turn webhooks **off** (evidence is polled).
6. Permissions: **Actions · Read-only** only (plus required Metadata read).
7. Installable on **Any account**.
8. Copy the numeric App ID, the slug, and generate a private key (`.pem`, keep server-side).

## 5. Deploy to Vercel

Set the root directory to `website` and configure Production environment variables:

| Variable | Value |
| --- | --- |
| `NEXT_PUBLIC_SITE_URL` | `https://YOUR_DOMAIN` |
| `NEXT_PUBLIC_SUPABASE_URL` | Your Supabase Project URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_…` key (safe in clients) |
| `SUPABASE_SECRET_KEY` | `sb_secret_…` key (server-only) |
| `SUPABASE_MANAGEMENT_CLIENT_ID` | From step 3 |
| `SUPABASE_MANAGEMENT_CLIENT_SECRET` | From step 3 |
| `CREDENTIAL_ENCRYPTION_KEY` | `openssl rand -base64 32` — keep stable forever |
| `GITHUB_APP_ID` / `GITHUB_APP_SLUG` / `GITHUB_APP_PRIVATE_KEY` | From step 4 |
| `CRON_SECRET` | Long random value for the retention cron |

Without the Supabase variables the deployment serves only the static demo: the landing page and legal pages work, and `/sign-in` and `/dashboard` explain that Signalcase is self-hosted.

Redeploy after saving, then verify:

- `https://YOUR_DOMAIN/api/health` → `"ok": true`
- `https://YOUR_DOMAIN/sign-in` → GitHub sign-in reaches `/dashboard`

Generate every secret yourself. Nothing from any other Signalcase deployment is reused.

## 6. Build the Mac app

```bash
cd macOS
cp .env.build.example .env.build   # fill YOUR_DOMAIN + your Supabase public values
./scripts/build-app.sh --open
```

The script registers the `signalcase://` deep-link scheme and embeds only the three public values. For distribution outside your machine, Developer ID sign, notarize, staple, then host the artifact and set `NEXT_PUBLIC_MAC_DOWNLOAD_URL`.

Release updates by bumping `macOS/VERSION`, building, and setting `MAC_RELEASE_VERSION` / `MAC_RELEASE_BUILD` so clients see the new version through `/api/releases/latest`.

## 7. Operational notes

- Retention cleanup runs daily via the Vercel cron at `/api/cron/cleanup`, authenticated with `CRON_SECRET`.
- Errors from the server and connected apps land in the `error_reports` table (90-day retention).
- Fair-use limits (members per workspace, projects per workspace, event history days) live in `workspace_settings`; tune them there if you want different defaults.
- Legal pages at `/terms`, `/privacy`, and `/support` ship with placeholder entity details — replace them in `website/lib/site.ts` before serving real users.

## 8. Verify your deployment

With the app built and pointed at your server:

**Sign-in and Supabase evidence**

1. Launch the app, complete onboarding, then **Sign in with GitHub** — the browser should open and return you with your email shown.
2. **Settings → Connections → Supabase → Connect Supabase** and approve the `projects:read` + `analytics:read` request.
3. In the monitored project's SQL editor, run this harmless failing read:

   ```sql
   select * from public.signalcase_connection_test_table_that_does_not_exist;
   ```

4. Wait about a minute, then sync the last 15 minutes from Signalcase. A database-error case should appear.

If sync returns `403`, your Management OAuth app is missing a scope — reconnect after enabling both read scopes.

**GitHub evidence**

1. **Settings → Connections → GitHub → Connect GitHub**, approve one repository, install.
2. Trigger a failing Actions workflow (or pick an older window containing a failure) and sync.
3. The failed run appears as a case with branch, run number, actor, commit SHA, and a link back to Actions.

**Application Logs**

1. **Settings → Connections → Application Logs → Create production endpoint**, copy the generated variables into a server-side test project.
2. Send the JSON example shown in the app while the Mac app is closed, reopen, sync the matching window.

**Collaboration**

1. Invite a second account from **Settings → Team**, accept via the copied link in a private browser window.
2. Sign in on another Mac (or another user account), select the shared project, and confirm cases and status changes propagate — including a resolved case reopening when newer evidence arrives.
3. Test role changes, member removal, project deletion, and account deletion with disposable accounts.
4. `GET /api/cron/cleanup` without the bearer token must return `401`.

## 9. Releases and updates

- Bump `macOS/VERSION`, rebuild, and note the build number printed by `build-app.sh`.
- Set `MAC_RELEASE_VERSION` / `MAC_RELEASE_BUILD` on your deployment so connected apps see the update through `/api/releases/latest` within a day or via **Settings → General → Check for Updates**.
- This channel notifies users; they replace the app themselves. Locally built apps are not notarized, so downloaded binaries will require a right-click → Open (or `xattr -cr`) on machines other than the build machine.

## License

Running your own instance is exactly what the AGPL-3.0 intends. If you modify the server code and offer it as a network service, section 13 of the license requires you to offer your modified source to your users. See [LICENSE](../LICENSE).
