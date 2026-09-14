// Guard 1 (#8122) — the emit path must not leak General Legal vendor marks.
//
// Property: for EVERY file under
// plugins/soleur/skills/legal-generate/references/templates/<dir>/template.md,
// strip-vendor-credit.sh emits a document with zero residual vendor marks and
// zero claim-leakage tokens. The corpus quantifies over the DIRECTORY, never
// a hardcoded list — a 13th vendored template enrolls itself the day it lands.
//
// Mutation rows this suite is written to catch (each asserted below):
//   1. Strip with no deletion logic → residual marks (scan on UNstripped
//      bytes proves the scan has teeth).
//   2. Empty corpus → the >=12 floor fails (a vacuous walk is a red walk).
//   3. A 13th template whose marks survive stripping → flagged.
//   4. From-scratch output (no marker) → strip exits 2, never passes through.
//   5. Narrowing the emit grep to dot-only (`general\.legal`) misses the
//      hyphenated `General-Legal` header and spaced `General Legal` credit.

import { describe, test, expect } from "bun:test";
import { readdirSync, existsSync, mkdtempSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";

const REPO_ROOT = resolve(__dirname, "../../..");
const TEMPLATES_DIR = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/legal-generate/references/templates",
);
const STRIP = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/legal-generate/scripts/strip-vendor-credit.sh",
);

// The widened emit-scan pattern — covers general.legal, General-Legal,
// "General Legal" (spaced). This is the literal the SKILL/generator greps.
const VENDOR_MARK = /general[-.\s]?legal/i;
// Claim-leakage tokens, scoped to attorney-credential claims. Bare
// `prepared by`/`reviewed by` false-positive on legitimate clause text —
// measured: the corpus's DecisionLayer arbitration option says "reviewed by
// a human case manager", which is content, not a credential claim.
const CLAIM_TOKENS =
  /attorney[- ]draft|prepared by[^.\n]{0,30}(attorney|law firm)|reviewed by[^.\n]{0,30}attorney/i;

const CORPUS_FLOOR = 12;

function corpusFiles(): string[] {
  if (!existsSync(TEMPLATES_DIR)) return [];
  return readdirSync(TEMPLATES_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => join(TEMPLATES_DIR, d.name, "template.md"))
    .filter((p) => existsSync(p))
    .sort();
}

function runStrip(path: string): { rc: number; stdout: string; stderr: string } {
  const r = spawnSync("bash", [STRIP, path], { encoding: "utf8" });
  return {
    rc: r.status ?? -1,
    stdout: r.stdout ?? "",
    stderr: r.stderr ?? "",
  };
}

describe("Guard 1 — vendored-template emit surface", () => {
  const files = corpusFiles();

  test("corpus-count floor: the walk found >= 12 templates (anti-vacuity)", () => {
    expect(files.length).toBeGreaterThanOrEqual(CORPUS_FLOOR);
  });

  test.each(files.map((f) => [f.split("/").slice(-2)[0], f] as const))(
    "%s strips to zero vendor marks and zero claim-leakage tokens",
    (_name, path) => {
      const r = runStrip(path);
      expect(r.rc).toBe(0);
      expect(VENDOR_MARK.test(r.stdout)).toBe(false);
      expect(CLAIM_TOKENS.test(r.stdout)).toBe(false);
      // The strip must emit a document, not an empty file.
      expect(r.stdout.trim().length).toBeGreaterThan(0);
    },
  );

  test("mutation row 1 — the scan has teeth: UNstripped corpus carries marks", () => {
    // If the deletion logic were removed, every file would fail this suite.
    // Proving the UNSCRUBBED input flags is what makes the stripped green mean
    // something.
    const { readFileSync } = require("node:fs");
    const flagged = files.filter((f) =>
      VENDOR_MARK.test(readFileSync(f, "utf8")),
    );
    expect(flagged.length).toBe(files.length);
  });

  test("mutation row 2 — empty corpus fixture trips the floor", () => {
    const empty = mkdtempSync(join(tmpdir(), "legal-corpus-empty-"));
    const walked = readdirSync(empty, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => join(empty, d.name, "template.md"))
      .filter((p) => existsSync(p));
    expect(walked.length).toBeLessThan(CORPUS_FLOOR);
  });

  test("mutation row 3 — a synthetic template whose marks survive stripping flags", () => {
    const dir = mkdtempSync(join(tmpdir(), "legal-corpus-synth-"));
    const synth = join(dir, "synthetic", "template.md");
    require("node:fs").mkdirSync(join(dir, "synthetic"), { recursive: true });
    writeFileSync(
      synth,
      [
        "<!-- Adapted from General-Legal/legal-templates (CC0-1.0) — see NOTICE -->",
        "# Synthetic",
        "",
        "Body text that still says General Legal mid-document.",
        "",
        "---",
        "",
        'This template was prepared and made publicly available by General Legal, PC ("General Legal").',
      ].join("\n"),
    );
    const r = runStrip(synth);
    // The mid-document mark survives the strip (strip exits 0) OR the
    // anomaly contract fires (exit 2) — either way the guard catches it.
    const leaked = r.rc === 0 && VENDOR_MARK.test(r.stdout);
    expect(r.rc === 2 || leaked).toBe(true);
  });

  test("mutation row 4 — from-scratch output bypasses strip and exits 2", () => {
    const dir = mkdtempSync(join(tmpdir(), "legal-fallback-"));
    const scratch = join(dir, "scratch.md");
    writeFileSync(scratch, "# Generated from scratch\n\nNo vendor marks.\n");
    const r = runStrip(scratch);
    expect(r.rc).toBe(2);
  });

  test("mutation row 5 — dot-only grep misses hyphenated and spaced marks", () => {
    const narrow = /general\.legal/i;
    const fixture = [
      "Adapted from General-Legal/legal-templates",
      "prepared by General Legal, PC",
    ].join("\n");
    expect(narrow.test(fixture)).toBe(false); // proves the narrow form is blind
    expect(VENDOR_MARK.test(fixture)).toBe(true); // and the widened form is not
  });
});
