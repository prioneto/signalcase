import { createAdminClient, createUserClient } from "@/lib/supabase/admin";

export class APIError extends Error {
  constructor(
    message: string,
    readonly status = 400,
  ) {
    super(message);
  }
}

export function bearerToken(request: Request) {
  const authorization = request.headers.get("authorization") ?? "";
  const [scheme, token] = authorization.split(" ");
  if (scheme?.toLowerCase() !== "bearer" || !token) {
    throw new APIError("Sign in to Signalcase first.", 401);
  }
  return token;
}

export async function authenticate(request: Request) {
  const accessToken = bearerToken(request);
  const admin = createAdminClient();
  const { data, error } = await admin.auth.getUser(accessToken);
  if (error || !data.user) throw new APIError("Your session expired. Sign in again.", 401);
  return {
    accessToken,
    user: data.user,
    userClient: createUserClient(accessToken),
    admin,
  };
}

export async function requireProjectAccess(request: Request, projectId: string) {
  const auth = await authenticate(request);
  const { data, error } = await auth.userClient
    .from("projects")
    .select("id, workspace_id, name, slug")
    .eq("id", projectId)
    .maybeSingle();

  if (error || !data) throw new APIError("Project not found or access denied.", 404);
  return { ...auth, project: data };
}

export function jsonError(error: unknown) {
  const status = error instanceof APIError ? error.status : 500;
  const message = error instanceof Error ? error.message : "Unexpected server error.";
  return Response.json(
    { error: status === 500 ? "The server could not complete this request." : message },
    { status, headers: { "Cache-Control": "no-store" } },
  );
}
