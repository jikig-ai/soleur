// #5487 — the live-verify GitHub Actions job pipes the harness's raw stdout/
// stderr tail through `redact-stdin.ts` before embedding it in a
// CANT-RUN:no-result-line Sentry event (the harness crashed before emitting its
// own already-redacted RESULT line). This test proves the shim actually reads
// stdin and applies redact() — the security-sensitive wiring assertion.
//
// Fixtures are synthesized — never a real token (cq-test-fixtures-synthesized-only).
// Secret-shaped literals are split across concatenation so GitHub Push
// Protection does not flag the synthetic values.

import { describe, expect, it } from "vitest";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const SHIM = resolve(here, "../../scripts/live-verify/redact-stdin.ts");

function runShim(input: string): string {
  const r = spawnSync("bun", ["run", SHIM], { input, encoding: "utf8" });
  if (r.error) throw r.error;
  expect(r.status).toBe(0);
  return r.stdout;
}

describe("redact-stdin shim", () => {
  it("scrubs a JWT-shaped token from piped stdin", () => {
    const jwt = "eyJ" + "hbGciOiJIUzI1NiJ9" + "." + "eyJzdWIiOiJ4In0" + "." + "sig_synthetic_value";
    const out = runShim(`crashed before RESULT — token=${jwt} end`);
    expect(out).toContain("[REDACTED_JWT]");
    expect(out).not.toContain(jwt);
  });

  it("scrubs an email and a supabase session blob", () => {
    const blob = "base64-" + "A".repeat(60);
    const out = runShim(`user live-verify@soleur.ai cookie sb-api-auth-token=${blob}`);
    expect(out).toContain("[REDACTED_EMAIL]");
    expect(out).not.toContain("live-verify@soleur.ai");
    expect(out).not.toContain(blob);
  });

  it("passes through benign text unchanged", () => {
    const out = runShim("RESULT: CANT-RUN exit=1 plain diagnostic line");
    expect(out).toBe("RESULT: CANT-RUN exit=1 plain diagnostic line");
  });
});
