// TR9 Phase-2 — cron-content-vendor-drift registration smoke + source-shape anchors.
//
// Test coverage:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Source-shape anchors — verbatim strings from the implementation that
//      must survive silent refactoring.
//   3. Exported constants (SYNTHETIC_CHECK_NAMES, MAX_RUN_DURATION_MS,
//      ISSUE_EXIT_CODES, NOTICE_FILE_REL, CLASSIFIER_REL, PARSER_REL).
//   4. Trust-model routing: ISSUE_EXIT_CODES set shape.

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronContentVendorDrift,
  MAX_RUN_DURATION_MS,
  ISSUE_EXIT_CODES,
  NOTICE_FILE_REL,
  PARSER_REL,
  CLASSIFIER_REL,
  SKILL_PREFIX,
} from "@/server/inngest/functions/cron-content-vendor-drift";
// #5111: consolidated into the safe-commit helper (was a per-cron copy).
import { SYNTHETIC_CHECK_NAMES } from "@/server/inngest/functions/_cron-safe-commit";

// =============================================================================
// Registration smoke
// =============================================================================

describe("cronContentVendorDrift — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronContentVendorDrift).toBeDefined();
    expect(typeof cronContentVendorDrift).toBe("object");
  });
});

// =============================================================================
// Source-shape anchors
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-content-vendor-drift.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-content-vendor-drift"', "canonical function id"],
    ['cron: "17 11 * * 1"', "Monday 11:17 off-peak schedule"],
    [
      'event: "cron/content-vendor-drift.manual-trigger"',
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
    ["scheduled-content-vendor-drift", "Sentry monitor slug"],
    ["plugins/soleur/skills/gdpr-gate/NOTICE", "NOTICE file path"],
    [
      "plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh",
      "parser script path",
    ],
    [
      "plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh",
      "classifier script path",
    ],
    [
      "chore(vendor-drift): re-vendor gosprinto/compliance-skills",
      "commit message",
    ],
    ["vendor-pin-drift-resolution.md", "runbook reference"],
    ["mintInstallationToken", "token minting"],
    ["setupEphemeralWorkspace", "workspace setup"],
    ["teardownEphemeralWorkspace", "workspace teardown"],
    ["postSentryHeartbeat", "heartbeat at end"],
    ["reportSilentFallback", "Sentry mirror on error"],
    ["ensureLabels", "label creation"],
    ["vendor/pin-drift", "drift label"],
    ["vendor/license-changed", "license drift label"],
    ["vendor/upstream-archived", "archived label"],
    ["vendor/upstream-rollback", "rollback label"],
    ["vendor/cron-failure", "cron failure label"],
    ["compliance/critical", "compliance label"],
    ["needs-human-review", "human review label"],
    [
      "drift requires human re-vendor",
      "trust model routing explanation",
    ],
    ["Ref #3517", "issue reference"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("handler-side persistence (#5111)", () => {
  it("routes the PR path through safeCommitAndPr with direct merge, labels, and synthetic checks", () => {
    expect(SUT_SOURCE).toContain('from "./_cron-safe-commit"');
    expect(SUT_SOURCE).toMatch(/safeCommitAndPr\(\{/);
    expect(SUT_SOURCE).toContain('mergeMode: "direct"');
    expect(SUT_SOURCE).toContain("syntheticChecks");
    expect(SUT_SOURCE).toContain("prLabels: detectResult.labels");
    // Directory allowlist entry carries the trailing slash the helper's
    // startsWith matching requires; NOTICE is an exact-file entry.
    expect(SUT_SOURCE).toContain(
      "allowedPaths: [`${SKILL_PREFIX}/NOTICE`, `${SKILL_PREFIX}/references/`]",
    );
    // The private staging pipeline must not return.
    expect(SUT_SOURCE).not.toContain("spawnGitChecked");
  });
});

// =============================================================================
// Exported constants
// =============================================================================

describe("exported constants", () => {
  it("MAX_RUN_DURATION_MS is 15 minutes", () => {
    expect(MAX_RUN_DURATION_MS).toBe(15 * 60 * 1000);
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

  it("NOTICE_FILE_REL points to gdpr-gate NOTICE", () => {
    expect(NOTICE_FILE_REL).toBe("plugins/soleur/skills/gdpr-gate/NOTICE");
  });

  it("PARSER_REL points to notice-frontmatter.sh", () => {
    expect(PARSER_REL).toBe(
      "plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh",
    );
  });

  it("CLASSIFIER_REL points to vendor-drift-classify.sh", () => {
    expect(CLASSIFIER_REL).toBe(
      "plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh",
    );
  });

  it("SKILL_PREFIX is plugins/soleur/skills/gdpr-gate", () => {
    expect(SKILL_PREFIX).toBe("plugins/soleur/skills/gdpr-gate");
  });
});

// =============================================================================
// Trust-model routing: ISSUE_EXIT_CODES
// =============================================================================

describe("ISSUE_EXIT_CODES — trust-model routing", () => {
  it("contains exit codes 10, 11, 12, 15, 16 (security-relevant)", () => {
    expect(ISSUE_EXIT_CODES.has(10)).toBe(true);
    expect(ISSUE_EXIT_CODES.has(11)).toBe(true);
    expect(ISSUE_EXIT_CODES.has(12)).toBe(true);
    expect(ISSUE_EXIT_CODES.has(15)).toBe(true);
    expect(ISSUE_EXIT_CODES.has(16)).toBe(true);
  });

  it("does NOT contain exit code 13 (low-risk batched drift → PR route)", () => {
    expect(ISSUE_EXIT_CODES.has(13)).toBe(false);
  });

  it("does NOT contain exit code 0 (no drift)", () => {
    expect(ISSUE_EXIT_CODES.has(0)).toBe(false);
  });

  it("has exactly 5 entries", () => {
    expect(ISSUE_EXIT_CODES.size).toBe(5);
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
