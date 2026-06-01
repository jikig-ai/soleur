// TR9 PR-11 — cron-community-monitor handler unit tests.
//
// Minimal test coverage focused on the invariants the substrate-extraction
// cohort (PR-5/PR-7/PR-8/PR-9/PR-10) flagged as load-bearing PLUS this
// PR's bucket-ii-specific surface (buildSpawnEnv allowlist widening):
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (## Instructions, community-router.sh path,
//      Hacker News / Discord / Bluesky verbs, digest output path) — original
//      anchors from the GHA prompt that must survive silent paraphrasing.
//   3. Safety-guard anchors (DEDUP RULE for daily cadence, MILESTONE RULE,
//      Persist-via-PR pattern, "Do NOT push directly to main").
//   4. Timing constants exported (MAX_TURN_DURATION_MS, KILL_ESCALATION_MS).
//   5. buildSpawnEnv allowlist — bucket-ii positive class (7 community vars
//      added) AND negative class (9-item sensitive denylist + spread operator).
//      This is the primary security regression detector: additions to the
//      allowlist are caught by code review; widening to a passthrough/denylist
//      shape (e.g., `...process.env`) is caught here.

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE all ES-module imports below — sets NEXT_PHASE so
// the inngest client's startup-key check short-circuits (same path Next.js
// `next build` uses). Mirrors cron-roadmap-review.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronCommunityMonitor,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-community-monitor";

describe("cronCommunityMonitor — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronCommunityMonitor).toBeDefined();
    expect(typeof cronCommunityMonitor).toBe("object");
  });
});

describe("cronCommunityMonitor — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 50 minutes (cohort budget)", () => {
    expect(MAX_TURN_DURATION_MS).toBe(50 * 60 * 1000);
  });

  it("KILL_ESCALATION_MS is 5 seconds (SIGTERM → SIGKILL grace)", () => {
    expect(KILL_ESCALATION_MS).toBe(5_000);
  });
});

// Source-file-content tests — read the SUT file and assert the prompt
// constant and buildSpawnEnv allowlist contain the verbatim anchors. Per
// AGENTS.md `cq-test-fixtures-synthesized-only`, we read the production
// source via readFileSync rather than synthesising a parallel prompt
// fixture (the prompt + allowlist ARE the artifacts under test).

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-community-monitor.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-community-monitor"', "canonical function id"],
    ['cron: "0 8 * * *"', "daily 08:00 UTC schedule"],
    [
      'event: "cron/community-monitor.manual-trigger"',
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

describe("COMMUNITY_MONITOR_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["You are a community monitoring agent", "opening line"],
      ["## Instructions", "section marker"],
      [
        "plugins/soleur/skills/community/scripts/community-router.sh",
        "router path (NOT abbreviated as router.sh)",
      ],
      [
        'ROUTER="plugins/soleur/skills/community/scripts/community-router.sh"',
        "shell var assignment",
      ],
      [
        "knowledge-base/support/community/",
        "digest output directory",
      ],
      ["YYYY-MM-DD-digest.md", "digest filename pattern"],
      ["[Scheduled] Community Monitor", "issue title prefix"],
      ["scheduled-community-monitor", "label name"],
      ['--milestone "Post-MVP / Later"', "MILESTONE RULE target"],
      ["## Period", "digest section marker"],
      ["## Activity Summary", "digest section marker"],
      ["## Top Contributors", "digest section marker"],
      ["Repository Stats", "GitHub Activity sub-section marker"],
      ["Community Interactions", "GitHub Activity sub-section marker"],
      ["bash $ROUTER discord", "Discord platform invocation"],
      ["bash $ROUTER github activity", "GitHub activity invocation"],
      ["bash $ROUTER hn mentions", "Hacker News invocation"],
      ["bash $ROUTER bsky get-metrics", "Bluesky invocation"],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });

  describe("safety-guard anchors (cohort discipline)", () => {
    it.each([
      ["MILESTONE RULE:", "rule keyword"],
      [
        "Do NOT push directly to main",
        "PR-based commit pattern (no direct main writes)",
      ],
      [
        "git checkout -b",
        "PR branch creation in Persist-via-PR step",
      ],
      [
        "gh pr merge",
        "Persist-via-PR auto-merge",
      ],
      [
        "DEDUP RULE",
        "duplicate-issue prevention (manual+cron same day)",
      ],
      [
        "within the last 24 hours",
        "daily cadence dedup window (not 6 days)",
      ],
      [
        "CLONE DEPTH RULE:",
        "stale git-log misuse on --depth=1 clone",
      ],
      [
        "post your findings as a comment on the most recent existing issue",
        "dedup fallback behaviour",
      ],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });
});

