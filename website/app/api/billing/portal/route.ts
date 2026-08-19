import { APIError, jsonError } from "@/lib/api-auth";
import { publicSiteURL, requireWorkspaceOwner, stripe, workspaceBillingState } from "@/lib/billing";
import { requireProjectContext } from "@/lib/project-context";

type Body = { projectId?: string };

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (!body.projectId) throw new APIError("Choose a Signalcase project first.");
    const context = await requireProjectContext(request, body.projectId, {
      bucket: "billing:portal",
      maximum: 20,
      requireEntitlement: false,
    });
    const workspaceID = context.project.workspace_id;
    await requireWorkspaceOwner(context.admin, workspaceID, context.user.id);
    const billing = await workspaceBillingState(context.admin, workspaceID, "owner");
    if (!billing.customerID) throw new APIError("Subscribe before opening billing management.", 409);
    const session = await stripe().billingPortal.sessions.create({
      customer: billing.customerID,
      return_url: `${publicSiteURL()}/dashboard`,
    });
    return Response.json({ url: session.url });
  } catch (error) {
    return jsonError(error, request);
  }
}
