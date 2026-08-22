import assert from "node:assert/strict";
import test from "node:test";
import { normalizeClientErrorReport } from "../lib/error-reporting";

const now = new Date("2026-08-22T12:00:00.000Z");

test("client error reports are normalized and secrets redacted", () => {
  const row = normalizeClientErrorReport({
    source: "macos",
    message: "Sync failed with Authorization: Bearer sc_live_secret",
    stack: "at SignalcaseCloud.request\nauthorization: Bearer topsecret",
    request_id: "req_42",
    app_version: "0.1.0",
    os_version: "macOS 15.3.0",
    context: { api_key: "sk_live_hidden", project: "fitref" },
    occurred_at: "2026-08-22T11:59:00.000Z",
  }, now);

  assert.equal(row.source, "macos");
  assert.equal(row.message, "Sync failed with Authorization: Bearer [REDACTED]");
  assert.match(row.stack ?? "", /\[REDACTED\]/);
  assert.equal(row.request_id, "req_42");
  assert.deepEqual(row.context, { api_key: "[REDACTED: KEY]", project: "fitref" });
  assert.equal(row.occurred_at, "2026-08-22T11:59:00.000Z");
});

test("reports without a message are rejected", () => {
  assert.throws(() => normalizeClientErrorReport({ stack: "nothing else" }, now));
  assert.throws(() => normalizeClientErrorReport("not an object", now));
  assert.throws(() => normalizeClientErrorReport(null, now));
});

test("future and ancient timestamps fall back to the received time", () => {
  const future = normalizeClientErrorReport(
    { message: "boom", occurred_at: "2026-09-01T00:00:00.000Z" },
    now,
  );
  const ancient = normalizeClientErrorReport(
    { message: "boom", occurred_at: "2020-01-01T00:00:00.000Z" },
    now,
  );
  assert.equal(future.occurred_at, now.toISOString());
  assert.equal(ancient.occurred_at, now.toISOString());
});

test("unknown sources default to macos and web is allowed", () => {
  assert.equal(normalizeClientErrorReport({ message: "x", source: "hacker" }, now).source, "macos");
  assert.equal(normalizeClientErrorReport({ message: "x", source: "web" }, now).source, "web");
});
