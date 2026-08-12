import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "./actions";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const supabase = await createClient();

  const { data: claimsData } = await supabase.auth.getClaims();

  if (!claimsData?.claims) {
    redirect("/sign-in");
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: workspaces, error: workspaceError } = await supabase
    .from("workspaces")
    .select("id, name, created_at")
    .order("created_at")
    .limit(1);

  if (workspaceError) {
    throw new Error(workspaceError.message);
  }

  const workspace = workspaces?.[0];

  const { data: projects, error: projectError } = workspace
    ? await supabase
        .from("projects")
        .select("id, name, slug, created_at")
        .eq("workspace_id", workspace.id)
        .order("created_at")
    : { data: [], error: null };

  if (projectError) {
    throw new Error(projectError.message);
  }

  return (
    <main className="cloud-page">
      <header className="cloud-header">
        <a className="auth-brand" href="/">
          <span>⌁</span>
          SIGNALCASE
        </a>

        <div className="cloud-account">
          <span>{user?.email ?? "Signed in"}</span>

          <form action={signOut}>
            <button className="cloud-secondary" type="submit">
              Sign out
            </button>
          </form>
        </div>
      </header>

      <section className="cloud-content">
        <div className="auth-eyebrow">WORKSPACE</div>
        <h1>{workspace?.name ?? "Your workspace"}</h1>

        <div className="cloud-card">
          <div>
            <span className="cloud-status" />
            <strong>Signalcase Cloud is connected</strong>
          </div>

          <p>
            Your account and workspace are now stored in the hosted Signalcase
            database.
          </p>
        </div>

        <div className="cloud-section-title">
          <div>
            <h2>Projects</h2>
            <p>Each project keeps its own connections and cases.</p>
          </div>

          <span>{projects?.length ?? 0}</span>
        </div>

        {projects?.length ? (
          <div className="cloud-projects">
            {projects.map((project) => (
              <article className="cloud-project" key={project.id}>
                <div>▰</div>
                <section>
                  <strong>{project.name}</strong>
                  <p>{project.slug}</p>
                </section>
              </article>
            ))}
          </div>
        ) : (
          <div className="cloud-empty">
            <strong>No project yet</strong>
            <p>
              Open the Signalcase app to create your first project.
            </p>
          </div>
        )}
      </section>
    </main>
  );
}
