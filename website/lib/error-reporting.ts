import { createAdminClient } from "@/lib/supabase/admin";
import { redactApplicationValue } from "@/lib/application-events";
import { enforceRateLimit } from "@/lib/rate-limit";

export const maximumClientErrorBodyBytes = 16_384;
const maximumMessageLength = 2_000;
const maximumStackLength = 8_000;
const maximumContextEntries = 30;

export type ClientErrorRow = {
  source: string;
  message: string;
  stack: string | null;
  request_id: string | null;
  app_version: string | null;
  os_version: string | null;
  context: Record<string, unknown>;
  occurred_at: string;
};

function boundedText(value: unknown, maximum: number) {
  if (typeof value !== "string") return null;
  const cleaned = value.trim();
  if (!cleaned) return null;
  return String(redactApplicationValue(cleaned)).slice(0, maximum);
}

// Pure normalizer used by the client error endpoint. Throws with a helpful
// message for invalid payloads so routes can return 400.
export function normalizeClientErrorReport(
  input: unknown,
  receivedAt = new Date(),
): ClientErrorRow {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("Send a JSON object describing one error.");
  }
  const report = input as Record<string, unknown>;
  const message = boundedText(report.message, maximumMessageLength)
    ?? boundedText(report.error ?? report.detail, maximumMessageLength);
  if (!message) throw new Error("The report needs a message.");

  let source = "macos";
  const requestedSource = typeof report.source === "string" ? report.source.toLowerCase() : "";
  if (["macos", "web"].includes(requestedSource)) source = requestedSource;

  let occurredAt = receivedAt.toISOString();
  const parsedTimestamp = new Date(
    typeof report.occurred_at === "string" ? report.occurred_at : "",
  );
  if (
    !Number.isNaN(parsedTimestamp.getTime())
    && parsedTimestamp.getTime() <= receivedAt.getTime() + 5 * 60_000
    && parsedTimestamp.getTime() >= receivedAt.getTime() - 7 * 24 * 60 * 60_000
  ) {
    occurredAt = parsedTimestamp.toISOString();
  }

  const rawContext = report.context && typeof report.context === "object" && !Array.isArray(report.context)
    ? report.context as Record<string, unknown>
    : {};
  const context = Object.fromEntries(
    Object.entries(rawContext)
      .slice(0, maximumContextEntries)
      .map(([key, value]) => [key.slice(0, 80), redactApplicationValue(value)]),
  );

  return {
    source,
    message,
    stack: boundedText(report.stack, maximumStackLength),
    request_id: boundedText(report.request_id ?? report.requestId, 200),
    app_version: boundedText(report.app_version ?? report.appVersion, 100),
    os_version: boundedText(report.os_version ?? report.osVersion, 200),
    context,
    occurred_at: occurredAt,
  };
}

// Server-side capture used inside jsonError. Never throws and never delays
// failure paths longer than one short insert; failures degrade to console.
export async function captureServerError(
  error: unknown,
  context: {
    path?: string;
    method?: string;
    requestId?: string;
  } = {},
) {
  try {
    const message = error instanceof Error ? error.message : String(error);
    const admin = createAdminClient();
    try {
      await enforceRateLimit(admin, {
        bucket: "error-capture-server",
        subject: `${context.path ?? "unknown"}:${message.slice(0, 120)}`,
        maximum: 40,
        windowSeconds: 300,
      });
    } catch {
      return; // Rate limit exceeded or unavailable: skip storing a duplicate.
    }
    await admin.from("error_reports").insert({
      source: "server",
      message: String(redactApplicationValue(message)).slice(0, maximumMessageLength),
      stack: error instanceof Error && error.stack
        ? String(redactApplicationValue(error.stack)).slice(0, maximumStackLength)
        : null,
      path: context.path?.slice(0, 500) ?? null,
      method: context.method?.slice(0, 20) ?? null,
      request_id: context.requestId?.slice(0, 200) ?? null,
      context: {},
    });
  } catch (captureFailure) {
    console.warn("Signalcase could not store an error report", {
      message: captureFailure instanceof Error ? captureFailure.message : String(captureFailure),
    });
  }
}
