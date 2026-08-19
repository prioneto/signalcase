import type { SupabaseClient } from "@supabase/supabase-js";
import Stripe from "stripe";
import { APIError } from "@/lib/api-auth";

export type WorkspaceRole = "owner" | "member";

export type BillingState = {
  configured: boolean;
  enforcementEnabled: boolean;
  access: boolean;
  plan: string;
  status: string;
  provider: string;
  trialEndsAt: string | null;
  currentPeriodEndsAt: string | null;
  cancelAtPeriodEnd: boolean;
  memberLimit: number;
  projectLimit: number;
  eventRetentionDays: number;
  canManage: boolean;
};

type SubscriptionRow = {
  provider: string;
  plan_key: string;
  status: string;
  stripe_customer_id: string | null;
  stripe_subscription_id: string | null;
  stripe_price_id: string | null;
  trial_ends_at: string | null;
  current_period_ends_at: string | null;
  cancel_at_period_end: boolean;
  last_payment_failed_at: string | null;
};

type WorkspaceSettingsRow = {
  member_limit: number;
  project_limit: number;
  event_retention_days: number;
};

let stripeClient: Stripe | null = null;

export function stripeConfigured() {
  return Boolean(
    process.env.STRIPE_SECRET_KEY
      && process.env.STRIPE_WEBHOOK_SECRET
      && process.env.STRIPE_TEAM_PRICE_ID,
  );
}

export function billingEnforcementEnabled() {
  return process.env.BILLING_ENFORCEMENT_ENABLED === "true";
}

export function stripe() {
  const secret = process.env.STRIPE_SECRET_KEY;
  if (!secret) throw new APIError("Billing is not configured yet.", 503);
  stripeClient ??= new Stripe(secret, { maxNetworkRetries: 2 });
  return stripeClient;
}

export function stripeTeamPriceID() {
  const value = process.env.STRIPE_TEAM_PRICE_ID;
  if (!value) throw new APIError("The Signalcase Team price is not configured.", 503);
  return value;
}

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

export async function workspaceBillingState(
  admin: SupabaseClient,
  workspaceID: string,
  role: WorkspaceRole,
): Promise<BillingState & { customerID: string | null; subscriptionID: string | null }> {
  const [{ data: subscription, error: subscriptionError }, { data: settings, error: settingsError }] = await Promise.all([
    admin
      .from("workspace_subscriptions")
      .select("provider, plan_key, status, stripe_customer_id, stripe_subscription_id, stripe_price_id, trial_ends_at, current_period_ends_at, cancel_at_period_end, last_payment_failed_at")
      .eq("workspace_id", workspaceID)
      .maybeSingle(),
    admin
      .from("workspace_settings")
      .select("member_limit, project_limit, event_retention_days")
      .eq("workspace_id", workspaceID)
      .maybeSingle(),
  ]);
  if (subscriptionError || settingsError) {
    throw subscriptionError ?? settingsError ?? new Error("Workspace billing could not be loaded.");
  }

  const current = subscription as SubscriptionRow | null;
  const limits = settings as WorkspaceSettingsRow | null;
  const now = Date.now();
  const status = current?.status ?? "trialing";
  const trialActive = status === "trialing"
    && Boolean(current?.trial_ends_at)
    && new Date(current!.trial_ends_at!).getTime() > now;
  const paidActive = status === "active";
  const graceActive = status === "past_due"
    && Boolean(current?.last_payment_failed_at)
    && new Date(current!.last_payment_failed_at!).getTime() + 3 * 86_400_000 > now;
  const enforcement = billingEnforcementEnabled();

  return {
    configured: stripeConfigured(),
    enforcementEnabled: enforcement,
    access: !enforcement || trialActive || paidActive || graceActive,
    plan: current?.plan_key ?? "team",
    status,
    provider: current?.provider ?? "internal",
    trialEndsAt: current?.trial_ends_at ?? null,
    currentPeriodEndsAt: current?.current_period_ends_at ?? null,
    cancelAtPeriodEnd: current?.cancel_at_period_end ?? false,
    memberLimit: limits?.member_limit ?? 5,
    projectLimit: limits?.project_limit ?? 3,
    eventRetentionDays: limits?.event_retention_days ?? 30,
    canManage: role === "owner",
    customerID: current?.stripe_customer_id ?? null,
    subscriptionID: current?.stripe_subscription_id ?? null,
  };
}

export async function requireWorkspaceEntitlement(
  admin: SupabaseClient,
  workspaceID: string,
  role: WorkspaceRole,
) {
  const state = await workspaceBillingState(admin, workspaceID, role);
  if (!state.access) {
    throw new APIError("Your Signalcase trial ended. Ask a workspace owner to subscribe.", 402);
  }
  return state;
}

function unixTimestamp(value: unknown) {
  return typeof value === "number" && Number.isFinite(value)
    ? new Date(value * 1_000).toISOString()
    : null;
}

export function subscriptionDatabaseValues(subscription: Stripe.Subscription) {
  const raw = subscription as unknown as Record<string, unknown>;
  const items = subscription.items.data;
  const periodEnd = items
    .map((item) => (item as unknown as Record<string, unknown>).current_period_end)
    .find((value) => typeof value === "number");
  return {
    provider: "stripe",
    plan_key: "team",
    status: subscription.status,
    stripe_customer_id: typeof subscription.customer === "string"
      ? subscription.customer
      : subscription.customer.id,
    stripe_subscription_id: subscription.id,
    stripe_price_id: items[0]?.price.id ?? null,
    trial_ends_at: unixTimestamp(subscription.trial_end),
    current_period_ends_at: unixTimestamp(raw.current_period_end ?? periodEnd),
    cancel_at_period_end: subscription.cancel_at_period_end,
    last_payment_failed_at: subscription.status === "past_due"
      ? new Date().toISOString()
      : null,
  };
}
