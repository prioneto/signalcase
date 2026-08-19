import type Stripe from "stripe";
import { createAdminClient } from "@/lib/supabase/admin";
import { stripe, subscriptionDatabaseValues } from "@/lib/billing";

function stripeObjectID(value: unknown) {
  if (typeof value === "string") return value;
  if (value && typeof value === "object" && "id" in value && typeof value.id === "string") return value.id;
  return null;
}

function metadataWorkspace(value: unknown) {
  if (!value || typeof value !== "object" || !("metadata" in value)) return null;
  const metadata = value.metadata;
  if (!metadata || typeof metadata !== "object") return null;
  const candidate = (metadata as Record<string, unknown>).signalcase_workspace_id;
  return typeof candidate === "string" ? candidate : null;
}

async function subscriptionForEvent(event: Stripe.Event) {
  if (event.type.startsWith("customer.subscription.")) {
    return event.data.object as Stripe.Subscription;
  }
  if (event.type === "checkout.session.completed") {
    const session = event.data.object as Stripe.Checkout.Session;
    const subscriptionID = stripeObjectID(session.subscription);
    return subscriptionID ? stripe().subscriptions.retrieve(subscriptionID) : null;
  }
  return null;
}

export async function POST(request: Request) {
  const signature = request.headers.get("stripe-signature");
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!signature || !secret) return Response.json({ error: "Webhook is not configured." }, { status: 503 });

  let event: Stripe.Event;
  try {
    event = stripe().webhooks.constructEvent(await request.text(), signature, secret);
  } catch {
    return Response.json({ error: "Invalid webhook signature." }, { status: 400 });
  }

  const admin = createAdminClient();
  const { data: existing } = await admin.from("stripe_webhook_events")
    .select("event_id").eq("event_id", event.id).maybeSingle();
  if (existing) return Response.json({ received: true, duplicate: true });

  try {
    const subscription = await subscriptionForEvent(event);
    if (subscription) {
      const workspaceID = metadataWorkspace(subscription)
        ?? metadataWorkspace(event.data.object)
        ?? (event.type === "checkout.session.completed"
          ? (event.data.object as Stripe.Checkout.Session).client_reference_id
          : null);
      if (!workspaceID) throw new Error("Stripe event has no Signalcase workspace ID.");
      const { error } = await admin.from("workspace_subscriptions").upsert({
        workspace_id: workspaceID,
        ...subscriptionDatabaseValues(subscription),
      }, { onConflict: "workspace_id" });
      if (error) throw error;
    } else if (event.type === "invoice.payment_failed" || event.type === "invoice.paid") {
      const invoice = event.data.object as Stripe.Invoice;
      const customerID = stripeObjectID(invoice.customer);
      if (customerID) {
        const values = event.type === "invoice.payment_failed"
          ? { status: "past_due", last_payment_failed_at: new Date().toISOString() }
          : { status: "active", last_payment_failed_at: null };
        const { error } = await admin.from("workspace_subscriptions").update(values)
          .eq("stripe_customer_id", customerID);
        if (error) throw error;
      }
    }

    const { error: ledgerError } = await admin.from("stripe_webhook_events").insert({
      event_id: event.id,
      event_type: event.type,
      livemode: event.livemode,
    });
    if (ledgerError && ledgerError.code !== "23505") throw ledgerError;
    return Response.json({ received: true });
  } catch (error) {
    console.error("stripe webhook processing failed", {
      eventID: event.id,
      eventType: event.type,
      message: error instanceof Error ? error.message : "unknown",
    });
    return Response.json({ error: "Webhook processing failed." }, { status: 500 });
  }
}
