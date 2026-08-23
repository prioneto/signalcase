import { requireProjectAccess } from "@/lib/api-auth";
import { workspaceLimits, workspaceRole, type WorkspaceLimits } from "@/lib/workspace";
import { enforceRateLimit } from "@/lib/rate-limit";

export async function requireProjectContext(
  request: Request,
  projectID: string,
  input: { bucket: string; maximum?: number; includeLimits?: boolean },
) {
  const context = await requireProjectAccess(request, projectID);
  const role = await workspaceRole(context.admin, context.project.workspace_id, context.user.id);
  await enforceRateLimit(context.admin, {
    bucket: input.bucket,
    subject: `${context.user.id}:${projectID}`,
    maximum: input.maximum ?? 120,
    windowSeconds: 60,
  });
  const limits: WorkspaceLimits | null = input.includeLimits === false
    ? null
    : await workspaceLimits(context.admin, context.project.workspace_id);
  return { ...context, role, limits };
}
