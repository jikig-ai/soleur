/**
 * Recursion invariant for the hard-rule body-weakening gate (ADR-092, #6103).
 *
 * The #6038 auto-proposer may draft-edit anything matching `TARGET_ALLOW_RE`
 * (AGENTS.core.md + skill SKILL.md files). The body-weakening gate exists
 * precisely BECAUSE AGENTS.core.md is auto-editable. The gate's own control
 * surface — the linter, the committed manifest, the WORM ack file, the CI
 * wiring, the ADR, the C4 model — MUST stay OUTSIDE that auto-editable set, or a
 * proposer could weaken a rule and rewrite the gate that would have caught it in
 * the same draft.
 *
 * Two assertions, per AC8:
 *   1. ∉ property — import the LIVE `TARGET_ALLOW_RE` and assert every
 *      load-bearing gate file is NOT auto-editable (rot-safe: reads the real
 *      symbol, not a copy).
 *   2. Real catch property (NOT the vacuous ∉ tautology) — run the ACTUAL
 *      `scripts/lint-rule-bodies.py --check` against a temp git repo where a
 *      synthetic proposer-style diff to AGENTS.core.md weakens a body / drops a
 *      security tag, and assert it is BLOCKED. Proves the auto-editable target
 *      is genuinely gated, not merely that the gate files are un-editable.
 */

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// cron-compound-promote → server/inngest/client.ts throws
// "INNGEST_SIGNING_KEY missing at startup" at module-eval unless we mark the
// build phase (mirrors the sibling cron-compound-promote.test.ts guard). Must
// run BEFORE the import below, hence vi.hoisted. Without this the file errors
// at collection under CI (no INNGEST_* env) → the required `test` context reds.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { TARGET_ALLOW_RE } from "@/server/inngest/functions/cron-compound-promote";

function repoRoot(): string {
  let d = dirname(fileURLToPath(import.meta.url));
  while (d !== "/" && !existsSync(join(d, "scripts", "lint-rule-bodies.py"))) {
    d = dirname(d);
  }
  return d;
}

const ROOT = repoRoot();
const GATE = join(ROOT, "scripts", "lint-rule-bodies.py");

// Every load-bearing file the gate depends on MUST be outside TARGET_ALLOW_RE.
// `_agents_md_sections.py` is the SECTIONS oracle the gate parses with — it is a
// gate dependency and must be pinned alongside the linter itself.
const GATE_CONTROL_FILES = [
  "scripts/lint-rule-bodies.py",
  "scripts/_agents_md_sections.py",
  ".claude/rule-body-hashes.txt",
  ".claude/rule-weakening-acks.txt",
  ".github/workflows/ci.yml",
  ".github/actions/bot-pr-with-synthetic-checks/action.yml",
  "scripts/ci-required-ruleset-canonical-required-status-checks.json",
  "infra/github/ruleset-ci-required.tf",
  "lefthook.yml",
  "knowledge-base/engineering/architecture/decisions/ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md",
  "knowledge-base/engineering/architecture/diagrams/model.c4",
  "knowledge-base/engineering/architecture/diagrams/spec.c4",
  "knowledge-base/engineering/architecture/diagrams/views.c4",
];

describe("rule-body gate recursion invariant (ADR-092, AC8)", () => {
  it("the gate exists because AGENTS.core.md IS auto-editable (positive control)", () => {
    expect(TARGET_ALLOW_RE.test("AGENTS.core.md")).toBe(true);
  });

  it("no gate control file is inside the auto-editable set", () => {
    for (const f of GATE_CONTROL_FILES) {
      // Guard against silent rot: the ∉ assertion is vacuously true for a
      // nonexistent path, so assert the file actually exists first.
      expect(existsSync(join(ROOT, f)), `${f} must exist`).toBe(true);
      expect(TARGET_ALLOW_RE.test(f), `${f} must be ∉ TARGET_ALLOW_RE`).toBe(false);
    }
  });

  describe("real catch property (not the ∉ tautology)", () => {
    let repo: string;
    let baseSha: string;
    const CORE = [
      "# AGENTS Core",
      "",
      "## Hard Rules",
      "",
      "- Never do the dangerous thing [id: hr-never-dangerous]. Do the safe thing.",
      "- Gate regulated data [id: hr-gdpr-example] [compliance-tier]. Mandatory on every write.",
      "",
    ].join("\n");

    const git = (...args: string[]) =>
      execFileSync("git", ["-C", repo, ...args], { encoding: "utf8" });
    const write = () =>
      execFileSync("python3", [GATE, "--root", repo, "--write"], { encoding: "utf8" });

    /** Run --check against the pinned baseline commit; return {code, stderr}. */
    const check = (): { code: number; stderr: string } => {
      try {
        execFileSync("python3", [GATE, "--root", repo, "--check", "--base", baseSha], {
          encoding: "utf8",
        });
        return { code: 0, stderr: "" };
      } catch (e) {
        const err = e as { status?: number; stderr?: Buffer | string };
        return {
          code: err.status ?? 1,
          stderr: err.stderr ? err.stderr.toString() : "",
        };
      }
    };

    beforeEach(() => {
      repo = mkdtempSync(join(tmpdir(), "rule-body-recursion-"));
      git("init", "-q", "-b", "main");
      git("config", "user.email", "t@t");
      git("config", "user.name", "t");
      writeFileSync(join(repo, "AGENTS.core.md"), CORE);
      writeFileSync(join(repo, "AGENTS.docs.md"), "# Docs\n");
      writeFileSync(join(repo, "AGENTS.rest.md"), "# Rest\n");
      mkdirSync(join(repo, ".claude"));
      writeFileSync(join(repo, ".claude", "rule-weakening-acks.txt"), "# acks\n");
      write();
      git("add", "-A");
      git("commit", "-qm", "baseline");
      baseSha = git("rev-parse", "HEAD").trim();
    });

    afterEach(() => rmSync(repo, { recursive: true, force: true }));

    it("BLOCKS a synthetic body weakening to AGENTS.core.md", () => {
      writeFileSync(
        join(repo, "AGENTS.core.md"),
        CORE.replace("Do the safe thing.", "Optional: maybe."),
      );
      write();
      git("commit", "-qam", "weaken");
      const r = check();
      expect(r.code).not.toBe(0);
      expect(r.stderr).toContain("hr-never-dangerous");
    });

    it("BLOCKS a synthetic security-tag drop on AGENTS.core.md", () => {
      writeFileSync(
        join(repo, "AGENTS.core.md"),
        // Drop [compliance-tier] — a weakening the gate must catch.
        CORE.replace(" [compliance-tier].", "."),
      );
      write();
      git("commit", "-qam", "drop-tag");
      const r = check();
      expect(r.code).not.toBe(0);
      expect(r.stderr).toContain("hr-gdpr-example");
      // The dropped tag must still trip the louder mandatory-human-review signal
      // (old body carried [compliance-tier]).
      expect(r.stderr.toLowerCase()).toContain("mandatory-human-review");
    });
  });
});
