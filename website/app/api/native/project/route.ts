import { APIError, authenticate, jsonError } from "@/lib/api-auth";
import { requireWorkspaceEntitlement, requireWorkspaceOwner, workspaceRole } from "@/lib/billing";
import { enforceRateLimit } from "@/lib/rate-limit";
import { requireProjectContext } from "@/lib/project-context";

type Body = { name?: string; slug?: string; projectId?: string; workspaceId?: string };

async function workspaceFor(request: Request) {
  const auth = await authenticate(request);
  const { user, userClient } = auth;
  const suggestedName = `${user.user_metadata.user_name ?? user.user_metadata.name ?? "My"}'s workspace`;
  const { data: workspace, error } = await userClient.rpc("ensure_workspace", {
    workspace_name: suggestedName,
  });
  if (error || !workspace) throw error ?? new Error("Workspace was not created.");
  return { ...auth, workspace };
}

export async function GET(request: Request) {
  try {
    const { user, userClient, admin } = await workspaceFor(request);
    await enforceRateLimit(admin, {
      bucket: "projects:read", subject: user.id, maximum: 120, windowSeconds: 60,
    });
    const { data: projects, error } = await userClient
      .from("projects")
      .select("id, workspace_id, name, slug")
      .order("created_at");
    if (error) throw error;
    return Response.json({ projects: projects ?? [] });
  } catch (error) {
    return jsonError(error, request);
  }
}

export async function POST(request: Request) {
  try {
    const { user, userClient, admin, workspace } = await workspaceFor(request);
    await enforceRateLimit(admin, {
      bucket: "projects:create", subject: user.id, maximum: 10, windowSeconds: 3_600,
    });
    const body = (await request.json()) as Body;
    const workspaceID = body.workspaceId ?? workspace.id;
    const role = await workspaceRole(admin, workspaceID, user.id);
    await requireWorkspaceOwner(admin, workspaceID, user.id);
    const billing = await requireWorkspaceEntitlement(admin, workspaceID, role);
    const name = body.name?.trim();
    const slug = body.slug?.trim().toLowerCase();
    if (!name || !slug || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) {
      throw new APIError("Enter a valid project name.");
    }

    const { data: existing, error: selectError } = await userClient
      .from("projects")
      .select("id, workspace_id, name, slug")
      .eq("workspace_id", workspaceID)
      .eq("slug", slug)
      .maybeSingle();
    if (selectError) throw selectError;
    if (existing) return Response.json({ project: existing });

    const { count, error: countError } = await admin.from("projects")
      .select("id", { count: "exact", head: true }).eq("workspace_id", workspaceID);
    if (countError) throw countError;
    if ((count ?? 0) >= billing.projectLimit) {
      throw new APIError(`This plan includes ${billing.projectLimit} projects.`, 409);
    }

    const { data: project, error: insertError } = await userClient
      .from("projects")
      .insert({ workspace_id: workspaceID, name, slug })
      .select("id, workspace_id, name, slug")
      .single();
    if (insertError || !project) throw insertError ?? new Error("Project was not created.");
    return Response.json({ project }, { status: 201 });
  } catch (error) {
    return jsonError(error, request);
  }
}

export async function DELETE(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (!body.projectId) throw new APIError("Choose a project to delete.");
    const context = await requireProjectContext(request, body.projectId, {
      bucket: "projects:delete", maximum: 10, requireEntitlement: false,
    });
    await requireWorkspaceOwner(context.admin, context.project.workspace_id, context.user.id);
    const { error } = await context.admin.from("projects").delete().eq("id", body.projectId);
    if (error) throw error;
    return Response.json({ deleted: true });
  } catch (error) {
    return jsonError(error, request);
  }
}
