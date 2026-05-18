// TR9 PR-1 (#3948) — cron-daily-triage handler unit tests.
//
// Mocks: node:child_process.spawn (eager-factory race-safe via
// mockImplementation per cq-write-failing-tests-before guidance),
// node:process.kill, fetch, observability. Drives cronDailyTriageHandler
// directly with a fake `step` whose run() executes callbacks eagerly —
// same shape as cfo-on-payment-failed.test.ts.

import { EventEmitter } from "node:events";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks (hoisted by vitest) ---------------------------------------

interface FakeChild extends EventEmitter {
  pid?: number;
  killed: boolean;
}

const spawnSpy = vi.fn();
vi.mock("node:child_process", () => ({
  spawn: spawnSpy,
}));

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

// --- Helpers ----------------------------------------------------------------

interface MockStep {
  calls: { name: string; result: unknown }[];
  run<T>(name: string, cb: () => Promise<T>): Promise<T>;
}

function makeStep(): MockStep {
  const calls: { name: string; result: unknown }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      const result = await cb();
      calls.push({ name, result });
      return result;
    },
  };
}

function makeChild(pid = 11111): FakeChild {
  const child = new EventEmitter() as FakeChild;
  child.pid = pid;
  child.killed = false;
  return child;
}

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

const ORIGINAL_ENV = {
  SENTRY_INGEST_DOMAIN: process.env.SENTRY_INGEST_DOMAIN,
  SENTRY_PROJECT_ID: process.env.SENTRY_PROJECT_ID,
  SENTRY_PUBLIC_KEY: process.env.SENTRY_PUBLIC_KEY,
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_DEV: process.env.INNGEST_DEV,
};

function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) delete process.env[key];
  else process.env[key] = ORIGINAL_ENV[key];
}

beforeEach(() => {
  vi.resetModules();
  spawnSpy.mockReset();
  reportSilentFallbackSpy.mockReset();
  logger.info.mockReset();
  logger.warn.mockReset();
  logger.error.mockReset();
  vi.stubGlobal("fetch", vi.fn(async () => new Response("", { status: 200 })));
  process.env.SENTRY_INGEST_DOMAIN = "ingest.sentry.io";
  process.env.SENTRY_PROJECT_ID = "999";
  // 32-hex public key — production shape; matches SENTRY_PUBLIC_KEY_RE.
  process.env.SENTRY_PUBLIC_KEY = "abc123def4567890abc123def4567890";
  process.env.INNGEST_SIGNING_KEY =
    "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY =
    "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  process.env.INNGEST_DEV = "1";
});

afterEach(() => {
  vi.unstubAllGlobals();
  restoreEnv("SENTRY_INGEST_DOMAIN");
  restoreEnv("SENTRY_PROJECT_ID");
  restoreEnv("SENTRY_PUBLIC_KEY");
  restoreEnv("INNGEST_SIGNING_KEY");
  restoreEnv("INNGEST_EVENT_KEY");
  restoreEnv("INNGEST_DEV");
});

async function importHandler() {
  const mod = await import("@/server/inngest/functions/cron-daily-triage");
  return mod.cronDailyTriageHandler;
}

describe("cron-daily-triage — T1 happy path", () => {
  it("spawn exits 0 → result.ok, Sentry POST status=ok, no silent-fallback", async () => {
    const child = makeChild();
    spawnSpy.mockImplementation(() => {
      queueMicrotask(() => child.emit("exit", 0, null));
      return child;
    });

    const handler = await importHandler();
    const step = makeStep();
    const result = await handler({ step, logger });

    expect(spawnSpy).toHaveBeenCalledTimes(1);
    expect(result.exitCode).toBe(0);
    expect(result.abortedByTimeout).toBe(false);

    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const url = fetchMock.mock.calls[0][0] as string;
    expect(url).toContain("scheduled-daily-triage");
    expect(url).toContain("status=ok");
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();

    // step.run called for claude-eval AND sentry-heartbeat.
    expect(step.calls.map((c) => c.name)).toEqual([
      "claude-eval",
      "sentry-heartbeat",
    ]);
  });
});

describe("cron-daily-triage — T2 spawn error (ENOENT)", () => {
  it("child.on('error') → reportSilentFallback called + Sentry POST status=error", async () => {
    const child = makeChild();
    spawnSpy.mockImplementation(() => {
      queueMicrotask(() => child.emit("error", new Error("spawn ENOENT")));
      return child;
    });

    const handler = await importHandler();
    const step = makeStep();
    const result = await handler({ step, logger });

    expect(result.exitCode).toBe(-1);
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const ctx = reportSilentFallbackSpy.mock.calls[0][1] as {
      feature: string;
      op?: string;
    };
    expect(ctx.feature).toBe("cron-claude-eval");

    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    const url = fetchMock.mock.calls[0][0] as string;
    expect(url).toContain("status=error");
  });
});

