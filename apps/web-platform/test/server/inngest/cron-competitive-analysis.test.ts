// TR9 PR-10 (#4448) — cron-competitive-analysis handler unit tests.
//
// Minimal test coverage focused on the invariants the multi-agent review
// flagged as load-bearing:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (MILESTONE RULE, /soleur:competitive-analysis
//      --tiers 0,3 invocation, platform-persistence directive, issue-title
//      format, label, competitive-intelligence.md persistence target) —
//      anchors that must survive silent paraphrasing across
//      plan→work→ship cycles.
//   3. Timing constants exported (MAX_TURN_DURATION_MS, KILL_ESCALATION_MS)
//      so the substrate-extraction follow-up can centralise them without
//      breaking parity with the handler's actual values.

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE all ES-module imports below — sets NEXT_PHASE so
// the inngest client's startup-key check short-circuits (same path Next.js
// `next build` uses). Mirrors cron-roadmap-review.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronCompetitiveAnalysis,
  COMPETITIVE_ANALYSIS_ALLOWED_PATHS,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-competitive-analysis";

describe("cronCompetitiveAnalysis — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    // Smoke test: the import at the top of this file already drove the
    // module's top-level code; if registration shape were structurally
    // broken (missing trigger, malformed concurrency), it would have
    // thrown during inngest.createFunction at module load.
    expect(cronCompetitiveAnalysis).toBeDefined();
    expect(typeof cronCompetitiveAnalysis).toBe("object");
  });
});

describe("cronCompetitiveAnalysis — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 50 minutes (matches claude-eval cohort)", () => {
    expect(MAX_TURN_DURATION_MS).toBe(50 * 60 * 1000);
  });

  it("KILL_ESCALATION_MS is 5 seconds (SIGTERM → SIGKILL grace)", () => {
    expect(KILL_ESCALATION_MS).toBe(5_000);
  });
});

// Source-file-content tests — read the SUT file and assert the prompt
// constant contains the verbatim anchors. Per AGENTS.md
// `cq-test-fixtures-synthesized-only`, we read the production source via
// readFileSync rather than synthesising a parallel prompt fixture (the
// prompt IS the artifact under test; mirroring it in a fixture would defeat
// the regression-detection purpose).

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-competitive-analysis.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-competitive-analysis"', "canonical function id"],
    ['cron: "0 9 1 * *"', "monthly 1st @ 09:00 UTC schedule"],
    [
      'event: "cron/competitive-analysis.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on agent-loop failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("COMPETITIVE_ANALYSIS_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["MILESTONE RULE:", "rule keyword"],
      [
        "Run /soleur:competitive-analysis --tiers 0,3",
        "skill invocation with tier args",
      ],
      ["[Scheduled] Competitive Analysis", "issue-title format"],
      ["scheduled-competitive-analysis", "label / Sentry monitor slug"],
      [
        "knowledge-base/product/competitive-intelligence.md",
        "persistence target file",
      ],
      [
        "PERSISTENCE: Do NOT run git add",
        "platform-persistence directive (#5111)",
      ],
      [
        "opens a PR for your changes",
        "handler-side persistence note (#5111)",
      ],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });
});

describe("#5111 — handler-side persistence (safeCommitAndPr migration)", () => {
  it("prompt carries the platform-persistence directive, not a commit block", () => {
    expect(SUT_SOURCE).toContain("PERSISTENCE: Do NOT run git add");
    expect(SUT_SOURCE).not.toContain("MANDATORY FINAL STEP");
    // No prompt-side staging command survives. The PERSISTENCE directive's
    // own "git add," mention is comma-delimited, so the trailing-space form
    // below only matches a real `git add <paths>` shell command.
    expect(SUT_SOURCE).not.toMatch(/git add /);
  });

  it("wires the gated safe-commit-pr step (issue-verified AND not timed out)", () => {
    expect(SUT_SOURCE).toContain('from "./_cron-safe-commit"');
    expect(SUT_SOURCE).toContain('step.run("safe-commit-pr"');
    // Plan AC: persistence MUST be gated on issue-verified output AND
    // not-timed-out — a regression to `spawnResult.ok` (the #4747 hazard)
    // or a dropped timeout clause turns this red. Mirrors the parity test.
    expect(SUT_SOURCE).toMatch(
      /if \(heartbeatOk && !spawnResult\.abortedByTimeout\) \{[\s\S]{0,800}?safeCommitAndPr\(\{/,
    );
  });

  it("allowedPaths cover the cascade write-set (deliberate widening vs the old prompt)", () => {
    // The old prompt committed ONLY competitive-intelligence.md and silently
    // discarded cascade outputs (content-strategy, pricing, battlecards,
    // seo-refresh-queue). Asserted on the exported CONST (not whole-file
    // text) so a path dropped from the const cannot stay green via its
    // remaining mention in the prompt prose.
    expect([...COMPETITIVE_ANALYSIS_ALLOWED_PATHS]).toEqual([
      "knowledge-base/product/competitive-intelligence.md",
      "knowledge-base/marketing/content-strategy.md",
      "knowledge-base/product/pricing-strategy.md",
      "knowledge-base/sales/battlecards/",
      "knowledge-base/marketing/seo-refresh-queue.md",
    ]);
  });
});

// #5786 — producer-side date-dedup serialization anchor (AC6). The cohort
// behavioral test (cron-cohort-dedup.test.ts) proves the exactly-one-digest
// invariant; that fake-store test serializes by invoking the handler twice in
// sequence, so it CANNOT exercise real Inngest concurrency. This anchors the
// registration's `{ scope: "fn", limit: 1 }` — the serializer BOTH the handler
// dedup and the cohort test's "invocation #2 sees #1's create" depend on.
describe("#5786 producer-side dedup — concurrency serialization anchor (AC6)", () => {
  it('registration concurrency contains { scope: "fn", limit: 1 }', () => {
    expect(SUT_SOURCE).toContain('{ scope: "fn", limit: 1 }');
  });
});
