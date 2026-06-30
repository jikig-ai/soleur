// TR9 PR-8 (#4439) — cron-legal-audit handler unit tests.
//
// Minimal test coverage focused on the invariants the PR-7 multi-agent
// review surfaced as load-bearing (this handler reuses that pattern):
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (MILESTONE RULE, Run /soleur:legal-audit,
//      CAP_OPEN_ISSUES = 20, CAP_PER_RUN     = 5, "[Scheduled] Legal Audit"
//      title prefix) — original anchors from the GHA prompt that must
//      survive silent paraphrasing across plan→work→ship cycles.
//   3. Timing constants exported (MAX_TURN_DURATION_MS, KILL_ESCALATION_MS)
//      so the substrate-extraction follow-up can centralise them without
//      breaking parity with the handler's actual values.

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE all ES-module imports below — sets NEXT_PHASE so
// the inngest client's startup-key check short-circuits (same path Next.js
// `next build` uses). Mirrors cron-strategy-review-graymatter.test.ts and
// cron-roadmap-review.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronLegalAudit,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-legal-audit";

describe("cronLegalAudit — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    // Smoke test: the import at the top of this file already drove the
    // module's top-level code; if registration shape were structurally
    // broken (missing trigger, malformed concurrency), it would have
    // thrown during inngest.createFunction at module load.
    expect(cronLegalAudit).toBeDefined();
    expect(typeof cronLegalAudit).toBe("object");
  });
});

describe("cronLegalAudit — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 50 minutes (matches sibling claude-eval crons)", () => {
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
    "../../../server/inngest/functions/cron-legal-audit.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-legal-audit"', "canonical function id"],
    ['cron: "0 11 1 1,4,7,10 *"', "quarterly Jan/Apr/Jul/Oct 1 @ 11:00 UTC schedule"],
    ['event: "cron/legal-audit.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on agent-loop failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("LEGAL_AUDIT_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["Run /soleur:legal-audit", "skill-invocation directive"],
      ["MILESTONE RULE:", "rule keyword"],
      ["CAP_OPEN_ISSUES = 20", "open-issue cap enforcement"],
      ["CAP_PER_RUN     = 5", "per-run severity-ranked cap"],
      ["[Scheduled] Legal Audit", "issue-title format"],
      ["scheduled-legal-audit", "label name"],
      ["US, EU/GDPR,", "jurisdiction enumeration"],
      ["90-day window prevents reopen-loops", "idempotency window"],
      ["Injection safety:", "agent-output interpolation guard"],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });
});

describe("#4730 — heartbeat decoupled from claude exit code (best-effort)", () => {
  it("success-path heartbeat is liveness (ok: true), not the bare spawn exit code", () => {
    // The prompt exits cleanly without filing when no legal documents are found
    // (explicit zero-issue clean path), so a non-zero/no-artifact run is NORMAL.
    // The monitor's liveness contract is "pipeline ran end-to-end without an
    // INFRA fault" — decoupled from claude's exit. Mirrors cron-bug-fixer.ts
    // (PR #4727). The pre-fix line was the forbidden `ok: spawnResult.ok`.
    expect(SUT_SOURCE).not.toContain("ok: spawnResult.ok");
    // #5674 classify-fatal: the final heartbeat is gated on decision.ok from
    // resolveBestEffortEvalOk (green on clean/benign, red on a fatal class),
    // NOT an unconditional `ok: true`.
    expect(SUT_SOURCE).toContain("resolveBestEffortEvalOk(spawnResult)");
    expect(SUT_SOURCE).toContain("postSentryHeartbeat({ ok: decision.ok");
    // A FATAL class (credit/auth/spawn/timeout) reports + flips the monitor red.
    expect(SUT_SOURCE).toContain('op: "claude-eval-fatal"');
  });

  it("surfaces the non-zero exit as a non-paging WARNING Sentry event (off-host visible)", () => {
    // warnSilentFallback (queryable WARNING), NOT a bare logger.warn — see
    // cq-silent-fallback-must-mirror-to-sentry / hr-observability-layer-citation.
    expect(SUT_SOURCE).toContain("warnSilentFallback");
    expect(SUT_SOURCE).toContain('op: "claude-eval-nonzero-noop"');
  });
});

// #5046 PR-2 Phase 2.C (AC-P2.12) — this restored cron mints the
// issue-creator least-privilege token (contents:read + issues:write,
// repo-scoped to soleur), never the full installation grant and never
// push/PR write. Source anchors per this file's idiom.
describe("least-privilege token mint (#5046 PR-2)", () => {
  it("mints with ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS + repositories: [REPO_NAME]", () => {
    expect(SUT_SOURCE).toContain("permissions: ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS");
    expect(SUT_SOURCE).toContain("repositories: [REPO_NAME]");
    expect(SUT_SOURCE).not.toContain("DEFAULT_CRON_TOKEN_PERMISSIONS");
  });

  // Gate #1 is --allowedTools (the hook is gate #2 and runHookSelfTest
  // cannot see the flags): dropping Task/Skill here silently breaks the
  // skill invocation with green heartbeats.
  it("--allowedTools carries Task + Skill (the restored constructs)", () => {
    expect(SUT_SOURCE).toContain('"Bash,Read,Write,Edit,Glob,Grep,Task,Skill"');
  });
});
