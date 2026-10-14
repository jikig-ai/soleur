/**
 * #10032 follow-up — the REAL reportSilentFallback path (no observability mock). The sibling test mocks
 * mirrorWithDebounce, so it cannot see that a real Error first argument makes the pino mirror capture the event
 * untagged and user-less while Sentry drops the tagged second capture (#8629). This pins what Sentry receives.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

const sentry = vi.hoisted(() => ({
  captureException: vi.fn(),
  captureMessage: vi.fn(),
  addBreadcrumb: vi.fn(),
  withScope: vi.fn(),
  setTag: vi.fn(),
  setUser: vi.fn(),
  setContext: vi.fn(),
  init: vi.fn(),
}));
vi.mock("@sentry/nextjs", () => sentry);

import { mirrorBashSandboxFailure } from "@/server/cc-dispatcher";

const CONV = "c0ffee00-0000-4000-8000-000000000001";

describe("mirrorBashSandboxFailure reaches Sentry tagged and user-scoped (#8629)", () => {
  beforeEach(() => vi.clearAllMocks());

  it("emits a tagged captureMessage with a per-tenant user and no captureException", () => {
    // A distinct user per test: the per-user debounce is process-global.
    mirrorBashSandboxFailure(
      "bwrap: Can't mount proc on /newroot/proc: Operation not permitted",
      "9b3f1a52-7d6e-4c11-8a40-2f6d0c5e7a91",
      CONV,
    );
    const programmatic = sentry.captureException.mock.calls.filter(([e]) => e instanceof Error);
    expect(programmatic.some(([, o]) => o?.tags?.feature === "pino-mirror")).toBe(false);
    expect(sentry.captureMessage).toHaveBeenCalledTimes(1);
    const [msg, opts] = sentry.captureMessage.mock.calls[0];
    expect(msg).toBe("bash sandbox denial: proc_mount_eperm");
    expect(opts.tags.feature).toBe("agent-sandbox");
    expect(opts.tags.op).toBe("bash-tool-result");
    expect(opts.user?.id).toBeTruthy();
    expect(opts.extra.sandboxStderr).toContain("Can't mount proc");
    expect(JSON.stringify(opts)).not.toContain("9b3f1a52-7d6e-4c11-8a40-2f6d0c5e7a91");
  });
});
