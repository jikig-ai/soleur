import { beforeEach, describe, expect, it, vi } from "vitest";

// NEXT_PHASE hoisted so the inngest client's load-time key check short-circuits
// when the module under test is imported.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

// Stub only postSentryHeartbeat (it does its own fs/fetch); keep the real
// module otherwise.
vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return {
    ...actual,
    postSentryHeartbeat: vi.fn(async () => {}),
  };
});

import { cronInngestCronWatchdogHandler } from "@/server/inngest/functions/cron-inngest-cron-watchdog";
import { postSentryHeartbeat } from "@/server/inngest/functions/_cron-shared";

// Fake Inngest step: runs each step body inline (no replay machinery).
const fakeStep = { run: <T>(_name: string, fn: () => Promise<T>) => fn() };
const fakeLogger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

// #4682: the watchdog was retired to a liveness-only beacon. Inngest's
// /v1/functions introspection is loopback-gated and unreachable from the app
// container (health=200 but /v1/functions=404), and the self-heal is redundant
// with --poll-interval 60 (#4652) + the per-function Sentry monitors. The
// handler now just posts an ok=true heartbeat proving the cron scheduler fired
// it — no registry read, no manual-trigger, no restart, no 4-hourly false-page.
describe("cronInngestCronWatchdogHandler — liveness-only beacon (#4682)", () => {
  beforeEach(() => {
    vi.mocked(postSentryHeartbeat).mockClear();
  });

  it("posts an ok=true liveness heartbeat and returns the liveness shape", async () => {
    const out = await cronInngestCronWatchdogHandler({
      step: fakeStep,
      logger: fakeLogger,
    } as never);

    expect(out).toEqual({
      ok: true,
      results: [],
      healed: { manualTriggers: [], restartRequested: false },
    });
    const hb = vi.mocked(postSentryHeartbeat).mock.calls.at(-1);
    expect(hb).toBeDefined();
    expect(hb![0]).toMatchObject({
      ok: true,
      sentryMonitorSlug: "scheduled-inngest-cron-watchdog",
      cronName: "cron-inngest-cron-watchdog",
    });
  });

  it("does NOT read the inngest registry — the retired self-heal makes no fetch", async () => {
    // Regression guard for the retirement: the handler must not attempt the
    // (loopback-gated, 404ing) /v1/functions read or any restart webhook.
    const fetchSpy = vi.fn(async () => {
      throw new Error("fetch should not be called by the liveness-only watchdog");
    });
    vi.stubGlobal("fetch", fetchSpy);
    try {
      const out = await cronInngestCronWatchdogHandler({
        step: fakeStep,
        logger: fakeLogger,
      } as never);
      expect(out.ok).toBe(true);
      expect(out.healed.restartRequested).toBe(false);
      expect(fetchSpy).not.toHaveBeenCalled();
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
