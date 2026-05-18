/**
 * TR9 PR-1 (#3948) — cron-* MUST NOT import or call runWithByokLease.
 *
 * Inverse-assertion sentinel enforcing ADR-033 I2: Inngest cron-*.ts
 * functions consume the OPERATOR `ANTHROPIC_API_KEY` only, never a
 * founder's BYOK key. This file is the inverse of
 * byok-audit-writer-sweep.test.ts — that file REQUIRES `runWithByokLease`
 * at BYOK-write paths; this file FORBIDS it at cron-* paths. Two simple
 * source-grep files, one invariant each (Kieran P1-2 simplification).
 *
 * Three shapes asserted (each a real bypass vector):
 *   - LEASE_CALL_RE: direct `runWithByokLease(...)` call.
 *   - ALIAS_IMPORT_RE: `import { runWithByokLease as foo }` rename.
 *   - BARE_IMPORT_RE: bare named import + later indirect call
 *     (Architecture F6 — catches the shape that aliases through a
 *     local const without the `as` keyword).
 *
 * `expect.soft` reports which shape triggered the violation per cron file.
 */

import { readFileSync } from "node:fs";
import { sync as globSync } from "fast-glob";
import { describe, expect, it } from "vitest";
import {
  ALIAS_IMPORT_RE,
  BARE_IMPORT_RE,
  LEASE_CALL_RE,
} from "./byok-audit-writer-sweep.test";

const stripComments = (src: string): string =>
  src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");

describe("cron-*.ts MUST NOT import or call runWithByokLease (ADR-033 I2)", () => {
  const cronFiles = globSync("server/inngest/functions/cron-*.ts", {
    ignore: ["**/*.test.ts", "**/*.d.ts"],
  });

  it("at least one cron-* function exists (sentinel sanity)", () => {
    // Zero cron-* files means either (a) all cron migrations were reverted —
    // in which case this sentinel can be deleted, or (b) the glob regressed
    // silently. Treat zero as a hard fail so the sweep cannot vacuously pass.
    expect(cronFiles.length).toBeGreaterThan(0);
  });

  for (const file of cronFiles) {
    it(`${file}: MUST NOT import or call runWithByokLease`, () => {
      const src = stripComments(readFileSync(file, "utf8"));
      expect.soft(LEASE_CALL_RE.test(src), "direct call site").toBe(false);
      expect.soft(ALIAS_IMPORT_RE.test(src), "aliased import").toBe(false);
      expect.soft(BARE_IMPORT_RE.test(src), "bare named import").toBe(false);
    });
  }
});

describe("inverse sentinel — fixture proofs", () => {
  it("catches a direct call site (LEASE_CALL_RE)", () => {
    const violating = `import { runWithByokLease } from "@/server/byok-lease";\nawait runWithByokLease(uid, async () => {});`;
    expect(LEASE_CALL_RE.test(violating)).toBe(true);
  });

  it("catches an aliased import (ALIAS_IMPORT_RE)", () => {
    const violating = `import { runWithByokLease as withByokSession } from "@/server/byok-lease";`;
    expect(ALIAS_IMPORT_RE.test(violating)).toBe(true);
  });

  it("catches a bare named import with no immediate call (Architecture F6, BARE_IMPORT_RE)", () => {
    const violating = `import { runWithByokLease } from "@/server/byok-lease";\nconst fn = runWithByokLease;\nfn(uid, async () => {});`;
    // BARE_IMPORT_RE matches the import shape regardless of whether the
    // call site is direct or aliased — sufficient for the inverse
    // assertion (cron files must not even import the symbol).
    expect(BARE_IMPORT_RE.test(violating)).toBe(true);
  });

  it("passes a compliant cron-* file (operator-key only, no lease import)", () => {
    const compliant = `import { spawn } from "node:child_process";\nspawn("claude", ["--print", "..."], { env: { ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY } });`;
    expect(LEASE_CALL_RE.test(compliant)).toBe(false);
    expect(ALIAS_IMPORT_RE.test(compliant)).toBe(false);
    expect(BARE_IMPORT_RE.test(compliant)).toBe(false);
  });
});
