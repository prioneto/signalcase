const required = [
  "NEXT_PUBLIC_SITE_URL",
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  "SUPABASE_SECRET_KEY",
  "SUPABASE_MANAGEMENT_CLIENT_ID",
  "SUPABASE_MANAGEMENT_CLIENT_SECRET",
  "CREDENTIAL_ENCRYPTION_KEY",
  "GITHUB_APP_ID",
  "GITHUB_APP_SLUG",
  "GITHUB_APP_PRIVATE_KEY",
] as const;

export async function GET() {
  const missing = required.filter((name) => !process.env[name]);
  const encryptionKey = process.env.CREDENTIAL_ENCRYPTION_KEY;
  const encryptionKeyValid = encryptionKey
    ? Buffer.from(encryptionKey, "base64").length === 32
    : false;
  const ok = missing.length === 0 && encryptionKeyValid;

  return Response.json(
    {
      ok,
      missing,
      checks: {
        encryptionKey: encryptionKeyValid ? "valid" : "invalid",
        providerOAuth: process.env.SUPABASE_MANAGEMENT_CLIENT_ID
          && process.env.SUPABASE_MANAGEMENT_CLIENT_SECRET
          ? "configured"
          : "missing",
        githubApp: process.env.GITHUB_APP_ID
          && process.env.GITHUB_APP_SLUG
          && process.env.GITHUB_APP_PRIVATE_KEY
          ? "configured"
          : "missing",
        billing: process.env.STRIPE_SECRET_KEY
          && process.env.STRIPE_WEBHOOK_SECRET
          && process.env.STRIPE_TEAM_PRICE_ID
          ? "configured"
          : "missing",
        billingEnforcement: process.env.BILLING_ENFORCEMENT_ENABLED === "true"
          ? "enabled"
          : "disabled",
        retentionCleanup: process.env.CRON_SECRET ? "configured" : "missing",
      },
    },
    {
      status: ok ? 200 : 503,
      headers: { "Cache-Control": "no-store" },
    },
  );
}
