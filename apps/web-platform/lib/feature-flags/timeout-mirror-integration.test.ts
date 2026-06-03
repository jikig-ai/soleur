/**
 * Integration test for the #4571 fix: proves the call site → real
 * mirrorWarnWithDebounce → real warnSilentFallback → Sentry emission seam
 * end-to-end. server.test.ts mocks @/server/observability (so it only asserts
 * call-site wiring) and observability-mirror-debounce.test.ts exercises the
 * helper directly — neither proves that a getIdentityFlags timeout on the
 * /login render path actually lands in Sentry at WARNING level. This file
 * closes that seam: real observability, only Sentry + logger + the Flagsmith
 * SDK are mocked.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mockGetIdentityFlags = vi.fn();

vi.mock("flagsmith-nodejs", () => ({
  Flagsmith: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    this.getIdentityFlags = mockGetIdentityFlags;
  }),
}));

const { mockCaptureException } = vi.hoisted(() => ({
  mockCaptureException: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: vi.fn(),
  addBreadcrumb: vi.fn(),
}));

// Silence the pino mirror inside warnSilentFallback.
vi.mock("@/server/logger", () => ({
  default: { error: vi.fn(), warn: vi.fn(), info: vi.fn(), debug: vi.fn() },
}));

import { __resetMirrorDebounceForTests } from "@/server/observability";
import { getFeatureFlags, ANON_IDENTITY, __resetFeatureFlagsForTests } from "./server";

const ORIGINAL_ENV = process.env;

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
  mockGetIdentityFlags.mockReset();
  mockCaptureException.mockReset();
  __resetFeatureFlagsForTests();
  __resetMirrorDebounceForTests();
});

afterEach(() => {
  process.env = ORIGINAL_ENV;
});

describe("getIdentityFlags timeout → end-to-end warn-level Sentry mirror (#4571)", () => {
  it("emits captureException at level 'warning' (not error) when the /login render times out", async () => {
    mockGetIdentityFlags.mockRejectedValueOnce(
      new Error("getIdentityFlags failed and no default flag handler was provided"),
    );

    await expect(getFeatureFlags(ANON_IDENTITY)).resolves.toBeDefined();

    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    expect(mockCaptureException).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        level: "warning",
        tags: expect.objectContaining({
          feature: "feature-flags",
          op: "flagsmith.getIdentityFlags",
        }),
      }),
    );
    // The pre-fix bug emitted at error level (default, no `level` key).
    const opts = mockCaptureException.mock.calls[0]![1] as { level?: string };
    expect(opts.level).not.toBe("error");
  });

  it("debounces a burst of timeouts for the same segment to a single Sentry event", async () => {
    mockGetIdentityFlags.mockRejectedValue(
      new Error("getIdentityFlags failed and no default flag handler was provided"),
    );

    await getFeatureFlags(ANON_IDENTITY);
    __resetFeatureFlagsForTests(); // drop snapshot cache so the second call re-enters fetch
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    await getFeatureFlags(ANON_IDENTITY);

    // Real _mirrorDebounce coalesces the same (role:orgId, errorClass) window.
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
  });
});
