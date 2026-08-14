import { APIError, jsonError, requireProjectAccess } from "@/lib/api-auth";

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { projectId?: string };
    if (!body.projectId) throw new APIError("Missing project ID.");
    const { admin } = await requireProjectAccess(request, body.projectId);
    const { error } = await admin
      .from("provider_connections")
      .update({
        state: "disconnected",
        metadata: {},
        connected_at: null,
        last_synced_at: null,
        last_error: null,
      })
      .eq("project_id", body.projectId)
      .eq("provider", "github");
    if (error) throw error;
    const { error: projectError } = await admin
      .from("projects")
      .update({ repository_url: null })
      .eq("id", body.projectId);
    if (projectError) throw projectError;
    return Response.json({ state: "disconnected" });
  } catch (error) {
    return jsonError(error);
  }
}
