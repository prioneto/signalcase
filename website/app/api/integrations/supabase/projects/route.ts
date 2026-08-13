import { APIError, jsonError, requireProjectAccess } from "@/lib/api-auth";
import { decryptSecret, encryptSecret } from "@/lib/credential-crypto";
import { exchangeManagementToken, managementAPI } from "@/lib/supabase-management";

type SelectBody = { projectId?: string; projectRef?: string };

type ManagementProject = {
  id?: string;
  ref?: string;
  name?: string;
  organization_id?: string;
  organization_slug?: string;
  region?: string;
  status?: string;
};

async function authorizedConnection(request: Request, projectId: string) {
  const { admin } = await requireProjectAccess(request, projectId);
  const { data: connection, error: connectionError } = await admin
    .from("provider_connections")
    .select("id, state")
    .eq("project_id", projectId)
    .eq("provider", "supabase")
    .maybeSingle();
  if (connectionError || !connection || !["connecting", "connected"].includes(connection.state)) {
    throw new APIError("Authorize Supabase before choosing a project.", 409);
  }

  const { data: credential, error: credentialError } = await admin
    .from("provider_credentials")
    .select("*")
    .eq("connection_id", connection.id)
    .maybeSingle();
  if (credentialError || !credential) {
    throw new APIError("Authorize Supabase before choosing a project.", 409);
  }

  let accessToken = decryptSecret(credential.access_token_ciphertext);
  if (credential.expires_at && new Date(credential.expires_at).getTime() < Date.now() + 60_000) {
    if (!credential.refresh_token_ciphertext) {
      throw new APIError("Supabase authorization expired. Connect it again.", 409);
    }
    const refreshed = await exchangeManagementToken(new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: decryptSecret(credential.refresh_token_ciphertext),
    }));
    accessToken = refreshed.access_token;
    const expiresAt = refreshed.expires_in
      ? new Date(Date.now() + refreshed.expires_in * 1000).toISOString()
      : null;
    const { error: refreshError } = await admin.from("provider_credentials").update({
      access_token_ciphertext: encryptSecret(refreshed.access_token),
      refresh_token_ciphertext: refreshed.refresh_token
        ? encryptSecret(refreshed.refresh_token)
        : credential.refresh_token_ciphertext,
      expires_at: expiresAt,
      granted_scope: refreshed.scope ?? credential.granted_scope,
    }).eq("connection_id", connection.id);
    if (refreshError) throw refreshError;
  }

  return { admin, connection, accessToken };
}

async function accessibleProjects(accessToken: string) {
  const response = await fetch(`${managementAPI}/projects`, {
    headers: { Authorization: `Bearer ${accessToken}` },
    cache: "no-store",
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const providerMessage = payload.message ?? payload.error ?? `Supabase returned ${response.status}.`;
    if (response.status === 401) {
      throw new APIError(
        "Your Supabase authorization is no longer valid. Reconnect Supabase to authorize it again.",
        401,
      );
    }
    if (response.status === 403) {
      throw new APIError(
        "Signalcase's Supabase OAuth app is missing Projects · Read permission. The app owner must enable Projects · Read and Analytics · Read in Supabase, then reconnect.",
        403,
      );
    }
    throw new APIError(String(providerMessage), 502);
  }
  if (!Array.isArray(payload)) throw new APIError("Supabase returned an unreadable project list.", 502);

  return (payload as ManagementProject[]).flatMap((project) => {
    const ref = project.ref ?? project.id;
    if (!ref || !project.name) return [];
    return [{
      ref,
      name: project.name,
      organizationSlug: project.organization_slug ?? null,
      region: project.region ?? null,
      status: project.status ?? null,
    }];
  }).sort((left, right) => left.name.localeCompare(right.name));
}

export async function GET(request: Request) {
  try {
    const projectId = new URL(request.url).searchParams.get("projectId");
    if (!projectId) throw new APIError("Missing Signalcase project ID.");
    const { accessToken } = await authorizedConnection(request, projectId);
    return Response.json({ projects: await accessibleProjects(accessToken) });
  } catch (error) {
    return jsonError(error);
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as SelectBody;
    if (!body.projectId) throw new APIError("Missing Signalcase project ID.");
    const projectRef = body.projectRef?.trim();
    if (!projectRef || !/^[a-z0-9]{10,40}$/i.test(projectRef)) {
      throw new APIError("Choose a valid Supabase project.");
    }

    const { admin, connection, accessToken } = await authorizedConnection(request, body.projectId);
    const projects = await accessibleProjects(accessToken);
    const selected = projects.find((project) => project.ref === projectRef);
    if (!selected) throw new APIError("That Supabase project is not available to this account.", 403);

    const { error } = await admin.from("provider_connections").update({
      state: "connected",
      metadata: {
        external_project_ref: selected.ref,
        external_project_name: selected.name,
        organization_slug: selected.organizationSlug,
        external_project_region: selected.region,
        external_project_status: selected.status,
      },
      connected_at: new Date().toISOString(),
      last_error: null,
    }).eq("id", connection.id);
    if (error) throw error;

    return Response.json({
      state: "connected",
      externalProjectRef: selected.ref,
      project: selected,
    });
  } catch (error) {
    return jsonError(error);
  }
}
