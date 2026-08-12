import { APIError, jsonError, requireProjectAccess } from "@/lib/api-auth";
import { encryptSecret } from "@/lib/credential-crypto";
import {
  managementAuthorizationURL,
  managementCallbackURL,
  randomURLSafe,
  sha256,
} from "@/lib/supabase-management";

type Body = { projectId?: string };

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (!body.projectId) throw new APIError("Link a project before connecting Supabase.");
    const { admin } = await requireProjectAccess(request, body.projectId);
    const state = randomURLSafe();
    const verifier = randomURLSafe(48);
    const redirectURI = managementCallbackURL();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    const { data: connection, error: connectionError } = await admin
      .from("provider_connections")
      .upsert({
        project_id: body.projectId,
        provider: "supabase",
        state: "connecting",
        metadata: {},
        last_error: null,
      }, { onConflict: "project_id,provider" })
      .select("id")
      .single();
    if (connectionError || !connection) throw connectionError ?? new Error("Connection was not prepared.");

    const { error: stateError } = await admin.from("provider_oauth_states").insert({
      project_id: body.projectId,
      provider: "supabase",
      state_hash: sha256(state),
      code_verifier_ciphertext: encryptSecret(verifier),
      external_project_ref: null,
      redirect_uri: redirectURI,
      expires_at: expiresAt,
    });
    if (stateError) throw stateError;

    return Response.json({
      authorizationUrl: managementAuthorizationURL({
        state,
        codeChallenge: sha256(verifier),
        redirectURI,
      }),
    });
  } catch (error) {
    return jsonError(error);
  }
}
