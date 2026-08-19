import assert from "node:assert/strict";
import test from "node:test";
import {
  mergeSharedCaseSnapshot,
  normalizeSharedCase,
  snapshotFromRow,
  type SharedCaseRow,
} from "../lib/shared-cases";

const base = {
  id: "6fcae9b0-d272-4a3c-b0e7-e12507f36060",
  reference: "SIG-1",
  title: "Checkout failed",
  summary: "Authorization Bearer secret-value failed",
  status: "new",
  severity: "high",
  occurrenceCount: 1,
  affectedUsers: 1,
  firstSeen: "2026-08-19T10:00:00.000Z",
  lastSeen: "2026-08-19T10:00:00.000Z",
  release: "abc123",
  environment: "Production",
  fingerprint: "checkout-failure",
  events: [{ id: "event-1", timestamp: "2026-08-19T10:00:00.000Z", authorization: "secret" }],
};

test("shared cases are bounded and redact credentials", () => {
  const normalized = normalizeSharedCase(base);
  assert.equal(normalized.summary.includes("secret-value"), false);
  assert.equal(normalized.events[0].authorization, "[REDACTED]");
});

test("the server-owned status survives a teammate snapshot merge", () => {
  const row: SharedCaseRow = {
    id: base.id,
    reference_number: 41,
    title: base.title,
    summary: base.summary,
    status: "resolved",
    severity: "high",
    occurrence_count: 2,
    affected_users: 1,
    first_seen_at: base.firstSeen,
    last_seen_at: base.lastSeen,
    release: base.release,
    environment: base.environment,
    fingerprint: base.fingerprint,
    snapshot: base,
    revision: 3,
    updated_at: base.lastSeen,
    deleted_at: null,
  };
  const incoming = normalizeSharedCase({
    ...base,
    status: "new",
    occurrenceCount: 4,
    lastSeen: "2026-08-19T10:05:00.000Z",
  });
  const merged = mergeSharedCaseSnapshot(row, incoming);
  assert.equal(merged.status, "resolved");
  assert.equal(merged.reference, "SIG-41");
  assert.equal(merged.occurrenceCount, 4);
});

test("database columns override stale snapshot display values", () => {
  const snapshot = snapshotFromRow({
    id: base.id,
    reference_number: 9,
    title: "Current title",
    summary: "Current summary",
    status: "active",
    severity: "critical",
    occurrence_count: 7,
    affected_users: 3,
    first_seen_at: base.firstSeen,
    last_seen_at: base.lastSeen,
    release: base.release,
    environment: base.environment,
    fingerprint: base.fingerprint,
    snapshot: { ...base, title: "Stale title", status: "new" },
    revision: 2,
    updated_at: base.lastSeen,
    deleted_at: null,
  });
  assert.equal(snapshot.title, "Current title");
  assert.equal(snapshot.status, "active");
  assert.equal(snapshot.reference, "SIG-9");
});
