// #8495 — watchdog dispatch clock. GitHub Actions `schedule:` drops ticks (the
// external Inngest watchdog measured one run every 2-7 h against a declared
// */15), so the web server fires `workflow_dispatch` on a reliable wall clock.
// ADR-248 owns the rationale; this file pins the behaviour (plan Test Scenarios
// C1-C15 + Guard 2). Every scenario injects its table, so a two-entry table is
// used only where the second member is the point (C11, C15).

import { readFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from "vitest";

// C12 drives the DEFAULT mint (no `mint` injected) through these two seams, so
// the token-scope contract is asserted at the boundary the clock does not own.
const { generateInstallationTokenMock, createProbeOctokitMock } = vi.hoisted(
  () => ({
    generateInstallationTokenMock: vi.fn(
      async (..._args: unknown[]) => "ghs_DEFAULTMINTTOKEN",
    ),
    createProbeOctokitMock: vi.fn(async (..._args: unknown[]) => ({
      request: vi.fn(async (..._a: unknown[]) => ({ data: { id: 4242 } })),
    })),
  }),
);

vi.mock("@/server/github-app", () => ({
  generateInstallationToken: generateInstallationTokenMock,
}));
vi.mock("@/server/github/probe-octokit", () => ({
  createProbeOctokit: createProbeOctokitMock,
}));

import {
  JITTER_MAX_MS,
  JITTER_MIN_MS,
  POLL_MS,
  TICK_DEADLINE_MS,
  slotAlreadyHasRun,
  slotStartAt,
  startWatchdogDispatchClock,
  type GitHubRequestClient,
  type WatchdogClockDeps,
} from "@/server/watchdog-dispatch-clock";
import type { WatchdogDispatchEntry } from "@/server/watchdog-dispatch-table";
import type { WatchdogDispatchMarker } from "@/server/cron-liveness-marker";

const TOKEN = "ghs_SECRETINSTALLATIONTOKEN0123456789";
const DISPATCH_ROUTE =
  "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches";
const RUNS_ROUTE =
  "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs";

const INNGEST: WatchdogDispatchEntry = {
  workflowFile: "scheduled-inngest-health.yml",
  monitorSlug: "scheduled-inngest-health",
  intervalMinutes: 15,
  eligibility: "test",
};
const ZOT: WatchdogDispatchEntry = {
  workflowFile: "scheduled-zot-restart-loop.yml",
  monitorSlug: "scheduled-zot-restart-loop",
  intervalMinutes: 60,
  eligibility: "test",
};

// 10:00:00Z is aligned for BOTH the 15-min and the 60-min entry.
const S0 = Date.UTC(2026, 8, 24, 10, 0, 0);
const MIN = 60_000;
// random() value that yields an exact jitter in ms.
const r = (jitterMs: number) =>
  (jitterMs - JITTER_MIN_MS) / (JITTER_MAX_MS - JITTER_MIN_MS);

// ---------------------------------------------------------------------------
// Fake GitHub: a runs list per workflow; a POST creates a run that becomes
// visible to reads `visibilityDelayMs` later (GitHub's own list lag).
// ---------------------------------------------------------------------------
interface FakeRun {
  id: number;
  event: string;
  status: string;
  createdAtMs: number;
  visibleAtMs: number;
}
type Req = { route: string; params: Record<string, unknown> };

function fakeGitHub(opts: { visibilityDelayMs?: number } = {}) {
  const delay = opts.visibilityDelayMs ?? 0;
  const runs = new Map<string, FakeRun[]>();
  const calls: Req[] = [];
  let nextId = 9000;
  const hooks: {
    read?: (p: Record<string, unknown>) => Promise<unknown>;
    dispatch?: (p: Record<string, unknown>) => Promise<unknown>;
  } = {};
  const client = {
    request: vi.fn(async (route: string, params: Record<string, unknown>) => {
      calls.push({ route, params });
      const wf = String(params.workflow_id);
      if (route === RUNS_ROUTE) {
        if (hooks.read) return hooks.read(params);
        const now = Date.now();
        const visible = (runs.get(wf) ?? [])
          .filter((x) => x.visibleAtMs <= now)
          .sort((a, b) => b.createdAtMs - a.createdAtMs)
          .slice(0, Number(params.per_page ?? 30));
        return {
          data: {
            total_count: visible.length,
            workflow_runs: visible.map((x) => ({
              id: x.id,
              event: x.event,
              status: x.status,
              created_at: new Date(x.createdAtMs).toISOString(),
            })),
          },
        };
      }
      if (route === DISPATCH_ROUTE) {
        if (hooks.dispatch) return hooks.dispatch(params);
        const now = Date.now();
        const list = runs.get(wf) ?? [];
        list.push({
          id: nextId++,
          event: "workflow_dispatch",
          status: "queued",
          createdAtMs: now,
          visibleAtMs: now + delay,
        });
        runs.set(wf, list);
        return { status: 204, data: undefined };
      }
      throw new Error(`unexpected route ${route}`);
    }),
  };
  return {
    client,
    api: client as unknown as GitHubRequestClient,
    calls,
    hooks,
    seed(wf: string, run: Partial<FakeRun> & { createdAtMs: number }) {
      const list = runs.get(wf) ?? [];
      list.push({
        id: run.id ?? nextId++,
        event: run.event ?? "schedule",
        status: run.status ?? "completed",
        createdAtMs: run.createdAtMs,
        visibleAtMs: run.visibleAtMs ?? run.createdAtMs,
      });
      runs.set(wf, list);
    },
    posts(wf: string) {
      return calls.filter(
        (c) => c.route === DISPATCH_ROUTE && c.params.workflow_id === wf,
      ).length;
    },
    reads(wf: string) {
      return calls.filter(
        (c) => c.route === RUNS_ROUTE && c.params.workflow_id === wf,
      ).length;
    },
  };
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------
const realSetImmediate = setImmediate;
const flushReal = () => new Promise<void>((res) => realSetImmediate(res));

let unhandled: Mock<(...args: unknown[]) => void>;
let report: Mock<(...args: unknown[]) => void>;
let emit: Mock<(...args: unknown[]) => void>;
let stops: Array<() => void>;

function markers(): WatchdogDispatchMarker[] {
  return emit.mock.calls.map((c) => c[0] as WatchdogDispatchMarker);
}
function outcomes(workflow?: string): string[] {
  return markers()
    .filter((m) => workflow === undefined || m.workflow === workflow)
    .map((m) => m.outcome);
}

function start(
  gh: ReturnType<typeof fakeGitHub>,
  over: Partial<WatchdogClockDeps> = {},
) {
  const clock = startWatchdogDispatchClock({
    table: [INNGEST],
    env: { NODE_ENV: "production", SOLEUR_HOST_ID: "hetzner-1" },
    random: () => 0,
    mint: async () => TOKEN,
    octokitFor: () => gh.api,
    report: report as unknown as WatchdogClockDeps["report"],
    emit: emit as unknown as WatchdogClockDeps["emit"],
    ...over,
  });
  stops.push(clock.stop);
  return clock;
}

async function advanceTo(t: number) {
  const delta = t - Date.now();
  if (delta > 0) await vi.advanceTimersByTimeAsync(delta);
  await flushReal();
}

beforeEach(() => {
  vi.useFakeTimers({ now: S0 });
  unhandled = vi.fn((..._a: unknown[]) => undefined);
  process.on("unhandledRejection", unhandled);
  report = vi.fn((..._a: unknown[]) => undefined);
  emit = vi.fn((..._a: unknown[]) => undefined);
  stops = [];
  generateInstallationTokenMock.mockClear();
  createProbeOctokitMock.mockClear();
});

afterEach(async () => {
  for (const s of stops) s();
  await flushReal();
  process.off("unhandledRejection", unhandled);
  // No tick may ever escape its fences (Guard 2) — asserted for EVERY case.
  expect(unhandled).not.toHaveBeenCalled();
  expect(outcomes()).not.toContain("tick_escaped");
  vi.useRealTimers();
});

// ---------------------------------------------------------------------------
describe("C1 arm predicate", () => {
  it("production + blank SOLEUR_HOST_ID → disarmed, one op=arm report, disarmed marker", () => {
    const setIntervalSpy = vi.fn(() => ({ unref: vi.fn() }));
    const gh = fakeGitHub();
    start(gh, {
      env: { NODE_ENV: "production", SOLEUR_HOST_ID: "  " },
      setInterval: setIntervalSpy as unknown as WatchdogClockDeps["setInterval"],
    });
    expect(setIntervalSpy).not.toHaveBeenCalled();
    expect(report).toHaveBeenCalledTimes(1);
    expect(report.mock.calls[0][1]).toMatchObject({
      feature: "watchdog-dispatch-clock",
      op: "arm",
    });
    expect(outcomes()).toEqual(["disarmed"]);
  });

  it("non-production with a host id → disarmed, no report", () => {
    const setIntervalSpy = vi.fn(() => ({ unref: vi.fn() }));
    start(fakeGitHub(), {
      env: { NODE_ENV: "test", SOLEUR_HOST_ID: "hetzner-123" },
      setInterval: setIntervalSpy as unknown as WatchdogClockDeps["setInterval"],
    });
    expect(setIntervalSpy).not.toHaveBeenCalled();
    expect(report).not.toHaveBeenCalled();
    expect(outcomes()).toEqual(["disarmed"]);
  });

  it("production + host id → armed: interval registered at POLL_MS and unref'd", () => {
    const unref = vi.fn();
    const setIntervalSpy = vi.fn(() => ({ unref }));
    start(fakeGitHub(), {
      env: { NODE_ENV: "production", SOLEUR_HOST_ID: "hetzner-123" },
      setInterval: setIntervalSpy as unknown as WatchdogClockDeps["setInterval"],
    });
    expect(setIntervalSpy).toHaveBeenCalledTimes(1);
    expect((setIntervalSpy.mock.calls[0] as unknown[])[1]).toBe(POLL_MS);
    expect(unref).toHaveBeenCalledTimes(1);
    expect(report).not.toHaveBeenCalled();
    expect(markers()).toEqual([
      expect.objectContaining({ outcome: "armed", host_id: "hetzner-123" }),
    ]);
  });
});

describe("C2 slot math", () => {
  const at = (h: number, m: number, s: number, ms = 0) =>
    Date.UTC(2026, 8, 24, h, m, s, ms);
  it.each([
    [at(10, 15, 30), 15, at(10, 15, 0)],
    [at(10, 14, 59, 999), 15, at(10, 0, 0)],
    [at(10, 15, 0), 15, at(10, 15, 0)],
    [at(0, 0, 0), 60, at(0, 0, 0)],
    [at(10, 59, 59, 999), 60, at(10, 0, 0)],
  ])("slotStartAt(%i, %i) = %i", (now, interval, expected) => {
    expect(slotStartAt(now, interval)).toBe(expected);
  });
});

describe("C3 skip: this slot already has a run", () => {
  it("a GH schedule run created in-slot suppresses the dispatch; the marker names it", async () => {
    const gh = fakeGitHub();
    gh.seed(INNGEST.workflowFile, {
      id: 777,
      event: "schedule",
      createdAtMs: S0 + 2_000,
    });
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(gh.reads(INNGEST.workflowFile)).toBe(1);
    expect(gh.posts(INNGEST.workflowFile)).toBe(0);
    expect(markers()).toContainEqual(
      expect.objectContaining({
        outcome: "skipped_slot_has_run",
        workflow: INNGEST.workflowFile,
        run_id: 777,
        run_event: "schedule",
      }),
    );
  });
});

describe("C4 an earlier slot's run never suppresses this slot (age-window regression)", () => {
  it.each(["completed", "queued"])(
    "newest run created at :05 (%s) → exactly 1 POST at :15",
    async (status) => {
      const S = S0 + 15 * MIN;
      vi.setSystemTime(S - 1_000);
      const gh = fakeGitHub();
      gh.seed(INNGEST.workflowFile, {
        createdAtMs: S0 + 5 * MIN,
        status,
      });
      start(gh);
      await advanceTo(S + 60_000);
      expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    },
  );
});

describe("C4b dedup cutoff exactness", () => {
  it("slotAlreadyHasRun: created exactly S−60 s → true; S−60.001 s → false", () => {
    const S = S0;
    expect(slotAlreadyHasRun(new Date(S - 60_000).toISOString(), S)).toBe(true);
    expect(slotAlreadyHasRun(new Date(S - 60_001).toISOString(), S)).toBe(
      false,
    );
    // Unparseable → "not this slot" (fail-open to dispatch).
    expect(slotAlreadyHasRun("not-a-date", S)).toBe(false);
  });

  it.each([
    [-60_000, 0],
    [-60_001, 1],
  ])("run at S%+i ms → %i POST", async (offset, expected) => {
    const gh = fakeGitHub();
    gh.seed(INNGEST.workflowFile, { createdAtMs: S0 + offset });
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(expected);
  });
});

describe("C5 empty runs list", () => {
  it("zero runs → 1 POST with the exact request shape; exactly ONE timer pending after settle", async () => {
    const gh = fakeGitHub();
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    expect(outcomes(INNGEST.workflowFile)).toEqual(["dispatched"]);
    // Guard 2: the per-tick deadline timer is cleared — only the poll interval remains.
    expect(vi.getTimerCount()).toBe(1);
  });
});

describe("C6 dedup read fails → fail-open", () => {
  it("still dispatches, reports op=dedup-read, and the next slot still ticks", async () => {
    const gh = fakeGitHub();
    gh.hooks.read = async () => {
      throw Object.assign(new Error("boom"), { status: 502 });
    };
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    expect(report).toHaveBeenCalledTimes(1);
    expect(report.mock.calls[0][1]).toMatchObject({
      feature: "watchdog-dispatch-clock",
      op: "dedup-read",
      extra: expect.objectContaining({ reason: "http", status: 502 }),
    });
    await advanceTo(S0 + 15 * MIN + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(2);
  });
});

describe("C7 failures are reported redacted, fenced, and never stall the clock", () => {
  function assertNoTokenAnywhere() {
    const blob = JSON.stringify([
      report.mock.calls.map(([err, opts]) => [
        { name: (err as Error)?.name, message: (err as Error)?.message },
        opts,
      ]),
      emit.mock.calls,
    ]);
    expect(blob).not.toContain(TOKEN);
    for (const [err] of report.mock.calls) {
      expect(err).toBeInstanceOf(Error);
      expect(String((err as Error).message)).not.toContain(TOKEN);
      for (const k of ["request", "response", "headers"]) {
        expect(Object.keys(err as object)).not.toContain(k);
        expect((err as Record<string, unknown>)[k]).toBeUndefined();
      }
    }
  }

  async function assertNextSlotTicks(gh: ReturnType<typeof fakeGitHub>) {
    const before = gh.calls.length;
    gh.hooks.read = undefined;
    gh.hooks.dispatch = undefined;
    await advanceTo(S0 + 15 * MIN + 40_000);
    expect(gh.calls.length).toBeGreaterThan(before);
    expect(outcomes(INNGEST.workflowFile)).toContain("dispatched");
  }

  it("mint throws → op=mint reason=throw", async () => {
    const gh = fakeGitHub();
    let calls = 0;
    start(gh, {
      mint: async () => {
        calls++;
        if (calls === 1) throw new Error("installation lookup failed");
        return TOKEN;
      },
    });
    await advanceTo(S0 + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(0);
    expect(report).toHaveBeenCalledTimes(1);
    expect(report.mock.calls[0][1]).toMatchObject({
      op: "mint",
      extra: expect.objectContaining({
        workflow: INNGEST.workflowFile,
        reason: "throw",
      }),
    });
    expect(markers()).toContainEqual(
      expect.objectContaining({ outcome: "failed", op: "mint", reason: "throw" }),
    );
    assertNoTokenAnywhere();
    await assertNextSlotTicks(gh);
  });

  it("dispatch throws an Octokit-shaped 422 carrying the token everywhere → op=dispatch reason=http status=422, redacted", async () => {
    const gh = fakeGitHub();
    gh.hooks.dispatch = async () => {
      throw Object.assign(
        new Error(`HttpError: Workflow does not have 'workflow_dispatch' trigger (token ${TOKEN})`),
        {
          name: "HttpError",
          status: 422,
          request: { headers: { authorization: `token ${TOKEN}` } },
          response: { data: { message: `bad ${TOKEN}` }, headers: {} },
        },
      );
    };
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(report).toHaveBeenCalledTimes(1);
    const [err, opts] = report.mock.calls[0];
    expect(opts).toMatchObject({
      op: "dispatch",
      extra: expect.objectContaining({ reason: "http", status: 422 }),
    });
    expect((err as Error).name).toBe("HttpError");
    expect((err as Error).message).toContain("[REDACTED-INSTALLATION-TOKEN]");
    expect(markers()).toContainEqual(
      expect.objectContaining({
        outcome: "failed",
        op: "dispatch",
        reason: "http",
        status: 422,
      }),
    );
    assertNoTokenAnywhere();
    await assertNextSlotTicks(gh);
  });

  it("dispatch never settles → after TICK_DEADLINE_MS: op=dispatch reason=timeout, no timer leak", async () => {
    const gh = fakeGitHub();
    gh.hooks.dispatch = () => new Promise(() => undefined);
    start(gh);
    await advanceTo(S0 + 30_000 + TICK_DEADLINE_MS - 1);
    expect(report).not.toHaveBeenCalled();
    await advanceTo(S0 + 30_000 + TICK_DEADLINE_MS + 1);
    expect(report).toHaveBeenCalledTimes(1);
    expect(report.mock.calls[0][1]).toMatchObject({
      op: "dispatch",
      extra: expect.objectContaining({ reason: "timeout" }),
    });
    expect(vi.getTimerCount()).toBe(1);
    assertNoTokenAnywhere();
    await assertNextSlotTicks(gh);
  });

  it("a report() that throws never escapes the tick (reporter fence)", async () => {
    const gh = fakeGitHub();
    gh.hooks.dispatch = async () => {
      throw Object.assign(new Error("nope"), { status: 500 });
    };
    report.mockImplementation(() => {
      throw new Error("sentry down");
    });
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(report).toHaveBeenCalled();
    expect(outcomes(INNGEST.workflowFile)).toContain("failed");
    await assertNextSlotTicks(gh);
  });

  it("an emit() that throws never escapes the tick", async () => {
    const gh = fakeGitHub();
    emit.mockImplementation(() => {
      throw new Error("pino down");
    });
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    await advanceTo(S0 + 15 * MIN + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(2);
  });
});

describe("C9 once per slot", () => {
  it("five polls inside one due slot → exactly 1 read and 1 POST", async () => {
    const gh = fakeGitHub();
    start(gh);
    // polls at +30, +60, +90, +120, +150 s — all inside slot S0 and due.
    await advanceTo(S0 + 150_000);
    expect(gh.reads(INNGEST.workflowFile)).toBe(1);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
  });
});

describe("C10 late cutoff", () => {
  it("boot at S+13:30 → no tick for S, then a tick for S+15", async () => {
    vi.setSystemTime(S0 + 13 * MIN + 30_000);
    const gh = fakeGitHub();
    start(gh);
    await advanceTo(S0 + 15 * MIN - 1);
    expect(gh.reads(INNGEST.workflowFile)).toBe(0);
    await advanceTo(S0 + 15 * MIN + 60_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
  });

  it("exact boundary: a poll at S+12:59.999 ticks", async () => {
    vi.setSystemTime(S0 + 12 * MIN + 29_999);
    const gh = fakeGitHub();
    start(gh);
    await advanceTo(S0 + 12 * MIN + 59_999);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
  });

  it("exact boundary: a poll at S+13:00.000 does not tick", async () => {
    vi.setSystemTime(S0 + 12 * MIN + 30_000);
    const gh = fakeGitHub();
    start(gh);
    await advanceTo(S0 + 15 * MIN - 1);
    expect(gh.reads(INNGEST.workflowFile)).toBe(0);
  });
});

describe("C11 two hosts share one GitHub", () => {
  it("jitters 40 s / 100 s → exactly 1 POST (the later host sees the earlier run)", async () => {
    const gh = fakeGitHub({ visibilityDelayMs: 3_000 });
    start(gh, { random: () => r(40_000) });
    start(gh, { random: () => r(100_000) });
    await advanceTo(S0 + 150_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    expect(outcomes(INNGEST.workflowFile)).toEqual(
      expect.arrayContaining(["dispatched", "skipped_slot_has_run"]),
    );
  });

  it("jitters 40 s / 45 s land on the same poll → 2 POSTs (the accepted, harmless duplicate)", async () => {
    const gh = fakeGitHub({ visibilityDelayMs: 3_000 });
    start(gh, { random: () => r(40_000) });
    start(gh, { random: () => r(45_000) });
    await advanceTo(S0 + 150_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(2);
  });
});

describe("C12 token scope and request shape (default mint)", () => {
  it("mints actions:write on soleur only, and POSTs {ref: main} with no inputs", async () => {
    const gh = fakeGitHub();
    start(gh, { mint: undefined, octokitFor: () => gh.api });
    await advanceTo(S0 + 40_000);
    expect(createProbeOctokitMock).toHaveBeenCalledTimes(1);
    expect(generateInstallationTokenMock).toHaveBeenCalledTimes(1);
    expect(generateInstallationTokenMock.mock.calls[0][0]).toBe(4242);
    expect(generateInstallationTokenMock.mock.calls[0][1]).toMatchObject({
      permissions: { actions: "write" },
      repositories: ["soleur"],
    });
    expect(
      Object.keys(
        (generateInstallationTokenMock.mock.calls[0][1] as { permissions: object })
          .permissions,
      ),
    ).toEqual(["actions"]);
    const post = gh.calls.find((c) => c.route === DISPATCH_ROUTE);
    expect(post).toBeDefined();
    const { request: _signal, ...params } = post!.params;
    expect(params).toEqual({
      owner: "jikig-ai",
      repo: "soleur",
      workflow_id: "scheduled-inngest-health.yml",
      ref: "main",
    });
    const read = gh.calls.find((c) => c.route === RUNS_ROUTE);
    expect(read?.params).toMatchObject({
      owner: "jikig-ai",
      repo: "soleur",
      workflow_id: "scheduled-inngest-health.yml",
      per_page: 1,
    });
  });
});

describe("C13 stop", () => {
  it("stop() while a tick is in flight → once it settles: 0 timers and no new tick", async () => {
    const gh = fakeGitHub();
    let release!: () => void;
    gh.hooks.dispatch = () =>
      new Promise((res) => {
        release = () => res({ status: 204 });
      });
    const clock = start(gh);
    await advanceTo(S0 + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    clock.stop();
    release();
    await flushReal();
    await vi.advanceTimersByTimeAsync(0);
    expect(vi.getTimerCount()).toBe(0);
    const before = gh.calls.length;
    await advanceTo(S0 + 2 * 60 * MIN);
    expect(gh.calls.length).toBe(before);
  });
});

describe("C14 jitter bounds", () => {
  it("random=0: no tick at S+29.999 s", async () => {
    vi.setSystemTime(S0 - 1);
    const gh = fakeGitHub();
    start(gh, { random: () => 0 });
    await advanceTo(S0 + 29_999);
    expect(gh.reads(INNGEST.workflowFile)).toBe(0);
  });

  it("random=0: a tick at S+30 s", async () => {
    const gh = fakeGitHub();
    start(gh, { random: () => 0 });
    await advanceTo(S0 + 30_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
  });

  it("random=max: no tick before S+150 s, a tick at S+150 s", async () => {
    const gh = fakeGitHub();
    start(gh, { random: () => 1 });
    await advanceTo(S0 + 149_999);
    expect(gh.reads(INNGEST.workflowFile)).toBe(0);
    await advanceTo(S0 + 150_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
  });
});

describe("C15 one jitter draw per slot per entry (two-entry table)", () => {
  it("draws once per entry per slot, and each entry is ticked", async () => {
    const gh = fakeGitHub();
    const random = vi
      .fn()
      .mockReturnValueOnce(0.999)
      .mockReturnValueOnce(0.999)
      .mockReturnValue(0);
    start(gh, { table: [INNGEST, ZOT], random });
    await advanceTo(S0 + 120_000);
    // A fresh draw on every poll would have ticked both at S+60 s.
    expect(gh.posts(INNGEST.workflowFile)).toBe(0);
    expect(gh.posts(ZOT.workflowFile)).toBe(0);
    expect(random).toHaveBeenCalledTimes(2);
    await advanceTo(S0 + 150_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    expect(gh.posts(ZOT.workflowFile)).toBe(1);
    expect(random).toHaveBeenCalledTimes(2);
  });
});

// ---------------------------------------------------------------------------
// Guard 2 (static half) — the clock must never route through the thing it
// watches. Walks the clock's TRANSITIVE value-import graph (type-only imports
// are erased and skipped) and asserts no module under server/inngest/ is
// reachable. Enforced here rather than in the generated, non-blocking
// .dependency-cruiser.cjs, because this suite runs in the required `test` context.
// ---------------------------------------------------------------------------
const APP_ROOT = resolve(__dirname, "../..");

function resolveSpecifier(spec: string, fromFile: string): string | null {
  let base: string;
  if (spec.startsWith("@/")) base = join(APP_ROOT, spec.slice(2));
  else if (spec.startsWith(".")) base = resolve(dirname(fromFile), spec);
  else return null; // bare package
  for (const cand of [base, `${base}.ts`, `${base}.tsx`, join(base, "index.ts")]) {
    if (existsSync(cand) && /\.(tsx?)$/.test(cand)) return cand;
  }
  return null;
}

function valueImports(file: string): string[] {
  const src = readFileSync(file, "utf-8");
  const specs: string[] = [];
  const re =
    /^\s*(import|export)\s+(?!type\b)(?:[^;]*?\sfrom\s+)?["']([^"']+)["']|import\(\s*["']([^"']+)["']\s*\)/gm;
  for (const m of src.matchAll(re)) specs.push(m[2] ?? m[3]);
  return specs;
}

function reachableFrom(entry: string): Set<string> {
  const seen = new Set<string>();
  const stack = [entry];
  while (stack.length) {
    const f = stack.pop()!;
    if (seen.has(f)) continue;
    seen.add(f);
    for (const spec of valueImports(f)) {
      const target = resolveSpecifier(spec, f);
      if (target) stack.push(target);
    }
  }
  return seen;
}

describe("Guard 2 — the clock never imports the Inngest tree", () => {
  const CLOCK = join(APP_ROOT, "server/watchdog-dispatch-clock.ts");

  it("the walker is live: it finds the clock's known direct dependencies", () => {
    const reach = [...reachableFrom(CLOCK)].map((p) =>
      p.slice(APP_ROOT.length + 1),
    );
    expect(reach).toEqual(
      expect.arrayContaining([
        "server/watchdog-dispatch-clock.ts",
        "server/watchdog-dispatch-table.ts",
        "server/github-app.ts",
        "server/github/probe-octokit.ts",
        "server/observability.ts",
        "server/cron-liveness-marker.ts",
      ]),
    );
  });

  it("no module under server/inngest/ is transitively reachable", () => {
    const offenders = [...reachableFrom(CLOCK)]
      .map((p) => p.slice(APP_ROOT.length + 1))
      .filter((p) => p.startsWith("server/inngest/"));
    expect(offenders).toEqual([]);
  });

  it("the walker detects a server/inngest import (positive control)", () => {
    const fake = join(APP_ROOT, "server/watchdog-dispatch-clock.ts");
    // Resolving the forbidden specifier from the clock's own directory must land
    // under server/inngest/ — proves resolveSpecifier can see the tree it guards.
    const target = resolveSpecifier(
      "@/server/inngest/functions/_cron-shared",
      fake,
    );
    expect(target && target.includes("/server/inngest/")).toBe(true);
  });
});
