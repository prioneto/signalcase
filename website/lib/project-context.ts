import { requireProjectAccess } from "@/lib/api-auth";
import { requireWorkspaceEntitlement, workspaceRole } from "@/lib/billing";
import { enforceRateLimit } from "@/lib/rate-limit";

export async function requireProjectContext(
  request: Request,
  projectID: string,
  input: { bucket: string; maximum?: number; requireEntitlement?: boolean },
) {
  const context = await requireProjectAccess(request, projectID);
  const role = await workspaceRole(context.admin, context.project.workspace_id, context.user.id);
  await enforceRateLimit(context.admin, {
    bucket: input.bucket,
    subject: `${context.user.id}:${projectID}`,
    maximum: input.maximum ?? 120,
    windowSeconds: 60,
  });
  const billing = input.requireEntitlement === false
    ? null
    : await requireWorkspaceEntitlement(context.admin, context.project.workspace_id, role);
  return { ...context, role, billing };
}
