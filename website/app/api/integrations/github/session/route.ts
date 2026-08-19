import { APIError, jsonError } from "@/lib/api-auth";
import { encryptSecret } from "@/lib/credential-crypto";
import { githubCallbackURL, githubInstallationURL } from "@/lib/github-app";
import { requireProjectContext } from "@/lib/project-context";
import { randomURLSafe, sha256 } from "@/lib/supabase-management";

type Body = { projectId?: string };

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (!body.projectId) throw new APIError("Choose a Signalcase project first.");
    const { admin } = await requireProjectContext(request, body.projectId, {
      bucket: "github-connect",
      maximum: 10,
    });
    const state = randomURLSafe();

    const { error: connectionError } = await admin
      .from("provider_connections")
      .upsert({
        project_id: body.projectId,
        provider: "github",
        state: "connecting",
        metadata: {},
        connected_at: null,
        last_error: null,
      }, { onConflict: "project_id,provider" });
    if (connectionError) throw connectionError;

    const { error: stateError } = await admin.from("provider_oauth_states").insert({
      project_id: body.projectId,
      provider: "github",
      state_hash: sha256(state),
      code_verifier_ciphertext: encryptSecret(randomURLSafe()),
      external_project_ref: null,
      redirect_uri: githubCallbackURL(),
      expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    });
    if (stateError) throw stateError;

    return Response.json({ authorizationUrl: githubInstallationURL(state) });
  } catch (error) {
    return jsonError(error, request);
  }
}
