import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "./actions";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const inviteNotices: Record<string, string> = {
  accepted: "Invitation accepted. The shared workspace is now available in the Mac app.",
  expired: "That invitation expired or was already used.",
  "email-mismatch": "Sign in with the email address that received the invitation.",
  full: "That workspace has reached its member limit.",
  failed: "The invitation could not be accepted. Ask the owner for a new link.",
};

export default async function DashboardPage({ searchParams }: Props) {
  const query = await searchParams;
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  if (!claimsData?.claims) redirect("/sign-in");
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/sign-in");

  const { data: memberships, error: membershipError } = await supabase
    .from("workspace_members")
    .select("workspace_id, role, created_at")
    .eq("user_id", user.id)
    .order("created_at");
  if (membershipError) throw new Error(membershipError.message);
  const workspaceIDs = (memberships ?? []).map((item) => item.workspace_id);

  const [workspaceResult, projectResult, settingsResult, membersResult] = workspaceIDs.length
    ? await Promise.all([
        supabase.from("workspaces").select("id, name, created_at").in("id", workspaceIDs),
        supabase.from("projects").select("id, workspace_id, name, slug, created_at").in("workspace_id", workspaceIDs).order("created_at"),
        supabase.from("workspace_settings").select("workspace_id, member_limit, project_limit, event_retention_days").in("workspace_id", workspaceIDs),
        supabase.from("workspace_members").select("workspace_id, user_id").in("workspace_id", workspaceIDs),
      ])
    : [
        { data: [], error: null }, { data: [], error: null },
        { data: [], error: null }, { data: [], error: null },
      ];
  const firstError = [workspaceResult, projectResult, settingsResult, membersResult]
    .find((result) => result.error)?.error;
  if (firstError) throw new Error(firstError.message);

  const workspaces = workspaceResult.data ?? [];
  const projects = projectResult.data ?? [];
  const settings = settingsResult.data ?? [];
  const allMembers = membersResult.data ?? [];
  const downloadURL = process.env.NEXT_PUBLIC_MAC_DOWNLOAD_URL;
  const notice = typeof query.invite === "string"
    ? inviteNotices[query.invite]
    : null;

  return (
    <main className="cloud-page">
      <header className="cloud-header">
        <a className="auth-brand" href="/"><span>⌁</span>SIGNALCASE</a>
        <div className="cloud-account">
          <span>{user.email ?? "Signed in"}</span>
          <form action={signOut}><button className="cloud-secondary" type="submit">Sign out</button></form>
        </div>
      </header>

      <section className="cloud-content">
        <div className="auth-eyebrow">YOUR ACCOUNT</div>
        <h1>Signalcase Cloud</h1>
        {notice ? <div className="cloud-notice">{notice}</div> : null}

        {downloadURL ? (
          <div className="cloud-card cloud-download">
            <div><span className="cloud-status" /><strong>Signalcase for macOS</strong></div>
            <p>Download the signed Mac app, then sign in with this same account.</p>
            <a className="auth-button" href={downloadURL}>Download for Mac <span>↓</span></a>
          </div>
        ) : null}

        {workspaces.length ? workspaces.map((workspace) => {
          const membership = memberships?.find((item) => item.workspace_id === workspace.id);
          const workspaceProjects = projects.filter((item) => item.workspace_id === workspace.id);
          const limits = settings.find((item) => item.workspace_id === workspace.id);
          const memberCount = allMembers.filter((item) => item.workspace_id === workspace.id).length;
          return (
            <section className="cloud-workspace" key={workspace.id}>
              <div className="cloud-section-title cloud-workspace-title">
                <div><div className="auth-eyebrow">WORKSPACE</div><h2>{workspace.name}</h2><p>{membership?.role === "owner" ? "Owner" : "Member"}</p></div>
                <span>FREE</span>
              </div>

              <div className="cloud-metrics">
                <div><strong>{memberCount} / {limits?.member_limit ?? 5}</strong><span>Members</span></div>
                <div><strong>{workspaceProjects.length} / {limits?.project_limit ?? 3}</strong><span>Projects</span></div>
                <div><strong>{limits?.event_retention_days ?? 30} days</strong><span>Event history</span></div>
              </div>

              <div className="cloud-section-title"><div><h2>Projects</h2><p>Cases and statuses sync through these projects.</p></div><span>{workspaceProjects.length}</span></div>
              {workspaceProjects.length ? (
                <div className="cloud-projects">
                  {workspaceProjects.map((item) => <article className="cloud-project" key={item.id}><div>▰</div><section><strong>{item.name}</strong><p>{item.slug}</p></section></article>)}
                </div>
              ) : <div className="cloud-empty"><strong>No project yet</strong><p>Open the Signalcase app to create your first project.</p></div>}
            </section>
          );
        }) : (
          <div className="cloud-empty"><strong>No workspace yet</strong><p>Open the Signalcase app and create your first project.</p></div>
        )}
      </section>
    </main>
  );
}
