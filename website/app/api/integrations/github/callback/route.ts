import { createAdminClient } from "@/lib/supabase/admin";
import { getGitHubInstallation } from "@/lib/github-app";
import { sha256 } from "@/lib/supabase-management";

function appRedirect(status: "authorized" | "error", message?: string) {
  const url = new URL("signalcase://integration/github");
  url.searchParams.set("status", status);
  if (message) url.searchParams.set("message", message.slice(0, 180));
  return Response.redirect(url, 302);
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const state = url.searchParams.get("state");
  const installationValue = url.searchParams.get("installation_id");
  const setupAction = url.searchParams.get("setup_action");
  if (!state || !installationValue) {
    return appRedirect("error", "GitHub did not return an installation. Try connecting again.");
  }
  const installationID = Number(installationValue);
  if (!Number.isSafeInteger(installationID) || installationID <= 0) {
    return appRedirect("error", "GitHub returned an invalid installation.");
  }

  const admin = createAdminClient();
  try {
    const { data: pending, error } = await admin
      .from("provider_oauth_states")
      .select("id, project_id, expires_at, consumed_at")
      .eq("provider", "github")
      .eq("state_hash", sha256(state))
      .maybeSingle();
    if (error || !pending) throw new Error("This GitHub connection request is not valid.");
    if (pending.consumed_at || new Date(pending.expires_at).getTime() <= Date.now()) {
      throw new Error("This GitHub connection request expired. Start it again in Signalcase.");
    }

    const { data: consumed, error: consumeError } = await admin
      .from("provider_oauth_states")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", pending.id)
      .is("consumed_at", null)
      .select("id")
      .maybeSingle();
    if (consumeError || !consumed) throw new Error("This GitHub connection request was already used.");

    const installation = await getGitHubInstallation(installationID);
    if (installation.suspended_at) throw new Error("This GitHub App installation is suspended.");
    const account = installation.account?.login ?? "GitHub account";

    const { error: updateError } = await admin
      .from("provider_connections")
      .update({
        state: "connecting",
        metadata: {
          installation_id: installation.id,
          account_login: account,
          account_avatar_url: installation.account?.avatar_url ?? null,
          account_type: installation.account?.type ?? null,
          repository_selection: installation.repository_selection ?? null,
          setup_action: setupAction ?? "install",
        },
        connected_at: null,
        last_error: null,
      })
      .eq("project_id", pending.project_id)
      .eq("provider", "github");
    if (updateError) throw updateError;

    return appRedirect("authorized");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not connect GitHub.";
    return appRedirect("error", message);
  }
}
