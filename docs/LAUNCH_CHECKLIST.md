# Signalcase 0.1 launch checklist

## Implemented and live

- Shared cloud cases with synchronized New, Active, and Resolved status.
- Team invitations, atomic seat limits, Member/Owner roles, removal, and invitation revocation.
- Stripe Checkout, webhook processing, customer portal, 14-day trials, grace handling, and server-side entitlements.
- Project and account deletion, provider credential deletion, secret redaction, request size limits, rate limits, and request IDs.
- Thirty-day event retention with authenticated daily Vercel cleanup.
- Native Team and Billing settings plus website pricing and account dashboard.
- Supabase production migrations and Vercel production deployment.

## Required before public download

- [ ] Create and test the Stripe Team product/price, live webhook, and customer portal.
- [ ] Add Stripe Production environment variables, redeploy, then enable billing enforcement.
- [ ] Choose the final public price and make `NEXT_PUBLIC_TEAM_PRICE_LABEL` match Stripe.
- [ ] Buy the production domain and update Vercel, Supabase redirect URLs, Supabase Management OAuth, GitHub App URLs, and `NEXT_PUBLIC_SITE_URL`.
- [ ] Enroll in the Apple Developer Program; Developer ID sign, notarize, staple, and package the app.
- [ ] Host the notarized download and set `NEXT_PUBLIC_MAC_DOWNLOAD_URL`.
- [ ] Publish Terms of Service, Privacy Policy, refund/cancellation wording, support contact, and company/tax details. Have the legal text reviewed for the countries you sell into.
- [ ] Enable Supabase leaked-password protection if password sign-in remains enabled, or disable password sign-in if GitHub is the only supported method.
- [ ] Confirm the Supabase plan has appropriate backups and perform one restore rehearsal.
- [ ] Add transactional email delivery for invitation links, or explicitly launch with copy-link invitations.
- [ ] Run the collaboration, billing, deletion, provider, and fresh-Mac tests in `docs/PRODUCTION_SETUP.md`.
- [ ] Add customer-facing support/error monitoring for the Signalcase server itself.
- [ ] Commit and push the reviewed release changes, tag `v0.1.0`, and keep the GitHub repository private.
