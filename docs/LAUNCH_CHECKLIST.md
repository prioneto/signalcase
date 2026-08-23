# Signalcase 0.1 launch checklist

Signalcase is a **free** product: download, sign in, use it. There is no payment, subscription, or billing enforcement.

## Implemented and live

- Shared cloud cases with synchronized New, Active, and Resolved status.
- Team invitations, seat limits, Member/Owner roles, removal, and invitation revocation.
- Project and account deletion, provider credential deletion, secret redaction, request size limits, rate limits, and request IDs.
- Thirty-day event retention with authenticated daily Vercel cleanup.
- Native Team settings plus website pricing-free landing page and account dashboard.
- Supabase production migrations and Vercel production deployment.
- Terms of Service, Privacy Policy, and a support page (`/terms`, `/privacy`, `/support`).
- First-party error monitoring: server 5xx capture plus native crash/error reporting into `error_reports`.
- GitHub Actions CI running website typecheck/tests/build and Swift build/tests on every push and PR.
- Versioned builds (`macOS/VERSION`) with an update channel: `/api/releases/latest` manifest and in-app update check.

## Required before public download

- [ ] Buy the production domain and update Vercel, Supabase redirect URLs, Supabase Management OAuth, GitHub App URLs, and `NEXT_PUBLIC_SITE_URL`.
- [ ] Enroll in the Apple Developer Program; Developer ID sign, notarize, staple, and package the app.
- [ ] Host the notarized download and set `NEXT_PUBLIC_MAC_DOWNLOAD_URL`, `MAC_RELEASE_VERSION`, and `MAC_RELEASE_BUILD`.
- [ ] Review the legal text on `/terms` and `/privacy`, and fill in the real entity details in `website/lib/site.ts`.
- [ ] Decide the free-tier limits for launch (members, projects, retention) and confirm they match what the landing page promises.
- [ ] Enable Supabase leaked-password protection if password sign-in remains enabled, or disable password sign-in if GitHub is the only supported method.
- [ ] Confirm the Supabase plan has appropriate backups and perform one restore rehearsal.
- [ ] Add transactional email delivery for invitation links, or explicitly launch with copy-link invitations.
- [ ] Run the collaboration, deletion, provider, and fresh-Mac tests in `docs/PRODUCTION_SETUP.md`.
- [ ] Watch `error_reports` during the first beta week.
- [ ] Open-source preparation is complete: AGPL `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, gitleaks CI job, project ref scrubbed from docs, and `docs/SELF_HOSTING.md` published. Remaining: flip the GitHub repository to public, then tag `v0.1.0`.
