import { APIError, jsonError, requireProjectAccess } from "@/lib/api-auth";
import {
  applicationEndpointPath,
  generateApplicationSecret,
  hashApplicationSecret,
} from "@/lib/application-events";

type Body = { projectId?: string };

function endpoint(request: Request) {
  return new URL(applicationEndpointPath, request.url).toString();
}

export async function GET(request: Request) {
  try {
    const projectId = new URL(request.url).searchParams.get("projectId");
    if (!projectId) throw new APIError("Choose a Signalcase project first.");
    const { admin } = await requireProjectAccess(request, projectId);
    const { data: connection, error } = await admin
      .from("provider_connections")
      .select("id, state, connected_at, last_synced_at, last_error")
      .eq("project_id", projectId)
      .eq("provider", "application")
      .maybeSingle();
    if (error) throw error;
    if (!connection) return Response.json({ state: "disconnected", endpoint: endpoint(request) });
    const { data: key, error: keyError } = await admin
      .from("application_ingest_keys")
      .select("last_used_at")
      .eq("project_id", projectId)
      .maybeSingle();
    if (keyError) throw keyError;
    return Response.json({
      state: key ? connection.state : "disconnected",
      endpoint: endpoint(request),
      connectedAt: connection.connected_at,
      lastEventAt: key?.last_used_at ?? null,
      error: connection.last_error,
    });
  } catch (error) {
    return jsonError(error);
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (!body.projectId) throw new APIError("Choose a Signalcase project first.");
    const { admin } = await requireProjectAccess(request, body.projectId);
    const now = new Date().toISOString();
    const { data: connection, error: connectionError } = await admin
      .from("provider_connections")
      .upsert({
        project_id: body.projectId,
        provider: "application",
        state: "connected",
        metadata: { mode: "hosted", endpoint_path: applicationEndpointPath },
        connected_at: now,
        last_error: null,
      }, { onConflict: "project_id,provider" })
      .select("id")
      .single();
    if (connectionError || !connection) throw connectionError ?? new Error("Could not create the receiver.");

    const secret = generateApplicationSecret();
    const { error: keyError } = await admin
      .from("application_ingest_keys")
      .upsert({
        project_id: body.projectId,
        connection_id: connection.id,
        secret_hash: hashApplicationSecret(secret),
        last_used_at: null,
      }, { onConflict: "project_id" });
    if (keyError) throw keyError;

    return Response.json({
      state: "connected",
      endpoint: endpoint(request),
      authorization: `Bearer ${secret}`,
      connectedAt: now,
    }, { status: 201 });
  } catch (error) {
    return jsonError(error);
  }
}

export async function DELETE(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (!body.projectId) throw new APIError("Choose a Signalcase project first.");
    const { admin } = await requireProjectAccess(request, body.projectId);
    const { error: keyError } = await admin
      .from("application_ingest_keys")
      .delete()
      .eq("project_id", body.projectId);
    if (keyError) throw keyError;
    const { error: connectionError } = await admin
      .from("provider_connections")
      .update({ state: "disconnected", connected_at: null, last_error: null })
      .eq("project_id", body.projectId)
      .eq("provider", "application");
    if (connectionError) throw connectionError;
    return Response.json({ state: "disconnected", endpoint: endpoint(request) });
  } catch (error) {
    return jsonError(error);
  }
}
