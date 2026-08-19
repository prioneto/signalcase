import { APIError, jsonError } from "@/lib/api-auth";
import { workspaceBillingState } from "@/lib/billing";
import { requireProjectContext } from "@/lib/project-context";

export async function GET(request: Request) {
  try {
    const projectID = new URL(request.url).searchParams.get("projectId");
    if (!projectID) throw new APIError("Choose a Signalcase project first.");
    const context = await requireProjectContext(request, projectID, {
      bucket: "billing:status",
      maximum: 120,
      requireEntitlement: false,
    });
    const state = await workspaceBillingState(
      context.admin,
      context.project.workspace_id,
      context.role,
    );
    const { customerID: _customerID, subscriptionID: _subscriptionID, ...publicState } = state;
    return Response.json(publicState);
  } catch (error) {
    return jsonError(error, request);
  }
}
