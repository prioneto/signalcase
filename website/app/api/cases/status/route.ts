import { APIError, jsonError } from "@/lib/api-auth";
import { requireProjectContext } from "@/lib/project-context";
import { sharedCaseSelection, snapshotFromRow, type SharedCaseRow } from "@/lib/shared-cases";

type Body = {
  projectId?: string;
  caseId?: string;
  status?: "new" | "active" | "resolved";
};

export async function PATCH(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (!body.projectId || !body.caseId || !["new", "active", "resolved"].includes(body.status ?? "")) {
      throw new APIError("Choose a valid case status.");
    }
    const { admin, user } = await requireProjectContext(request, body.projectId, {
      bucket: "cases:status",
      maximum: 90,
    });
    const { data: current, error: currentError } = await admin
      .from("cases")
      .select(sharedCaseSelection)
      .eq("id", body.caseId)
      .eq("project_id", body.projectId)
      .is("deleted_at", null)
      .maybeSingle();
    if (currentError || !current) throw new APIError("Case not found.", 404);
    const row = current as unknown as SharedCaseRow;
    const nextStatus = body.status as "new" | "active" | "resolved";
    const snapshot = { ...row.snapshot, id: row.id, status: nextStatus };
    const { data: updated, error: updateError } = await admin
      .from("cases")
      .update({
        status: nextStatus,
        snapshot,
        revision: row.revision + 1,
        updated_by: user.id,
      })
      .eq("id", row.id)
      .eq("revision", row.revision)
      .select(sharedCaseSelection)
      .maybeSingle();
    if (updateError || !updated) throw new APIError("The case changed elsewhere. Refresh and try again.", 409);
    if (row.status !== nextStatus) {
      const { error: auditError } = await admin.from("case_status_changes").insert({
        case_id: row.id,
        changed_by: user.id,
        from_status: row.status,
        to_status: nextStatus,
      });
      if (auditError) console.error("case status audit failed", { caseID: row.id, message: auditError.message });
    }
    return Response.json({ case: snapshotFromRow(updated as unknown as SharedCaseRow) });
  } catch (error) {
    return jsonError(error, request);
  }
}
