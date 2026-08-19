"use server";

import { redirect } from "next/navigation";
import { APIError } from "@/lib/api-auth";
import {
  publicSiteURL,
  stripe,
  stripeConfigured,
  stripeTeamPriceID,
  workspaceBillingState,
} from "@/lib/billing";
import { enforceRateLimit } from "@/lib/rate-limit";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export async function signOut() {
  const supabase = await createClient();

  await supabase.auth.signOut({
    scope: "local",
  });

  redirect("/sign-in");
}

async function billingContext(formData: FormData, bucket: string) {
  const projectID = String(formData.get("projectId") ?? "");
  if (!projectID) throw new APIError("Choose a project first.");
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/sign-in");
  const { data: project } = await supabase.from("projects")
    .select("id, workspace_id").eq("id", projectID).maybeSingle();
  if (!project) throw new APIError("Project not found.", 404);
  const { data: membership } = await supabase.from("workspace_members")
    .select("role").eq("workspace_id", project.workspace_id).eq("user_id", user.id).maybeSingle();
  if (membership?.role !== "owner") throw new APIError("Only a workspace owner can manage billing.", 403);
  const admin = createAdminClient();
  await enforceRateLimit(admin, {
    bucket,
    subject: user.id,
    maximum: 10,
    windowSeconds: 60,
  });
  return { admin, project, user };
}

export async function startCheckout(formData: FormData) {
  if (!stripeConfigured()) redirect("/dashboard?billing=not-configured");
  const { admin, project, user } = await billingContext(formData, "dashboard:checkout");
  const billing = await workspaceBillingState(admin, project.workspace_id, "owner");
  if (billing.subscriptionID && ["trialing", "active", "past_due"].includes(billing.status)) {
    redirect("/dashboard?billing=already-subscribed");
  }

  let customerID = billing.customerID;
  if (!customerID) {
    const customer = await stripe().customers.create({
      email: user.email,
      name: user.user_metadata?.name ?? undefined,
      metadata: { signalcase_workspace_id: project.workspace_id },
    });
    customerID = customer.id;
    const { error } = await admin.from("workspace_subscriptions")
      .update({ stripe_customer_id: customerID }).eq("workspace_id", project.workspace_id);
    if (error) throw error;
  }
  const trialEnd = billing.trialEndsAt
    ? Math.floor(new Date(billing.trialEndsAt).getTime() / 1_000)
    : 0;
  const subscriptionData: Record<string, unknown> = {
    metadata: { signalcase_workspace_id: project.workspace_id },
  };
  if (trialEnd > Math.floor(Date.now() / 1_000) + 48 * 3_600) subscriptionData.trial_end = trialEnd;
  const session = await stripe().checkout.sessions.create({
    mode: "subscription",
    customer: customerID,
    client_reference_id: project.workspace_id,
    line_items: [{ price: stripeTeamPriceID(), quantity: 1 }],
    allow_promotion_codes: true,
    automatic_tax: { enabled: true },
    success_url: `${publicSiteURL()}/dashboard?billing=success`,
    cancel_url: `${publicSiteURL()}/dashboard?billing=cancelled`,
    metadata: { signalcase_workspace_id: project.workspace_id },
    subscription_data: subscriptionData,
  });
  if (!session.url) throw new Error("Stripe did not return a checkout page.");
  redirect(session.url);
}

export async function manageBilling(formData: FormData) {
  const { admin, project } = await billingContext(formData, "dashboard:portal");
  const billing = await workspaceBillingState(admin, project.workspace_id, "owner");
  if (!billing.customerID) redirect("/dashboard?billing=not-subscribed");
  const session = await stripe().billingPortal.sessions.create({
    customer: billing.customerID,
    return_url: `${publicSiteURL()}/dashboard`,
  });
  redirect(session.url);
}
