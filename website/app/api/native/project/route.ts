import { APIError, authenticate, jsonError } from "@/lib/api-auth";

type Body = { name?: string; slug?: string };

async function workspaceFor(request: Request) {
  const { user, userClient } = await authenticate(request);
  const suggestedName = `${user.user_metadata.user_name ?? user.user_metadata.name ?? "My"}'s workspace`;
  const { data: workspace, error } = await userClient.rpc("ensure_workspace", {
    workspace_name: suggestedName,
  });
  if (error || !workspace) throw error ?? new Error("Workspace was not created.");
  return { userClient, workspace };
}

export async function GET(request: Request) {
  try {
    const { userClient, workspace } = await workspaceFor(request);
    const { data: projects, error } = await userClient
      .from("projects")
      .select("id, workspace_id, name, slug")
      .eq("workspace_id", workspace.id)
      .order("created_at");
    if (error) throw error;
    return Response.json({ projects: projects ?? [] });
  } catch (error) {
    return jsonError(error);
  }
}

export async function POST(request: Request) {
  try {
    const { userClient, workspace } = await workspaceFor(request);
    const body = (await request.json()) as Body;
    const name = body.name?.trim();
    const slug = body.slug?.trim().toLowerCase();
    if (!name || !slug || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) {
      throw new APIError("Enter a valid project name.");
    }

    const { data: existing, error: selectError } = await userClient
      .from("projects")
      .select("id, workspace_id, name, slug")
      .eq("workspace_id", workspace.id)
      .eq("slug", slug)
      .maybeSingle();
    if (selectError) throw selectError;
    if (existing) return Response.json({ project: existing });

    const { data: project, error: insertError } = await userClient
      .from("projects")
      .insert({ workspace_id: workspace.id, name, slug })
      .select("id, workspace_id, name, slug")
      .single();
    if (insertError || !project) throw insertError ?? new Error("Project was not created.");
    return Response.json({ project }, { status: 201 });
  } catch (error) {
    return jsonError(error);
  }
}
