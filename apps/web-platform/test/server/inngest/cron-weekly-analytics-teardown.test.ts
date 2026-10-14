// #8726 review — cron-weekly-analytics assigned its handler-scope `ephemeralRoot`
// INSIDE the `run-analytics` step callback. Inngest ends the request after the
// step and re-enters the handler with the memoized result, so on the
// invocation that reaches `finally` the variable was null and the ~100 MB
// clone was never removed (left for cron-workspace-gc). Driven through
// runLikeInngest, which re-enters the handler after every step as production
// does; an inline step mock keeps the closure assignment alive and hides this.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { EventEmitter } from "node:events";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const rmSpy = vi.fn(async (_p: string, _o?: unknown) => {});
vi.mock("node:fs/promises", async (importOriginal) => ({
  ...(await importOriginal<typeof import("node:fs/promises")>()),
  mkdtemp: vi.fn(async () => "/tmp/wa-root/soleur-cron-weekly-analytics-abc"),
  rm: (p: string, o?: unknown) => rmSpy(p, o),
}));

vi.mock("node:child_process", () => ({
  spawn: vi.fn(() => {
    const child = new EventEmitter();
    queueMicrotask(() => child.emit("exit", 0, null));
    return child;
  }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));

vi.mock("@/server/inngest/functions/_cron-safe-commit", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/inngest/functions/_cron-safe-commit")>()),
  safeCommitAndPr: vi.fn(async () => ({ status: "no-changes" })),
}));

vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>()),
  mintInstallationToken: vi.fn(async () => "ghs_faketoken"),
  resolveCronWorkspaceRoot: () => "/tmp/wa-root",
  warnIfCronWorkspaceLowOnDisk: vi.fn(async () => {}),
  postSentryHeartbeat: vi.fn(async () => {}),
  postDiscordWebhook: vi.fn(async () => {}),
}));

import { cronWeeklyAnalyticsHandler } from "@/server/inngest/functions/cron-weekly-analytics";
import { runLikeInngest } from "../../helpers/inngest-step-harness";

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
type HandlerArg = Parameters<typeof cronWeeklyAnalyticsHandler>[0];

beforeEach(() => {
  vi.stubEnv("PLAUSIBLE_API_KEY", "");
  vi.stubEnv("PLAUSIBLE_SITE_ID", "");
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.clearAllMocks();
});

describe("cron-weekly-analytics — ephemeral workspace teardown across step re-entry", () => {
  it("removes the clone created inside run-analytics on the invocation that reaches finally", async () => {
    const out = await runLikeInngest(
      ({ step, attempt, maxAttempts }) =>
        cronWeeklyAnalyticsHandler({
          step: step as unknown as HandlerArg["step"],
          logger: logger as unknown as HandlerArg["logger"],
          attempt,
          maxAttempts,
        } as HandlerArg),
      { maxAttempts: 2 },
    );
    expect(out.outcome).toBe("returned");
    expect(rmSpy).toHaveBeenCalledWith(
      "/tmp/wa-root/soleur-cron-weekly-analytics-abc",
      expect.objectContaining({ recursive: true }),
    );
  });
});
