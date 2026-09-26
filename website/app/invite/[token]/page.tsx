import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { invitationTokenHash } from "@/lib/team";
import { acceptInvitation } from "./actions";

type InvitePageProps = { params: Promise<{ token: string }> };

export default async function InvitePage({ params }: InvitePageProps) {
  const { token } = await params;
  const admin = createAdminClient();
  const { data: invitation } = await admin.from("invitations")
    .select("workspace_id, email, role, expires_at, accepted_at, revoked_at")
    .eq("token_hash", invitationTokenHash(token))
    .maybeSingle();
  const valid = Boolean(
    invitation
      && !invitation.accepted_at
      && !invitation.revoked_at
      && new Date(invitation.expires_at).getTime() > Date.now(),
  );
  const { data: workspace } = valid
    ? await admin.from("workspaces").select("name").eq("id", invitation!.workspace_id).maybeSingle()
    : { data: null };
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  return (
    <main className="auth-page">
      <Link className="auth-brand" href="/"><span><BrandMark /></span>SIGNALCASE</Link>
      <section className="auth-card">
        <div className="auth-eyebrow">TEAM INVITATION</div>
        {valid ? (
          <>
            <h1>Join {workspace?.name ?? "this workspace"}</h1>
            <p>You were invited as {invitation!.role === "owner" ? "an owner" : "a member"}. Shared cases and statuses appear on every team Mac.</p>
            {user?.email?.toLowerCase() === invitation!.email.toLowerCase() ? (
              <form action={acceptInvitation}>
                <input name="token" type="hidden" value={token} />
                <button className="auth-button" type="submit">Accept invitation <span>→</span></button>
              </form>
            ) : (
              <Link className="auth-button" href={`/sign-in?next=${encodeURIComponent(`/invite/${token}`)}`}>
                {user ? "Sign in with the invited account" : "Sign in to accept"}<span>→</span>
              </Link>
            )}
            <small>The invitation must be accepted with {invitation!.email}.</small>
          </>
        ) : (
          <>
            <h1>This invitation is no longer available</h1>
            <p>It may have expired, been revoked, or already been accepted.</p>
            <Link className="auth-button" href="/dashboard">Open Signalcase <span>→</span></Link>
          </>
        )}
      </section>
    </main>
  );
}
