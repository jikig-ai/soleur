// #8495 — watchdog dispatch clock. GitHub Actions `schedule:` drops ticks (the
// external Inngest watchdog measured one run every 2-7 h against a declared
// */15), so the web server fires `workflow_dispatch` on a reliable wall clock.
// ADR-248 owns the rationale; this file pins the behaviour (plan Test Scenarios
// C1-C15 + Guard 2). Every scenario injects its table, so a two-entry table is
// used only where the second member is the point (C11, C15).

import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import ts from "typescript";
import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from "vitest";

// C12 drives the DEFAULT mint (no `mint` injected) through these two seams, so
// the token-scope contract is asserted at the boundary the clock does not own.
const { generateInstallationTokenMock, createAppJwtOctokitMock, lookupMock } =
  vi.hoisted(() => {
    const lookupMock = vi.fn(async (..._a: unknown[]) => ({ data: { id: 4242 } }));
    return {
      generateInstallationTokenMock: vi.fn(
        async (..._args: unknown[]) => "ghs_DEFAULTMINTTOKEN",
      ),
      lookupMock,
      createAppJwtOctokitMock: vi.fn(async (..._args: unknown[]) => ({
        octokit: { request: lookupMock },
      })),
    };
  });

vi.mock("@/server/github-app", () => ({
  generateInstallationToken: generateInstallationTokenMock,
}));
vi.mock("@/server/github/probe-octokit", () => ({
  createAppJwtOctokit: createAppJwtOctokitMock,
  // The clock must never use createProbeOctokit (it reports its own failures
  // under feature=cron-oauth-probe); a call here throws.
  createProbeOctokit: () => {
    throw new Error("createProbeOctokit must not be used by the clock");
  },
  PROBE_ISSUE_OWNER: "jikig-ai",
  PROBE_ISSUE_REPO: "soleur",
}));

