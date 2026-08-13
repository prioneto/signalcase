import { createHash, randomBytes } from "node:crypto";

export const applicationEndpointPath = "/api/ingest/events";
export const maximumApplicationBodyBytes = 1_048_576;
export const maximumApplicationBatchSize = 100;

const sensitiveKey = /authorization|cookie|password|passwd|token|secret|api[_-]?key|credit[_-]?card|card[_-]?number|cvv/i;
const bearerValue = /\bBearer\s+[A-Za-z0-9._~+/=-]+/gi;
const jwtValue = /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g;
const providerKey = /\b(?:sb_(?:secret|publishable)_[A-Za-z0-9_-]+|sk_(?:live|test)_[A-Za-z0-9]+)\b/g;

function text(value: unknown, maximum = 4_000) {
  if (typeof value === "string") return value.trim().slice(0, maximum);
  if (typeof value === "number" || typeof value === "boolean") return String(value).slice(0, maximum);
  return "";
}

function first(event: Record<string, unknown>, keys: string[], maximum?: number) {
  for (const key of keys) {
    const value = text(event[key], maximum);
    if (value) return value;
  }
  return null;
}

export function redactApplicationValue(value: unknown, depth = 0): unknown {
  if (depth > 8) return "[REDACTED: DEPTH]";
  if (typeof value === "string") {
    return value
      .replace(bearerValue, "Bearer [REDACTED]")
      .replace(jwtValue, "[REDACTED: JWT]")
      .replace(providerKey, "[REDACTED: KEY]")
      .slice(0, 16_000);
  }
  if (Array.isArray(value)) {
    return value.slice(0, 100).map((item) => redactApplicationValue(item, depth + 1));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .slice(0, 100)
        .map(([key, item]) => [
          key.slice(0, 120),
          sensitiveKey.test(key) ? "[REDACTED]" : redactApplicationValue(item, depth + 1),
        ]),
    );
  }
  return value;
}

export function generateApplicationSecret() {
  return `sc_live_${randomBytes(32).toString("base64url")}`;
}

export function hashApplicationSecret(secret: string) {
  return createHash("sha256").update(secret).digest("hex");
}

export type ApplicationEventRow = {
  project_id: string;
  connection_id: string;
  provider: "application";
  provider_event_id: string | null;
  dedupe_key: string;
  level: "debug" | "info" | "warning" | "error" | "critical";
  event_type: string;
  title: string;
  summary: string;
  request_id: string | null;
  actor_external_id: string | null;
  release: string | null;
  route: string | null;
  payload: Record<string, unknown>;
  occurred_at: string;
};

export function normalizeApplicationEvent(
  input: unknown,
  projectId: string,
  connectionId: string,
  receivedAt = new Date(),
): ApplicationEventRow {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("Each application event must be a JSON object.");
  }
  const event = input as Record<string, unknown>;
  const message = first(event, ["message", "detail", "title"]);
  if (!message) throw new Error("Each event needs a message, detail, or title.");

  const levelText = (first(event, ["level", "severity"], 40) ?? "info").toLowerCase();
  const level = levelText.includes("critical") || levelText.includes("fatal")
    ? "critical"
    : levelText.includes("error") || levelText.includes("exception")
      ? "error"
      : levelText.includes("warn")
        ? "warning"
        : levelText.includes("debug")
          ? "debug"
          : "info";
  const title = first(event, ["title", "error_name", "name"], 200)
    ?? message.split("\n", 1)[0].slice(0, 200);
  const providerEventId = first(event, ["event_id", "eventId", "id"], 500);
  const requestId = first(event, ["request_id", "requestId", "trace_id", "traceId"], 500);
  const actorId = first(event, ["user_id", "userId", "actor_id"], 500);
  const release = first(event, ["release", "commit", "version"], 500);
  const route = first(event, ["route", "path", "operation"], 1_000);
  const eventType = first(event, ["event_type", "type"], 200) ?? "application.error";
  const parsedTimestamp = new Date(first(event, ["timestamp", "occurred_at"], 100) ?? receivedAt.toISOString());
  const occurredAt = Number.isFinite(parsedTimestamp.getTime())
    && parsedTimestamp.getTime() <= receivedAt.getTime() + 5 * 60_000
    ? parsedTimestamp
    : receivedAt;
  const payload = redactApplicationValue(event) as Record<string, unknown>;
  const safeOptional = (value: string | null) => value
    ? String(redactApplicationValue(value))
    : null;
  const dedupeMaterial = providerEventId
    ? `id:${providerEventId}`
    : [occurredAt.toISOString(), level, title, message, requestId ?? ""].join("|");
  const dedupeKey = createHash("sha256")
    .update(`${projectId}|application|${dedupeMaterial}`)
    .digest("hex");

  return {
    project_id: projectId,
    connection_id: connectionId,
    provider: "application",
    provider_event_id: safeOptional(providerEventId),
    dedupe_key: dedupeKey,
    level,
    event_type: String(redactApplicationValue(eventType)),
    title: String(redactApplicationValue(title)),
    summary: String(redactApplicationValue(message)).slice(0, 4_000),
    request_id: safeOptional(requestId),
    actor_external_id: safeOptional(actorId),
    release: safeOptional(release),
    route: safeOptional(route),
    payload,
    occurred_at: occurredAt.toISOString(),
  };
}

export function applicationRows(
  payload: unknown,
  projectId: string,
  connectionId: string,
  receivedAt = new Date(),
) {
  const inputs = Array.isArray(payload) ? payload : [payload];
  if (!inputs.length || inputs.length > maximumApplicationBatchSize) {
    throw new Error(`Send between 1 and ${maximumApplicationBatchSize} events at a time.`);
  }
  return inputs.map((event) => normalizeApplicationEvent(
    event,
    projectId,
    connectionId,
    receivedAt,
  ));
}