describe("cron-daily-triage — T3 AbortSignal SIGTERM→SIGKILL escalation", () => {
  it("at MAX_TURN_DURATION_MS: SIGTERM to -pid; at +KILL_ESCALATION_MS: SIGKILL", async () => {
    // Import SUT constants so test fails for SUT-tuning reasons only when
    // the SUT's tuning actually changes (vs hard-coded literals which
    // would force test edits on any constant tweak).
    const { MAX_TURN_DURATION_MS, KILL_ESCALATION_MS } = await import(
      "@/server/inngest/functions/cron-daily-triage"
    );
    vi.useFakeTimers();
    try {
      const killSpy = vi.spyOn(process, "kill").mockImplementation(
        // Return true (real process.kill returns true on success). The
        // child stays alive — the test asserts both signals are issued
        // before exit, mirroring the SIGTERM-then-SIGKILL escalation.
        () => true,
      );
      const child = makeChild(54321);
      spawnSpy.mockImplementation(() => child);

      const handler = await importHandler();
      const step = makeStep();
      const promise = handler({ step, logger });

      // Advance past AbortSignal ceiling → SIGTERM should fire.
      await vi.advanceTimersByTimeAsync(MAX_TURN_DURATION_MS + 10);
      const sigtermCalls = killSpy.mock.calls.filter(
        (c) => c[0] === -54321 && c[1] === "SIGTERM",
      );
      // expect.soft: report BOTH signal-missing failures rather than
      // short-circuiting on the first — caller learns which leg of the
      // escalation regressed, not just that one of them did.
      expect.soft(sigtermCalls.length, "SIGTERM was not issued").toBeGreaterThan(0);

      // Advance another KILL_ESCALATION_MS → SIGKILL escalation.
      await vi.advanceTimersByTimeAsync(KILL_ESCALATION_MS + 10);
      const sigkillCalls = killSpy.mock.calls.filter(
        (c) => c[0] === -54321 && c[1] === "SIGKILL",
      );
      expect.soft(sigkillCalls.length, "SIGKILL escalation did not fire").toBeGreaterThan(0);

      // Emit exit so the handler can resolve.
      child.emit("exit", null, "SIGKILL");
      const result = await promise;
      expect(result.abortedByTimeout).toBe(true);

      killSpy.mockRestore();
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("cron-daily-triage — T4 Sentry env vars missing", () => {
  it("no SENTRY_INGEST_DOMAIN → no fetch call; step still resolves", async () => {
    delete process.env.SENTRY_INGEST_DOMAIN;
    const child = makeChild();
    spawnSpy.mockImplementation(() => {
      queueMicrotask(() => child.emit("exit", 0, null));
      return child;
    });

    const handler = await importHandler();
    const step = makeStep();
    const result = await handler({ step, logger });

    expect(result.exitCode).toBe(0);
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("cron-daily-triage — T5 event-trigger registration", () => {
  it("cronDailyTriage registers BOTH cron AND event triggers on the same handler", async () => {
    // The handler signature does not branch on cron-vs-event — Inngest
    // routes both triggers to the same handler. The load-bearing invariant
    // is the REGISTRATION: both triggers MUST be wired so an operator can
    // type `inngest send cron/daily-triage.manual-trigger` to retry after
    // a missed 04:00 fire. Pin the registration shape directly (the prior
    // shape — invoking the handler twice and comparing return shapes —
    // was structurally guaranteed by the handler's lack of source-
    // discriminating input).
    const { cronDailyTriage } = await import(
      "@/server/inngest/functions/cron-daily-triage"
    );
    // Inngest functions expose the configured triggers via `.opts` (private,
    // but stable enough for a structural assertion). Fall back to scanning
    // the public-facing shape if `.opts` is undefined.
    const cf = cronDailyTriage as unknown as {
      opts?: { triggers?: Array<Record<string, unknown>> };
      triggers?: Array<Record<string, unknown>>;
    };
    const triggers = cf.opts?.triggers ?? cf.triggers ?? [];
    expect(triggers).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ cron: "0 4 * * *" }),
        expect.objectContaining({ event: "cron/daily-triage.manual-trigger" }),
      ]),
    );
  });
});