import {
  JITTER_MAX_MS,
  JITTER_MIN_MS,
  MAX_ATTEMPTS_PER_SLOT,
  POLL_MS,
  RETRY_BACKOFF_MS,
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
  conclusion: string | null;
  headBranch: string;
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
        // Mirrors the real endpoint: newest-first, `branch` filters head_branch,
        // `per_page` bounds the page.
        const visible = (runs.get(wf) ?? [])
          .filter((x) => x.visibleAtMs <= now)
          .filter((x) => params.branch === undefined || x.headBranch === params.branch)
          .sort((a, b) => b.createdAtMs - a.createdAtMs)
          .slice(0, Number(params.per_page ?? 30));
        return {
          data: {
            total_count: visible.length,
            workflow_runs: visible.map((x) => ({
              id: x.id,
              event: x.event,
              status: x.status,
              conclusion: x.conclusion,
              head_branch: x.headBranch,
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
          conclusion: null,
          headBranch: String(params.ref),
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
        conclusion: run.conclusion === undefined ? "success" : run.conclusion,
        headBranch: run.headBranch ?? "main",
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
// Set by the one case that deliberately drives the outer fence.
let allowEscaped = false;

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
  allowEscaped = false;
  generateInstallationTokenMock.mockClear();
  createAppJwtOctokitMock.mockClear();
  lookupMock.mockClear();
});

afterEach(async () => {
  for (const s of stops) s();
  await flushReal();
  process.off("unhandledRejection", unhandled);
  // No tick may ever escape its fences (Guard 2) — asserted for EVERY case.
  expect(unhandled).not.toHaveBeenCalled();
  if (!allowEscaped) expect(outcomes()).not.toContain("tick_escaped");
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
  it("slotAlreadyHasRun: created exactly at S → true; S−1 ms → false", () => {
    const S = S0;
    expect(slotAlreadyHasRun(new Date(S).toISOString(), S)).toBe(true);
    expect(slotAlreadyHasRun(new Date(S - 1).toISOString(), S)).toBe(false);
    // Unparseable → "not this slot" (fail-open to dispatch).
    expect(slotAlreadyHasRun("not-a-date", S)).toBe(false);
  });

  it.each([
    [0, 0],
    [-1, 1],
    // A LATE run of the previous slot (created in its final seconds) never
    // suppresses this slot.
    [-5_000, 1],
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
      throw Object.assign(new Error(`bad gateway for token ${TOKEN}`), {
        name: "HttpError",
        status: 502,
        request: { headers: { authorization: `token ${TOKEN}` } },
        response: { data: { message: `x ${TOKEN}` }, headers: {} },
      });
    };
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    expect(report).toHaveBeenCalledTimes(1);
    assertNoTokenAnywhere();
    expect((report.mock.calls[0][0] as Error).name).toBe("HttpError:dedup-read");
    expect(report.mock.calls[0][1]).toMatchObject({
      feature: "watchdog-dispatch-clock",
      op: "dedup-read",
      extra: expect.objectContaining({ reason: "http", status: 502 }),
      tags: { workflow: INNGEST.workflowFile, reason: "http", status: "502" },
    });
    await advanceTo(S0 + 15 * MIN + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(2);
  });
});

describe("C7 failures are reported redacted, fenced, and never stall the clock", () => {
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
    expect((err as Error).name).toBe("HttpError:dispatch");
    expect(opts).toMatchObject({
      tags: { workflow: INNGEST.workflowFile, reason: "http", status: "422" },
    });
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

describe("C10 a late boot still covers the current slot", () => {
  it("boot at S+13:30 → the tick for S fires, then one for S+15", async () => {
    vi.setSystemTime(S0 + 13 * MIN + 30_000);
    const gh = fakeGitHub();
    start(gh);
    await advanceTo(S0 + 14 * MIN + 1);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    // The S-slot run (created S+14:00) is older than S+15, so it does not
    // suppress the next slot.
    await advanceTo(S0 + 15 * MIN + 60_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(2);
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
    expect(createAppJwtOctokitMock).toHaveBeenCalledTimes(1);
    expect(lookupMock).toHaveBeenCalledWith(
      "GET /repos/{owner}/{repo}/installation",
      { owner: "jikig-ai", repo: "soleur" },
    );
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
      branch: "main",
    });
    expect(Number(read?.params.per_page)).toBeGreaterThanOrEqual(5);
  });

  it("caches the installation id: a second slot mints without a second lookup; a failure drops the cache", async () => {
    const gh = fakeGitHub();
    start(gh, { mint: undefined, octokitFor: () => gh.api });
    await advanceTo(S0 + 40_000);
    await advanceTo(S0 + 15 * MIN + 40_000);
    expect(lookupMock).toHaveBeenCalledTimes(1);
    expect(generateInstallationTokenMock).toHaveBeenCalledTimes(2);
    generateInstallationTokenMock.mockRejectedValueOnce(new Error("revoked"));
    await advanceTo(S0 + 30 * MIN + 40_000);
    await advanceTo(S0 + 45 * MIN + 40_000);
    // The failed slot-3 mint dropped the cache; its in-slot retry re-looked-up and dispatched.
    expect(lookupMock).toHaveBeenCalledTimes(2);
    expect(gh.posts(INNGEST.workflowFile)).toBe(4);
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

  it("random=max: no tick before S+JITTER_MAX_MS, a tick at it", async () => {
    const gh = fakeGitHub();
    start(gh, { random: () => 1 });
    await advanceTo(S0 + JITTER_MAX_MS - 1);
    expect(gh.reads(INNGEST.workflowFile)).toBe(0);
    await advanceTo(S0 + JITTER_MAX_MS);
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
    await advanceTo(S0 + 90_000);
    // A fresh draw on every poll would have ticked both at S+60 s.
    expect(gh.posts(INNGEST.workflowFile)).toBe(0);
    expect(gh.posts(ZOT.workflowFile)).toBe(0);
    expect(random).toHaveBeenCalledTimes(2);
    await advanceTo(S0 + JITTER_MAX_MS);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    expect(gh.posts(ZOT.workflowFile)).toBe(1);
    expect(random).toHaveBeenCalledTimes(2);
  });
});

describe("C16 dedup read counts only runs that could have covered the slot", () => {
  it.each([
    ["a pull_request run (branch/fork copy with an extra trigger)", { event: "pull_request" }],
    ["a dispatch on a non-main ref", { event: "workflow_dispatch", headBranch: "feat-x" }],
    ["a cancelled run (replaced in the concurrency queue)", { conclusion: "cancelled" }],
    ["a startup_failure run", { conclusion: "startup_failure" }],
  ])("%s created in-slot does NOT suppress the dispatch", async (_label, over) => {
    const gh = fakeGitHub();
    gh.seed(INNGEST.workflowFile, { createdAtMs: S0 + 5_000, ...over });
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
  });

  it("an eligible in-slot run behind newer ineligible ones still suppresses", async () => {
    const gh = fakeGitHub();
    gh.seed(INNGEST.workflowFile, { id: 501, event: "schedule", createdAtMs: S0 + 2_000 });
    gh.seed(INNGEST.workflowFile, { event: "pull_request", createdAtMs: S0 + 10_000 });
    gh.seed(INNGEST.workflowFile, { conclusion: "cancelled", createdAtMs: S0 + 20_000 });
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(0);
    expect(markers()).toContainEqual(
      expect.objectContaining({ outcome: "skipped_slot_has_run", run_id: 501 }),
    );
  });

  it("an in-progress run (not yet concluded) in-slot suppresses", async () => {
    const gh = fakeGitHub();
    gh.seed(INNGEST.workflowFile, {
      createdAtMs: S0 + 2_000,
      status: "in_progress",
      conclusion: null,
    });
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(0);
  });
});

describe("C17 the tick deadline aborts the in-flight request and discards a late result", () => {
  it("the dispatch request's AbortSignal is aborted at TICK_DEADLINE_MS", async () => {
    const gh = fakeGitHub();
    let seen: AbortSignal | undefined;
    gh.hooks.dispatch = (p) => {
      seen = (p.request as { signal?: AbortSignal } | undefined)?.signal;
      return new Promise(() => undefined);
    };
    start(gh);
    await advanceTo(S0 + 30_000 + 1);
    expect(seen).toBeDefined();
    expect(seen!.aborted).toBe(false);
    await advanceTo(S0 + 30_000 + TICK_DEADLINE_MS + 1);
    expect(seen!.aborted).toBe(true);
  });

  it("the runs read also carries the AbortSignal", async () => {
    const gh = fakeGitHub();
    start(gh);
    await advanceTo(S0 + 40_000);
    const read = gh.calls.find((c) => c.route === RUNS_ROUTE)!;
    expect((read.params.request as { signal?: unknown }).signal).toBeInstanceOf(AbortSignal);
  });

  it("a dispatch that succeeds AFTER the deadline yields exactly one `failed` marker, never `dispatched`", async () => {
    const gh = fakeGitHub();
    gh.hooks.dispatch = () =>
      new Promise((res) => setTimeout(() => res({ status: 204 }), TICK_DEADLINE_MS + 5_000));
    start(gh);
    await advanceTo(S0 + 30_000 + TICK_DEADLINE_MS + 10_000);
    expect(outcomes(INNGEST.workflowFile)).toEqual(["failed"]);
  });

  it("a mint that resolves AFTER the deadline never reads or dispatches", async () => {
    const gh = fakeGitHub();
    start(gh, {
      mint: () => new Promise((res) => setTimeout(() => res(TOKEN), TICK_DEADLINE_MS + 5_000)),
    });
    await advanceTo(S0 + 30_000 + TICK_DEADLINE_MS + 10_000);
    expect(gh.calls).toEqual([]);
    expect(outcomes(INNGEST.workflowFile)).toEqual(["failed"]);
  });
});

describe("C18 the outer fence and the poll guard", () => {
  it("an error whose `message` getter throws escapes the inner catch; the outer fence contains it and the next slot proceeds", async () => {
    allowEscaped = true;
    const gh = fakeGitHub();
    let calls = 0;
    const hostile = {
      get message(): string {
        throw new Error("hostile getter");
      },
      name: "Hostile",
    };
    start(gh, {
      mint: async () => {
        calls++;
        if (calls === 1) throw hostile;
        return TOKEN;
      },
    });
    await advanceTo(S0 + 40_000);
    expect(outcomes(INNGEST.workflowFile)).toContain("tick_escaped");
    expect(report.mock.calls.map((c) => (c[1] as { op?: string }).op)).toContain("tick");
    await advanceTo(S0 + 15 * MIN + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
  });

  it("a poll that throws is reported (op=poll) and the clock keeps ticking", async () => {
    const gh = fakeGitHub();
    let n = 0;
    start(gh, {
      random: () => {
        n++;
        if (n === 1) throw new Error("rng broke");
        return 0;
      },
    });
    await advanceTo(S0 + 40_000);
    expect(report.mock.calls.map((c) => (c[1] as { op?: string }).op)).toContain("poll");
    await advanceTo(S0 + 70_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
  });
});

describe("C20 bounded retry inside the slot after a failed tick", () => {
  it("a transient dispatch failure is retried after the backoff, and the slot is covered", async () => {
    const gh = fakeGitHub();
    gh.hooks.dispatch = async () => {
      gh.hooks.dispatch = undefined; // fail once, then the real (fake) endpoint
      throw Object.assign(new Error("bad gateway"), { status: 502 });
    };
    start(gh);
    await advanceTo(S0 + 40_000);
    expect(outcomes(INNGEST.workflowFile)).toEqual(["failed"]);
    // No retry before the backoff elapses.
    await advanceTo(S0 + 30_000 + RETRY_BACKOFF_MS - 1);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    await advanceTo(S0 + 40_000 + RETRY_BACKOFF_MS + POLL_MS);
    expect(gh.posts(INNGEST.workflowFile)).toBe(2);
    expect(outcomes(INNGEST.workflowFile)).toEqual(["failed", "dispatched"]);
  });

  it("a retry re-reads first: a timed-out POST that actually landed is not dispatched twice", async () => {
    const gh = fakeGitHub();
    gh.hooks.dispatch = async (p) => {
      gh.hooks.dispatch = undefined;
      await gh.client.request(DISPATCH_ROUTE, p); // the run IS created...
      return new Promise(() => undefined); // ...but the response never arrives
    };
    start(gh);
    await advanceTo(S0 + 30_000 + TICK_DEADLINE_MS + RETRY_BACKOFF_MS + 2 * POLL_MS);
    expect(outcomes(INNGEST.workflowFile)).toEqual(["failed", "skipped_slot_has_run"]);
  });

  it(`gives up after MAX_ATTEMPTS_PER_SLOT failures in one slot`, async () => {
    const gh = fakeGitHub();
    gh.hooks.dispatch = async () => {
      throw Object.assign(new Error("down"), { status: 503 });
    };
    start(gh);
    await advanceTo(S0 + 14 * MIN);
    expect(outcomes(INNGEST.workflowFile)).toEqual(
      Array(MAX_ATTEMPTS_PER_SLOT).fill("failed"),
    );
  });
});

describe("C19 table and clock sanity", () => {
  it("a row with a non-positive/non-integer interval is dropped loudly and never storms; valid rows still tick", async () => {
    const gh = fakeGitHub();
    const BAD: WatchdogDispatchEntry = { ...ZOT, workflowFile: "bad.yml", intervalMinutes: 0 };
    start(gh, { table: [BAD, INNGEST] });
    expect(report.mock.calls.map((c) => (c[1] as { op?: string }).op)).toContain("arm");
    await advanceTo(S0 + 5 * MIN);
    expect(gh.posts("bad.yml")).toBe(0);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
  });

  it("a backwards clock step never replays an already-handled slot", async () => {
    const gh = fakeGitHub();
    vi.setSystemTime(S0 + 15 * MIN);
    start(gh);
    await advanceTo(S0 + 15 * MIN + 40_000);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
    // NTP steps the clock back into the previous slot.
    vi.setSystemTime(S0 + 5 * MIN);
    await vi.advanceTimersByTimeAsync(3 * POLL_MS);
    await flushReal();
    expect(gh.reads(INNGEST.workflowFile)).toBe(1);
    expect(gh.posts(INNGEST.workflowFile)).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Guard 2 (static half) — the clock must never route through the thing it
// watches. Walks the clock's TRANSITIVE import graph with the TypeScript parser
// (static import/export-from, `import x = require()`, `require()`, and
// `import()` in any position or quoting) and asserts no module under
// server/inngest/ is reachable. It FAILS CLOSED: a local specifier that does
// not resolve, or an `import()`/`require()` with a non-literal argument, is an
// offender rather than a silently dropped edge. Enforced here rather than in
// the generated, non-blocking .dependency-cruiser.cjs, because this suite runs
// in the required `test` context. Type-only imports are erased and skipped.
// ---------------------------------------------------------------------------
const APP_ROOT = resolve(__dirname, "../..");
const SOURCE_EXTS = [".ts", ".tsx", ".js", ".mjs", ".cjs"];

function resolveSpecifier(spec: string, fromFile: string): string | null | "unresolved" {
  let base: string;
  if (spec.startsWith("@/")) base = join(APP_ROOT, spec.slice(2));
  else if (spec.startsWith(".")) base = resolve(dirname(fromFile), spec);
  else return null; // bare package — outside the property
  const stem = base.replace(/\.(js|mjs|cjs)$/, "");
  const candidates = [
    base,
    ...SOURCE_EXTS.map((e) => `${stem}${e}`),
    ...SOURCE_EXTS.map((e) => join(base, `index${e}`)),
  ];
  for (const cand of candidates) {
    if (existsSync(cand) && SOURCE_EXTS.some((e) => cand.endsWith(e))) return cand;
  }
  return "unresolved";
}

function specifiersOf(file: string): string[] {
  const src = readFileSync(file, "utf-8");
  const sf = ts.createSourceFile(
    file,
    src,
    ts.ScriptTarget.Latest,
    true,
    file.endsWith(".tsx") ? ts.ScriptKind.TSX : file.endsWith(".ts") ? ts.ScriptKind.TS : ts.ScriptKind.JS,
  );
  const out: string[] = [];
  const visit = (n: ts.Node): void => {
    if (
      (ts.isImportDeclaration(n) || ts.isExportDeclaration(n)) &&
      n.moduleSpecifier &&
      ts.isStringLiteral(n.moduleSpecifier)
    ) {
      const typeOnly = ts.isImportDeclaration(n) ? !!n.importClause?.isTypeOnly : n.isTypeOnly;
      if (!typeOnly) out.push(n.moduleSpecifier.text);
    } else if (
      ts.isImportEqualsDeclaration(n) &&
      ts.isExternalModuleReference(n.moduleReference) &&
      ts.isStringLiteral(n.moduleReference.expression)
    ) {
      out.push(n.moduleReference.expression.text);
    } else if (
      ts.isCallExpression(n) &&
      (n.expression.kind === ts.SyntaxKind.ImportKeyword ||
        (ts.isIdentifier(n.expression) && n.expression.text === "require"))
    ) {
      const a = n.arguments[0];
      if (a && (ts.isStringLiteral(a) || ts.isNoSubstitutionTemplateLiteral(a))) out.push(a.text);
      else out.push("<non-literal-dynamic-import>");
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return out;
}

function walk(entry: string): { reach: Set<string>; problems: string[] } {
  const reach = new Set<string>();
  const problems: string[] = [];
  const stack = [entry];
  while (stack.length) {
    const f = stack.pop()!;
    if (reach.has(f)) continue;
    reach.add(f);
    for (const spec of specifiersOf(f)) {
      if (spec === "<non-literal-dynamic-import>") {
        problems.push(`${f}: non-literal import()/require()`);
        continue;
      }
      const target = resolveSpecifier(spec, f);
      if (target === "unresolved") problems.push(`${f}: unresolved local specifier ${spec}`);
      else if (target) stack.push(target);
    }
  }
  return { reach, problems };
}

const rel = (p: string) => p.slice(APP_ROOT.length + 1);

describe("Guard 2 — the clock never imports the Inngest tree", () => {
  const CLOCK = join(APP_ROOT, "server/watchdog-dispatch-clock.ts");

  it("the walker is live: it finds the clock's known direct dependencies", () => {
    const reach = [...walk(CLOCK).reach].map(rel);
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

  it("the walk is total: every local specifier resolved and every dynamic import is a literal", () => {
    expect(walk(CLOCK).problems).toEqual([]);
  });

  it("no module under server/inngest/ is transitively reachable", () => {
    const offenders = [...walk(CLOCK).reach].map(rel).filter((p) => p.startsWith("server/inngest/"));
    expect(offenders).toEqual([]);
  });

  // Positive control: every import form the walker claims to see must, when
  // pointed at the Inngest tree, land there — through the SAME walk the real
  // assertion uses.
  it.each([
    ["static import", `import { inngest } from "@/server/inngest/client";`],
    ["import after another statement", `const a = 1; import { inngest } from "@/server/inngest/client";`],
    ["export-from", `export * from "@/server/inngest/client";`],
    ["require()", `const c = require("@/server/inngest/client");`],
    ["import = require()", `import c = require("@/server/inngest/client");`],
    ["dynamic import()", `void import("@/server/inngest/client");`],
    ["dynamic import() with comment", `void import(/* x */ "@/server/inngest/client");`],
    ["template-literal import()", "void import(`@/server/inngest/client`);"],
    [".js-suffixed specifier", `import { inngest } from "@/server/inngest/client.js";`],
  ])("positive control: %s reaching server/inngest/ is detected", (_label, code) => {
    const dir = mkdtempSync(join(tmpdir(), "wd-walk-"));
    try {
      const f = join(dir, "probe.ts");
      writeFileSync(f, `${code}\n`);
      const reach = [...walk(f).reach].filter((p) => p.startsWith(APP_ROOT)).map(rel);
      expect(reach.some((p) => p.startsWith("server/inngest/"))).toBe(true);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("positive control: a non-literal import() and an unresolvable local specifier are problems, not silent drops", () => {
    const dir = mkdtempSync(join(tmpdir(), "wd-walk-"));
    try {
      const f = join(dir, "probe.ts");
      writeFileSync(
        f,
        `const p = "@/server/inngest/client"; void import(p);\nimport "@/server/does-not-exist";\n`,
      );
      const { problems } = walk(f);
      expect(problems.some((x) => x.includes("non-literal"))).toBe(true);
      expect(problems.some((x) => x.includes("unresolved local specifier @/server/does-not-exist"))).toBe(true);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
