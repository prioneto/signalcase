# Signalcase 0.1 launch checklist

Signalcase is **free and self-hosted**: clone the repo, build the Mac app, run your own server. There is no payment, no Apple Developer requirement, and nothing to purchase — apps built locally run without notarization.

## Implemented and live

- Shared cloud cases with synchronized New, Active, and Resolved status.
- Team invitations, seat limits, Member/Owner roles, removal, and invitation revocation.
- Project and account deletion, provider credential deletion, secret redaction, request size limits, rate limits, and request IDs.
- Thirty-day event retention with authenticated daily Vercel cleanup.
- Native Team settings plus a free-positioned landing page and account dashboard.
- Supabase migrations and a working Vercel deployment recipe (`docs/SELF_HOSTING.md`).
- Terms of Service, Privacy Policy, and a support page (`/terms`, `/privacy`, `/support`).
- First-party error monitoring: server 5xx capture plus native crash/error reporting into `error_reports`.
- GitHub Actions CI running website typecheck/tests/build, Swift build/tests, and gitleaks on every push and PR.
- Versioned builds (`macOS/VERSION`) with an update channel: `/api/releases/latest` manifest and in-app update check.

## Required to publish

- [ ] Fill in real contact details in `website/lib/site.ts` (entity name is optional for a personal project; keep the support email deliverable).
- [ ] Flip the GitHub repository to public (Settings → General → Danger Zone).
- [ ] Tag `v0.1.0` and push the tag.
- [ ] Create a GitHub Release for `v0.1.0` with release notes. Source-only is fine; if you attach a built `.app`/`.zip`, note in the notes that users must right-click → Open (or run `xattr -cr`) because it is not notarized.
- [ ] Tear down everything except the demo website: delete the Supabase project last, after removing the Supabase org Management OAuth app, the Signalcase GitHub App, and the GitHub sign-in OAuth app. The Vercel deployment stays as a demo — with no backend env vars it shows the landing demo and legal pages, while `/dashboard` and `/sign-in` explain that Signalcase is self-hosted.
- [ ] Enable Supabase leaked-password protection if password sign-in remains enabled, or disable password sign-in if GitHub is the only supported method.
- [ ] Confirm the Supabase plan has automatic backups and perform one restore rehearsal.
- [ ] Launch with copy-link invitations (documented in-product); add transactional email later only if needed.
- [ ] Run the deployment verification steps in `docs/SELF_HOSTING.md` (§8).

## After publishing

- [ ] Watch `error_reports` on your instance during the first weeks.
- [ ] Add repo topics/description on GitHub for discoverability.
