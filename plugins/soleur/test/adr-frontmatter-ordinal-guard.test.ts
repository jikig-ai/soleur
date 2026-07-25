// #6800 — check-adr-ordinals.sh layer 4: no `adr:` frontmatter ordinal key.
//
// The filename is the sole authoritative ADR ordinal. A frontmatter `adr:` key
// can disagree with it (ADR-037's read `035`), making `ADR-NNN` references
// resolve to two documents. Layer 4 forbids the key so the disagreement is
// structurally impossible. This test pins BOTH directions:
//   - the shipped corpus passes (exit 0);
//   - an ADR carrying an `adr:` key FAILS (exit 1) — the non-vacuity guard.
import { describe, test, expect, afterEach } from "bun:test";
import { resolve } from "path";
import { spawnSync } from "child_process";
import { writeFileSync, rmSync, existsSync } from "fs";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const CHECKER = resolve(REPO_ROOT, "scripts/check-adr-ordinals.sh");
const DECDIR = resolve(
  REPO_ROOT,
  "knowledge-base/engineering/architecture/decisions",
);
// A synthesized ADR whose filename ordinal is deliberately unused, carrying an
// `adr:` key — layer 4 must reject it. Cleaned up in afterEach.
const NEG_FIXTURE = resolve(DECDIR, "ADR-901-layer4-negative-fixture.md");

function runChecker(): number {
  return spawnSync("bash", [CHECKER], { encoding: "utf8" }).status ?? -1;
}

afterEach(() => {
  if (existsSync(NEG_FIXTURE)) rmSync(NEG_FIXTURE);
});

describe("check-adr-ordinals.sh layer 4 — no frontmatter ordinal key (#6800)", () => {
  test("the shipped corpus passes (no adr: key anywhere)", () => {
    expect(runChecker()).toBe(0);
  });

  test("an ADR carrying an `adr:` frontmatter key FAILS layer 4 (non-vacuity)", () => {
    writeFileSync(
      NEG_FIXTURE,
      [
        "---",
        "adr: ADR-901",
        "title: negative fixture",
        "status: active",
        "date: 2026-07-22",
        "---",
        "",
        "## Status",
        "## Context",
        "## Decision",
        "## Consequences",
      ].join("\n"),
    );
    expect(runChecker()).toBe(1);
  });
});
