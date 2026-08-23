# Self-hosting Signalcase

Signalcase is free software (AGPL-3.0). The hosted instance at [signalcase.app](https://signalcase.app) is one deployment of this code — you can run your own completely independent copy with your own Supabase project, your own OAuth applications, and zero connection to the hosted service.

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

## License

Running your own instance is exactly what the AGPL-3.0 intends. If you modify the server code and offer it as a network service, section 13 of the license requires you to offer your modified source to your users. See [LICENSE](../LICENSE).
