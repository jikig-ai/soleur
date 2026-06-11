// TR9 Phase-2 — cron-rule-prune registration smoke + source-shape anchors.
//
// Test coverage:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Source-shape anchors — verbatim strings from the implementation that
//      must survive silent refactoring.
//   3. Exported constants (SYNTHETIC_CHECK_NAMES, MAX_RUN_DURATION_MS,
//      SENTINEL_PR_TITLE, SENTINEL_PR_BODY).
//   4. parseSentinels helper unit tests.

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronRulePrune,
  MAX_RUN_DURATION_MS,
  SENTINEL_PR_TITLE,
  SENTINEL_PR_BODY,
  parseSentinels,
} from "@/server/inngest/functions/cron-rule-prune";
// #5111: consolidated into the safe-commit helper (was a per-cron copy).
import { SYNTHETIC_CHECK_NAMES } from "@/server/inngest/functions/_cron-safe-commit";

// =============================================================================
// Registration smoke
// =============================================================================

describe("cronRulePrune — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronRulePrune).toBeDefined();
    expect(typeof cronRulePrune).toBe("object");
  });
});

// =============================================================================
// Source-shape anchors
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-rule-prune.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-rule-prune"', "canonical function id"],
    ['cron: "0 9 1 1,4,7,10 *"', "quarterly schedule (Jan/Apr/Jul/Oct)"],
    [
      'event: "cron/rule-prune.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("handler source-shape anchors", () => {
  it.each([
    ["scheduled-rule-prune", "Sentry monitor slug"],
    ["scripts/rule-prune.sh", "spawns the existing bash script"],
    ["--weeks=26", "26-week threshold"],
    ["--propose-retirement", "retirement proposal mode"],
    ["::rule-prune-pr-title::", "PR title sentinel"],
    ["::rule-prune-pr-body::", "PR body sentinel"],
    [
      "chore(rule-prune): propose retirement of stale rules",
      "commit message",
    ],
    ["retired-rule-ids.txt", "retirement tracking file"],
    ["mintInstallationToken", "token minting"],
    ["setupEphemeralWorkspace", "workspace setup"],
    ["teardownEphemeralWorkspace", "workspace teardown"],
    ["postSentryHeartbeat", "heartbeat at end"],
    ["reportSilentFallback", "Sentry mirror on error"],
    [
      "partial-failure recovery",
      "partial-failure detection for modified file without sentinels",
    ],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("handler-side persistence (#5111)", () => {
  it("routes persistence through safeCommitAndPr with direct merge, dynamic title, synthetic checks", () => {
    expect(SUT_SOURCE).toContain('from "./_cron-safe-commit"');
    expect(SUT_SOURCE).toMatch(/safeCommitAndPr\(\{/);
    expect(SUT_SOURCE).toContain('mergeMode: "direct"');
    expect(SUT_SOURCE).toContain("syntheticChecks");
    expect(SUT_SOURCE).toContain('allowedPaths: ["scripts/retired-rule-ids.txt"]');
    // The script's sentinel-derived dynamic title survives the migration.
    expect(SUT_SOURCE).toContain("prTitle: `${pruneResult.prTitle} ${dateSuffix}`");
    // The private staging pipeline must not return.
    expect(SUT_SOURCE).not.toContain("spawnGitChecked");
  });
});

// =============================================================================
// Exported constants
// =============================================================================

describe("exported constants", () => {
  it("MAX_RUN_DURATION_MS is 5 minutes", () => {
    expect(MAX_RUN_DURATION_MS).toBe(5 * 60 * 1000);
  });

  it("SYNTHETIC_CHECK_NAMES has exactly 7 entries", () => {
    expect(SYNTHETIC_CHECK_NAMES.length).toBe(7);
  });

  it("SYNTHETIC_CHECK_NAMES matches the verbatim list", () => {
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

  it("SENTINEL_PR_TITLE is the correct sentinel prefix", () => {
    expect(SENTINEL_PR_TITLE).toBe("::rule-prune-pr-title::");
  });

  it("SENTINEL_PR_BODY is the correct sentinel prefix", () => {
    expect(SENTINEL_PR_BODY).toBe("::rule-prune-pr-body::");
  });
});

// =============================================================================
// parseSentinels unit tests
// =============================================================================

describe("parseSentinels", () => {
  it("extracts PR title and body from stdout with sentinels", () => {
    const stdout = [
      "Processing rule-metrics.json...",
      "Found 3 candidates.",
      "::rule-prune-pr-title::chore(rule-prune): retire 3 stale rules",
      "::rule-prune-pr-body::Retiring wg-old-gate, cq-unused, rf-stale after 26 weeks of zero hits.",
      "Done.",
    ].join("\n");

    const result = parseSentinels(stdout);
    expect(result.prTitle).toBe(
      "chore(rule-prune): retire 3 stale rules",
    );
    expect(result.prBody).toBe(
      "Retiring wg-old-gate, cq-unused, rf-stale after 26 weeks of zero hits.",
    );
  });

  it("returns null for both when no sentinels are present", () => {
    const stdout = [
      "Processing rule-metrics.json...",
      "No candidates found.",
    ].join("\n");

    const result = parseSentinels(stdout);
    expect(result.prTitle).toBeNull();
    expect(result.prBody).toBeNull();
  });

  it("returns null for body when only title sentinel is present", () => {
    const stdout =
      "::rule-prune-pr-title::chore(rule-prune): retire 1 stale rule\n";

    const result = parseSentinels(stdout);
    expect(result.prTitle).toBe(
      "chore(rule-prune): retire 1 stale rule",
    );
    expect(result.prBody).toBeNull();
  });

  it("handles empty stdout", () => {
    const result = parseSentinels("");
    expect(result.prTitle).toBeNull();
    expect(result.prBody).toBeNull();
  });

  it("trims whitespace from sentinel values", () => {
    const stdout =
      "::rule-prune-pr-title::  title with spaces  \n::rule-prune-pr-body::  body with spaces  \n";
    const result = parseSentinels(stdout);
    expect(result.prTitle).toBe("title with spaces");
    expect(result.prBody).toBe("body with spaces");
  });
});

// =============================================================================
// No claude binary spawn
// =============================================================================

describe("no claude binary spawn", () => {
  it("handler source contains no claude spawn references", () => {
    expect(SUT_SOURCE).not.toMatch(/CLAUDE_BIN/);
    expect(SUT_SOURCE).not.toMatch(/resolveClaudeBin/);
    expect(SUT_SOURCE).not.toMatch(/spawnClaudeEval/);
    expect(SUT_SOURCE).not.toMatch(/--allowedTools/);
  });
});
