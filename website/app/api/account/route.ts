import { APIError, authenticate, jsonError } from "@/lib/api-auth";
import { enforceRateLimit } from "@/lib/rate-limit";

type Body = { confirmation?: string };

export async function DELETE(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (body.confirmation !== "DELETE") throw new APIError("Type DELETE to confirm account deletion.");
    const { admin, user } = await authenticate(request);
    await enforceRateLimit(admin, {
      bucket: "account:delete", subject: user.id, maximum: 3, windowSeconds: 3_600,
    });
    const { data: memberships, error } = await admin.from("workspace_members")
      .select("workspace_id, role").eq("user_id", user.id);
    if (error) throw error;

    for (const membership of memberships ?? []) {
      if (membership.role !== "owner") {
        const { error: removeError } = await admin.from("workspace_members").delete()
          .eq("workspace_id", membership.workspace_id).eq("user_id", user.id);
        if (removeError) throw removeError;
        continue;
      }
      const [{ count: ownerCount, error: ownerError }, { count: memberCount, error: memberError }] = await Promise.all([
        admin.from("workspace_members").select("user_id", { count: "exact", head: true })
          .eq("workspace_id", membership.workspace_id).eq("role", "owner"),
        admin.from("workspace_members").select("user_id", { count: "exact", head: true })
          .eq("workspace_id", membership.workspace_id),
      ]);
      if (ownerError || memberError) throw ownerError ?? memberError;
      if ((ownerCount ?? 0) > 1) {
        const { error: removeError } = await admin.from("workspace_members").delete()
          .eq("workspace_id", membership.workspace_id).eq("user_id", user.id);
        if (removeError) throw removeError;
      } else if ((memberCount ?? 0) > 1) {
        throw new APIError("Transfer workspace ownership before deleting your account.", 409);
      } else {
        const { error: workspaceError } = await admin.from("workspaces").delete()
          .eq("id", membership.workspace_id);
        if (workspaceError) throw workspaceError;
      }
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id, false);
    if (deleteError) throw deleteError;
    return Response.json({ deleted: true });
  } catch (error) {
    return jsonError(error, request);
  }
}
