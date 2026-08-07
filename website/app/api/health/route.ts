const required = [
  "NEXT_PUBLIC_SITE_URL",
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  "SUPABASE_SECRET_KEY",
  "SUPABASE_MANAGEMENT_CLIENT_ID",
  "SUPABASE_MANAGEMENT_CLIENT_SECRET",
  "CREDENTIAL_ENCRYPTION_KEY",
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
      },
    },
    {
      status: ok ? 200 : 503,
      headers: { "Cache-Control": "no-store" },
    },
  );
}
