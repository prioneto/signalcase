import assert from "node:assert/strict";
import test from "node:test";
import { githubInstallationURL } from "../lib/github-app";

test("GitHub installation URL preserves the connection state", () => {
  const previous = process.env.GITHUB_APP_SLUG;
  process.env.GITHUB_APP_SLUG = "signalcase-test";
  try {
    const url = new URL(githubInstallationURL("state_123"));
    assert.equal(url.origin, "https://github.com");
    assert.equal(url.pathname, "/apps/signalcase-test/installations/new");
    assert.equal(url.searchParams.get("state"), "state_123");
  } finally {
    if (previous === undefined) delete process.env.GITHUB_APP_SLUG;
    else process.env.GITHUB_APP_SLUG = previous;
  }
});
