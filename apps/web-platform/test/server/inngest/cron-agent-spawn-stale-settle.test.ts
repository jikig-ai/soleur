// cron-agent-spawn-stale-settle test battery (#8839).
//
// THE NEGATIVE PIN IS THE POINT. The sweep's failure class is "a live run's
// row marked stale" — a Working row whose Inngest run is still alive must
// NEVER be selected or written. That is asserted as a test row here (the
// live-run-must-survive case), not left as a comment: `isStaleWorkingRow`
// refuses a row whose last turn-write is inside finish-timeout+margin, and
// the handler-level case proves the UPDATE never touches it.
//
// Fixtures are synthesized (cq-test-fixtures-synthesized-only): ids are
// fabricated UUIDs, timestamps derived from a pinned `now`.

import { describe, expect, it, vi, beforeEach } from "vitest";

// client.ts throws on missing signing keys at module load; test-only values,
// set before ANY import touches the client (vi.hoisted runs ahead of imports).
vi.hoisted(() => {
  process.env.INNGEST_SIGNING_KEY ||= "signkey-test-0000000000000000";
  process.env.INNGEST_EVENT_KEY ||= "test-event-key";
});

const reportSpawnDeadLetter = vi.hoisted(() => vi.fn());
const reportSilentFallback = vi.hoisted(() => vi.fn());
const postSentryHeartbeat = vi.hoisted(() => vi.fn(async () => undefined));

vi.mock("@sentry/nextjs", async (importOriginal) => ({
  ...(await importOriginal<object>()),
  captureMessage: vi.fn(),
  captureException: vi.fn(),
}));
vi.mock("@/server/spawn-dead-letter", async (importOriginal) => ({
  ...(await importOriginal<object>()),
  reportSpawnDeadLetter,
}));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<object>()),
  reportSilentFallback,
  warnSilentFallback: vi.fn(),
}));
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => ({
  ...(await importOriginal<object>()),
  postSentryHeartbeat,
}));

interface Filter {
  col: string;
  op: string;
  val: unknown;
}
interface Row {
  id: string;
  user_id: string;
  message_id: string;
  action_class: string;
  source_ref: string | null;
  current_turn_started_at: string | null;
  created_at: string;
  failure_reason: string | null;
  acknowledged_at: string | null;
  undone_at: string | null;
  cancellation_requested_at?: string | null;
  [k: string]: unknown;
}

const db = vi.hoisted(() => ({
  rows: [] as unknown[],
  ops: [] as { table: string; mode: string; filters: Filter[]; patch?: Record<string, unknown> }[],
  failAll: null as null | { code: string; message: string },
}));

function matches(row: Row, filters: Filter[]): boolean {
  return filters.every(({ col, op, val }) => {
    const cell = (row as Record<string, unknown>)[col];
    if (op === "lt") return String(cell) < String(val);
    if (op === "or") {
      // Minimal evaluator for the staleBeforeIso conjunct:
      // and(current_turn_started_at.is.null,created_at.lt.X) OR
      // current_turn_started_at.lt.X
      const iso = String(val).match(/lt\.([^,)]+)/)?.[1] ?? "";
      const ctsa = row.current_turn_started_at as string | null;
      return (ctsa == null && String(row.created_at) < iso) || (ctsa != null && ctsa < iso);
    }
    return cell === val;
  });
}

