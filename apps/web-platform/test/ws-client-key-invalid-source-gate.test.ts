import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// feat-skip-api-key-onboarding (#4642) — AC5 grep gate. Negative-space
// regression: the `key_invalid` branch of lib/ws-client.ts must NOT contain a
// hard `window.location.href` redirect (the source of the skip→/setup-key
// loop). A `location.href` reintroduced into this branch re-arms the loop.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(join(__dirname, "../lib/ws-client.ts"), "utf8");

/** Extract the `if (msg.errorCode === "key_invalid") { ... }` block body. */
function keyInvalidBranch(src: string): string {
  const start = src.indexOf('msg.errorCode === "key_invalid"');
  expect(start, "key_invalid branch must exist").toBeGreaterThan(-1);
  // From the marker to the `teardown();` call that closes the branch.
  const teardownAt = src.indexOf("teardown();", start);
  expect(teardownAt, "key_invalid branch must call teardown()").toBeGreaterThan(start);
  return src.slice(start, teardownAt);
}

describe("ws-client key_invalid branch (AC5)", () => {
  it("does not hard-redirect via window.location.href", () => {
    expect(keyInvalidBranch(SRC)).not.toMatch(/location\.href/);
  });
});
