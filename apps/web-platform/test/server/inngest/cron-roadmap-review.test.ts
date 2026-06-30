// TR9 PR-7 (#4425) — cron-roadmap-review handler unit tests.
//
// Minimal test coverage focused on the invariants the multi-agent review
// flagged as load-bearing:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (Part 1, Part 2, MILESTONE RULE, BIDIRECTIONAL
//      RULE) — original anchors from the GHA prompt that must survive
//      silent paraphrasing across plan→work→ship cycles.
//   3. Safety-guard anchors (DEDUP RULE, ISSUE CLOSURE SAFETY, ROADMAP.MD
//      CONFLICT GUARD, CLONE DEPTH RULE) — added at review time to bound
//      blast radius (duplicate-issue, stale-issue closure, conflict with
//      human edits, shallow-clone staleness). A regression removing these
//      reverts the data-integrity-guardian P1/P2 fixes from PR review.
//   4. Timing constants exported (MAX_TURN_DURATION_MS, KILL_ESCALATION_MS)
//      so the substrate-extraction follow-up can centralise them without
//      breaking parity with the handler's actual values.

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE all ES-module imports below — sets NEXT_PHASE so
// the inngest client's startup-key check short-circuits (same path Next.js
// `next build` uses). Mirrors cron-strategy-review-graymatter.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronRoadmapReview,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-roadmap-review";

describe("cronRoadmapReview — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    // Smoke test: the import at the top of this file already drove the
    // module's top-level code; if registration shape were structurally
    // broken (missing trigger, malformed concurrency), it would have
    // thrown during inngest.createFunction at module load.
    expect(cronRoadmapReview).toBeDefined();
    expect(typeof cronRoadmapReview).toBe("object");
  });
});

describe("cronRoadmapReview — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 50 minutes (matches sibling cron-bug-fixer)", () => {
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
    "../../../server/inngest/functions/cron-roadmap-review.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-roadmap-review"', "canonical function id"],
    ['cron: "0 9 * * 1"', "Monday 09:00 UTC schedule"],
    ['event: "cron/roadmap-review.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on agent-loop failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("ROADMAP_REVIEW_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["Part 1: Issue-to-Milestone Alignment", "section header"],
      ["Part 2: Bidirectional Integrity Gate", "section header"],
      ["MILESTONE RULE:", "rule keyword"],
      ["BIDIRECTIONAL RULE:", "rule keyword"],
      ["[Scheduled] Weekly Roadmap Review", "issue-title format"],
      ["scheduled-roadmap-review", "label name"],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });

  describe("review-added safety-guard anchors (PR-7 data-integrity-guardian fixes)", () => {
    it.each([
      ["DEDUP RULE", "duplicate-issue prevention (manual+cron same week)"],
      ["ISSUE CLOSURE SAFETY:", "close/reassign blast-radius bound"],
      ["ROADMAP.MD CONFLICT GUARD:", "human/agent edit collision"],
      ["CLONE DEPTH RULE:", "stale `git log` misuse on --depth=1 clone"],
      ["STAGING RULE (#5091):", "scoped staging on the live Tier-1 auto-fix-PR path"],
      [
        "no comments, no commits referencing the issue) in the last 14 days",
        "activity-window guard for closures",
      ],
      ["priority/p0-critical", "exclusion label for closures"],
      [
        "post your findings as a comment on the most recent existing issue",
        "dedup fallback behaviour",
      ],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
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
