import { APIError, jsonError } from "@/lib/api-auth";
import { requireProjectContext } from "@/lib/project-context";
import {
  mergeSharedCaseSnapshot,
  normalizeSharedCase,
  sharedCaseColumns,
  sharedCaseSelection,
  snapshotFromRow,
  type SharedCaseRow,
} from "@/lib/shared-cases";

type SyncBody = { projectId?: string; cases?: unknown[] };

async function allProjectCases(admin: Awaited<ReturnType<typeof requireProjectContext>>["admin"], projectID: string) {
  const { data, error } = await admin
    .from("cases")
    .select(sharedCaseSelection)
    .eq("project_id", projectID)
    .is("deleted_at", null)
    .order("last_seen_at", { ascending: false })
    .limit(1_000);
  if (error) throw error;
  return ((data ?? []) as unknown as SharedCaseRow[]).map(snapshotFromRow);
}

export async function GET(request: Request) {
  try {
    const projectID = new URL(request.url).searchParams.get("projectId");
    if (!projectID) throw new APIError("Choose a Signalcase project first.");
    const { admin } = await requireProjectContext(request, projectID, {
      bucket: "cases:read",
      maximum: 180,
    });
    return Response.json({ cases: await allProjectCases(admin, projectID) });
  } catch (error) {
    return jsonError(error, request);
  }
}

export async function POST(request: Request) {
  try {
    const contentLength = Number(request.headers.get("content-length") ?? "0");
    if (Number.isFinite(contentLength) && contentLength > 5_000_000) {
      throw new APIError("The shared case update is too large.", 413);
    }
    const body = (await request.json()) as SyncBody;
    if (!body.projectId || !Array.isArray(body.cases)) {
      throw new APIError("Send a project and its cases.");
    }
    if (body.cases.length > 500) throw new APIError("Sync at most 500 cases at once.", 413);

    const { admin, user } = await requireProjectContext(request, body.projectId, {
      bucket: "cases:sync",
      maximum: 30,
    });
    const incomingCases = body.cases.map(normalizeSharedCase);

    for (const incoming of incomingCases) {
      const { data: existing, error: existingError } = await admin
        .from("cases")
        .select(sharedCaseSelection)
        .eq("project_id", body.projectId)
        .eq("fingerprint", incoming.fingerprint)
        .maybeSingle();
      if (existingError) throw existingError;
      const current = existing as unknown as SharedCaseRow | null;
      const merged = mergeSharedCaseSnapshot(current, incoming);

      if (!current) {
        const { error: insertError } = await admin.from("cases").insert({
          id: incoming.id,
          project_id: body.projectId,
          ...sharedCaseColumns(merged, user.id),
          created_by: user.id,
        });
        if (!insertError) continue;

        // Another teammate may have inserted the fingerprint between the read
        // and write. Re-read it and merge instead of surfacing a false failure.
        const { data: raced, error: racedError } = await admin
          .from("cases")
          .select(sharedCaseSelection)
          .eq("project_id", body.projectId)
          .eq("fingerprint", incoming.fingerprint)
          .maybeSingle();
        if (racedError || !raced) throw insertError;
        const racedRow = raced as unknown as SharedCaseRow;
        const racedSnapshot = mergeSharedCaseSnapshot(racedRow, incoming);
        const { error: updateError } = await admin.from("cases").update({
          ...sharedCaseColumns(racedSnapshot, user.id),
          deleted_at: racedRow.deleted_at
            && new Date(incoming.lastSeen).getTime() > new Date(racedRow.last_seen_at).getTime()
            ? null
            : racedRow.deleted_at,
          revision: racedRow.revision + 1,
        }).eq("id", racedRow.id).eq("revision", racedRow.revision);
        if (updateError) throw updateError;
        continue;
      }

      const { error: updateError } = await admin.from("cases").update({
        ...sharedCaseColumns(merged, user.id),
        deleted_at: current.deleted_at
          && new Date(incoming.lastSeen).getTime() > new Date(current.last_seen_at).getTime()
          ? null
          : current.deleted_at,
        revision: current.revision + 1,
      }).eq("id", current.id).eq("revision", current.revision);
      if (updateError) throw updateError;
    }

    return Response.json({ cases: await allProjectCases(admin, body.projectId) });
  } catch (error) {
    return jsonError(error, request);
  }
}

type CaseMutationBody = { projectId?: string; caseId?: string };

export async function DELETE(request: Request) {
  try {
    const body = (await request.json()) as CaseMutationBody;
    if (!body.projectId || !body.caseId) throw new APIError("Choose a case to delete.");
    const { admin, user } = await requireProjectContext(request, body.projectId, {
      bucket: "cases:delete",
      maximum: 60,
    });
    const { error } = await admin.from("cases").update({
      deleted_at: new Date().toISOString(),
      updated_by: user.id,
    }).eq("id", body.caseId).eq("project_id", body.projectId);
    if (error) throw error;
    return Response.json({ deleted: true });
  } catch (error) {
    return jsonError(error, request);
  }
}

export async function PUT(request: Request) {
  try {
    const body = (await request.json()) as CaseMutationBody;
    if (!body.projectId || !body.caseId) throw new APIError("Choose a case to restore.");
    const { admin, user } = await requireProjectContext(request, body.projectId, {
      bucket: "cases:restore",
      maximum: 60,
    });
    const { error } = await admin.from("cases").update({
      deleted_at: null,
      updated_by: user.id,
    }).eq("id", body.caseId).eq("project_id", body.projectId);
    if (error) throw error;
    return Response.json({ restored: true });
  } catch (error) {
    return jsonError(error, request);
  }
}
