import { APIError, jsonError, requireProjectAccess } from "@/lib/api-auth";

export async function GET(request: Request) {
  try {
    const projectId = new URL(request.url).searchParams.get("projectId");
    if (!projectId) throw new APIError("Missing project ID.");
    const { admin } = await requireProjectAccess(request, projectId);
    const { data, error } = await admin
      .from("provider_connections")
      .select("state, metadata, connected_at, last_synced_at, last_error")
      .eq("project_id", projectId)
      .eq("provider", "supabase")
      .maybeSingle();
    if (error) throw error;
    return Response.json({
      state: data?.state ?? "disconnected",
      externalProjectRef: data?.metadata?.external_project_ref ?? null,
      connectedAt: data?.connected_at ?? null,
      lastSyncedAt: data?.last_synced_at ?? null,
      error: data?.last_error ?? null,
    });
  } catch (error) {
    return jsonError(error);
  }
}
