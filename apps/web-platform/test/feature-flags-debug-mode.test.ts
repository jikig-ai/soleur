/**
 * feat-debug-mode-stream AC2 — `isDebugModeAvailable` hard-gates the `dev`
 * cohort BEFORE consulting the Flagsmith flag, so the role-blind env-fallback
 * (`FLAG_DEBUG_MODE=1`) cannot open the harness stream to `prd` on a Flagsmith
 * outage (P0-8 — do NOT clone `isTeamWorkspaceInviteEnabled`, which is
 * fail-open).
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`. No
 * FLAGSMITH_ENVIRONMENT_KEY is set, so `client()` is null and the resolver
 * falls through to `runtimeEnvFallback()` — i.e. these tests exercise the
 * Flagsmith-outage path directly.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
  captureMessage: vi.fn(),
  captureException: vi.fn(),
}));

import {
  isDebugModeAvailable,
  __resetFeatureFlagsForTests,
  type Identity,
} from "@/lib/feature-flags/server";

const ORIGINAL_ENV = process.env;

const devIdentity: Identity = { userId: "u-dev", role: "dev", orgId: null };
const prdIdentity: Identity = { userId: "u-prd", role: "prd", orgId: null };

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  delete process.env.FLAGSMITH_ENVIRONMENT_KEY; // force env-fallback (outage path)
  __resetFeatureFlagsForTests();
});

afterEach(() => {
  process.env = ORIGINAL_ENV;
});

describe("isDebugModeAvailable (AC2 — fail-closed dev-cohort gate)", () => {
  it("non-dev identity → false even with FLAG_DEBUG_MODE=1 (P0-8 fail-closed)", async () => {
    process.env.FLAG_DEBUG_MODE = "1";
    await expect(isDebugModeAvailable(prdIdentity)).resolves.toBe(false);
  });

  it("dev identity + FLAG_DEBUG_MODE=1 → true", async () => {
    process.env.FLAG_DEBUG_MODE = "1";
    await expect(isDebugModeAvailable(devIdentity)).resolves.toBe(true);
  });

  it("dev identity + flag OFF → false", async () => {
    delete process.env.FLAG_DEBUG_MODE;
    await expect(isDebugModeAvailable(devIdentity)).resolves.toBe(false);
  });

  it("prd identity + flag OFF → false (role gate)", async () => {
    delete process.env.FLAG_DEBUG_MODE;
    await expect(isDebugModeAvailable(prdIdentity)).resolves.toBe(false);
  });
});
