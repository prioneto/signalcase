import { createAdminClient } from "@/lib/supabase/admin";
import { authenticate } from "@/lib/api-auth";
import {
  maximumClientErrorBodyBytes,
  normalizeClientErrorReport,
} from "@/lib/error-reporting";
import { enforceRateLimit } from "@/lib/rate-limit";

function error(message: string, status: number) {
  return Response.json({ error: message }, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

export async function POST(request: Request) {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return error("Content-Type must be application/json.", 415);
  }
  const length = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(length) && length > maximumClientErrorBodyBytes) {
    return error("Request body is too large.", 413);
  }

  let bodyText: string;
  try {
    bodyText = await request.text();
  } catch {
    return error("Could not read the request body.", 400);
  }
  if (Buffer.byteLength(bodyText, "utf8") > maximumClientErrorBodyBytes) {
    return error("Request body is too large.", 413);
  }
  let payload: unknown;
  try {
    payload = JSON.parse(bodyText);
  } catch {
    return error("Send a valid JSON object.", 400);
  }

  let report;
  try {
    report = normalizeClientErrorReport(payload);
  } catch (normalizationError) {
    return error(
      normalizationError instanceof Error ? normalizationError.message : "Invalid report.",
      400,
    );
  }

  const admin = createAdminClient();

  // Reports are accepted from signed-in users and, more narrowly rate limited,
  // from anonymous clients so crash reports still arrive after sign-in issues.
  let subject: string;
  try {
    const auth = await authenticate(request);
    subject = auth.user.id;
  } catch {
    const forwarded = request.headers.get("x-forwarded-for") ?? "";
    subject = `anonymous:${forwarded.split(",")[0].trim() || "unknown"}`;
  }
  try {
    await enforceRateLimit(admin, {
      bucket: "client-error-reports",
      subject,
      maximum: 20,
      windowSeconds: 3_600,
    });
  } catch {
    return error("Too many error reports. Retry later.", 429);
  }

  const { error: insertError } = await admin
    .from("error_reports")
    .insert(report);
  if (insertError) return error("The server could not store this report.", 500);

  return Response.json({ accepted: true }, { status: 202 });
}
