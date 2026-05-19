// TR9 PR-2 (#4063) — cron-follow-through-monitor handler unit tests.
//
// Mocks: node:child_process.spawn (eager-factory race-safe via
// mockImplementation per cq-write-failing-tests-before guidance),
// node:process.kill, fetch, observability. Drives the handler directly
// with a fake `step` whose run() executes callbacks eagerly — same shape
// as cron-daily-triage.test.ts (PR-1 #3985, the structural template).
//
// PR-2 deltas vs PR-1 (plan §Workflow-specific deltas + §Pattern Boundaries):
//   - Slug: scheduled-follow-through (NEW resource, see Phase 4)
//   - Cron: 0 9 * * 1-5 (weekday-only)
//   - Event: cron/follow-through-monitor.manual-trigger
//   - MAX_TURN_DURATION_MS = 15 min (vs PR-1's 60 min)
//   - 3 step.run steps (ensure-labels added vs PR-1's 2)

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

function makeChild(pid = 22222): FakeChild {
  const child = new EventEmitter() as FakeChild;
  child.pid = pid;
  child.killed = false;
  return child;
}

// Wrap a "default-claude" spawn implementation with a routing layer that
// auto-exits ensure-labels' `gh` calls. The PR-2 SUT has THREE gh-label-create
// spawns in step.run("ensure-labels") that precede the claude spawn; under
// vi.useFakeTimers() (T3), those gh spawns hang forever unless the mock
// emits exit. The router lets T1/T2/T3/T4 each provide their own claude
// behavior while ensure-labels stays out of the way.
function withEnsureLabelsAutoExit(
  claudeImpl: (cmd: string, args: string[]) => FakeChild,
): (cmd: string, args: string[]) => FakeChild {
  return (cmd: string, args: string[]) => {
    if (cmd === "gh") {
      const c = makeChild(99999);
      queueMicrotask(() => c.emit("exit", 0, null));
      return c;
    }
    return claudeImpl(cmd, args);
  };
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
  const mod = await import(
    "@/server/inngest/functions/cron-follow-through-monitor"
  );
  return mod.cronFollowThroughMonitorHandler;
}

describe("cron-follow-through-monitor — T1 happy path", () => {
  it("spawn exits 0 → result.ok, Sentry POST status=ok, three step.run steps", async () => {
    const child = makeChild();
    spawnSpy.mockImplementation(
      withEnsureLabelsAutoExit(() => {
        queueMicrotask(() => child.emit("exit", 0, null));
        return child;
      }),
    );

    const handler = await importHandler();
    const step = makeStep();
    const result = await handler({ step, logger });

    // 3 ensure-labels gh calls + 1 claude call = 4 total spawn invocations.
    expect(spawnSpy).toHaveBeenCalledTimes(4);
    const claudeCalls = spawnSpy.mock.calls.filter((c) => c[0] !== "gh");
    expect(claudeCalls).toHaveLength(1);
    expect(result.exitCode).toBe(0);
    expect(result.abortedByTimeout).toBe(false);

    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const url = fetchMock.mock.calls[0][0] as string;
    // Sentry slug: scheduled-follow-through (NEW monitor, PR-2 delta).
    expect(url).toContain("scheduled-follow-through");
    expect(url).toContain("status=ok");
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();

    // PR-2 has THREE step.run steps: ensure-labels precedes claude-eval +
    // sentry-heartbeat. The ensure-labels step is the workflow-specific
    // delta vs PR-1 (carries the GHA `Ensure labels exist` step's intent
    // into the Inngest function so the labels exist before the agent
    // touches them).
    expect(step.calls.map((c) => c.name)).toEqual([
      "ensure-labels",
      "claude-eval",
      "sentry-heartbeat",
    ]);
  });
});

