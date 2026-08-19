import { redactApplicationValue } from "@/lib/application-events";
import { APIError } from "@/lib/api-auth";

export type SharedCaseSnapshot = Record<string, unknown> & {
  id: string;
  reference: string;
  title: string;
  summary: string;
  status: "new" | "active" | "resolved";
  severity: "normal" | "high" | "critical";
  occurrenceCount: number;
  affectedUsers: number;
  firstSeen: string;
  lastSeen: string;
  release: string;
  environment: string;
  fingerprint: string;
  events: Array<Record<string, unknown>>;
};

export type SharedCaseRow = {
  id: string;
  reference_number: number;
  title: string;
  summary: string | null;
  status: string;
  severity: string;
  occurrence_count: number;
  affected_users: number;
  first_seen_at: string;
  last_seen_at: string;
  release: string | null;
  environment: string;
  fingerprint: string;
  snapshot: Record<string, unknown>;
  revision: number;
  updated_at: string;
  deleted_at: string | null;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function boundedString(value: unknown, name: string, maximum: number, required = true) {
  const result = typeof value === "string" ? value.trim().slice(0, maximum) : "";
  if (required && !result) throw new APIError(`Every shared case needs ${name}.`);
  return result;
}

function boundedInteger(value: unknown, maximum: number, minimum = 0) {
  const number = typeof value === "number" ? Math.trunc(value) : Number(value);
  return Number.isFinite(number) ? Math.max(minimum, Math.min(maximum, number)) : minimum;
}

function isoDate(value: unknown, name: string) {
  const date = new Date(typeof value === "string" || typeof value === "number" ? value : "");
  if (!Number.isFinite(date.getTime())) throw new APIError(`Every shared case needs a valid ${name}.`);
  return date.toISOString();
}

function caseStatus(value: unknown): SharedCaseSnapshot["status"] {
  if (value === "resolved" || value === "verified") return "resolved";
  if (value === "active" || value === "reviewed" || value === "fixing" || value === "triaged") return "active";
  return "new";
}

function caseSeverity(value: unknown): SharedCaseSnapshot["severity"] {
  if (value === "critical" || value === "urgent") return "critical";
  if (value === "high" || value === "elevated") return "high";
  return "normal";
}

function eventKey(event: Record<string, unknown>) {
  const source = typeof event.source === "string" ? event.source : "unknown";
  const external = typeof event.externalID === "string" ? event.externalID : "";
  const id = typeof event.id === "string" ? event.id : "";
  const fingerprint = typeof event.fingerprint === "string" ? event.fingerprint : "";
  const timestamp = typeof event.timestamp === "string" ? event.timestamp : String(event.timestamp ?? "");
  return external ? `${source}:external:${external}` : (id || `${source}:${timestamp}:${fingerprint}`);
}

function mergeEvents(
  existing: unknown,
  incoming: Array<Record<string, unknown>>,
) {
  const combined = [
    ...incoming,
    ...(Array.isArray(existing) ? existing.filter((item): item is Record<string, unknown> => Boolean(item && typeof item === "object")) : []),
  ];
  const seen = new Set<string>();
  return combined.filter((event) => seen.add(eventKey(event))).slice(0, 500);
}

export function normalizeSharedCase(value: unknown): SharedCaseSnapshot {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new APIError("Shared cases must be JSON objects.");
  }
  const input = redactApplicationValue(value) as Record<string, unknown>;
  const id = boundedString(input.id, "an ID", 36);
  if (!uuidPattern.test(id)) throw new APIError("A shared case contained an invalid ID.");
  const events = Array.isArray(input.events)
    ? input.events
      .filter((event): event is Record<string, unknown> => Boolean(event && typeof event === "object" && !Array.isArray(event)))
      .slice(0, 500)
    : [];
  const firstSeen = isoDate(input.firstSeen, "first-seen time");
  const lastSeen = isoDate(input.lastSeen, "last-seen time");
  if (new Date(lastSeen) < new Date(firstSeen)) throw new APIError("A shared case has an invalid time range.");

  const snapshot: SharedCaseSnapshot = {
    ...input,
    id,
    reference: boundedString(input.reference, "a reference", 40, false) || "SIG",
    title: boundedString(input.title, "a title", 300),
    summary: boundedString(input.summary, "a summary", 4_000, false),
    status: caseStatus(input.status),
    severity: caseSeverity(input.severity),
    occurrenceCount: boundedInteger(input.occurrenceCount, 1_000_000, 1),
    affectedUsers: boundedInteger(input.affectedUsers, 1_000_000),
    firstSeen,
    lastSeen,
    release: boundedString(input.release, "a release", 500, false) || "Unknown release",
    environment: boundedString(input.environment, "an environment", 200, false) || "Production",
    fingerprint: boundedString(input.fingerprint, "a fingerprint", 2_000),
    events,
  };
  const encodedBytes = Buffer.byteLength(JSON.stringify(snapshot), "utf8");
  if (encodedBytes > 750_000) throw new APIError("A shared case is too large. Reduce its attached events.", 413);
  return snapshot;
}

