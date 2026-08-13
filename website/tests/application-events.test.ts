import assert from "node:assert/strict";
import test from "node:test";
import {
  applicationRows,
  generateApplicationSecret,
  hashApplicationSecret,
  normalizeApplicationEvent,
} from "../lib/application-events";

const projectId = "00000000-0000-0000-0000-000000000001";
const connectionId = "00000000-0000-0000-0000-000000000002";
const now = new Date("2026-08-13T00:00:00.000Z");

test("production application events are normalized and secrets are redacted", () => {
  const row = normalizeApplicationEvent({
    event_id: "evt_17",
    timestamp: "2026-08-12T23:59:00.000Z",
    level: "error",
    title: "Checkout failed",
    message: "Authorization: Bearer top-secret",
    request_id: "req_17",
    user_id: "usr_17",
    route: "/checkout",
    password: "do-not-store",
    metadata: { api_key: "sk_live_secret", safe: "kept" },
  }, projectId, connectionId, now);

  assert.equal(row.level, "error");
  assert.equal(row.request_id, "req_17");
  assert.equal(row.summary, "Authorization: Bearer [REDACTED]");
  assert.equal(row.payload.password, "[REDACTED]");
  assert.deepEqual(row.payload.metadata, { api_key: "[REDACTED]", safe: "kept" });
});

test("stable event ids produce stable dedupe keys", () => {
  const first = normalizeApplicationEvent({ id: "same", message: "first" }, projectId, connectionId, now);
  const second = normalizeApplicationEvent({ id: "same", message: "changed" }, projectId, connectionId, now);
  assert.equal(first.dedupe_key, second.dedupe_key);
});

test("receiver secrets are long, scoped, and hashed before storage", () => {
  const secret = generateApplicationSecret();
  assert.match(secret, /^sc_live_[A-Za-z0-9_-]{40,}$/);
  assert.match(hashApplicationSecret(secret), /^[a-f0-9]{64}$/);
  assert.notEqual(hashApplicationSecret(secret), secret);
});

test("batches are limited", () => {
  assert.throws(() => applicationRows([], projectId, connectionId, now));
  assert.throws(() => applicationRows(
    Array.from({ length: 101 }, () => ({ message: "failure" })),
    projectId,
    connectionId,
    now,
  ));
});
