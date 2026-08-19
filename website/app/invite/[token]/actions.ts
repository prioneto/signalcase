"use server";

import { redirect } from "next/navigation";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { invitationTokenHash } from "@/lib/team";

export async function acceptInvitation(formData: FormData) {
  const token = String(formData.get("token") ?? "");
  if (!token || token.length > 200) redirect("/dashboard?invite=invalid");

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user?.email) redirect(`/sign-in?next=${encodeURIComponent(`/invite/${token}`)}`);

  const admin = createAdminClient();
  const { data: invitation, error } = await admin.from("invitations")
    .select("id, workspace_id, email, role, expires_at, accepted_at, revoked_at")
    .eq("token_hash", invitationTokenHash(token))
    .maybeSingle();
  if (error || !invitation || invitation.accepted_at || invitation.revoked_at
      || new Date(invitation.expires_at).getTime() <= Date.now()) {
    redirect("/dashboard?invite=expired");
  }
  if (invitation.email.toLowerCase() !== user.email.toLowerCase()) {
    redirect("/dashboard?invite=email-mismatch");
  }

  const { error: acceptError } = await admin.rpc("accept_signalcase_invitation", {
    invited_token_hash: invitationTokenHash(token),
    accepting_user_id: user.id,
    accepting_email: user.email,
  });
  if (acceptError?.message.toLowerCase().includes("limit")) redirect("/dashboard?invite=full");
  if (acceptError) redirect("/dashboard?invite=failed");
  redirect("/dashboard?invite=accepted");
}