describe("buildSpawnEnv allowlist (PR-11 bucket-ii security surface)", () => {
  // Extract the buildSpawnEnv function body from SUT_SOURCE for targeted
  // grep. The function is a single returned object literal; we slice from
  // the function signature to its closing brace.
  const buildEnvMatch = SUT_SOURCE.match(
    /function buildSpawnEnv\([\s\S]+?\n\}\n/,
  );
  const buildEnvBody = buildEnvMatch ? buildEnvMatch[0] : "";

  it("buildSpawnEnv function is present in source", () => {
    expect(buildEnvBody.length).toBeGreaterThan(0);
  });

  describe("positive class — community vars MUST be allowlisted", () => {
    it.each([
      "DISCORD_WEBHOOK_URL",
      "DISCORD_BOT_TOKEN",
      "DISCORD_GUILD_ID",
      "BSKY_HANDLE",
      "BSKY_APP_PASSWORD",
      "LINKEDIN_ACCESS_TOKEN",
      "LINKEDIN_PERSON_URN",
    ])("allowlist contains %s", (key) => {
      expect(buildEnvBody).toContain(`${key}: process.env.${key}`);
    });
  });

  describe("negative class — sensitive vars MUST NOT be allowlisted", () => {
    // The list is intentionally over-broad: anything sensitive in `prd`
    // Doppler that a future careless edit could add. The spread operator
    // is the catch-all that would defeat the allowlist entirely.
    it.each([
      ["DOPPLER_TOKEN", "Doppler service token; full secrets-read on prd"],
      [
        "GITHUB_APP_PRIVATE_KEY",
        "GitHub App PEM; full repo write across installations",
      ],
      [
        "SENTRY_AUTH_TOKEN",
        "Sentry write API token; full project access",
      ],
      [
        "SENTRY_IAC_AUTH_TOKEN",
        "Sentry IaC-write token; destructive against Sentry resources",
      ],
      [
        "SUPABASE_SERVICE_ROLE_KEY",
        "Supabase service role; bypasses RLS",
      ],
      [
        "INNGEST_SIGNING_KEY",
        "Inngest substrate auth; arbitrary event forging",
      ],
      [
        "INNGEST_EVENT_KEY",
        "Inngest substrate auth; arbitrary event forging",
      ],
      ["STRIPE_SECRET_KEY", "Stripe API; payment surface"],
      ["RESEND_API_KEY", "Resend email; impersonation surface"],
      [
        "BYOK_ENCRYPTION_KEY",
        "Symmetric key for user BYOK secrets; full plaintext recovery",
      ],
      [
        "VAPID_PRIVATE_KEY",
        "Web Push VAPID signing key; push notification impersonation",
      ],
      [
        "STRIPE_WEBHOOK_SECRET",
        "Webhook signature verification bypass; event forgery",
      ],
      [
        "CF_API_TOKEN_PURGE",
        "Cloudflare cache-purge API token; cache-poisoning surface",
      ],
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
    // This cron writes a dated digest and creates a GitHub issue summarizing the
    // findings every run (even the no-platform-enabled path creates a titled
    // issue), so a clean exit that produced no artifact must turn the monitor
    // RED (output-aware) instead of false-green. Mirrors the 3 producers wired
    // by PR #4714. The pre-fix line was the forbidden `ok: spawnResult.ok`.
    expect(SUT_SOURCE).not.toContain("ok: spawnResult.ok");
    expect(SUT_SOURCE).toContain("resolveOutputAwareOk(");
    expect(SUT_SOURCE).toContain("runStartedAt");
    expect(SUT_SOURCE).toContain("ok: heartbeatOk");
  });
});
