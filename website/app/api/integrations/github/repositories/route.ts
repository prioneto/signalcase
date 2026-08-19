import { APIError, jsonError, requireProjectAccess } from "@/lib/api-auth";
import { actionableGitHubError, listGitHubRepositories } from "@/lib/github-app";

type SelectBody = { projectId?: string; repositoryId?: number };

async function accessibleRepositories(installationID: number) {
  try {
    return await listGitHubRepositories(installationID);
  } catch (error) {
    throw new APIError(actionableGitHubError(error, "load repositories"), 502);
  }
}

async function authorizedInstallation(request: Request, projectId: string) {
  const { admin } = await requireProjectAccess(request, projectId);
  const { data: connection, error } = await admin
    .from("provider_connections")
    .select("id, state, metadata")
    .eq("project_id", projectId)
    .eq("provider", "github")
    .maybeSingle();
  const installationID = Number(connection?.metadata?.installation_id);
  if (error || !connection || !Number.isSafeInteger(installationID) || installationID <= 0) {
    throw new APIError("Install the Signalcase GitHub App before choosing a repository.", 409);
  }
  return { admin, connection, installationID };
}

function repositoryOption(repository: Awaited<ReturnType<typeof listGitHubRepositories>>[number]) {
  return {
    id: repository.id,
    name: repository.name,
    fullName: repository.full_name,
    owner: repository.owner?.login ?? repository.full_name.split("/")[0],
    htmlUrl: repository.html_url,
    defaultBranch: repository.default_branch,
    isPrivate: repository.private,
  };
}

export async function GET(request: Request) {
  try {
    const projectId = new URL(request.url).searchParams.get("projectId");
    if (!projectId) throw new APIError("Missing Signalcase project ID.");
    const { installationID } = await authorizedInstallation(request, projectId);
    const repositories = await accessibleRepositories(installationID);
    return Response.json({ repositories: repositories.map(repositoryOption) });
  } catch (error) {
    return jsonError(error);
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as SelectBody;
    if (!body.projectId || !Number.isSafeInteger(body.repositoryId) || Number(body.repositoryId) <= 0) {
      throw new APIError("Choose a valid GitHub repository.");
    }
    const { admin, connection, installationID } = await authorizedInstallation(request, body.projectId);
    const repositories = await accessibleRepositories(installationID);
    const repository = repositories.find((item) => item.id === Number(body.repositoryId));
    if (!repository) throw new APIError("That repository is not available to this GitHub installation.", 403);
    const selected = repositoryOption(repository);
    const metadata = {
      ...connection.metadata,
      repository_id: selected.id,
      repository_name: selected.name,
      repository_full_name: selected.fullName,
      repository_owner: selected.owner,
      repository_html_url: selected.htmlUrl,
      default_branch: selected.defaultBranch,
      repository_private: selected.isPrivate,
    };
    const now = new Date().toISOString();
    const { error: projectError } = await admin
      .from("projects")
      .update({ repository_url: selected.htmlUrl })
      .eq("id", body.projectId);
    if (projectError) {
      console.warn("GitHub repository selected but project link could not be updated", {
        projectId: body.projectId,
        code: projectError.code,
      });
    }
    const { error: updateError } = await admin
      .from("provider_connections")
      .update({ state: "connected", metadata, connected_at: now, last_error: null })
      .eq("id", connection.id);
    if (updateError) throw updateError;
    return Response.json({ state: "connected", repository: selected });
  } catch (error) {
    return jsonError(error);
  }
}
