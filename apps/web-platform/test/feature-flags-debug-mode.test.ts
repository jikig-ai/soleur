/**
 * feat-debug-mode-stream — `isDebugModeAvailable` is flag-only: the original
 * P0-8 `dev`-cohort hard-gate was retired when the debug stream opened to all
 * roles during beta (users send harness logs to support). The Flagsmith flag
 * is the sole cohort gate and kill switch.
 *
 * No FLAGSMITH_ENVIRONMENT_KEY is set, so `client()` is null and the resolver
 * falls through to `runtimeEnvFallback()` — i.e. these tests exercise the
 * Flagsmith-outage path directly, where `FLAG_DEBUG_MODE=1` now opens the
 * stream to every role (accepted beta posture; emission still requires the
 * owner-set per-workspace toggle).
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
  captureMessage: vi.fn(),
  captureException: vi.fn(),
}));

import {
  isDebugModeAvailable,
  isEngineRolloutEnabled,
  __resetFeatureFlagsForTests,
  type Identity,
} from "@/lib/feature-flags/server";

const ORIGINAL_ENV = process.env;

const devIdentity: Identity = { userId: "u-dev", role: "dev", orgId: null, email: null, subscriptionStatus: null };
const prdIdentity: Identity = { userId: "u-prd", role: "prd", orgId: null, email: null, subscriptionStatus: null };

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  delete process.env.FLAGSMITH_ENVIRONMENT_KEY; // force env-fallback (outage path)
  __resetFeatureFlagsForTests();
});

afterEach(() => {
  process.env = ORIGINAL_ENV;
});

describe("isDebugModeAvailable (beta — flag-only, all roles)", () => {
  it("prd identity + FLAG_DEBUG_MODE=1 → true (beta: no role gate)", async () => {
    process.env.FLAG_DEBUG_MODE = "1";
    await expect(isDebugModeAvailable(prdIdentity)).resolves.toBe(true);
  });

  it("dev identity + FLAG_DEBUG_MODE=1 → true", async () => {
    process.env.FLAG_DEBUG_MODE = "1";
    await expect(isDebugModeAvailable(devIdentity)).resolves.toBe(true);
  });

  it("dev identity + flag OFF → false", async () => {
    delete process.env.FLAG_DEBUG_MODE;
    await expect(isDebugModeAvailable(devIdentity)).resolves.toBe(false);
  });

  it("prd identity + flag OFF → false (flag is the only gate)", async () => {
    delete process.env.FLAG_DEBUG_MODE;
    await expect(isDebugModeAvailable(prdIdentity)).resolves.toBe(false);
  });
});

describe("isEngineRolloutEnabled (engine registry rollout mapping)", () => {
  it("keeps the always-on Claude engine available without an organization flag", async () => {
    await expect(isEngineRolloutEnabled("claude-code", null, prdIdentity)).resolves.toBe(true);
  });

  it("fails closed for an engine without an explicit rollout registration", async () => {
    await expect(isEngineRolloutEnabled("grok-build", "org-1", { ...prdIdentity, orgId: "org-1" })).resolves.toBe(false);
  });

  it("requires the identity organization to match the rollout target", async () => {
    process.env.FLAG_CODEX_ENGINE = "1";
    await expect(isEngineRolloutEnabled("codex", "org-1", prdIdentity)).resolves.toBe(false);
  });
});
