import { APIError, jsonError, requireProjectAccess } from "@/lib/api-auth";
import { githubRepositoryEvidence } from "@/lib/github-app";

type Body = { projectId?: string; start?: string; end?: string };

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (!body.projectId || !body.start || !body.end) throw new APIError("Missing sync time range.");
    const start = new Date(body.start);
    const end = new Date(body.end);
    if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || end <= start) {
      throw new APIError("Choose a valid sync time range.");
    }
    if (end.getTime() - start.getTime() > 24 * 60 * 60 * 1000) {
      throw new APIError("A single sync can cover at most 24 hours.");
    }

    const { admin } = await requireProjectAccess(request, body.projectId);
    const { data: connection, error } = await admin
      .from("provider_connections")
      .select("id, state, metadata")
      .eq("project_id", body.projectId)
      .eq("provider", "github")
      .maybeSingle();
    const installationID = Number(connection?.metadata?.installation_id);
    const repositoryFullName = String(connection?.metadata?.repository_full_name ?? "");
    if (error || !connection || connection.state !== "connected" || !repositoryFullName || !Number.isSafeInteger(installationID)) {
      throw new APIError("Connect a GitHub repository before syncing.", 409);
    }

    try {
      const workflowRuns = await githubRepositoryEvidence({
        installationID,
        repositoryFullName,
        start,
        end,
      });
      const now = new Date().toISOString();
      await admin.from("provider_connections").update({
        state: "connected",
        last_synced_at: now,
        last_error: null,
      }).eq("id", connection.id);
      return Response.json({ payload: { repository: repositoryFullName, workflow_runs: workflowRuns } });
    } catch (providerError) {
      const message = providerError instanceof Error ? providerError.message : "GitHub sync failed.";
      await admin.from("provider_connections").update({ state: "error", last_error: message }).eq("id", connection.id);
      throw new APIError(message, 502);
    }
  } catch (error) {
    return jsonError(error);
  }
}
