import { createAdminClient } from "@/lib/supabase/admin";
import { decryptSecret, encryptSecret } from "@/lib/credential-crypto";
import { exchangeManagementToken, sha256 } from "@/lib/supabase-management";

function appRedirect(status: "authorized" | "error", message?: string) {
  const url = new URL("signalcase://integration/supabase");
  url.searchParams.set("status", status);
  if (message) url.searchParams.set("message", message.slice(0, 180));
  return Response.redirect(url, 302);
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const providerError = url.searchParams.get("error_description") ?? url.searchParams.get("error");
  if (providerError) return appRedirect("error", providerError);
  if (!code || !state) return appRedirect("error", "The authorization response was incomplete.");

  const admin = createAdminClient();
  try {
    const { data: pending, error } = await admin
      .from("provider_oauth_states")
      .select("id, project_id, code_verifier_ciphertext, redirect_uri, expires_at, consumed_at")
      .eq("state_hash", sha256(state))
      .maybeSingle();
    if (error || !pending) throw new Error("This connection request is not valid.");
    if (pending.consumed_at || new Date(pending.expires_at).getTime() <= Date.now()) {
      throw new Error("This connection request expired. Start it again in the app.");
    }

    const { data: consumed, error: consumeError } = await admin
      .from("provider_oauth_states")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", pending.id)
      .is("consumed_at", null)
      .select("id")
      .maybeSingle();
    if (consumeError || !consumed) throw new Error("This connection request was already used.");

    const token = await exchangeManagementToken(new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: pending.redirect_uri,
      code_verifier: decryptSecret(pending.code_verifier_ciphertext),
    }));

    const { data: connection, error: connectionError } = await admin
      .from("provider_connections")
      .select("id")
      .eq("project_id", pending.project_id)
      .eq("provider", "supabase")
      .single();
    if (connectionError || !connection) throw connectionError ?? new Error("Connection was not saved.");

    const expiresAt = token.expires_in
      ? new Date(Date.now() + token.expires_in * 1000).toISOString()
      : null;
    const { error: credentialError } = await admin.from("provider_credentials").upsert({
      connection_id: connection.id,
      access_token_ciphertext: encryptSecret(token.access_token),
      refresh_token_ciphertext: token.refresh_token ? encryptSecret(token.refresh_token) : null,
      token_type: token.token_type ?? "Bearer",
      granted_scope: token.scope ?? null,
      expires_at: expiresAt,
    });
    if (credentialError) throw credentialError;

    const { error: updateError } = await admin
      .from("provider_connections")
      .update({
        state: "connecting",
        connected_at: null,
        last_error: null,
        metadata: {},
      })
      .eq("id", connection.id);
    if (updateError) throw updateError;
    return appRedirect("authorized");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not connect Supabase.";
    return appRedirect("error", message);
  }
}
