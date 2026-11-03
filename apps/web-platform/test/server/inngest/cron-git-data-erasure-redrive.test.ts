// cron-git-data-erasure-redrive (#8211 PR-B2): re-drives removeGitDataRepo for every id in the
// durable pending-erasure ledger until the host confirms `erased`, but only for accounts that are
// really gone.

import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const mockRpc = vi.fn();
const mockCreateClient = vi.fn();
vi.mock("@/lib/supabase/service", () => ({ createServiceClient: () => mockCreateClient() }));

const mockRemove = vi.fn();
vi.mock("@/server/git-data-replication", () => ({
  removeGitDataRepo: (...a: unknown[]) => mockRemove(...a),
}));

vi.mock("@/server/inngest/functions/_cron-shared", () => ({
  postSentryHeartbeat: vi.fn(async () => {}),
}));

vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));

import { postSentryHeartbeat } from "@/server/inngest/functions/_cron-shared";
import { reportSilentFallback, warnSilentFallback, infoSilentFallback } from "@/server/observability";
import {
  cronGitDataErasureRedrive,
  cronGitDataErasureRedriveHandler,
  parseSeedRequest,
  CLAIM_LIMIT,
  CLAIM_MIN_INTERVAL,
  ESCALATE_AFTER_SECONDS,
  ESCALATION_REPEAT_MS,
  HARD_STOP_AFTER_SECONDS,
  LIVE_OWNER_WARN_AFTER_SECONDS,
  MAX_SEED_IDS,
  REDRIVE_OP,
  SENTRY_MONITOR_SLUG,
  _resetProcessMemosForTest,
} from "@/server/inngest/functions/cron-git-data-erasure-redrive";

const A = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
const B = "6ba7b810-9dad-41d1-80b4-00c04fd430c8";
const C = "9b2f7a64-1c3e-4f0a-8d55-5e7c2f1a0b99";
const DAY = 86400;

const stepNames: string[] = [];
const fakeStep = {
  run: async <T>(name: string, cb: () => Promise<T>): Promise<T> => {
    stepNames.push(name);
    return cb();
  },
};
const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
const run = (event?: { name?: string; data?: Record<string, unknown> }) =>
  cronGitDataErasureRedriveHandler({ event, step: fakeStep, logger });

// In-memory ledger with the RPCs' semantics (claim: oldest first, skips rows stamped inside the window).
type Row = { id: string; attempts: number; stamped: boolean; outcome: string | null; requestedAt?: string };
let ledger: Map<string, Row>;
let liveOwners: Set<string>;
let oldest: number | null; // oldest age among rows whose owner is GONE
let oldestLive: number | null; // oldest age among rows whose owner still exists
let failRpc: Record<string, { message: string }>;
const seedLedger = (...ids: string[]) => ids.forEach((id) => ledger.set(id, { id, attempts: 0, stamped: false, outcome: "refused" }));

function installRpc() {
  mockRpc.mockImplementation(async (name: string, args?: Record<string, unknown>) => {
    if (failRpc[name]) return { data: null, error: failRpc[name] };
    switch (name) {
      case "claim_git_data_erasure_pending": {
        const out = [];
        for (const r of ledger.values()) {
          if (r.stamped || out.length >= (args!.p_limit as number)) continue;
          r.stamped = true;
          r.attempts += 1;
          out.push({ workspace_id: r.id, requested_at: "2026-10-01T00:00:00Z", attempts: r.attempts, last_outcome: r.outcome });
        }
        return { data: out, error: null };
      }
      case "git_data_erasure_owner_gone":
        return { data: !liveOwners.has(args!.p_workspace_id as string), error: null };
      case "resolve_git_data_erasure_pending": {
        const existed = ledger.delete(args!.p_workspace_id as string);
        return { data: existed ? "lt_1h" : null, error: null }; // NULL = no row existed (real RPC contract)
      }
      case "record_git_data_erasure_pending": {
        const id = args!.p_workspace_id as string;
        const prev = ledger.get(id);
        ledger.set(id, { ...(prev ?? { id, attempts: 0, stamped: false }), outcome: args!.p_outcome as string, requestedAt: args!.p_requested_at as string | undefined } as Row);
        return { data: null, error: null };
      }
      case "git_data_erasure_pending_ages":
        return { data: [{ oldest_gone_seconds: oldest, oldest_live_seconds: oldestLive }], error: null };
      default:
        return { data: null, error: null };
    }
  });
}
const rpcCalls = (name: string) => mockRpc.mock.calls.filter((c) => c[0] === name);
const calledIds = (name: string) => rpcCalls(name).map((c) => (c[1] as { p_workspace_id: string }).p_workspace_id);
const reports = () => (reportSilentFallback as ReturnType<typeof vi.fn>).mock.calls;
const warns = () => (warnSilentFallback as ReturnType<typeof vi.fn>).mock.calls;

function resetWorld() {
  vi.clearAllMocks();
  stepNames.length = 0;
  ledger = new Map();
  liveOwners = new Set();
  oldest = null;
  oldestLive = null;
  failRpc = {};
  mockCreateClient.mockImplementation(() => ({ rpc: mockRpc }));
  installRpc();
  mockRemove.mockResolvedValue({ status: "erased" });
  _resetProcessMemosForTest();
}
beforeEach(resetWorld);
afterEach(() => vi.useRealTimers());

/**
 * Inngest re-invokes the handler from the top after EVERY new step and answers already-completed steps
 * from memo (JSON round-tripped, callback NOT re-run). This harness does the same, so a closure counter
 * mutated inside a step callback (invisible to the run-once fake) shows up as a wrong result.
 */
