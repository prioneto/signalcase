# Contributing to Signalcase

Thanks for your interest in improving Signalcase! It is a free, open-source macOS app for small development teams.

## Ground rules

- **Issues are always welcome** — bug reports, false-positive detections, integration ideas, documentation gaps. The issue forms ask for what we need to reproduce a problem.
- **Please open an issue before starting a large PR.** This keeps the project maintainable by a solo maintainer and avoids wasted effort. Small, focused fixes can go straight to a PR.
- Every change must keep CI green: website typecheck + tests + build, and Swift build + tests.

## Development setup

1. **Website/server** (Next.js 16 + Supabase, Node.js 22.13+):

   ```bash
   cd website
   npm install
   npm run dev                  # http://localhost:3002
   npm run typecheck && npm test
   ```

   Without `.env.local` the site runs as the static demo, which is enough for landing-page work. For server features, `cp .env.example .env.local` and fill in your own development credentials.

2. **macOS app** (Swift 5.10 / SwiftUI):

   ```bash
   cd macOS
   swift build
   swift test
   ./scripts/build-app.sh --open   # packaged app in macOS/.build
   ```

3. **Database**: apply `supabase/migrations/` in filename order to your own Supabase project. See `docs/SELF_HOSTING.md`.

Use your own development Supabase project, OAuth applications, and GitHub App — never point local development at an instance real users depend on.

## Code style

- No comments unless they explain a non-obvious decision.
- Match the existing patterns: server-only tables have no client RLS policies, secrets are redacted before storage, every API route funnels errors through `jsonError`.
- Add tests for detection logic and API payload normalization.

## Reporting security issues

Do not open public issues for security problems. See [SECURITY.md](SECURITY.md).

## License

By contributing you agree that your contributions are licensed under the GNU Affero General Public License v3.0 (see [LICENSE](LICENSE)).
