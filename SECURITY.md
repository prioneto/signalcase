# Security Policy

## Reporting a vulnerability

Please report security issues privately — do not open a public issue.

- Email: **security@signalcase.app**
- Include: what you found, how to reproduce it, and the affected component (`macOS/` app or `website/` server).
- You will receive an acknowledgement within **3 business days** and a status update at least every 7 days until resolution.
- Coordinated disclosure is welcome; we will credit reporters in release notes unless asked otherwise. Please allow a reasonable window (up to 90 days) before public disclosure.

## Scope

In scope:

- The Signalcase macOS application (`macOS/`)
- The hosted server and website (`website/`), including API routes, OAuth flows, credential storage, and the Supabase schema in `supabase/migrations/`

Out of scope:

- Vulnerabilities in third-party services themselves (Supabase, Vercel, GitHub) — please report those to the vendor
- Reports from automated scanners without a demonstrated impact
- Social engineering of hosting providers

## Design notes for reviewers

Security-relevant behavior worth knowing when auditing:

- Provider OAuth tokens are encrypted at rest (`website/lib/credential-crypto.ts`) and never exposed to clients.
- Credential tables have no client RLS policies on purpose; they are reachable only by the server (`service_role`).
- OAuth state parameters are stored hashed and single-use.
- All secrets are redacted from stored event payloads where they can be detected.
- The Application Logs ingest endpoint authenticates with hashed bearer secrets and is rate limited.

## Supported versions

Only the latest tagged release receives security fixes.
