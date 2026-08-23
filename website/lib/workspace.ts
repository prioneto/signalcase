import type { SupabaseClient } from "@supabase/supabase-js";
import { APIError } from "@/lib/api-auth";

export type WorkspaceRole = "owner" | "member";

export type WorkspaceLimits = {
  memberLimit: number;
  projectLimit: number;
  eventRetentionDays: number;
};

export function publicSiteURL() {
  const value = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "");
  if (!value) throw new APIError("The Signalcase site URL is not configured.", 503);
  return value;
}

export async function workspaceRole(
  admin: SupabaseClient,
  workspaceID: string,
  userID: string,
): Promise<WorkspaceRole> {
  const { data, error } = await admin
    .from("workspace_members")
    .select("role")
    .eq("workspace_id", workspaceID)
    .eq("user_id", userID)
    .maybeSingle();
  if (error || !data) throw new APIError("Workspace not found or access denied.", 404);
  return data.role === "owner" ? "owner" : "member";
}

export async function requireWorkspaceOwner(
  admin: SupabaseClient,
  workspaceID: string,
  userID: string,
) {
  const role = await workspaceRole(admin, workspaceID, userID);
  if (role !== "owner") throw new APIError("Only a workspace owner can do that.", 403);
  return role;
}

// Signalcase is free. These are fair-use limits that keep the hosted service
// fast and affordable for everyone; they are not paywalls.
export async function workspaceLimits(
  admin: SupabaseClient,
  workspaceID: string,
): Promise<WorkspaceLimits> {
  const { data, error } = await admin
    .from("workspace_settings")
    .select("member_limit, project_limit, event_retention_days")
    .eq("workspace_id", workspaceID)
    .maybeSingle();
  if (error) throw new APIError("Workspace settings could not be loaded.", 503);
  return {
    memberLimit: data?.member_limit ?? 5,
    projectLimit: data?.project_limit ?? 3,
    eventRetentionDays: data?.event_retention_days ?? 30,
  };
}
