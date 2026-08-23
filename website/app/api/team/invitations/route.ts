import { APIError, jsonError } from "@/lib/api-auth";
import { publicSiteURL, requireWorkspaceOwner, workspaceLimits } from "@/lib/workspace";
import { requireProjectContext } from "@/lib/project-context";
import { invitationToken, invitationTokenHash, normalizedEmail } from "@/lib/team";

type Body = {
  projectId?: string;
  invitationId?: string;
  email?: string;
  role?: "owner" | "member";
};

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as Body;
    const email = normalizedEmail(body.email);
    if (!body.projectId || !email || !["owner", "member"].includes(body.role ?? "member")) {
      throw new APIError("Enter a valid email address and role.");
    }
    const context = await requireProjectContext(request, body.projectId, {
      bucket: "team:invite",
      maximum: 20,
    });
    const workspaceID = context.project.workspace_id;
    await requireWorkspaceOwner(context.admin, workspaceID, context.user.id);
    const limits = await workspaceLimits(context.admin, workspaceID);
    const { data: users } = await context.admin.auth.admin.listUsers({ page: 1, perPage: 1_000 });
    const existingUser = users.users.find((user) => user.email?.toLowerCase() === email);
    if (existingUser) {
      const { data: existingMember } = await context.admin.from("workspace_members").select("user_id")
        .eq("workspace_id", workspaceID).eq("user_id", existingUser.id).maybeSingle();
      if (existingMember) throw new APIError("That person is already in this workspace.", 409);
    }

    const token = invitationToken();
    const expiresAt = new Date(Date.now() + 7 * 86_400_000).toISOString();
    const { data: invitation, error } = await context.admin.rpc("create_signalcase_invitation", {
      target_workspace_id: workspaceID,
      actor_user_id: context.user.id,
      invited_email: email,
      invited_role: body.role ?? "member",
      invited_token_hash: invitationTokenHash(token),
      invitation_expires_at: expiresAt,
    });
    if (error?.message.toLowerCase().includes("limit")) {
      throw new APIError(`This workspace allows up to ${limits.memberLimit} team members.`, 409);
    }
    if (error || !invitation) throw error ?? new Error("Invitation was not created.");
    return Response.json({
      invitation: {
        id: invitation.id,
        email: invitation.email,
        role: invitation.role,
        expiresAt: invitation.expires_at,
        url: `${publicSiteURL()}/invite/${encodeURIComponent(token)}`,
      },
    }, { status: 201 });
  } catch (error) {
    return jsonError(error, request);
  }
}

export async function DELETE(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (!body.projectId || !body.invitationId) throw new APIError("Choose an invitation.");
    const context = await requireProjectContext(request, body.projectId, {
      bucket: "team:invite:revoke",
      maximum: 30,
      includeLimits: false,
    });
    await requireWorkspaceOwner(context.admin, context.project.workspace_id, context.user.id);
    const { error } = await context.admin.from("invitations").update({ revoked_at: new Date().toISOString() })
      .eq("id", body.invitationId).eq("workspace_id", context.project.workspace_id)
      .is("accepted_at", null).is("revoked_at", null);
    if (error) throw error;
    return Response.json({ revoked: true });
  } catch (error) {
    return jsonError(error, request);
  }
}
