import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
import {
  ANTHROPIC_MAX_TOKENS,
  ANTHROPIC_MODEL,
  MAX_DIFF_BYTES,
  PII_REGEX,
  TARGET_ALLOW_RE,
  diffRemovesHardRule,
  extractEnabledFlag,
} from "@/server/inngest/functions/cron-compound-promote";
// #5111: consolidated into the safe-commit helper (was a per-cron copy).
import { SYNTHETIC_CHECK_NAMES } from "@/server/inngest/functions/_cron-safe-commit";

// =============================================================================
// AC8: PII regex byte-equality with bash script
// =============================================================================

describe("PII regex parity (AC8)", () => {
  it("TS regex source matches the bash PII_REGEX at scripts/compound-promote.sh:75", () => {
    const repoRoot = join(__dirname, "..", "..", "..", "..", "..");
    const script = readFileSync(
      join(repoRoot, "scripts", "compound-promote.sh"),
      "utf-8",
    );
    const match = script.match(/^PII_REGEX='([^']+)'/m);
    expect(match).not.toBeNull();
    const bashRegex = match![1];
    expect(PII_REGEX.source).toBe(bashRegex);
  });

  it("matches email addresses", () => {
    expect(PII_REGEX.test("jean@example.test")).toBe(true);
  });

  it("matches IPv4", () => {
    expect(PII_REGEX.test("192.168.1.100")).toBe(true);
  });

  it("matches GitHub tokens", () => {
    expect(PII_REGEX.test("ghp_1234567890abcdefghij")).toBe(true);
    expect(PII_REGEX.test("ghs_1234567890abcdefghij")).toBe(true);
  });

  it("matches Anthropic API keys", () => {
    expect(PII_REGEX.test("sk-ant-abcdefghijklmnopqrst")).toBe(true);
  });

  it("matches Stripe keys", () => {
    expect(PII_REGEX.test("sk_live_abcdefghijklmnopqrst")).toBe(true);
    expect(PII_REGEX.test("pk_test_abcdefghijklmnopqrst")).toBe(true);
  });

  it("does not match safe content", () => {
    expect(PII_REGEX.test("This is a normal learning about TDD")).toBe(false);
  });
});

// =============================================================================
// AC9: Anthropic POST body constants
// =============================================================================

describe("Anthropic body constants (AC9)", () => {
  it("model is claude-sonnet-5", () => {
    expect(ANTHROPIC_MODEL).toBe("claude-sonnet-5");
  });

  it("max_tokens is 16384", () => {
    expect(ANTHROPIC_MAX_TOKENS).toBe(16384);
  });
});

// =============================================================================
// AC11: no claude binary spawn
// =============================================================================

describe("no claude binary spawn (AC11)", () => {
  it("handler source contains no claude spawn references", () => {
    const repoRoot = join(__dirname, "..", "..", "..", "..", "..");
    const src = readFileSync(
      join(repoRoot, "apps", "web-platform", "server", "inngest", "functions", "cron-compound-promote.ts"),
      "utf-8",
    );
    expect(src).not.toMatch(/claude_args/);
    expect(src).not.toMatch(/CLAUDE_BIN/);
    expect(src).not.toMatch(/resolveClaudeBin/);
    expect(src).not.toMatch(/spawnClaudeEval/);
    expect(src).not.toMatch(/--allowedTools/);
  });
});

// =============================================================================
// AC14: AGENTS.core.md hr- rule guard (FR10)
// =============================================================================

describe("diffRemovesHardRule (AC14 / FR10)", () => {
  it("detects removal of a line containing [id: hr-", () => {
    const diff = [
      "--- a/AGENTS.core.md",
      "+++ b/AGENTS.core.md",
      "@@ -10,3 +10,2 @@",
      " - [id: wg-something] some rule",
      "-  - [id: hr-foo] hard rule that must not be removed",
      " - [id: cq-bar] code quality",
    ].join("\n");
    expect(diffRemovesHardRule(diff)).toBe(true);
  });

  it("allows removal of non-hr rules", () => {
    const diff = [
      "--- a/AGENTS.core.md",
      "+++ b/AGENTS.core.md",
      "@@ -10,3 +10,2 @@",
      "-  - [id: wg-old-rule] old workflow gate",
      " - [id: cq-bar] code quality",
    ].join("\n");
    expect(diffRemovesHardRule(diff)).toBe(false);
  });

  it("allows additions of hr rules (not removals)", () => {
    const diff = [
      "--- a/AGENTS.core.md",
      "+++ b/AGENTS.core.md",
      "@@ -10,2 +10,3 @@",
      "+  - [id: hr-new] new hard rule",
      " - [id: cq-bar] code quality",
    ].join("\n");
    expect(diffRemovesHardRule(diff)).toBe(false);
  });
});

