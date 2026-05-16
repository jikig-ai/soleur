/**
 * BYOK audit writer sweep — source-grep CI lint (PR-E #3887).
 *
 * Discharges `hr-write-boundary-sentinel-sweep-all-write-sites` for the
 * BYOK audit-write boundary: every server file that OPENS a
 * `runWithByokLease(...)` ALS scope MUST either call `persistTurnCost(`
 * (which fans out to `write_byok_audit` per `cost-writer.ts:116`) or
 * carry the structured out-of-scope marker comment documenting why a
 * specific call-site rolls up its cost through a parent lease.
 *
 * Narrow filter rationale (deepen-plan 2026-05-16 design lock): all
 * BYOK SDK call paths today open with `runWithByokLease(userId, ...)`.
 * A new BYOK call path cannot land without a NEW
 * `runWithByokLease` (the lease is the ONLY way the SDK picks up the
 * user's BYOK key — see `byok-lease.ts` ALS contract). Sweeping the
 * lease-opening site is therefore canonical. Widening to grep `query(`
 * or `sdkQuery(` would force a type-only-import filter for marginal
 * benefit; the narrow filter is sufficient.
 *
 * Runs in the standard webplat suite (NO TENANT_INTEGRATION_TEST gate)
 * — deterministic source-grep, no DB required.
 */

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { sync as globSync } from "fast-glob";

const SERVER_DIR = "server";
const OUT_OF_SCOPE_MARKER = "byok-audit-writer-sweep: out-of-scope";

/**
 * Files matching `runWithByokLease\(` that we explicitly do NOT sweep:
 *
 * - `byok-lease.ts` itself: it DEFINES the lease primitive and naturally
 *   contains the literal `runWithByokLease(` in the function signature.
 *   Including it would create a meaningless tautology.
 *
 * No other allowlist entries. A new contributor adding a `runWithByokLease(`
 * call site MUST either wire `persistTurnCost(` or add the marker comment;
 * editing this allowlist is a PR-review signal.
 */
const SWEEP_ALLOWLIST = new Set<string>([
  "server/byok-lease.ts",
]);

describe("BYOK audit writer sweep", () => {
  const files = globSync(`${SERVER_DIR}/**/*.ts`, {
    ignore: ["**/*.test.ts", "**/*.d.ts"],
  });
  // `fast-glob` returns relative paths under the cwd; the vitest config sets
  // cwd to `apps/web-platform`, so paths are `server/<...>.ts`.

  /**
   * Strip line and block comments before pattern-matching so a docblock
   * mentioning `runWithByokLease(...)` in prose (e.g., the explanatory
   * marker comment on pdf-chapter-router.ts:148) does NOT spuriously
   * register as a call-site. The marker existence check (below) still
   * uses the raw source so the marker remains visible.
   *
   * Lightweight stripper, not a full JS parser: misses comments inside
   * string literals, but TypeScript code that puts `runWithByokLease(`
   * inside a string is itself a regression signal worth surfacing.
   */
  const stripComments = (src: string): string =>
    src
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/\/\/.*$/gm, "");

  // Filter to call-sites that open a BYOK lease (excluding the definition).
  const sweepable = files.filter((path) => {
    if (SWEEP_ALLOWLIST.has(path)) return false;
    const src = readFileSync(path, "utf8");
    return /\brunWithByokLease\s*\(/.test(stripComments(src));
  });

  it("at least one BYOK lease call-site exists (sentinel sanity)", () => {
    // If the sweep finds zero call-sites, either (a) BYOK paths have all
    // been deleted (then this test file should be deleted too), or (b)
    // the glob/filter regressed silently. Treat zero as a hard fail so
    // the sweep cannot vacuously pass.
    expect(sweepable.length).toBeGreaterThan(0);
  });

  for (const file of sweepable) {
    it(`${file}: emits persistTurnCost OR carries out-of-scope marker`, () => {
      const src = readFileSync(file, "utf8");
      const hasWriter = /\bpersistTurnCost\s*\(/.test(src);
      const hasMarker = src.includes(OUT_OF_SCOPE_MARKER);
      expect(
        hasWriter || hasMarker,
        `${file} opens runWithByokLease(...) but does not call persistTurnCost(...) ` +
          `and does not carry the "${OUT_OF_SCOPE_MARKER}" marker. Either wire ` +
          `the audit writer or add the marker with a single-line comment ` +
          `explaining why the cost rolls up through a parent lease.`,
      ).toBe(true);
    });
  }
});
