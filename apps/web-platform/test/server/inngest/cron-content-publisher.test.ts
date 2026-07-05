// TR9 Phase-2 — cron-content-publisher registration smoke + source-shape anchors.
//
// Test coverage:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Source-shape anchors — verbatim strings from the implementation that
//      must survive silent refactoring.
//   3. Exported constants (SYNTHETIC_CHECK_NAMES, PUBLISHER_ENV_KEYS,
//      MAX_RUN_DURATION_MS).
//   4. buildPublisherEnv allowlist — positive class (12 social API secrets)
//      AND negative class (sensitive denylist + spread operator).

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronContentPublisher,
  MAX_RUN_DURATION_MS,
  PUBLISHER_ENV_KEYS,
  buildPublisherEnv,
} from "@/server/inngest/functions/cron-content-publisher";
// #5111: consolidated into the safe-commit helper (was a per-cron copy).
import { SYNTHETIC_CHECK_NAMES } from "@/server/inngest/functions/_cron-safe-commit";

// =============================================================================
// Registration smoke
// =============================================================================

describe("cronContentPublisher — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronContentPublisher).toBeDefined();
    expect(typeof cronContentPublisher).toBe("object");
  });
});

// =============================================================================
// Source-shape anchors
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-content-publisher.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-content-publisher"', "canonical function id"],
    ['cron: "0 14 * * *"', "daily 14:00 UTC schedule"],
    [
      'event: "cron/content-publisher.manual-trigger"',
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
    ["scheduled-content-publisher", "Sentry monitor slug"],
    ["content-publisher.sh", "spawns the existing bash script"],
    ["scripts/content-publisher.sh", "script path"],
    ["knowledge-base/marketing/distribution-content", "content directory"],
    [
      "ci: promote review-ready drafts + update content distribution status",
      "commit message",
    ],
    ["buildPublisherEnv", "env builder function"],
    ["stale-content-detection", "stale content reporting op"],
    ["STALE_EVENTS_FILE", "stale events file env var"],
    ["mintInstallationToken", "token minting"],
    ["setupEphemeralWorkspace", "workspace setup"],
    ["teardownEphemeralWorkspace", "workspace teardown"],
    ["postSentryHeartbeat", "heartbeat at end"],
    ["reportSilentFallback", "Sentry mirror on error"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("handler-side persistence (#5111)", () => {
  it("routes persistence through safeCommitAndPr with direct merge + synthetic checks", () => {
    expect(SUT_SOURCE).toContain('from "./_cron-safe-commit"');
    expect(SUT_SOURCE).toMatch(/safeCommitAndPr\(\{/);
    expect(SUT_SOURCE).toContain('mergeMode: "direct"');
    expect(SUT_SOURCE).toContain("syntheticChecks");
    // Directory allowlist entry must carry the trailing slash the helper's
    // startsWith matching requires.
    expect(SUT_SOURCE).toContain("allowedPaths: [`${CONTENT_DIR_REL}/`]");
    // The private staging pipeline must not return.
    expect(SUT_SOURCE).not.toContain("spawnGitChecked");
  });
});

// =============================================================================
// Exported constants
// =============================================================================

describe("exported constants", () => {
  it("MAX_RUN_DURATION_MS is 10 minutes", () => {
    expect(MAX_RUN_DURATION_MS).toBe(10 * 60 * 1000);
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

  it("PUBLISHER_ENV_KEYS has exactly 12 social API secret names", () => {
    expect(PUBLISHER_ENV_KEYS.length).toBe(12);
  });

  it("PUBLISHER_ENV_KEYS contains all required social API secrets", () => {
    expect(PUBLISHER_ENV_KEYS).toEqual([
      "DISCORD_BLOG_WEBHOOK_URL",
      "DISCORD_WEBHOOK_URL",
      "X_API_KEY",
      "X_API_SECRET",
      "X_ACCESS_TOKEN",
      "X_ACCESS_TOKEN_SECRET",
      "LINKEDIN_ACCESS_TOKEN",
      "LINKEDIN_PERSON_URN",
      "LINKEDIN_ORG_ID",
      "LINKEDIN_ORG_ACCESS_TOKEN",
      "BSKY_HANDLE",
      "BSKY_APP_PASSWORD",
    ]);
  });
});

// =============================================================================
// buildPublisherEnv allowlist
// =============================================================================

describe("buildPublisherEnv allowlist (security surface)", () => {
  const env = buildPublisherEnv("test-token-123");

  describe("positive class — social API vars MUST be present", () => {
    it.each([
      "DISCORD_BLOG_WEBHOOK_URL",
      "DISCORD_WEBHOOK_URL",
      "X_API_KEY",
      "X_API_SECRET",
      "X_ACCESS_TOKEN",
      "X_ACCESS_TOKEN_SECRET",
      "LINKEDIN_ACCESS_TOKEN",
      "LINKEDIN_PERSON_URN",
      "LINKEDIN_ORG_ID",
      "LINKEDIN_ORG_ACCESS_TOKEN",
      "BSKY_HANDLE",
      "BSKY_APP_PASSWORD",
    ])("env contains key %s", (key) => {
      expect(key in env).toBe(true);
    });
  });

  it("env contains GH_TOKEN", () => {
    expect(env.GH_TOKEN).toBe("test-token-123");
  });

  it("env contains PATH and HOME", () => {
    expect("PATH" in env).toBe(true);
    expect("HOME" in env).toBe(true);
  });

  it("env contains allow-post flags", () => {
    expect(env.X_ALLOW_POST).toBe("true");
    expect(env.LINKEDIN_ALLOW_POST).toBe("true");
    expect(env.BSKY_ALLOW_POST).toBe("true");
  });

  // Extract the buildPublisherEnv function body for spread check
  const buildEnvMatch = SUT_SOURCE.match(
    /function buildPublisherEnv\([\s\S]+?\n\}\n/,
  );
  const buildEnvBody = buildEnvMatch ? buildEnvMatch[0] : "";

  describe("negative class — sensitive vars MUST NOT be in allowlist", () => {
    it.each([
      ["DOPPLER_TOKEN", "Doppler service token"],
      ["GITHUB_APP_PRIVATE_KEY", "GitHub App PEM"],
      ["SENTRY_AUTH_TOKEN", "Sentry write API token"],
      ["SUPABASE_SERVICE_ROLE_KEY", "Supabase service role"],
      ["INNGEST_SIGNING_KEY", "Inngest substrate auth"],
      ["INNGEST_EVENT_KEY", "Inngest event auth"],
      ["STRIPE_SECRET_KEY", "Stripe API"],
      ["RESEND_API_KEY", "Resend email"],
      ["BYOK_ENCRYPTION_KEY", "User BYOK secrets"],
      ["ANTHROPIC_API_KEY", "Anthropic API key"],
    ])("allowlist does NOT contain %s (%s)", (key) => {
      expect(buildEnvBody).not.toContain(key);
    });

    it("allowlist does NOT use ...process.env spread", () => {
      expect(buildEnvBody).not.toMatch(/\.\.\.process\.env/);
    });
  });
});
