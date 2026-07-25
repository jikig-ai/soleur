import { beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
// Partial mock — keep every real export (default logger, etc.) and only spy on
// reportSilentFallback so the over-strip fallback path is observable. A
// wholesale factory would drop siblings the cron's import graph needs.
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));
import { reportSilentFallback } from "@/server/observability";
import { stripFrontmatter } from "../../../../../scripts/lib/frontmatter-strip/strip";
import {
  ANTHROPIC_MAX_TOKENS,
  ANTHROPIC_MODEL,
  MAX_DIFF_BYTES,
  PII_REGEX,
  TARGET_ALLOW_RE,
  diffRemovesHardRule,
  extractEnabledFlag,
  measureAlwaysLoadedBytes,
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

  it("inlines stripFrontmatter — does NOT cross-root-import repo-root scripts/ (#6794/#6860)", () => {
    // The Next.js Docker build context copies only apps/web-platform/ (+ the
    // vendored plugin), NOT repo-root scripts/. A `../../../../../scripts/…`
    // import compiles under a local `next build` (full repo present) but FAILS
    // the containerized build with "Module not found: …/scripts/…" (release run
    // 29994907565, step 19). The frontmatter strip is therefore INLINED here,
    // contract-pinned to scripts/lib/frontmatter-strip/SPEC.md. Guard the
    // regression. (Non-vacuous: the pre-fix source matched via its 5-`../`
    // import; #6852 shipped it and broke the release.)
    expect(SUT_SOURCE).not.toMatch(/from\s+["'](\.\.\/){3,}scripts\//);
    expect(SUT_SOURCE).toContain("function stripFrontmatter(");
  });
});

// =============================================================================
// #6794: always-loaded byte measurement on the frontmatter-stripped basis
// =============================================================================

describe("measureAlwaysLoadedBytes (#6794 — stripped-basis measurement)", () => {
  const STRIP_PY = join(
    __dirname,
    "..",
    "..",
    "..",
    "..",
    "..",
    "scripts",
    "lib",
    "frontmatter-strip",
    "strip.py",
  );

  // Order-independence: this describe block is the only one that asserts on the
  // reportSilentFallback spy, and vitest.config sets no clearMocks. Clear per
  // test so the `.not.toHaveBeenCalled()` case does not depend on declaration
  // order (fail-safe today — leaked state can only false-RED — but explicit).
  beforeEach(() => {
    vi.mocked(reportSilentFallback).mockClear();
  });

  it("measures index raw + core stripped, matching the linter's B_ALWAYS basis", () => {
    // AGENTS.md has no leading frontmatter → strip is a no-op (raw bytes).
    const indexText = "# AGENTS — index\n\n- [id: hr-alpha] → core\n";
    // AGENTS.core.md carries a frontmatter block the strip must remove.
    const coreText =
      "---\nlast_reviewed: 2026-07-05\nowner: founder\n---\n\n- body [id: hr-alpha]\n- body [id: hr-beta]\n";

    const expected =
      Buffer.byteLength(indexText, "utf8") +
      Buffer.byteLength(stripFrontmatter(coreText), "utf8");

    // Invariant, not a shape check: a helper that sums the wrong files or
    // double-counts fails this.
    expect(measureAlwaysLoadedBytes(indexText, coreText)).toBe(expected);

    // Cross-language sanity: the TS-stripped core byte count equals the
    // canonical strip.py byte count (same authority the commit gate uses).
    const pyStrippedBytes = execFileSync("python3", [STRIP_PY], {
      input: coreText,
    }).length;
    expect(Buffer.byteLength(stripFrontmatter(coreText), "utf8")).toBe(
      pyStrippedBytes,
    );

    // No over-strip on well-formed input → no fallback signal.
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("falls back to RAW bytes + signals when the core over-strips (unterminated ---)", () => {
    const indexText = "# AGENTS — index\n";
    // Opening `---` with NO closing `---` line: strip consumes the whole file
    // to empty, dropping the two `[id: …]` rule lines — the dangerous
    // (falsely-smaller) direction the guard exists to catch.
    const coreOverStrip =
      "---\nlast_reviewed: 2026-07-05\n- body [id: hr-alpha]\n- body [id: hr-beta]\n";

    // Guard fires → RAW measurement (NOT the empty-strip 0-byte count).
    const result = measureAlwaysLoadedBytes(indexText, coreOverStrip);
    expect(result).toBe(
      Buffer.byteLength(indexText, "utf8") +
        Buffer.byteLength(coreOverStrip, "utf8"),
    );

    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "frontmatter-overstrip-fallback" }),
    );
  });
});