export function mergeSharedCaseSnapshot(
  row: SharedCaseRow | null,
  incoming: SharedCaseSnapshot,
) {
  if (!row) return incoming;
  const current = row.snapshot ?? {};
  const incomingIsNewer = new Date(incoming.lastSeen).getTime() >= new Date(row.last_seen_at).getTime();
  const base = incomingIsNewer ? incoming : current;
  return normalizeSharedCase({
    ...base,
    id: row.id,
    reference: `SIG-${row.reference_number}`,
    status: caseStatus(row.status),
    severity: incomingIsNewer ? incoming.severity : caseSeverity(row.severity),
    occurrenceCount: Math.max(row.occurrence_count, incoming.occurrenceCount),
    affectedUsers: Math.max(row.affected_users, incoming.affectedUsers),
    firstSeen: new Date(Math.min(
      new Date(row.first_seen_at).getTime(),
      new Date(incoming.firstSeen).getTime(),
    )).toISOString(),
    lastSeen: new Date(Math.max(
      new Date(row.last_seen_at).getTime(),
      new Date(incoming.lastSeen).getTime(),
    )).toISOString(),
    events: mergeEvents(current.events, incoming.events),
  });
}

export function sharedCaseColumns(snapshot: SharedCaseSnapshot, userID: string) {
  return {
    title: snapshot.title,
    summary: snapshot.summary || null,
    status: snapshot.status,
    severity: snapshot.severity,
    occurrence_count: snapshot.occurrenceCount,
    affected_users: snapshot.affectedUsers,
    first_seen_at: snapshot.firstSeen,
    last_seen_at: snapshot.lastSeen,
    release: snapshot.release,
    environment: snapshot.environment,
    fingerprint: snapshot.fingerprint,
    snapshot,
    updated_by: userID,
  };
}

export function snapshotFromRow(row: SharedCaseRow): SharedCaseSnapshot {
  return normalizeSharedCase({
    ...row.snapshot,
    id: row.id,
    reference: `SIG-${row.reference_number}`,
    title: row.title,
    summary: row.summary ?? "",
    status: row.status,
    severity: row.severity,
    occurrenceCount: row.occurrence_count,
    affectedUsers: row.affected_users,
    firstSeen: row.first_seen_at,
    lastSeen: row.last_seen_at,
    release: row.release ?? "Unknown release",
    environment: row.environment,
    fingerprint: row.fingerprint,
  });
}

export const sharedCaseSelection = [
  "id", "reference_number", "title", "summary", "status", "severity",
  "occurrence_count", "affected_users", "first_seen_at", "last_seen_at",
  "release", "environment", "fingerprint", "snapshot", "revision", "updated_at", "deleted_at",
].join(", ");
