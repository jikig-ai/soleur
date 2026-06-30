// TR9 Phase 2 — cron-campaign-calendar handler unit tests.
//
// Minimal test coverage focused on load-bearing invariants:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (campaign-calendar, overdue, heartbeat,
//      content-strategy.md, platform-persistence directive) — anchors that
//      must survive silent paraphrasing.
//   3. Timing constants exported (MAX_TURN_DURATION_MS, KILL_ESCALATION_MS).
//   4. buildSpawnEnv allowlist — positive class (5 base vars) AND negative
//      class (sensitive denylist + spread operator).

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE all ES-module imports below — sets NEXT_PHASE so
// the inngest client's startup-key check short-circuits (same path Next.js
// `next build` uses). Mirrors cron-roadmap-review.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronCampaignCalendar,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-campaign-calendar";

describe("cronCampaignCalendar — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronCampaignCalendar).toBeDefined();
    expect(typeof cronCampaignCalendar).toBe("object");
  });
});

describe("cronCampaignCalendar — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 30 minutes", () => {
    expect(MAX_TURN_DURATION_MS).toBe(30 * 60 * 1000);
  });

  it("KILL_ESCALATION_MS is 5 seconds (SIGTERM → SIGKILL grace)", () => {
    expect(KILL_ESCALATION_MS).toBe(5_000);
  });
});

// Source-file-content tests — read the SUT file and assert the prompt
// constant contains the verbatim anchors. Per AGENTS.md
// `cq-test-fixtures-synthesized-only`, we read the production source via
// readFileSync rather than synthesising a parallel prompt fixture.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-campaign-calendar.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-campaign-calendar"', "canonical function id"],
    ['cron: "0 16 * * 1"', "Monday 16:00 UTC schedule"],
    ['event: "cron/campaign-calendar.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on agent-loop failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("CAMPAIGN_CALENDAR_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["campaign-calendar", "skill invocation"],
      ["overdue", "overdue content detection"],
      ["heartbeat", "heartbeat audit issue"],
      ["content-strategy.md", "content-strategy review date update"],
      ["PERSISTENCE: Do NOT run git add", "platform-persistence directive (#5111)"],
      ["opens a PR for your changes", "handler-side persistence note (#5111)"],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });

  describe("safety-guard anchors (cohort discipline)", () => {
    it.each([
      [
        "Do NOT push directly to main",
        "no direct main writes (handler-side PR persistence)",
      ],
      [
        "scheduled-campaign-calendar",
        "label name for dedup",
      ],
      [
        '--milestone "Post-MVP / Later"',
        "MILESTONE target for issues",
      ],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });
});

describe("buildSpawnEnv allowlist (security surface)", () => {
  const buildEnvMatch = SUT_SOURCE.match(
    /function buildSpawnEnv\([\s\S]+?\n\}\n/,
  );
  const buildEnvBody = buildEnvMatch ? buildEnvMatch[0] : "";

  it("buildSpawnEnv function is present in source", () => {
    expect(buildEnvBody.length).toBeGreaterThan(0);
  });

  describe("positive class — base vars MUST be allowlisted", () => {
    it.each([
      "PATH",
      "HOME",
      "NODE_ENV",
      "ANTHROPIC_API_KEY",
    ])("allowlist contains %s", (key) => {
      expect(buildEnvBody).toContain(`${key}: process.env.${key}`);
    });
  });

  describe("negative class — sensitive vars MUST NOT be allowlisted", () => {
    it.each([
      ["DOPPLER_TOKEN", "Doppler service token; full secrets-read on prd"],
      ["GITHUB_APP_PRIVATE_KEY", "GitHub App PEM; full repo write across installations"],
      ["SENTRY_AUTH_TOKEN", "Sentry write API token; full project access"],
      ["SUPABASE_SERVICE_ROLE_KEY", "Supabase service role; bypasses RLS"],
      ["INNGEST_SIGNING_KEY", "Inngest substrate auth; arbitrary event forging"],
      ["INNGEST_EVENT_KEY", "Inngest substrate auth; arbitrary event forging"],
      ["STRIPE_SECRET_KEY", "Stripe API; payment surface"],
      ["RESEND_API_KEY", "Resend email; impersonation surface"],
      ["BYOK_ENCRYPTION_KEY", "Symmetric key for user BYOK secrets"],
    ])("allowlist does NOT contain %s (%s)", (key) => {
      expect(buildEnvBody).not.toContain(key);
    });

    it("allowlist does NOT use ...process.env spread (would defeat allowlist)", () => {
      expect(buildEnvBody).not.toMatch(/\.\.\.process\.env/);
    });
  });
});

describe("#4730 — output-aware heartbeat (always-create producer)", () => {
  it("gates the heartbeat on output, not the bare spawn exit code", () => {
    // This cron is an always-create producer, NOT best-effort: STEP 2(c) files a
    // per-overdue `scheduled-campaign-calendar` issue, and STEP 2.5 files (then
    // closes) a heartbeat audit issue with the SAME label when NEW == 0 — so a
    // labeled artifact lands in the run window every run. A clean exit that
    // produced none must turn the monitor RED (output-aware) instead of
    // false-green. Mirrors the producers wired by PR #4714.
    expect(SUT_SOURCE).not.toContain("ok: spawnResult.ok");
    expect(SUT_SOURCE).toContain("resolveOutputAwareOk(");
    expect(SUT_SOURCE).toContain("runStartedAt");
    expect(SUT_SOURCE).toContain("ok: heartbeatOk");
  });

  it("retains the STEP 2.5 unconditional heartbeat-issue path that makes it a producer", () => {
    // Guard the prompt invariant the classification depends on: if STEP 2.5 is
    // ever removed, the cron stops being always-create and the output-aware
    // wiring would start false-RED'ing healthy zero-overdue runs.
    expect(SUT_SOURCE).toContain("STEP 2.5");
    expect(SUT_SOURCE).toContain("scheduled-campaign-calendar");
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
});

// #5786 — producer-side date-dedup serialization anchor (AC6) + the suffix
// invariant. The cohort behavioral test proves exactly-one-digest; this anchors
// `{ scope: "fn", limit: 1 }` (the serializer a fake-store test can't exercise)
// and the ` (heartbeat)` titleSuffix (cheap future-deletion insurance — dropping
// it silently no-ops campaign-calendar's dedup with no RED monitor, fail-OPEN).
describe("#5786 producer-side dedup — concurrency + suffix anchors (AC6)", () => {
  it('registration concurrency contains { scope: "fn", limit: 1 }', () => {
    expect(SUT_SOURCE).toContain('{ scope: "fn", limit: 1 }');
  });

  it('dedup call passes titleSuffix: " (heartbeat)" (campaign-calendar suffix variant)', () => {
    expect(SUT_SOURCE).toContain('titleSuffix: " (heartbeat)"');
  });
});
