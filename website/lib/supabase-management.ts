import { createHash, randomBytes } from "node:crypto";

export const managementAPI = "https://api.supabase.com/v1";

export function randomURLSafe(bytes = 32) {
  return randomBytes(bytes).toString("base64url");
}

export function sha256(value: string) {
  return createHash("sha256").update(value).digest("base64url");
}

export function managementCallbackURL() {
  const site = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "");
  if (!site) throw new Error("Missing server environment variable: NEXT_PUBLIC_SITE_URL");
  return `${site}/api/integrations/supabase/callback`;
}

export function managementAuthorizationURL(input: {
  state: string;
  codeChallenge: string;
  redirectURI: string;
}) {
  const clientId = process.env.SUPABASE_MANAGEMENT_CLIENT_ID;
  if (!clientId) throw new Error("Missing server environment variable: SUPABASE_MANAGEMENT_CLIENT_ID");
  const url = new URL(`${managementAPI}/oauth/authorize`);
  url.searchParams.set("client_id", clientId);
  url.searchParams.set("redirect_uri", input.redirectURI);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("state", input.state);
  url.searchParams.set("code_challenge", input.codeChallenge);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("scope", "projects:read analytics:read");
  return url.toString();
}

export type ManagementToken = {
  access_token: string;
  refresh_token?: string;
  token_type?: string;
  expires_in?: number;
  scope?: string;
};

export async function exchangeManagementToken(parameters: URLSearchParams) {
  const clientId = process.env.SUPABASE_MANAGEMENT_CLIENT_ID;
  const clientSecret = process.env.SUPABASE_MANAGEMENT_CLIENT_SECRET;
  if (!clientId || !clientSecret) throw new Error("Supabase Management OAuth is not configured.");

  const response = await fetch(`${managementAPI}/oauth/token`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: parameters,
    cache: "no-store",
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const reason = payload.error_description ?? payload.message ?? payload.error ?? "Token exchange failed.";
    throw new Error(String(reason));
  }
  return payload as ManagementToken;
}
