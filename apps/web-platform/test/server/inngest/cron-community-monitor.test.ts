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
//   3. Safety-guard anchors (MILESTONE RULE, platform-persistence
//      directive, "Do NOT push directly to main"). NOTE: the prompt-level
//      DEDUP RULE was removed in #6143 (same-day dedup is now code-side via
//      digestIssueExistsForDate before the eval spawns) — a regression guard
//      below asserts those three strings stay absent.
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

describe("cron-community-monitor — turn budget (max-turns exhaustion fix)", () => {
  it("spawns claude with --max-turns 80 (daily-triage parity; was 50)", () => {
    // Root cause of Sentry WEB-PLATFORM-1Z (2026-06-03 08:06 UTC): the spawn
    // exhausted its 50-turn budget ("Error: Reached max turns (50)", exitCode 1,
    // ~6 min elapsed — NOT a wall-clock timeout) before reaching the final
    // issue-create step, so this always-create producer filed no
    // scheduled-community-monitor issue and the output-aware heartbeat
    // (resolveOutputAwareOk, #4714) correctly went RED. 80 matches the
    // proven-healthy cron-daily-triage budget through the same
    // DEFAULT_CLAUDE_SETTINGS. See plan
    // 2026-06-03-fix-cron-community-monitor-max-turns-exhaustion-plan.md.
    expect(SUT_SOURCE).toMatch(/"--max-turns",\s*"80"/);
    expect(SUT_SOURCE).not.toMatch(/"--max-turns",\s*"50"/);
  });
});

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-community-monitor"', "canonical function id"],
    ['cron: "0 8 * * *"', "daily 08:00 UTC schedule"],
    [
      'event: "cron/community-monitor.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    // #6143 — the full { scope: "fn", limit: 1 } is now the SOLE same-day TOCTOU
    // guard (the prompt-level DEDUP RULE was removed). Mirror
    // cron-roadmap-review.test.ts's concurrency anchor.
    ['{ scope: "fn", limit: 1 }', "sole same-day dedup serializer (#6143)"],
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
        // #5199 restore: the prompt now writes the LITERAL router path in every
        // invocation (no `ROUTER=` shell-var assignment) so each `bash <router>`
        // matches the containment hook's literal-path allowlist prefix.
        "do NOT assign it to a shell",
        "literal-path containment instruction (no shell-var)",
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
      ["bash plugins/soleur/skills/community/scripts/community-router.sh discord", "Discord platform invocation (literal path)"],
      ["bash plugins/soleur/skills/community/scripts/community-router.sh github activity", "GitHub activity invocation (literal path)"],
      ["bash plugins/soleur/skills/community/scripts/community-router.sh hn mentions", "Hacker News invocation (literal path)"],
      ["bash plugins/soleur/skills/community/scripts/community-router.sh bsky get-metrics", "Bluesky invocation (literal path)"],
      ["bash plugins/soleur/skills/community/scripts/community-router.sh linkedin fetch-metrics", "LinkedIn fetch-metrics invocation (literal path)"],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });

  describe("safety-guard anchors (cohort discipline)", () => {
    it.each([
      ["MILESTONE RULE:", "rule keyword"],
      [
        "Do NOT push directly to main",
        "no direct main writes (handler-side PR persistence)",
      ],
      [
        "PERSISTENCE: Do NOT run git add",
        "platform-persistence directive (#5111)",
      ],
      [
        "opens a PR for your changes",
        "handler-side persistence note (#5111)",
      ],
      [
        "CLONE DEPTH RULE:",
        "stale git-log misuse on --depth=1 clone",
      ],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });

  // #6143 — the prompt-level DEDUP RULE (24h window, comment-and-exit) was
  // removed; same-day manual+cron duplicates are now handled code-side by
  // digestIssueExistsForDate BEFORE the eval spawns (serialized by the
  // registration's { scope: "fn", limit: 1 } concurrency). These strings must
  // stay ABSENT from cron-community-monitor.ts — scoped to THIS file only,
  // since _cron-shared.ts legitimately still contains dedup-related language.
  // Mirrors cron-roadmap-review.test.ts's post-#6139 regression guard.
  describe("#6143 — prompt-level DEDUP RULE removed (regression guard)", () => {
    it.each([
      ["DEDUP RULE", "removed prompt-level dedup keyword"],
      ["within the last 24 hours", "removed 24h rolling window"],
      [
        "post your findings as a comment on the most recent existing issue",
        "removed comment-and-exit fallback",
      ],
    ])("SUT_SOURCE does NOT contain %s (%s)", (removed) => {
      expect(SUT_SOURCE).not.toContain(removed);
    });

    it("still creates the dated digest issue unconditionally (prefix anchor present)", () => {
      // The unconditional-create contract survives: step 5 files the issue on
      // every run; the code-level dedup skip happens before the eval spawns.
      expect(SUT_SOURCE).toContain("[Scheduled] Community Monitor");
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
      "LINKEDIN_ORG_ACCESS_TOKEN",
      "LINKEDIN_ORG_ID",
      "X_API_KEY",
      "X_API_SECRET",
      "X_ACCESS_TOKEN",
      "X_ACCESS_TOKEN_SECRET",
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

    // #6695 — the effective spawn env is now composed at the CALL SITE, which
    // wraps buildSpawnEnv to add the collector-status dir. That composition sits
    // outside `buildEnvBody`, so every assertion above is blind to it: a future
    // `...buildSpawnEnv(token), ...process.env` inside the wrapper would pass
    // the whole negative class with a green suite. Assert against the WHOLE
    // file — this module has no legitimate use of that spread anywhere.
    it("no ...process.env spread anywhere in the module (incl. the call-site wrapper)", () => {
      expect(SUT_SOURCE).not.toMatch(/\.\.\.process\.env/);
    });

    it("the call-site wrapper adds only the non-secret collector-status dir", () => {
      const wrapper = SUT_SOURCE.match(
        /buildSpawnEnv:\s*\(token: string\) => \(\{[\s\S]*?\}\),/,
      )?.[0];
      expect(wrapper).toBeDefined();
      // Exactly one added key, and it is a path — not a credential.
      expect(wrapper).toContain("...buildSpawnEnv(token)");
      expect(wrapper).toContain("SOLEUR_COLLECTOR_STATUS_DIR");
      expect(wrapper).not.toMatch(/process\.env\./);
    });

    // Read-only invariant: the community monitor forwards X read credentials
    // (X_API_KEY etc., positive class above) but MUST NOT forward X_ALLOW_POST
    // — the posting defense-in-depth guard (x-community.sh:611). Only the
    // publisher (cron-content-publisher.ts) arms posting. A future careless
    // edit that adds X_ALLOW_POST here would silently enable posting from a
    // read-only digest path.
    it("allowlist does NOT contain X_ALLOW_POST (monitor is read-only)", () => {
      expect(buildEnvBody).not.toContain("X_ALLOW_POST");
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
