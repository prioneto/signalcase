import { APIError, jsonError } from "@/lib/api-auth";
import { requireWorkspaceOwner, workspaceRole } from "@/lib/workspace";
import { requireProjectContext } from "@/lib/project-context";

type MutationBody = {
  projectId?: string;
  userId?: string;
  role?: "owner" | "member";
};

async function teamPayload(
  context: Awaited<ReturnType<typeof requireProjectContext>>,
) {
  const workspaceID = context.project.workspace_id;
  const [{ data: rows, error: membersError }, { data: invitations, error: invitationsError }] = await Promise.all([
    context.admin
      .from("workspace_members")
      .select("user_id, role, created_at")
      .eq("workspace_id", workspaceID)
      .order("created_at"),
    context.admin
      .from("invitations")
      .select("id, email, role, expires_at, created_at")
      .eq("workspace_id", workspaceID)
      .is("accepted_at", null)
      .is("revoked_at", null)
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false }),
  ]);
  if (membersError || invitationsError) throw membersError ?? invitationsError;
  const members = await Promise.all((rows ?? []).map(async (row) => {
    const { data } = await context.admin.auth.admin.getUserById(row.user_id);
    return {
      userId: row.user_id,
      email: data.user?.email ?? "Unknown account",
      role: row.role === "owner" ? "owner" : "member",
      joinedAt: row.created_at,
      isCurrentUser: row.user_id === context.user.id,
    };
  }));
  return {
    workspaceId: workspaceID,
    currentRole: context.role,
    members,
    invitations: (invitations ?? []).map((invite) => ({
      id: invite.id,
      email: invite.email,
      role: invite.role,
      expiresAt: invite.expires_at,
      createdAt: invite.created_at,
    })),
    memberLimit: context.limits?.memberLimit ?? 5,
  };
}

export async function GET(request: Request) {
  try {
    const projectID = new URL(request.url).searchParams.get("projectId");
    if (!projectID) throw new APIError("Choose a Signalcase project first.");
    const context = await requireProjectContext(request, projectID, {
      bucket: "team:read",
      maximum: 120,
    });
    return Response.json(await teamPayload(context));
  } catch (error) {
    return jsonError(error, request);
  }
}

export async function PATCH(request: Request) {
  try {
    const body = (await request.json()) as MutationBody;
    if (!body.projectId || !body.userId || !["owner", "member"].includes(body.role ?? "")) {
      throw new APIError("Choose a valid member role.");
    }
    const context = await requireProjectContext(request, body.projectId, {
      bucket: "team:role",
      maximum: 30,
    });
    const workspaceID = context.project.workspace_id;
    await requireWorkspaceOwner(context.admin, workspaceID, context.user.id);
    const targetRole = await workspaceRole(context.admin, workspaceID, body.userId);
    if (targetRole === "owner" && body.role === "member") {
      const { count, error } = await context.admin
        .from("workspace_members")
        .select("user_id", { count: "exact", head: true })
        .eq("workspace_id", workspaceID)
        .eq("role", "owner");
      if (error) throw error;
      if ((count ?? 0) <= 1) throw new APIError("A workspace must keep at least one owner.", 409);
    }
    const { error } = await context.admin.from("workspace_members").update({ role: body.role })
      .eq("workspace_id", workspaceID).eq("user_id", body.userId);
    if (error) throw error;
    return Response.json(await teamPayload({ ...context, role: await workspaceRole(context.admin, workspaceID, context.user.id) }));
  } catch (error) {
    return jsonError(error, request);
  }
}

export async function DELETE(request: Request) {
  try {
    const body = (await request.json()) as MutationBody;
    if (!body.projectId || !body.userId) throw new APIError("Choose a workspace member.");
    const context = await requireProjectContext(request, body.projectId, {
      bucket: "team:remove",
      maximum: 30,
    });
    const workspaceID = context.project.workspace_id;
    await requireWorkspaceOwner(context.admin, workspaceID, context.user.id);
    const targetRole = await workspaceRole(context.admin, workspaceID, body.userId);
    if (targetRole === "owner") {
      const { count, error } = await context.admin
        .from("workspace_members")
        .select("user_id", { count: "exact", head: true })
        .eq("workspace_id", workspaceID)
        .eq("role", "owner");
      if (error) throw error;
      if ((count ?? 0) <= 1) throw new APIError("A workspace must keep at least one owner.", 409);
    }
    const { error } = await context.admin.from("workspace_members").delete()
      .eq("workspace_id", workspaceID).eq("user_id", body.userId);
    if (error) throw error;
    if (body.userId === context.user.id) return Response.json({ leftWorkspace: true });
    return Response.json(await teamPayload(context));
  } catch (error) {
    return jsonError(error, request);
  }
}
