import { createAdminClient } from "@/lib/supabase/admin";
import {
  applicationRows,
  hashApplicationSecret,
  maximumApplicationBodyBytes,
} from "@/lib/application-events";

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
  if (Number.isFinite(length) && length > maximumApplicationBodyBytes) {
    return error("Request body is too large.", 413);
  }
  const authorization = request.headers.get("authorization") ?? "";
  const [scheme, secret, extra] = authorization.trim().split(/\s+/);
  if (scheme?.toLowerCase() !== "bearer" || !secret?.startsWith("sc_live_") || extra) {
    return error("Invalid Application Logs authorization.", 401);
  }

  let bodyText: string;
  try {
    bodyText = await request.text();
  } catch {
    return error("Could not read the request body.", 400);
  }
  if (Buffer.byteLength(bodyText, "utf8") > maximumApplicationBodyBytes) {
    return error("Request body is too large.", 413);
  }
  let payload: unknown;
  try {
    payload = JSON.parse(bodyText);
  } catch {
    return error("Send a valid JSON object or array.", 400);
  }
  const admin = createAdminClient();
  const { data: key, error: keyError } = await admin
    .from("application_ingest_keys")
    .select("project_id, connection_id")
    .eq("secret_hash", hashApplicationSecret(secret))
    .maybeSingle();
  if (keyError) return error("The receiver could not verify this request.", 500);
  if (!key) return error("Invalid Application Logs authorization.", 401);

  let rows;
  try {
    rows = applicationRows(payload, key.project_id, key.connection_id);
  } catch (normalizationError) {
    return error(normalizationError instanceof Error ? normalizationError.message : "Invalid event.", 400);
  }
  const { error: insertError } = await admin
    .from("raw_events")
    .upsert(rows, { onConflict: "project_id,dedupe_key", ignoreDuplicates: true });
  if (insertError) return error("The receiver could not store this event.", 500);

  const now = new Date().toISOString();
  await Promise.all([
    admin.from("application_ingest_keys").update({ last_used_at: now }).eq("project_id", key.project_id),
    admin.from("provider_connections").update({
      state: "connected",
      last_synced_at: now,
      last_error: null,
    }).eq("id", key.connection_id),
  ]);
  return Response.json({ accepted: rows.length }, { status: 202 });
}
