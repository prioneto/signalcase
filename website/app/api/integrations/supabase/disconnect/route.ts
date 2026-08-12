import { APIError, jsonError, requireProjectAccess } from "@/lib/api-auth";

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { projectId?: string };
    if (!body.projectId) throw new APIError("Missing project ID.");
    const { admin } = await requireProjectAccess(request, body.projectId);
    const { data: connection, error } = await admin
      .from("provider_connections")
      .select("id")
      .eq("project_id", body.projectId)
      .eq("provider", "supabase")
      .maybeSingle();
    if (error) throw error;
    if (connection) {
      await admin.from("provider_credentials").delete().eq("connection_id", connection.id);
      const { error: updateError } = await admin
        .from("provider_connections")
        .update({ state: "disconnected", metadata: {}, connected_at: null, last_error: null })
        .eq("id", connection.id);
      if (updateError) throw updateError;
    }
    return Response.json({ state: "disconnected" });
  } catch (error) {
    return jsonError(error);
  }
}