class FakeQuery {
  private mode: "select" | "update" = "select";
  private filters: Filter[] = [];
  private patch: Record<string, unknown> | undefined;
  private returning = false;
  constructor(private table: string) {}
  select(_cols: string) {
    if (this.mode === "update") this.returning = true;
    return this;
  }
  update(patch: Record<string, unknown>) {
    this.mode = "update";
    this.patch = patch;
    return this;
  }
  eq(col: string, val: unknown) {
    this.filters.push({ col, op: "eq", val });
    return this;
  }
  is(col: string, val: unknown) {
    this.filters.push({ col, op: "is", val });
    return this;
  }
  lt(col: string, val: unknown) {
    this.filters.push({ col, op: "lt", val });
    return this;
  }
  or(expr: string) {
    this.filters.push({ col: "__or__", op: "or", val: expr });
    return this;
  }
  order(_col: string, _opts?: unknown) {
    return this;
  }
  limit(_n: number) {
    return this;
  }
  maybeSingle() {
    return this.execute().then(({ data, error }) => ({
      data: Array.isArray(data) ? (data[0] ?? null) : data,
      error,
    }));
  }
  then<R1>(onOk: (v: { data: unknown; error: unknown }) => R1) {
    return this.execute().then(onOk);
  }
  private async execute(): Promise<{ data: unknown; error: unknown }> {
    db.ops.push({ table: this.table, mode: this.mode, filters: [...this.filters], patch: this.patch });
    if (db.failAll) return { data: null, error: db.failAll };
    const hit = (db.rows as Row[]).filter((r) => matches(r, this.filters));
    if (this.mode === "update") {
      for (const r of hit) Object.assign(r, this.patch);
      return { data: this.returning ? hit.map((r) => ({ id: r.id })) : null, error: null };
    }
    return { data: hit.map((r) => ({ ...r })), error: null };
  }
}

vi.mock("@/lib/supabase/service", () => ({
  getServiceClient: () => ({ from: (t: string) => new FakeQuery(t) }),
}));

import {
  cronAgentSpawnStaleSettleHandler,
  isStaleWorkingRow,
  STALE_WORKING_MARGIN_MS,
} from "@/server/inngest/functions/cron-agent-spawn-stale-settle";
import { FINISH_TIMEOUT_MS } from "@/server/inngest/functions/agent-on-spawn-requested";
import { runLikeInngest } from "../../helpers/inngest-step-harness";

const NOW = Date.parse("2026-11-05T12:00:00Z");
const BOUND_MS = FINISH_TIMEOUT_MS + STALE_WORKING_MARGIN_MS;

const U = (n: number) =>
  `00000000-0000-4000-8000-00000000000${n}` as string;

function row(over: Partial<Row>): Row {
  return {
    id: U(1),
    user_id: U(2),
    message_id: U(3),
    action_class: "engineering.pr_review_pending",
    source_ref: "jikig-ai/soleur#1",
    current_turn_started_at: new Date(NOW - 60 * 60_000).toISOString(),
    created_at: new Date(NOW - 2 * 60 * 60_000).toISOString(),
    failure_reason: null,
    acknowledged_at: null,
    undone_at: null,
    ...over,
  };
}

beforeEach(() => {
  db.rows = [];
  db.ops = [];
  db.failAll = null;
  vi.useRealTimers();
  reportSpawnDeadLetter.mockClear();
  reportSilentFallback.mockClear();
  postSentryHeartbeat.mockClear();
});

describe("isStaleWorkingRow — the live-run discriminator", () => {
  it("marks a Working row older than finish-timeout+margin stale", () => {
    expect(
      isStaleWorkingRow(
        row({ current_turn_started_at: new Date(NOW - BOUND_MS - 1).toISOString() }),
        NOW,
      ),
    ).toBe(true);
  });

  it("LIVE-RUN-MUST-SURVIVE: a Working row inside the bound is never stale", () => {
    // A live run writes current_turn_started_at at each turn start and cannot
    // outlive timeouts.finish; a fresh timestamp is a live run by construction.
    expect(
      isStaleWorkingRow(
        row({ current_turn_started_at: new Date(NOW - 60_000).toISOString() }),
        NOW,
      ),
    ).toBe(false);
    // …and the boundary itself: at exactly bound - 1ms the run can still be alive.
    expect(
      isStaleWorkingRow(
        row({ current_turn_started_at: new Date(NOW - BOUND_MS + 1).toISOString() }),
        NOW,
      ),
    ).toBe(false);
  });

  it("falls back to created_at for a run lost before turn-1", () => {
    expect(
      isStaleWorkingRow(
        row({ current_turn_started_at: null, created_at: new Date(NOW - BOUND_MS - 1).toISOString() }),
        NOW,
      ),
    ).toBe(true);
    expect(
      isStaleWorkingRow(
        row({ current_turn_started_at: null, created_at: new Date(NOW - 60_000).toISOString() }),
        NOW,
      ),
    ).toBe(false);
  });

  it("a terminal row is never a candidate (the Working triple)", () => {
    const stale = { current_turn_started_at: new Date(NOW - BOUND_MS - 1).toISOString() };
    expect(isStaleWorkingRow(row({ ...stale, failure_reason: "leader_internal_error" }), NOW)).toBe(false);
    expect(isStaleWorkingRow(row({ ...stale, acknowledged_at: new Date(NOW).toISOString() }), NOW)).toBe(false);
    expect(isStaleWorkingRow(row({ ...stale, undone_at: new Date(NOW).toISOString() }), NOW)).toBe(false);
  });

  it("an unparseable timestamp is never guessed stale", () => {
    expect(
      isStaleWorkingRow(row({ current_turn_started_at: "not-a-date", created_at: "also-not" }), NOW),
    ).toBe(false);
  });
});