describe("cron-follow-through-monitor — T2 spawn error (ENOENT)", () => {
  it("child.on('error') → reportSilentFallback called + Sentry POST status=error", async () => {
    const child = makeChild();
    spawnSpy.mockImplementation(
      withEnsureLabelsAutoExit(() => {
        queueMicrotask(() => child.emit("error", new Error("spawn ENOENT")));
        return child;
      }),
    );

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

describe("cron-follow-through-monitor — T3 AbortSignal SIGTERM→SIGKILL escalation", () => {
  it("at MAX_TURN_DURATION_MS: SIGTERM to -pid; at +KILL_ESCALATION_MS: SIGKILL", async () => {
    // Import SUT constants so test fails for SUT-tuning reasons only when
    // the SUT's tuning actually changes. For PR-2: MAX_TURN_DURATION_MS = 15min.
    const { MAX_TURN_DURATION_MS, KILL_ESCALATION_MS } = await import(
      "@/server/inngest/functions/cron-follow-through-monitor"
    );
    // AC10 sanity (also covered by direct grep): the constant exported
    // here is the PR-2-specific 15-min value, NOT PR-1's 60-min.
    expect(MAX_TURN_DURATION_MS).toBe(15 * 60 * 1000);
    expect(KILL_ESCALATION_MS).toBe(5_000);

    vi.useFakeTimers();
    try {
      const killSpy = vi.spyOn(process, "kill").mockImplementation(() => true);
      const child = makeChild(54322);
      spawnSpy.mockImplementation(withEnsureLabelsAutoExit(() => child));

      const handler = await importHandler();
      const step = makeStep();
      const promise = handler({ step, logger });

      // Advance past AbortSignal ceiling → SIGTERM should fire.
      await vi.advanceTimersByTimeAsync(MAX_TURN_DURATION_MS + 10);
      const sigtermCalls = killSpy.mock.calls.filter(
        (c) => c[0] === -54322 && c[1] === "SIGTERM",
      );
      expect.soft(sigtermCalls.length, "SIGTERM was not issued").toBeGreaterThan(0);

      // Advance another KILL_ESCALATION_MS → SIGKILL escalation.
      await vi.advanceTimersByTimeAsync(KILL_ESCALATION_MS + 10);
      const sigkillCalls = killSpy.mock.calls.filter(
        (c) => c[0] === -54322 && c[1] === "SIGKILL",
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

describe("cron-follow-through-monitor — T4 Sentry env vars missing", () => {
  it("no SENTRY_INGEST_DOMAIN → no fetch call; step still resolves", async () => {
    delete process.env.SENTRY_INGEST_DOMAIN;
    const child = makeChild();
    spawnSpy.mockImplementation(
      withEnsureLabelsAutoExit(() => {
        queueMicrotask(() => child.emit("exit", 0, null));
        return child;
      }),
    );

    const handler = await importHandler();
    const step = makeStep();
    const result = await handler({ step, logger });

    expect(result.exitCode).toBe(0);
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("cron-follow-through-monitor — T5 dual-trigger registration", () => {
  it("cronFollowThroughMonitor registers BOTH cron AND event triggers on the same handler", async () => {
    // The handler signature does not branch on cron-vs-event — Inngest
    // routes both triggers to the same handler. The load-bearing invariant
    // is the REGISTRATION: both triggers MUST be wired so an operator can
    // type `inngest send cron/follow-through-monitor.manual-trigger` to
    // retry after a missed 09:00 weekday fire.
    const { cronFollowThroughMonitor } = await import(
      "@/server/inngest/functions/cron-follow-through-monitor"
    );
    const cf = cronFollowThroughMonitor as unknown as {
      opts?: { triggers?: Array<Record<string, unknown>> };
      triggers?: Array<Record<string, unknown>>;
    };
    const triggers = cf.opts?.triggers ?? cf.triggers ?? [];
    expect(triggers).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ cron: "0 9 * * 1-5" }),
        expect.objectContaining({
          event: "cron/follow-through-monitor.manual-trigger",
        }),
      ]),
    );
  });
});
