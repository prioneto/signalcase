import { APIError, jsonError } from "@/lib/api-auth";
import {
  publicSiteURL,
  requireWorkspaceOwner,
  stripe,
  stripeConfigured,
  stripeTeamPriceID,
  workspaceBillingState,
} from "@/lib/billing";
import { requireProjectContext } from "@/lib/project-context";

type Body = { projectId?: string };

export async function POST(request: Request) {
  try {
    if (!stripeConfigured()) throw new APIError("Billing is not configured yet.", 503);
    const body = (await request.json()) as Body;
    if (!body.projectId) throw new APIError("Choose a Signalcase project first.");
    const context = await requireProjectContext(request, body.projectId, {
      bucket: "billing:checkout",
      maximum: 10,
      requireEntitlement: false,
    });
    const workspaceID = context.project.workspace_id;
    await requireWorkspaceOwner(context.admin, workspaceID, context.user.id);
    const billing = await workspaceBillingState(context.admin, workspaceID, "owner");
    if (billing.subscriptionID && ["trialing", "active", "past_due"].includes(billing.status)) {
      throw new APIError("This workspace already has a subscription. Open billing management instead.", 409);
    }

    const stripeClient = stripe();
    let customerID = billing.customerID;
    if (!customerID) {
      const customer = await stripeClient.customers.create({
        email: context.user.email,
        name: context.user.user_metadata?.name ?? undefined,
        metadata: { signalcase_workspace_id: workspaceID },
      });
      customerID = customer.id;
      const { error } = await context.admin.from("workspace_subscriptions").update({
        stripe_customer_id: customerID,
      }).eq("workspace_id", workspaceID);
      if (error) throw error;
    }

    const trialEndSeconds = billing.trialEndsAt
      ? Math.floor(new Date(billing.trialEndsAt).getTime() / 1_000)
      : 0;
    const subscriptionData: Record<string, unknown> = {
      metadata: { signalcase_workspace_id: workspaceID },
    };
    if (trialEndSeconds > Math.floor(Date.now() / 1_000) + 48 * 3_600) {
      subscriptionData.trial_end = trialEndSeconds;
    }
    const site = publicSiteURL();
    const session = await stripeClient.checkout.sessions.create({
      mode: "subscription",
      customer: customerID,
      client_reference_id: workspaceID,
      line_items: [{ price: stripeTeamPriceID(), quantity: 1 }],
      allow_promotion_codes: true,
      automatic_tax: { enabled: true },
      billing_address_collection: "auto",
      success_url: `${site}/dashboard?billing=success`,
      cancel_url: `${site}/dashboard?billing=cancelled`,
      metadata: { signalcase_workspace_id: workspaceID },
      subscription_data: subscriptionData,
    });
    if (!session.url) throw new APIError("Stripe did not return a checkout page.", 502);
    return Response.json({ url: session.url });
  } catch (error) {
    return jsonError(error, request);
  }
}