class NewStepRan extends Error {}
async function runReplaying(event?: { name?: string; data?: Record<string, unknown> }) {
  const memo = new Map<string, string>();
  for (let pass = 0; pass < 500; pass += 1) {
    const replayStep = {
      run: async <T>(name: string, cb: () => Promise<T>): Promise<T> => {
        if (memo.has(name)) return JSON.parse(memo.get(name)!) as T;
        const out = await cb();
        memo.set(name, JSON.stringify(out ?? null));
        throw new NewStepRan();
      },
    };
    try {
      return await cronGitDataErasureRedriveHandler({ event, step: replayStep, logger });
    } catch (err) {
      if (!(err instanceof NewStepRan)) throw err;
    }
  }
  throw new Error("replay did not converge");
}

describe("claim", () => {
  it("claims ONE row per step with a backoff of at least 60 s, at most 25 rows per run", async () => {
    // literal expectations: importing the constant as its own expectation would pass any value
    expect(CLAIM_LIMIT).toBe(25);
    expect(CLAIM_MIN_INTERVAL).toBe("1 hour");
    seedLedger(...Array.from({ length: 30 }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`));
    const out = await run();
    expect(out.claimed).toBe(25);
    for (const c of rpcCalls("claim_git_data_erasure_pending")) {
      expect(c[1]).toEqual({ p_limit: 1, p_min_interval: "1 hour" });
    }
    expect(rpcCalls("claim_git_data_erasure_pending")).toHaveLength(25);
  });

  it("the production backoff literal parses to at least one minute (the RPC floor)", () => {
    const m = /^(\d+) (second|minute|hour|day)s?$/.exec(CLAIM_MIN_INTERVAL);
    expect(m).not.toBeNull();
    const seconds = Number(m![1]) * { second: 1, minute: 60, hour: 3600, day: 86400 }[m![2] as "second"];
    expect(seconds).toBeGreaterThanOrEqual(60);
  });

  it("with nothing pending makes no host call, stops after one claim and heartbeats green", async () => {
    const out = await run();
    expect(mockRemove).not.toHaveBeenCalled();
    expect(rpcCalls("claim_git_data_erasure_pending")).toHaveLength(1);
    expect(out).toMatchObject({ claimed: 0, erased: 0 });
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG }));
  });

  it("a claim RPC error is attempted and reported exactly ONCE (the loop stops), drives nothing and turns the heartbeat red", async () => {
    failRpc.claim_git_data_erasure_pending = { message: "db down" };
    await run();
    expect(mockRemove).not.toHaveBeenCalled();
    expect(rpcCalls("claim_git_data_erasure_pending")).toHaveLength(1); // a `continue` would hammer a down DB 25x per tick
    expect(reports().filter((c) => (c[1] as { op: string }).op === REDRIVE_OP)).toHaveLength(1);
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
  });
});

describe("owner-gone gate (the ledger is not proof the account is gone)", () => {
  it("a LIVE owner's row is never erased, never resolved, counted, and warned once with no ids", async () => {
    seedLedger(A, B);
    liveOwners.add(A);
    liveOwners.add(B);
    const out = await run();
    expect(mockRemove).not.toHaveBeenCalled();
    expect(rpcCalls("resolve_git_data_erasure_pending")).toHaveLength(0);
    expect(ledger.has(A) && ledger.has(B)).toBe(true);
    expect(ledger.get(A)!.attempts).toBe(1); // the claim stamp is the backoff
    expect(out).toMatchObject({ claimed: 2, erased: 0, ownerPresent: 2 });
    const ownerWarns = warns().filter((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason === "owner_still_exists");
    expect(ownerWarns).toHaveLength(1);
    expect(JSON.stringify(warns())).not.toContain(A);
    // no "no progress" warning for rows that were deliberately not driven
    expect(warns().some((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason === "no_erasure_progress")).toBe(false);
  });

  it("an aborted deletion (live user) is left alone; once the owner is gone the next run erases and resolves", async () => {
    seedLedger(A);
    liveOwners.add(A);
    await run();
    expect(mockRemove).not.toHaveBeenCalled();
    ledger.get(A)!.stamped = false; // the hourly backoff elapsed
    liveOwners.delete(A); // the deletion completed later
    const out = await run();
    expect(mockRemove).toHaveBeenCalledWith(A);
    expect(ledger.has(A)).toBe(false);
    expect(out).toMatchObject({ erased: 1, ownerPresent: 0 });
  });

  it("the owner check runs BEFORE the host call, for every id", async () => {
    seedLedger(A, B);
    const order: string[] = [];
    mockRemove.mockImplementation(async (id: string) => {
      order.push(`remove:${id === A ? "A" : "B"}`);
      return { status: "erased" };
    });
    const base = mockRpc.getMockImplementation()!;
    mockRpc.mockImplementation(async (name: string, args?: Record<string, unknown>) => {
      if (name === "git_data_erasure_owner_gone") order.push(`gone:${args!.p_workspace_id === A ? "A" : "B"}`);
      return base(name, args);
    });
    await run();
    expect(order).toEqual(["gone:A", "remove:A", "gone:B", "remove:B"]);
  });

  it("an owner-check ERROR is treated as not gone: no host call, heartbeat red", async () => {
    seedLedger(A);
    failRpc.git_data_erasure_owner_gone = { message: "db down" };
    await run();
    expect(mockRemove).not.toHaveBeenCalled();
    expect(ledger.has(A)).toBe(true);
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
  });
});

describe("per-row re-drive", () => {
  it("erased => the row is resolved (deleted); no record call", async () => {
    seedLedger(A);
    const out = await run();
    expect(mockRemove).toHaveBeenCalledWith(A);
    expect(calledIds("resolve_git_data_erasure_pending")).toEqual([A]);
    expect(rpcCalls("record_git_data_erasure_pending")).toHaveLength(0);
    expect(out).toMatchObject({ claimed: 1, erased: 1, pending: 0 });
  });

  it.each([
    ["refused", { status: "refused", exitCode: 3, detail: "x" }],
    ["unreachable", { status: "unreachable", detail: "x" }],
    ["unauthorized", { status: "unauthorized", detail: "x" }],
    ["unconfigured", { status: "unconfigured", detail: "pin_absent: x" }],
    ["host_key_mismatch", { status: "host_key_mismatch", detail: "x" }],
  ])("%s => the row stays (no resolve) and last_outcome is refreshed", async (word, outcome) => {
    seedLedger(A);
    mockRemove.mockResolvedValue(outcome);
    const out = await run();
    expect(rpcCalls("resolve_git_data_erasure_pending")).toHaveLength(0);
    expect(rpcCalls("record_git_data_erasure_pending")).toEqual([
      ["record_git_data_erasure_pending", { p_workspace_id: A, p_outcome: word }],
    ]);
    expect(ledger.has(A)).toBe(true);
    expect(out).toMatchObject({ claimed: 1, erased: 0, pending: 1 });
  });

  it("skipped is NOT confirmation: the row stays and nothing is rewritten", async () => {
    seedLedger(A);
    mockRemove.mockResolvedValue({ status: "skipped" });
    const out = await run();
    expect(rpcCalls("resolve_git_data_erasure_pending")).toHaveLength(0);
    expect(rpcCalls("record_git_data_erasure_pending")).toHaveLength(0);
    expect(out).toMatchObject({ erased: 0, pending: 1 });
  });

  it("a throwing removeGitDataRepo leaves the row, records 'threw', and does not stop the other ids", async () => {
    seedLedger(A, B, C);
    mockRemove.mockImplementation(async (id: string) => {
      if (id === B) throw new Error(`refusing unsafe workspace_id ${id}`);
      return { status: "erased" };
    });
    const out = await run();
    expect(mockRemove).toHaveBeenCalledTimes(3);
    expect(calledIds("resolve_git_data_erasure_pending")).toEqual([A, C]);
    expect(rpcCalls("record_git_data_erasure_pending")).toEqual([
      ["record_git_data_erasure_pending", { p_workspace_id: B, p_outcome: "threw" }],
    ]);
    expect(out).toMatchObject({ claimed: 3, erased: 2, pending: 1 });
  });

  it("each row runs in its own step.run; no step name carries an id and no id is a step output", async () => {
    seedLedger(A, B);
    const outputs: unknown[] = [];
    const recordingStep = {
      run: async <T>(name: string, cb: () => Promise<T>): Promise<T> => {
        stepNames.push(name);
        const out = await cb();
        outputs.push(out);
        return out;
      },
    };
    await cronGitDataErasureRedriveHandler({ step: recordingStep, logger });
    const redriveSteps = stepNames.filter((n) => n.startsWith("redrive-"));
    expect(redriveSteps).toEqual(["redrive-0", "redrive-1", "redrive-2"]); // 2 rows + the empty claim
    expect(JSON.stringify([stepNames, outputs])).not.toContain(A);
    expect(JSON.stringify([stepNames, outputs])).not.toContain(B);
  });

  it.each(["resolve_git_data_erasure_pending", "record_git_data_erasure_pending"])(
    "a failed %s is reported, the row stays, and the heartbeat is RED (not ok)",
    async (failing) => {
      seedLedger(A);
      if (failing === "record_git_data_erasure_pending") mockRemove.mockResolvedValue({ status: "refused", exitCode: 1, detail: "x" });
      failRpc[failing] = { message: "db down" };
      const out = await run();
      expect(out).toMatchObject({ claimed: 1, erased: 0 });
      expect(ledger.has(A)).toBe(true);
      expect(reports().some((c) => (c[1] as { op: string }).op === REDRIVE_OP)).toBe(true);
      expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
    },
  );

  it("warns when rows were driven and none erased (fleet-wide refusal), before day 20", async () => {
    seedLedger(A, B);
    mockRemove.mockResolvedValue({ status: "unauthorized", detail: "Permission denied (publickey)" });
    await run();
    const w = warns().filter((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason === "no_erasure_progress");
    expect(w).toHaveLength(1);
  });

  it("a seeded LIVE id does not swallow no_erasure_progress for a refused ledger row", async () => {
    liveOwners.add(B);
    seedLedger(A);
    mockRemove.mockResolvedValue({ status: "refused", exitCode: 1, detail: "x" });
    const out = await run({ data: { ids: [B], requested_at: "2026-10-01T00:00:00Z" } });
    expect(out).toMatchObject({ claimed: 1, ownerPresent: 1, erased: 0 });
    expect(warns().filter((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason === "no_erasure_progress")).toHaveLength(1);
  });

  it("does not raise the no-progress warning when at least one erasure succeeded", async () => {
    seedLedger(A, B);
    mockRemove.mockImplementation(async (id: string) => (id === A ? { status: "erased" } : { status: "refused", exitCode: 1, detail: "x" }));
    await run();
    expect(warns().some((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason === "no_erasure_progress")).toBe(false);
  });
});

// There is deliberately no "malformed claimed id" case: git_data_erasure_pending.workspace_id is a uuid
// PRIMARY KEY and the claim RPC RETURNS TABLE (workspace_id uuid, ...), so Postgres cannot hand back a
// non-UUID (the branch that used to guard it was unreachable and was removed).

describe("manual event seeding", () => {
  const SEED_AT = "2026-10-01T00:00:00Z";
  const ev = (data: Record<string, unknown>) => ({ name: "cron/git-data-erasure-redrive.manual-trigger", data });

  it("records every valid, gone id as 'seeded' with the ORIGINAL requested_at, canonicalised and deduplicated, before claiming", async () => {
    const calls: string[] = [];
    const base = mockRpc.getMockImplementation()!;
    mockRpc.mockImplementation(async (name: string, args?: Record<string, unknown>) => {
      calls.push(name);
      return base(name, args);
    });
    const out = await run(ev({ ids: [A.toUpperCase(), B, A], requested_at: SEED_AT }));
    const rec = rpcCalls("record_git_data_erasure_pending").filter((c) => (c[1] as { p_outcome: string }).p_outcome === "seeded");
    expect(rec.map((c) => c[1])).toEqual([
      { p_workspace_id: A, p_outcome: "seeded", p_requested_at: "2026-10-01T00:00:00.000Z" },
      { p_workspace_id: B, p_outcome: "seeded", p_requested_at: "2026-10-01T00:00:00.000Z" },
    ]);
    expect(calls.indexOf("record_git_data_erasure_pending")).toBeLessThan(calls.indexOf("claim_git_data_erasure_pending"));
    expect(out).toMatchObject({ seeded: 2, rejectedIds: 0 });
  });

  it("a seeded LIVE id is never ledgered and so never erased", async () => {
    liveOwners.add(A);
    const out = await run(ev({ ids: [A, B], requested_at: SEED_AT }));
    expect(ledger.has(A)).toBe(false);
    expect(mockRemove).not.toHaveBeenCalledWith(A);
    expect(out).toMatchObject({ seeded: 1, ownerPresent: 1 });
    expect(warns().filter((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason === "owner_still_exists")).toHaveLength(1);
  });

  it("an owner-gone RPC that FAILS during a seed: no record call, the failure is counted, the heartbeat is red", async () => {
    failRpc.git_data_erasure_owner_gone = { message: "db down" };
    const out = await run(ev({ ids: [A, B], requested_at: SEED_AT }));
    expect(rpcCalls("record_git_data_erasure_pending")).toHaveLength(0);
    expect(ledger.size).toBe(0);
    expect(out.seeded).toBe(0);
    const seedReports = reports().filter((c) => (c[1] as { tags?: { stage?: string } }).tags?.stage === "seed");
    expect(seedReports).toHaveLength(2);
    expect(seedReports[0][0]).toBeNull(); // null err: an Error would lose its tags to the pino-mirror dedupe (#8629)
    expect(seedReports[0][1]).toMatchObject({ feature: "cron-git-data-erasure-redrive", op: REDRIVE_OP, extra: { cause: expect.stringContaining("db down") } });
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
    expect(out.ok).toBe(false);
  });

  it("a service-client SETUP failure during a seed is reported (stage=seed), turns the run red, and the claim loop still runs", async () => {
    seedLedger(A);
    mockCreateClient.mockImplementationOnce(() => {
      throw new Error("service env missing");
    });
    const out = await run(ev({ ids: [B], requested_at: SEED_AT }));
    expect(reports().filter((c) => (c[1] as { tags?: { stage?: string } }).tags?.stage === "seed")).toHaveLength(1);
    expect(out).toMatchObject({ ok: false, seeded: 0, claimed: 1, erased: 1 });
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
  });

  it("a row the claim returns as 'seeded' is NOT refreshed with the host outcome (seed provenance for owner_gone is kept)", async () => {
    seedLedger(A, B);
    ledger.get(A)!.outcome = "seeded";
    mockRemove.mockResolvedValue({ status: "refused", exitCode: 1, detail: "x" });
    const out = await run();
    expect(out).toMatchObject({ claimed: 2, pending: 2 });
    expect(calledIds("record_git_data_erasure_pending")).toEqual([B]); // A keeps 'seeded'
    expect(ledger.get(A)!.outcome).toBe("seeded");
    expect(ledger.get(B)!.outcome).toBe("refused");
    expect(rpcCalls("resolve_git_data_erasure_pending")).toHaveLength(0);
  });

  it("requested_at must be a STRICT ISO instant between 2020-01-01 and now ('1', 'Jan 1 2026', a bare date and a 2019 time are rejected)", async () => {
    for (const bad of [
      "1", "2026", "Jan 1 2026", "2026-10-01", "2026-10-01 00:00:00", "2019-12-31T23:59:59Z",
      // impossible dates that Date.parse rolls FORWARD (and so understates the Art. 12(3) age)
      "2026-02-31T00:00:00Z", "2026-04-31T10:00:00Z", "2025-02-29T00:00:00Z", "2026-10-01T24:00:00Z",
      "2026-10-01T00:60:00Z", "2026-10-01T00:00:60Z", "2026-10-01T00:00:00+24:00", "2026-13-01T00:00:00Z",
    ]) {
      mockRpc.mockClear();
      const out = await run(ev({ ids: [A], requested_at: bad }));
      expect(rpcCalls("record_git_data_erasure_pending"), bad).toHaveLength(0);
      expect(out.rejectedIds, bad).toBeGreaterThan(0);
    }
    for (const ok of ["2020-01-01T00:00:00Z", "2026-10-01T00:00:00.123Z", "2026-10-01T02:00:00+02:00", "2024-02-29T12:00:00Z"]) {
      mockRpc.mockClear();
      const out = await run(ev({ ids: [A], requested_at: ok }));
      expect(out.seeded, ok).toBe(1);
    }
  });

  it("MAX_SEED_IDS: exactly 500 ids are accepted, 501 are rejected", async () => {
    expect(MAX_SEED_IDS).toBe(500);
    const mk = (n: number) => Array.from({ length: n }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`);
    const ok = await run(ev({ ids: mk(500), requested_at: SEED_AT }));
    expect(ok.seeded).toBe(500);
    mockRpc.mockClear();
    const over = await run(ev({ ids: mk(501), requested_at: SEED_AT }));
    expect(rpcCalls("record_git_data_erasure_pending")).toHaveLength(0);
    expect(over.rejectedIds).toBe(501);
  });

  it("without a valid past requested_at NOTHING is seeded (a defaulted now() would restart the Art. 12(3) clock)", async () => {
    for (const bad of [undefined, "", "not a date", 123, new Date(Date.now() + 86_400_000).toISOString()]) {
      mockRpc.mockClear();
      const out = await run(ev({ ids: [A], requested_at: bad }));
      expect(rpcCalls("record_git_data_erasure_pending"), String(bad)).toHaveLength(0);
      expect(out.rejectedIds, String(bad)).toBeGreaterThan(0);
    }
  });

  it("validates every id: invalid ones are rejected (counted, reported without echoing them), valid ones still seed", async () => {
    const out = await run(ev({ ids: [A, "nope", 42, "", `${B}\n`, null], requested_at: SEED_AT }));
    expect(calledIds("record_git_data_erasure_pending")).toEqual([A]);
    expect(out).toMatchObject({ seeded: 1, rejectedIds: 5 });
    const rejected = reports().filter((c) => (c[1] as { tags?: { quarantine?: string } }).tags?.quarantine === "invalid_seed_id");
    expect(rejected).toHaveLength(1);
    expect(JSON.stringify(rejected)).not.toContain("nope");
  });

  it("a non-array ids payload or an oversized list seeds nothing", async () => {
    const o1 = await run(ev({ ids: "not-an-array", requested_at: SEED_AT }));
    const o2 = await run(ev({ ids: Array.from({ length: 501 }, () => A), requested_at: SEED_AT }));
    expect(rpcCalls("record_git_data_erasure_pending")).toHaveLength(0);
    expect(o1.rejectedIds).toBeGreaterThan(0);
    expect(o2.rejectedIds).toBeGreaterThan(0);
  });

  it("the scheduled run (no event data) seeds nothing", async () => {
    await run();
    expect(rpcCalls("record_git_data_erasure_pending")).toHaveLength(0);
  });

  it("parseSeedRequest: a future instant is rejected and the boundary is exclusive of the future", () => {
    const now = Date.parse("2026-10-23T12:00:00Z");
    expect(parseSeedRequest([A], "2026-10-23T12:00:00Z", now).ids).toEqual([A]);
    expect(parseSeedRequest([A], "2026-10-23T12:00:01Z", now).ids).toEqual([]);
  });
});

describe("age gauge and escalation (owner-gone rows only)", () => {
  const escalations = () => reports().filter((c) => (c[1] as { tags?: { escalation?: string } }).tags?.escalation);
  const liveWarns = () => warns().filter((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason === "live_owner_aged");

  it("emits the owner-gone and live-owner oldest ages as an info gauge every run", async () => {
    oldest = 3 * DAY;
    oldestLive = 1 * DAY;
    const out = await run();
    expect(infoSilentFallback).toHaveBeenCalledWith(null, expect.objectContaining({
      op: REDRIVE_OP,
      extra: expect.objectContaining({ oldestPendingAgeSeconds: 3 * DAY, oldestLiveOwnerAgeSeconds: 1 * DAY }),
    }));
    expect(out.oldestPendingAgeSeconds).toBe(3 * DAY);
    expect(escalations()).toHaveLength(0);
  });

  it("an idle run (nothing claimed, empty ledger) emits NO info event, does not escalate or warn, and still heartbeats green", async () => {
    const out = await run();
    expect(infoSilentFallback).not.toHaveBeenCalled(); // 96 identical info events a day otherwise
    expect(escalations()).toHaveLength(0);
    expect(liveWarns()).toHaveLength(0);
    expect(out).toMatchObject({ ok: true, oldestPendingAgeSeconds: 0 });
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: true }));
  });

  it("a run that claimed rows emits the info event even when the ages are 0", async () => {
    seedLedger(A);
    await run();
    expect(infoSilentFallback).toHaveBeenCalledTimes(1);
  });

  it("the age RPC is the owner-split one (the unsplit gauge would page about a live user's row)", async () => {
    await run();
    expect(mockRpc.mock.calls.map((c) => c[0])).toContain("git_data_erasure_pending_ages");
    expect(mockRpc.mock.calls.map((c) => c[0])).not.toContain("oldest_git_data_erasure_pending_age");
  });

  it("thresholds are the literal 20 and 28 days, and 3 days for a live owner", () => {
    expect(ESCALATE_AFTER_SECONDS).toBe(1_728_000);
    expect(HARD_STOP_AFTER_SECONDS).toBe(2_419_200);
    expect(LIVE_OWNER_WARN_AFTER_SECONDS).toBe(259_200);
  });

  it.each([
    [20 * DAY - 1, null],
    [20 * DAY, "20d"],
    [28 * DAY - 1, "20d"],
    [28 * DAY, "28d"],
    [40 * DAY, "28d"],
  ])("an owner-gone age of %s seconds escalates as %s (a Sentry error with the tag)", async (age, tier) => {
    oldest = age;
    await run();
    const e = escalations();
    if (tier === null) {
      expect(e).toHaveLength(0);
      return;
    }
    expect(e).toHaveLength(1);
    expect(e[0][1]).toMatchObject({ feature: "cron-git-data-erasure-redrive", op: REDRIVE_OP, tags: { escalation: tier } });
    const msg = (e[0][1] as { message: string }).message;
    expect(msg).toMatch(/no paging rule yet/);
    expect(msg).toMatch(/confirm git_data_erasure_owner_gone first/);
    expect(msg).not.toMatch(/hard-stop page|\bpage\b(?! rule| ing)/i);
  });

  it("a LIVE owner's row aged past any threshold NEVER escalates to 'erase by hand'", async () => {
    oldest = null;
    oldestLive = 40 * DAY;
    await run();
    expect(escalations()).toHaveLength(0);
  });

  it.each([
    [3 * DAY - 1, 0],
    [3 * DAY, 1],
    [40 * DAY, 1],
  ])("a live-owner age of %s seconds raises %s 'deletion aborted?' warn (never an error)", async (age, count) => {
    oldestLive = age;
    await run();
    expect(liveWarns()).toHaveLength(count);
    if (count) {
      expect((liveWarns()[0][1] as { message: string }).message).toMatch(/deletion aborted\?.*do NOT erase/);
    }
    expect(escalations()).toHaveLength(0);
  });

  it.each([
    ["20d", 21 * DAY, "escalation"],
    ["28d", 29 * DAY, "escalation"],
    ["live", null, "live"],
  ] as const)("the %s tier re-emits at most once per hour per process, not on every 15-minute run", async (_tier, goneAge, kind) => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-23T00:00:00Z"));
    oldest = goneAge;
    oldestLive = kind === "live" ? 5 * DAY : null;
    const count = () => (kind === "live" ? liveWarns().length : escalations().length);
    for (let i = 0; i < 4; i += 1) {
      await run();
      vi.advanceTimersByTime(15 * 60 * 1000);
    }
    expect(count()).toBe(1);
    vi.setSystemTime(new Date(Date.parse("2026-10-23T00:00:00Z") + ESCALATION_REPEAT_MS));
    await run();
    expect(count()).toBe(2);
  });

  it("the live warn and the owner-gone escalation are throttled INDEPENDENTLY: both fire in the same run", async () => {
    oldest = 25 * DAY;
    oldestLive = 5 * DAY;
    await run();
    expect(escalations()).toHaveLength(1);
    expect(liveWarns()).toHaveLength(1);
  });

  it("the 20d and 28d tiers are throttled independently: 21 days then 29 days inside one hour raise both", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-23T00:00:00Z"));
    oldest = 21 * DAY;
    await run();
    vi.advanceTimersByTime(15 * 60 * 1000);
    oldest = 29 * DAY;
    await run();
    expect(escalations().map((c) => (c[1] as { tags: { escalation: string } }).tags.escalation)).toEqual(["20d", "28d"]);
  });

  it("a stuck row is never purged: nothing resolves it without an erased outcome", async () => {
    oldest = 40 * DAY;
    seedLedger(A);
    mockRemove.mockResolvedValue({ status: "refused", exitCode: 1, detail: "x" });
    await run();
    expect(rpcCalls("resolve_git_data_erasure_pending")).toHaveLength(0);
    expect(ledger.has(A)).toBe(true);
  });

  it("an age-gauge failure is reported and turns the heartbeat red", async () => {
    failRpc.git_data_erasure_pending_ages = { message: "db down" };
    await run();
    expect(reports().some((c) => (c[1] as { tags?: { stage?: string } }).tags?.stage === "age-gauge")).toBe(true);
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
  });

  it("an age-gauge failure does NOT suppress the fleet warns (owner_still_exists, no_erasure_progress)", async () => {
    failRpc.git_data_erasure_pending_ages = { message: "db down" };
    seedLedger(A, B);
    liveOwners.add(A);
    mockRemove.mockResolvedValue({ status: "refused", exitCode: 1, detail: "x" });
    await run();
    const reasons = warns().map((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason);
    expect(reasons).toContain("owner_still_exists");
    expect(reasons).toContain("no_erasure_progress");
  });

  it("a clean run warns about nothing", async () => {
    seedLedger(A);
    await run();
    expect(warns()).toHaveLength(0);
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: true }));
  });
});

