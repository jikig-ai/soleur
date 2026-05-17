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

// Direct call site: file invokes `runWithByokLease(...)` literally.
const LEASE_CALL_RE = /\brunWithByokLease\s*\(/;

// PR-F (#3244) RV17: alias-rename bypass detection. A file importing
// the lease primitive under an alias (e.g.,
// `import { runWithByokLease as openLease } from "./byok-lease"`)
// and calling it via the alias would otherwise slip past the
// LEASE_CALL_RE source-grep. Catch the alias import shape too —
// any file matching this regex is sweepable regardless of whether
// the alias-call appears literally in source. Mitigates the
// 2026-05-15 ci-sentinel-paren-safety class for the BYOK boundary.
const ALIAS_IMPORT_RE = /import\s*\{[^}]*\brunWithByokLease\s+as\s+\w+/;

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
  // PR-F RV17: also flag alias-rename imports — see ALIAS_IMPORT_RE above.
  const sweepable = files.filter((path) => {
    if (SWEEP_ALLOWLIST.has(path)) return false;
    const src = readFileSync(path, "utf8");
    const stripped = stripComments(src);
    return LEASE_CALL_RE.test(stripped) || ALIAS_IMPORT_RE.test(stripped);
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

// PR-F (#3244) RV17: alias-rename bypass regression-guard.
//
// Source-grep sentinels suffer the alias-rename failure mode: a file that
// imports the canonical name under an alias and calls only the alias will
// slip past a literal-name regex even though it opens an ALS-scoped
// lease. The 2026-05-15-ci-sentinel-paren-safety class captures this
// shape generally; this block instantiates it for the BYOK boundary.
//
// In-test fixture strings avoid polluting the production server/**/*.ts
// glob (the sweep above) and the test/fixtures/ tree (Phase 2 sequencing
// — the fixture lives where the regex lives).
describe("BYOK audit writer sweep — alias-rename bypass detection (RV17)", () => {
  it("LEASE_CALL_RE catches a direct call site", () => {
    const direct = `
      import { runWithByokLease } from "./byok-lease";
      await runWithByokLease(userId, async (lease) => { /* ... */ });
    `;
    expect(LEASE_CALL_RE.test(direct)).toBe(true);
  });

  it("LEASE_CALL_RE MISSES a file that uses the aliased call only", () => {
    // This is the failure shape RV17 closes. Without the alias detector,
    // this file would slip past the sweep — load-bearing brand-survival
    // gap.
    const aliased = `
      import { runWithByokLease as openLease } from "./byok-lease";
      await openLease(userId, async (lease) => { /* ... */ });
    `;
    expect(LEASE_CALL_RE.test(aliased)).toBe(false);
  });

  it("ALIAS_IMPORT_RE catches the alias import shape", () => {
    const aliased = `
      import { runWithByokLease as openLease } from "./byok-lease";
      await openLease(userId, async (lease) => { /* ... */ });
    `;
    expect(ALIAS_IMPORT_RE.test(aliased)).toBe(true);
  });

  it("ALIAS_IMPORT_RE catches alias imports in multi-name import lists", () => {
    const mixed = `
      import { ByokLease, runWithByokLease as run, type ByokLeaseError } from "./byok-lease";
      await run(userId, async () => { /* ... */ });
    `;
    expect(ALIAS_IMPORT_RE.test(mixed)).toBe(true);
  });

  it("ALIAS_IMPORT_RE does NOT match a bare import (no alias)", () => {
    // Bare import is caught by LEASE_CALL_RE on the call site; the alias
    // detector should NOT false-positive on the import statement itself
    // when the file then calls the canonical name (otherwise every direct
    // caller would trigger both regexes, which is harmless but noisy).
    const bare = `
      import { runWithByokLease, ByokLease } from "./byok-lease";
      await runWithByokLease(userId, async (lease) => { /* ... */ });
    `;
    expect(ALIAS_IMPORT_RE.test(bare)).toBe(false);
  });

  it("ALIAS_IMPORT_RE does NOT match unrelated imports that mention 'as'", () => {
    const unrelated = `
      import { foo as bar } from "./other";
      import { runWithByokLease } from "./byok-lease";
    `;
    expect(ALIAS_IMPORT_RE.test(unrelated)).toBe(false);
  });

  it("filter sweepable selects an aliased file (combined OR-of-regexes)", () => {
    // The production filter uses LEASE_CALL_RE OR ALIAS_IMPORT_RE. Prove
    // the alias-only file is selected — without this OR, the file's
    // persistTurnCost call would not be required because the file
    // would not be classified as sweepable in the first place.
    const aliased = `
      import { runWithByokLease as openLease } from "./byok-lease";
      await openLease(userId, async (lease) => { /* ... */ });
    `;
    const sweepable = LEASE_CALL_RE.test(aliased) || ALIAS_IMPORT_RE.test(aliased);
    expect(sweepable).toBe(true);
  });
});
