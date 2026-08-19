import { APIError, jsonError } from "@/lib/api-auth";
import { requireProjectContext } from "@/lib/project-context";

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
    if (end.getTime() - start.getTime() > 24 * 60 * 60 * 1_000) {
      throw new APIError("A single sync can cover at most 24 hours.");
    }
    const { userClient } = await requireProjectContext(request, body.projectId, {
      bucket: "application-sync",
      maximum: 30,
    });
    const { data, error } = await userClient
      .from("raw_events")
      .select("provider_event_id, level, event_type, title, summary, request_id, actor_external_id, release, route, payload, occurred_at")
      .eq("project_id", body.projectId)
      .eq("provider", "application")
      .gte("occurred_at", start.toISOString())
      .lte("occurred_at", end.toISOString())
      .order("occurred_at", { ascending: false })
      .limit(1_000);
    if (error) throw error;

    const events = (data ?? []).map((row) => ({
      ...(row.payload && typeof row.payload === "object" ? row.payload : {}),
      event_id: row.provider_event_id,
      timestamp: row.occurred_at,
      level: row.level,
      event_type: row.event_type,
      title: row.title,
      message: row.summary ?? row.title,
      request_id: row.request_id,
      user_id: row.actor_external_id,
      release: row.release,
      route: row.route,
    }));
    return Response.json({ payload: { events } });
  } catch (error) {
    return jsonError(error, request);
  }
}