describe("privacy", () => {
  it("no id appears in any Sentry report, info/warn event or log line", async () => {
    seedLedger(A, B);
    liveOwners.add(C);
    oldest = 25 * DAY;
    oldestLive = 5 * DAY;
    mockRemove.mockImplementation(async (id: string) => {
      if (id === B) throw new Error(`refusing unsafe workspace_id ${id}`);
      return { status: "refused", exitCode: 1, detail: `dir ${id}` };
    });
    await run({ data: { ids: [C, "bad"], requested_at: "2026-10-01T00:00:00Z" } });
    const sink = JSON.stringify([
      reports(), warns(),
      (infoSilentFallback as ReturnType<typeof vi.fn>).mock.calls,
      logger.info.mock.calls, logger.warn.mock.calls, logger.error.mock.calls,
    ]);
    for (const id of [A, B, C]) expect(sink).not.toContain(id);
  });
});

describe("idempotence / double-run", () => {
  it("two concurrent runs against a stamping claim never drive the same id twice", async () => {
    seedLedger(A, B);
    const [r1, r2] = await Promise.all([run(), run()]);
    expect(mockRemove).toHaveBeenCalledTimes(2);
    expect(r1.claimed + r2.claimed).toBe(2);
    expect(ledger.size).toBe(0);
  });
});

