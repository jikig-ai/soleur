import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Drift guard against `@supabase/auth-js` upgrades. The classifier hardcodes
 * 5 ErrorCode strings that share the verifier-class recovery action. If the
 * upstream package renames or removes any of them on a dep bump, the
 * classifier silently falls through to "auth_failed" and OAuth users see the
 * wrong copy — exactly the regression class this PR fixes.
 *
 * `ErrorCode` is internal to auth-js (not re-exported from the package root)
 * so we cannot import it directly. Instead we read the union members from
 * `error-codes.d.ts` at test time and assert our hardcoded set is a subset.
 *
 * Standalone file (per cq-test-mocked-module-constant-import) — does not
 * mock node:fs.
 */
describe("error-classifier subset of @supabase/auth-js ErrorCode union", () => {
  const codesPath = resolve(
    __dirname,
    "../../../node_modules/@supabase/auth-js/dist/module/lib/error-codes.d.ts",
  );

  it("can read the upstream error-codes.d.ts", () => {
    expect(existsSync(codesPath)).toBe(true);
  });

  const dts = existsSync(codesPath) ? readFileSync(codesPath, "utf8") : "";

  it("upstream file is non-trivial", () => {
    expect(dts.length).toBeGreaterThan(200);
  });

  // Parse the `export type ErrorCode = '...' | '...' | ...;` declaration.
  const match = dts.match(/export\s+type\s+ErrorCode\s*=\s*([^;]+);/);
  const upstreamCodes = new Set(
    (match?.[1] ?? "")
      .split("|")
      .map((s) => s.trim().replace(/^['"]|['"]$/g, ""))
      .filter(Boolean),
  );

  // Hardcoded mirror of error-classifier.ts:VERIFIER_CLASS_CODES. Kept
  // verbatim per cq-test-mocked-module-constant-import — the production
  // file uses Set<string> which doesn't constrain to ErrorCode at compile
  // time, so this runtime test is the gate.
  const VERIFIER_CLASS_CODES = [
    "bad_code_verifier",
    "flow_state_not_found",
    "flow_state_expired",
    "bad_oauth_state",
    "bad_oauth_callback",
  ];

  it("parsed upstream union has reasonable size", () => {
    // Catches a parser regex failure that produces an empty set.
    expect(upstreamCodes.size).toBeGreaterThan(20);
  });

  it.each(VERIFIER_CLASS_CODES)(
    "%s is still a member of upstream ErrorCode",
    (code) => {
      expect(upstreamCodes.has(code)).toBe(true);
    },
  );
});