// =============================================================================
// FR9: target_path allowlist
// =============================================================================

describe("TARGET_ALLOW_RE (FR9)", () => {
  it("allows AGENTS.core.md", () => {
    expect(TARGET_ALLOW_RE.test("AGENTS.core.md")).toBe(true);
  });

  it("allows plugins/soleur/skills/foo-bar/SKILL.md", () => {
    expect(TARGET_ALLOW_RE.test("plugins/soleur/skills/foo-bar/SKILL.md")).toBe(
      true,
    );
  });

  it("refuses apps/web-platform/server/foo.ts", () => {
    expect(TARGET_ALLOW_RE.test("apps/web-platform/server/foo.ts")).toBe(false);
  });

  it("refuses AGENTS.md (index only)", () => {
    expect(TARGET_ALLOW_RE.test("AGENTS.md")).toBe(false);
  });

  it("refuses .github/workflows/x.yml", () => {
    expect(TARGET_ALLOW_RE.test(".github/workflows/x.yml")).toBe(false);
  });
});

// =============================================================================
// FR2: config gate
// =============================================================================

describe("extractEnabledFlag (FR2)", () => {
  it("returns true for enabled: true", () => {
    expect(extractEnabledFlag("enabled: true\n")).toBe(true);
  });

  it("returns false for enabled: false", () => {
    expect(extractEnabledFlag("enabled: false\n")).toBe(false);
  });

  it("returns false when key is missing", () => {
    expect(extractEnabledFlag("# nothing\n")).toBe(false);
  });
});

// =============================================================================
// FR14: synthetic checks count and names (AC18)
// =============================================================================

describe("synthetic checks (AC18)", () => {
  it("exactly 7 check names", () => {
    expect(SYNTHETIC_CHECK_NAMES.length).toBe(7);
  });

  it("names match the verbatim list from the workflow", () => {
    expect(SYNTHETIC_CHECK_NAMES).toEqual([
      "test",
      "dependency-review",
      "e2e",
      "skill-security-scan PR gate",
      "enforce",
      "cla-check",
      "cla-evidence",
    ]);
  });
});

// =============================================================================
// MAX_DIFF_BYTES constant
// =============================================================================

describe("MAX_DIFF_BYTES", () => {
  it("is 16384", () => {
    expect(MAX_DIFF_BYTES).toBe(16384);
  });
});

// =============================================================================
// Handler-side persistence (#5111)
// =============================================================================

describe("handler-side persistence (#5111)", () => {
  const SUT_SOURCE = readFileSync(
    join(
      __dirname,
      "../../../server/inngest/functions/cron-compound-promote.ts",
    ),
    "utf-8",
  );

  it("routes per-cluster persistence through safeCommitAndPr as a human-review draft", () => {
    expect(SUT_SOURCE).toContain('from "./_cron-safe-commit"');
    expect(SUT_SOURCE).toMatch(/safeCommitAndPr\(\{/);
    // Human-review proposal: draft PR, labels, NO merge.
    expect(SUT_SOURCE).toContain('mergeMode: "none"');
    expect(SUT_SOURCE).toContain("prDraft: true");
    expect(SUT_SOURCE).toContain('prLabels: ["self-healing/auto"]');
    // Per-cluster branch override survives the migration.
    expect(SUT_SOURCE).toContain("branchName,");
    expect(SUT_SOURCE).toContain("commitBody: trailer");
    // The private staging pipeline must not return.
    expect(SUT_SOURCE).not.toContain("spawnGitChecked");
  });
});