describe("run result (run-log ok/errorSummary) and Sentry stage tags", () => {
  const stageReports = (stage: string) =>
    reports().filter((c) => (c[1] as { tags?: { stage?: string } }).tags?.stage === stage);

  // [failing rpc, stage tag, setup]
  const failures: Array<[string, string, () => void]> = [
    ["claim_git_data_erasure_pending", "claim", () => {}],
    ["git_data_erasure_owner_gone", "owner-check", () => seedLedger(A)],
    ["resolve_git_data_erasure_pending", "resolve", () => seedLedger(A)],
    [
      "record_git_data_erasure_pending",
      "record",
      () => {
        seedLedger(A);
        mockRemove.mockResolvedValue({ status: "refused", exitCode: 1, detail: "x" });
      },
    ],
    ["git_data_erasure_pending_ages", "age-gauge", () => {}],
  ];

  it.each(failures)(
    "a failed %s returns ok:false with the stage in errorSummary, and the stage event carries its tags (null err + cause in extra)",
    async (rpcName, stage, setup) => {
      setup();
      failRpc[rpcName] = { message: "db down" };
      const out = await run();
      expect(out.ok).toBe(false);
      expect(out.errorSummary).toContain(stage);
      expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
      const r = stageReports(stage);
      expect(r).toHaveLength(1);
      expect(r[0][0]).toBeNull(); // an Error here would be deduplicated against the pino mirror, losing every tag (#8629)
      expect(r[0][1]).toMatchObject({
        feature: "cron-git-data-erasure-redrive",
        op: REDRIVE_OP,
        tags: { stage },
        extra: { fn: "cron-git-data-erasure-redrive", cause: expect.stringContaining("db down") },
      });
      expect(typeof (r[0][1] as { message: string }).message).toBe("string");
    },
  );

  it.each(failures)("a THROWN rejection from %s (socket hang up) is contained: no throw, stage reported, ok:false", async (rpcName, stage, setup) => {
    setup();
    const base = mockRpc.getMockImplementation()!;
    mockRpc.mockImplementation(async (name: string, args?: Record<string, unknown>) => {
      if (name === rpcName) throw new Error("socket hang up");
      return base(name, args);
    });
    const out = await run();
    expect(out.ok).toBe(false);
    expect(out.errorSummary).toContain(stage);
    expect(stageReports(stage)).toHaveLength(1);
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
  });

  it("a normal run, and a run where the host refuses, return ok:true with no errorSummary (a refusal is the ledger's normal state)", async () => {
    seedLedger(A);
    const normal = await run();
    expect(normal.ok).toBe(true);
    expect(normal).not.toHaveProperty("errorSummary");
    seedLedger(B);
    mockRemove.mockResolvedValue({ status: "refused", exitCode: 1, detail: "x" });
    const refused = await run();
    expect(refused).toMatchObject({ ok: true, pending: 1 });
    expect(refused).not.toHaveProperty("errorSummary");
    expect(postSentryHeartbeat).toHaveBeenLastCalledWith(expect.objectContaining({ ok: true }));
  });

  it("errorSummary names stages only (never an id or a row value)", async () => {
    seedLedger(A);
    failRpc.resolve_git_data_erasure_pending = { message: `boom for ${A}` };
    const out = await run();
    expect(out.errorSummary).toBe("failed stages: resolve");
    expect(out.errorSummary).not.toContain(A);
  });
});