describe("cronAgentSpawnStaleSettleHandler", () => {
  function drive() {
    return runLikeInngest(
      (ctx) => cronAgentSpawnStaleSettleHandler({ step: ctx.step, logger: console } as never),
      { maxAttempts: 1, maxInvocations: 200 },
    );
  }

  it("settles a stale Working row via the shared settle path and reports (stale_working)", async () => {
    vi.setSystemTime(NOW);
    db.rows = [row({})];
    const out = await drive();
    expect(out.outcome).toBe("returned");
    const v = out.value as { settled: number; candidates: number };
    expect(v.settled).toBe(1);
    expect((db.rows[0] as Row).failure_reason).toBe("leader_internal_error");
    expect(reportSpawnDeadLetter).toHaveBeenCalledWith(
      expect.objectContaining({ lifecycle: "stale_working", reason: "leader_internal_error" }),
    );
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: true }));
  });

  it("a stale row with a pending Stop settles leader_internal_error (lost run — the Stop never reached it)", async () => {
    vi.setSystemTime(NOW);
    db.rows = [row({ cancellation_requested_at: new Date(NOW - BOUND_MS - 1).toISOString() })];
    const out = await drive();
    const v = out.value as { settled: number };
    expect(v.settled).toBe(1);
    expect((db.rows[0] as Row).failure_reason).toBe("leader_internal_error");
    expect(reportSpawnDeadLetter).toHaveBeenCalledWith(
      expect.objectContaining({ reason: "leader_internal_error", lifecycle: "stale_working" }),
    );
  });

  it("LIVE-RUN-MUST-SURVIVE at the handler level: a fresh Working row is never UPDATEd", async () => {
    vi.setSystemTime(NOW);
    const live = row({ current_turn_started_at: new Date(NOW - 60_000).toISOString() });
    db.rows = [live];
    const out = await drive();
    const v = out.value as { settled: number; candidates: number };
    expect(v.candidates).toBe(0);
    expect(v.settled).toBe(0);
    expect((db.rows[0] as Row).failure_reason).toBeNull();
    // The settle UPDATE never ran: ops contain only the one select.
    expect(db.ops.filter((o) => o.mode === "update")).toHaveLength(0);
    expect(reportSpawnDeadLetter).not.toHaveBeenCalled();
  });

  it("skips a row a concurrent writer already settled (zero-row UPDATE, no report)", async () => {
    vi.setSystemTime(NOW);
    // failure_reason set between the select's predicate and the UPDATE would
    // be the live race; model it by pre-settling: the select's .is(null)
    // filters exclude it, so it is not even a candidate — assert that.
    db.rows = [row({ failure_reason: "leader_internal_error" })];
    const out = await drive();
    const v = out.value as { candidates: number; skipped: number };
    expect(v.candidates).toBe(0);
    expect(reportSpawnDeadLetter).not.toHaveBeenCalled();
  });

  it("a failed select reports, heartbeats !ok, and settles nothing", async () => {
    vi.setSystemTime(NOW);
    db.failAll = { code: "XX000", message: "db down" };
    db.rows = [row({})];
    const out = await drive();
    const v = out.value as { ok: boolean; settled: number };
    expect(v.ok).toBe(false);
    expect(v.settled).toBe(0);
    expect(reportSilentFallback).toHaveBeenCalled();
    expect(postSentryHeartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
    expect((db.rows[0] as Row).failure_reason).toBeNull();
  });
});