describe("resolve outcomes", () => {
  it("a resolve failure is NOT 'driven': no no_erasure_progress warn, and byStatus does not claim 'erased'", async () => {
    seedLedger(A);
    failRpc.resolve_git_data_erasure_pending = { message: "db down" };
    const out = await run();
    expect(out).toMatchObject({ claimed: 1, erased: 0, pending: 1, ok: false });
    expect(warns().some((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason === "no_erasure_progress")).toBe(false);
    expect(infoSilentFallback).toHaveBeenCalledWith(null, expect.objectContaining({
      extra: expect.objectContaining({ driven: 0, byStatus: { resolve_failed: 1 } }),
    }));
  });

  it("a NULL resolve (the row was already resolved by a racing run) is still an erasure, with a distinct byStatus key and no failure", async () => {
    seedLedger(A);
    const base = mockRpc.getMockImplementation()!;
    mockRpc.mockImplementation(async (name: string, args?: Record<string, unknown>) =>
      name === "resolve_git_data_erasure_pending" ? { data: null, error: null } : base(name, args),
    );
    const out = await run();
    expect(out).toMatchObject({ claimed: 1, erased: 1, ok: true });
    expect(infoSilentFallback).toHaveBeenCalledWith(null, expect.objectContaining({
      extra: expect.objectContaining({ byStatus: { already_resolved: 1 } }),
    }));
  });
});

describe("host refusal reason survives into the events", () => {
  const noProgress = () =>
    warns().filter((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason === "no_erasure_progress");

  it.each([
    ["remove_key_absent: GIT_REMOVE_SSH_PRIVATE_KEY is absent", "unconfigured:remove_key_absent"],
    ["pin_absent: GIT_DATA_SSH_HOST_KEY is unset", "unconfigured:pin_absent"],
    ["pin_invalid: bad base64", "unconfigured:pin_invalid"],
    ["ssh_client_absent: spawn ssh ENOENT, nothing dialed", "unconfigured:ssh_client_absent"],
    ["something unforeseen", "unconfigured:other"],
  ])("unconfigured (%s) is keyed %s in byStatus; only the reason word is shipped", async (detail, key) => {
    seedLedger(A);
    mockRemove.mockResolvedValue({ status: "unconfigured", detail });
    await run();
    const w = noProgress();
    expect(w).toHaveLength(1);
    const extra = (w[0][1] as { extra: { byStatus: Record<string, number>; hostDetails: string[] } }).extra;
    expect(extra.byStatus).toEqual({ [key]: 1 });
    expect(extra.hostDetails).toEqual([]); // the free text after the reason word is not guaranteed scrubbed
    expect(JSON.stringify(w)).not.toContain(detail);
  });

  it("refused rows ship up to 3 DISTINCT id-scrubbed host details and their exit codes", async () => {
    const ids = [A, B, C, "11111111-1111-4111-8111-111111111111"];
    seedLedger(...ids);
    const codes: Record<string, number> = { [A]: 3, [B]: 3, [C]: 1 };
    mockRemove.mockImplementation(async (id: string) => ({
      status: "refused",
      exitCode: codes[id] ?? 7,
      detail: id === C ? "store not mounted" : `dir ${id} frozen`,
    }));
    await run();
    const w = noProgress();
    expect(w).toHaveLength(1);
    const extra = (w[0][1] as { extra: { hostDetails: string[]; exitCodes: number[]; driven: number } }).extra;
    expect(extra.driven).toBe(4);
    expect(extra.hostDetails).toEqual(["dir WORKSPACE_ID_REDACTED frozen", "store not mounted"]);
    expect(extra.exitCodes).toEqual([3, 1, 7]);
    for (const id of ids) expect(JSON.stringify(w)).not.toContain(id);
  });

  it("unauthorized / unreachable details are shipped (scrubbed) too", async () => {
    seedLedger(A);
    mockRemove.mockResolvedValue({ status: "unauthorized", detail: "Permission denied (publickey)" });
    await run();
    const extra = (noProgress()[0][1] as { extra: { hostDetails: string[]; exitCodes: number[] } }).extra;
    expect(extra.hostDetails).toEqual(["Permission denied (publickey)"]);
    expect(extra.exitCodes).toEqual([]);
  });
});

describe("no_erasure_progress is throttled like the other tiers", () => {
  it("raises at most once per hour per process, not on every 15-minute run", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-23T00:00:00Z"));
    seedLedger(A);
    mockRemove.mockResolvedValue({ status: "refused", exitCode: 1, detail: "x" });
    const count = () =>
      warns().filter((c) => (c[1] as { tags?: { reason?: string } }).tags?.reason === "no_erasure_progress").length;
    for (let i = 0; i < 4; i += 1) {
      ledger.forEach((r) => (r.stamped = false)); // the claim backoff elapsed
      await run();
      vi.advanceTimersByTime(15 * 60 * 1000);
    }
    expect(count()).toBe(1);
    vi.setSystemTime(new Date(Date.parse("2026-10-23T00:00:00Z") + ESCALATION_REPEAT_MS));
    ledger.forEach((r) => (r.stamped = false));
    await run();
    expect(count()).toBe(2);
  });
});

describe("replay (Inngest re-enters the handler after every step and answers finished steps from memo)", () => {
  const scenarios: Array<[string, () => void, { name: string; data: Record<string, unknown> } | undefined]> = [
    ["happy path (all erased)", () => seedLedger(A, B), undefined],
    [
      "mixed outcomes (erased, refused, thrown, live owner, aged)",
      () => {
        seedLedger(A, B, C, "11111111-1111-4111-8111-111111111111");
        liveOwners.add("11111111-1111-4111-8111-111111111111");
        oldest = 21 * DAY;
        oldestLive = 4 * DAY;
        mockRemove.mockImplementation(async (id: string) => {
          if (id === B) return { status: "refused", exitCode: 3, detail: "frozen" };
          if (id === C) throw new Error("boom");
          return { status: "erased" };
        });
      },
      undefined,
    ],
    [
      "manual seed (gone + live ids)",
      () => {
        liveOwners.add(B);
        mockRemove.mockResolvedValue({ status: "refused", exitCode: 1, detail: "x" });
      },
      { name: "cron/git-data-erasure-redrive.manual-trigger", data: { ids: [A, B], requested_at: "2026-10-01T00:00:00Z" } },
    ],
  ];

  it.each(scenarios)("%s: the replayed result equals the run-once result and each id is driven once", async (_n, setup, event) => {
    setup();
    const once = await run(event);
    const onceRemoves = mockRemove.mock.calls.length;
    const onceClaims = rpcCalls("claim_git_data_erasure_pending").length;

    resetWorld();
    setup();
    const replayed = await runReplaying(event);
    expect(replayed).toEqual(once);
    expect(mockRemove.mock.calls.length).toBe(onceRemoves);
    expect(rpcCalls("claim_git_data_erasure_pending").length).toBe(onceClaims);
    expect(postSentryHeartbeat).toHaveBeenCalledTimes(1);
  });
});

describe("registration", () => {
  it("is a ~15-minute cron with the derived manual-trigger event, serialised", () => {
    expect(cronGitDataErasureRedrive).toBeDefined();
    const src = readFileSync(
      path.join(__dirname, "../../../server/inngest/functions/cron-git-data-erasure-redrive.ts"),
      "utf8",
    );
    expect(src).toContain('{ cron: "*/15 * * * *" }');
    expect(src).toContain('{ event: "cron/git-data-erasure-redrive.manual-trigger" }');
    expect(src).toMatch(/\{ scope: "fn", limit: 1 \}/);
  });

  it("runs on a DEDICATED account lane keyed on its own function id, never the shared cron-platform lane", () => {
    const src = readFileSync(
      path.join(__dirname, "../../../server/inngest/functions/cron-git-data-erasure-redrive.ts"),
      "utf8",
    );
    // claude-eval holds "cron-platform" for 50-70 minutes: sharing it would delay a 15-minute cron past its
    // 30-minute Sentry check-in margin (cron-approval-expiry and cron-bot-pr-reaper opt out for the same reason).
    expect(src).toContain(`{ scope: "account", key: '"cron-git-data-erasure-redrive"', limit: 1 }`);
    expect(src).not.toMatch(/scope: "account", key: '"cron-platform"'/);
  });

  it("never claims a hard-stop PAGE it does not have", () => {
    const src = readFileSync(
      path.join(__dirname, "../../../server/inngest/functions/cron-git-data-erasure-redrive.ts"),
      "utf8",
    );
    expect(src).not.toMatch(/hard-stop page/i);
    expect(src).toMatch(/NO PAGING RULE/);
    expect(src).toContain("#10914");
  });
});
