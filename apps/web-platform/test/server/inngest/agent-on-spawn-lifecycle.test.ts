/**
 * #8803 — a leader-loop run the handler never finished (a retry-exhausted
 * throw, the `finish` timeout, an Inngest-level cancel) is settled by
 * `agent-on-spawn-settle`, reached from the handler's `onFailure` forward and
 * from `inngest/function.cancelled`.
 *
 * The service client is an IN-MEMORY fake over fixture rows that APPLIES the
 * recorded `.eq` / `.is(col, null)` filters, so an UPDATE returns the rows that
 * really match and the assertions are about behaviour (rows written, events
 * sent), not call arguments. The dead-letter reporter is REAL; only
 * `@sentry/nextjs` is mocked, partially (`importOriginal`): the real inngest
 * client loads the correlation middleware, which needs the rest of the SDK.
 *
 * The REAL inngest client is imported (NEXT_PHASE hoist, as model-tiers.test.ts
 * does) so the registration tests read the SDK's own generated config.
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";

import { beforeEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const { captureExceptionSpy, captureMessageSpy, addBreadcrumbSpy } = vi.hoisted(() => ({
  captureExceptionSpy: vi.fn(),
  captureMessageSpy: vi.fn(),
  addBreadcrumbSpy: vi.fn(),
}));
vi.mock("@sentry/nextjs", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@sentry/nextjs")>()),
  captureException: captureExceptionSpy,
  captureMessage: captureMessageSpy,
  addBreadcrumb: addBreadcrumbSpy,
}));

// --- In-memory action_sends ---------------------------------------------------

interface FixtureRow {
  id: string;
  user_id: string | null;
  message_id: string;
  failure_reason: string | null;
  acknowledged_at: string | null;
  undone_at: string | null;
  cancellation_requested_at: string | null;
  reversal_handles: unknown[] | null;
  artifact_url: string | null;
  current_turn: number | null;
}

type Filter = { col: string; op: "eq" | "is"; val: unknown };
interface DbOp {
  table: string;
  mode: "select" | "update";
  filters: Filter[];
  patch?: Record<string, unknown>;
}

const db = vi.hoisted(() => ({
  rows: [] as unknown[],
  ops: [] as unknown[],
  // Every call returns this error when set.
  failAll: null as null | { code: string; message: string },
  // Only the Stop read (select of cancellation_requested_at) fails.
  failStopRead: false,
}));

function matches(row: FixtureRow, filters: Filter[]): boolean {
  return filters.every(({ col, val }) => (row as unknown as Record<string, unknown>)[col] === val);
}

// uuid columns: Postgres rejects a non-UUID operand with 22P02 rather than
// matching zero rows, so the fake must too.
const UUID_COLS = new Set(["id", "user_id", "message_id"]);
const UUID_SHAPE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

class FakeQuery {
  private mode: "select" | "update" = "select";
  private filters: Filter[] = [];
  private patch: Record<string, unknown> | undefined;
  private selectCols = "";
  // An UPDATE returns rows ONLY when `.select()` is chained: without it the
  // real client answers `data: null`, and the settle would never page.
  private returning = false;
  constructor(private table: string) {}
  select(cols: string) {
    if (this.mode === "select") this.selectCols = cols;
    else this.returning = true;
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
  maybeSingle() {
    return this.execute().then(({ data, error }) => {
      if (Array.isArray(data) && data.length > 1) {
        return { data: null, error: { code: "PGRST116", message: "multiple rows" } };
      }
      return { data: Array.isArray(data) ? (data[0] ?? null) : data, error };
    });
  }
  then<R1, R2>(
    onOk: (v: { data: unknown; error: unknown }) => R1,
    onErr?: (e: unknown) => R2,
  ) {
    return this.execute().then(onOk, onErr);
  }
  private async execute(): Promise<{ data: unknown; error: unknown }> {
    (db.ops as DbOp[]).push({
      table: this.table,
      mode: this.mode,
      filters: [...this.filters],
      patch: this.patch,
    });
    if (db.failAll) return { data: null, error: db.failAll };
    const badUuid = this.filters.find(
      (f) => f.op === "eq" && UUID_COLS.has(f.col) && !UUID_SHAPE.test(String(f.val)),
    );
    if (badUuid) {
      return { data: null, error: { code: "22P02", message: `invalid input syntax for type uuid: "${String(badUuid.val)}"` } };
    }
    if (
      this.mode === "select" &&
      db.failStopRead &&
      this.selectCols.includes("cancellation_requested_at")
    ) {
      return { data: null, error: { code: "XX000", message: "stop read failed" } };
    }
    const hit = (db.rows as FixtureRow[]).filter((r) => matches(r, this.filters));
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
  agentOnSpawnRequested,
  agentOnSpawnRequestedOnFailure,
  agentOnSpawnSettle,
  agentOnSpawnSettleHandler,
  FINISH_TIMEOUT_MS,
} from "@/server/inngest/functions/agent-on-spawn-requested";
import { deriveTodayCardState } from "@/components/dashboard/today-card-state-matrix";
import { FAILURE_REASON_COPY } from "@/components/dashboard/failure-reason-copy";
import { runLikeInngest } from "../../helpers/inngest-step-harness";
import { stripComments } from "../../helpers/strip-comments";
import { inngest } from "@/server/inngest/client";

// --- Fixtures (synthesized, cq-test-fixtures-synthesized-only) -----------------

const FOUNDER = "0f4c1d2e-3a5b-4c6d-8e9f-a0b1c2d3e4f5";
const OTHER_FOUNDER = "7a1b2c3d-4e5f-4061-8a7b-9c0d1e2f3a4b";
const MESSAGE = "5d6e7f80-9a1b-4c2d-8e3f-405162738495";
const ACTION_SEND = "2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091";
const FAILED_RUN = "01M3C0B5Z6VQSF5930F1K8GQTN";
const CLASS = "engineering.pr_review_pending";
const QUEUED_AT = 1_790_330_000_000;

function fixtureRow(overrides: Partial<FixtureRow> = {}): FixtureRow {
  return {
    id: ACTION_SEND,
    user_id: FOUNDER,
    message_id: MESSAGE,
    failure_reason: null,
    acknowledged_at: null,
    undone_at: null,
    cancellation_requested_at: null,
    reversal_handles: null,
    artifact_url: null,
    current_turn: 3,
    ...overrides,
  };
}

function original(overrides: Record<string, unknown> = {}, ts: number | undefined = QUEUED_AT) {
  return {
    name: "agent.spawn.requested",
    ...(ts === undefined ? {} : { ts }),
    data: {
      founderId: FOUNDER,
      messageId: MESSAGE,
      actionClass: CLASS,
      sourceRef: "pr-acme:repo:7",
      actionSendId: ACTION_SEND,
      ...overrides,
    },
  };
}

/** The forward `onFailure` sends: `agent.spawn.orphaned`. */
function orphanedEnvelope(opts: { ts?: number; orig?: unknown } = {}) {
  return {
    name: "agent.spawn.orphaned",
    data: {
      event: opts.orig ?? original(),
      run_id: FAILED_RUN,
      error: { name: "Error", message: "turn-2-progress-write failed" },
      ts: opts.ts ?? QUEUED_AT + 30_000,
    },
  };
}

/** The server's `inngest/function.cancelled` shape, as measured on v1.19.4 (no `error`). */
function cancelledEnvelope(opts: { elapsedMs?: number | null; orig?: unknown } = {}) {
  const elapsed = opts.elapsedMs === undefined ? 60_000 : opts.elapsedMs;
  return {
    name: "inngest/function.cancelled",
    ...(elapsed === null ? {} : { ts: QUEUED_AT + elapsed }),
    data: {
      _inngest: { status: "Cancelled" },
      event: opts.orig ?? original(),
      events: [original()],
      function_id: "soleur-runtime-agent-on-spawn-requested",
      run_id: FAILED_RUN,
    },
  };
}

function makeSettleStep() {
  const ops: string[] = [];
  return {
    ops,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      ops.push(name);
      return cb();
    },
    async sleep(id: string, _duration: string): Promise<void> {
      ops.push(id);
    },
  };
}

type Ctx = { level: string; tags: Record<string, string>; extra: Record<string, unknown> & { err?: { message?: string } } };

/** Every dead-letter message event sent to Sentry. */
function deadLetters(): [string, Ctx][] {
  return (captureMessageSpy.mock.calls as [string, Ctx][]).filter(([m]) =>
    m.startsWith("agent-on-spawn deadlettered:"),
  );
}

function allSentryText(): string {
  return JSON.stringify([
    captureMessageSpy.mock.calls,
    captureExceptionSpy.mock.calls,
    addBreadcrumbSpy.mock.calls,
  ]);
}

function row(): FixtureRow {
  return (db.rows as FixtureRow[])[0];
}

beforeEach(() => {
  captureExceptionSpy.mockReset();
  captureMessageSpy.mockReset();
  addBreadcrumbSpy.mockReset();
  db.rows = [fixtureRow()];
  db.ops = [];
  db.failAll = null;
  db.failStopRead = false;
});

// --- T7 ----------------------------------------------------------------------

describe("onFailure forwards; it never settles in place (T7)", () => {
  it("sends exactly one agent.spawn.orphaned carrying the ORPHANED run id, no DB call, no report", async () => {
    const sendEvent = vi.fn(async () => undefined);
    await agentOnSpawnRequestedOnFailure({
      event: {
        name: "inngest/function.failed",
        ts: QUEUED_AT + 30_000,
        data: {
          event: original(),
          run_id: FAILED_RUN,
          function_id: "soleur-runtime-agent-on-spawn-requested",
          error: { error: "Error", name: "Error", message: "turn-2-progress-write failed", stack: "s" },
        },
      },
      step: { sendEvent },
      // The -failure function's OWN run — never the one to settle.
      runId: "01FAILUREFUNCTIONOWNRUNID00",
    } as never);
    expect(sendEvent).toHaveBeenCalledTimes(1);
    const [id, payload] = sendEvent.mock.calls[0] as unknown as [
      string,
      { name: string; data: Record<string, unknown> },
    ];
    expect(id).toBe("forward-orphan");
    expect(payload.name).toBe("agent.spawn.orphaned");
    expect(payload.data).toEqual({
      event: original(),
      run_id: FAILED_RUN,
      error: { name: "Error", message: "turn-2-progress-write failed" },
      ts: QUEUED_AT + 30_000,
    });
    expect(db.ops).toHaveLength(0);
    expect(captureMessageSpy).not.toHaveBeenCalled();
  });

  it("falls back to the envelope id when data.run_id is missing (the failure event's id IS the run id)", async () => {
    const sendEvent = vi.fn(async () => undefined);
    await agentOnSpawnRequestedOnFailure({
      event: { id: FAILED_RUN, ts: QUEUED_AT, data: { event: original(), error: {} } },
      step: { sendEvent },
    } as never);
    const [, payload] = sendEvent.mock.calls[0] as unknown as [string, { data: Record<string, unknown> }];
    expect(payload.data.run_id).toBe(FAILED_RUN);
  });

  it("a forward that fails past its retries never throws and pages (settle_failed) once", async () => {
    const sendEvent = vi.fn(async () => {
      throw new Error("inngest api unreachable");
    });
    await expect(
      agentOnSpawnRequestedOnFailure({
        event: { ts: QUEUED_AT, data: { event: original(), run_id: FAILED_RUN, error: {} } },
        step: { sendEvent },
      } as never),
    ).resolves.toBeUndefined();
    const sent = deadLetters();
    expect(sent).toHaveLength(1);
    expect(sent[0][0]).toBe(`agent-on-spawn deadlettered: leader_internal_error [${CLASS}] (settle_failed)`);
    expect(sent[0][1].level).toBe("error");
    expect(sent[0][1].extra.failedRunId).toBe(FAILED_RUN);
    expect(allSentryText()).not.toContain(FOUNDER);
  });
});

// --- T8 ----------------------------------------------------------------------

describe("precedence matrix (T8)", () => {
  const cases = [
    ["failed", false, "leader_internal_error", "error", "(failed)"],
    ["failed", true, "leader_internal_error", "error", "(failed)"],
    ["cancelled", false, "leader_internal_error", "error", "(cancelled)"],
    ["cancelled", true, "cancelled_by_operator", "warning", "(cancelled)"],
    ["timed_out", false, "leader_internal_error", "error", "(timed_out)"],
    ["timed_out", true, "leader_internal_error", "error", "(timed_out)"],
  ] as const;

  it.each(cases)(
    "%s, Stop=%s → %s at %s level, suffix %s",
    async (lifecycle, stop, reason, level, suffix) => {
      if (stop) row().cancellation_requested_at = "2026-09-25T10:01:00.000Z";
      const event =
        lifecycle === "failed"
          ? orphanedEnvelope()
          : cancelledEnvelope({
              // Boundary fixtures: one ms short of the cutoff is a cancel, the cutoff itself a timeout.
              elapsedMs: lifecycle === "timed_out" ? FINISH_TIMEOUT_MS : FINISH_TIMEOUT_MS - 1,
            });
      const step = makeSettleStep();
      await agentOnSpawnSettleHandler({ event, step, attempt: 0 } as never);

      expect(row().failure_reason).toBe(reason);
      const sent = deadLetters();
      expect(sent).toHaveLength(1);
      const [message, ctx] = sent[0];
      expect(message).toBe(`agent-on-spawn deadlettered: ${reason} [${CLASS}] ${suffix}`);
      expect(ctx.level).toBe(level);
      expect(ctx.tags.reason).toBe(reason);
      expect(ctx.extra.failedRunId).toBe(FAILED_RUN);
      expect(ctx.extra.actionSendId).toBe(ACTION_SEND);
      if (lifecycle === "failed") {
        // The failed run's own error is the triage payload.
        expect(ctx.extra.err).toMatchObject({ name: "Error", message: "turn-2-progress-write failed" });
        expect(ctx.extra.elapsedMs).toBe(30_000);
      } else {
        expect(ctx.extra.elapsedMs).toBe(lifecycle === "timed_out" ? FINISH_TIMEOUT_MS : FINISH_TIMEOUT_MS - 1);
      }
      // No raw founder id anywhere Sentry was handed (T20, fallback form).
      expect(allSentryText()).not.toContain(FOUNDER);

      if (lifecycle === "failed") {
        expect(step.ops).not.toContain("settle-grace");
      } else {
        expect(step.ops.indexOf("settle-grace")).toBeGreaterThanOrEqual(0);
        expect(step.ops.indexOf("settle-grace")).toBeLessThan(
          step.ops.indexOf("settle-orphaned-spawn"),
        );
      }
    },
  );
});

// --- T9 ----------------------------------------------------------------------

describe("missing timestamps and a failed Stop read (T9)", () => {
  it("no ts on either event → elapsedMs null, suffix (cancelled)", async () => {
    await agentOnSpawnSettleHandler({
      event: cancelledEnvelope({ elapsedMs: null, orig: original({}, undefined) }),
      step: makeSettleStep(),
      attempt: 0,
    } as never);
    const [[message, ctx]] = deadLetters();
    expect(message.endsWith("(cancelled)")).toBe(true);
    expect(ctx.extra.elapsedMs).toBeNull();
  });

  it("a pending Stop with no timestamps is NOT honoured: nothing proves the cancel preceded the timeout", async () => {
    row().cancellation_requested_at = "2026-09-25T10:01:00.000Z";
    await agentOnSpawnSettleHandler({
      event: cancelledEnvelope({ elapsedMs: null, orig: original({}, undefined) }),
      step: makeSettleStep(),
      attempt: 0,
    } as never);
    expect(row().failure_reason).toBe("leader_internal_error");
    expect(deadLetters()[0][1].level).toBe("error");
  });

  it("a Stop read error falls back to leader_internal_error (paged)", async () => {
    row().cancellation_requested_at = "2026-09-25T10:01:00.000Z";
    db.failStopRead = true;
    await agentOnSpawnSettleHandler({
      event: cancelledEnvelope(),
      step: makeSettleStep(),
      attempt: 0,
    } as never);
    expect(row().failure_reason).toBe("leader_internal_error");
    expect(deadLetters()[0][1].level).toBe("error");
  });
});

// --- T10 / T13 -----------------------------------------------------------------

describe("a row that is terminal or not the founder's is never touched (T10, T13)", () => {
  it.each([
    ["acknowledged", { acknowledged_at: "2026-09-25T10:02:00.000Z", reversal_handles: [{ kind: "pr" }] }],
    ["already failed", { failure_reason: "leader_tool_invalid" }],
    ["already stopped", { failure_reason: "cancelled_by_operator" }],
    ["undone", { undone_at: "2026-09-25T10:03:00.000Z", acknowledged_at: "2026-09-25T10:02:00.000Z" }],
    ["another founder's", { user_id: OTHER_FOUNDER }],
    ["anonymised", { user_id: null }],
  ] as const)("%s row: unchanged, zero reports, on a forwarded failure AND on a cancel", async (_label, overrides) => {
    for (const event of [orphanedEnvelope(), cancelledEnvelope()]) {
      db.rows = [fixtureRow(overrides as Partial<FixtureRow>)];
      captureMessageSpy.mockReset();
      const before = { ...row() };
      await agentOnSpawnSettleHandler({ event, step: makeSettleStep(), attempt: 0 } as never);
      expect(row()).toEqual(before);
      expect(deadLetters()).toHaveLength(0);
    }
  });

  it("the UPDATE carries every guard filter (Guard 2 row 4 — read from the recorded call)", async () => {
    await agentOnSpawnSettleHandler({ event: orphanedEnvelope(), step: makeSettleStep(), attempt: 0 } as never);
    const update = (db.ops as DbOp[]).find((o) => o.mode === "update");
    expect(update?.table).toBe("action_sends");
    expect(update?.filters).toEqual(
      expect.arrayContaining([
        { col: "id", op: "eq", val: ACTION_SEND },
        { col: "user_id", op: "eq", val: FOUNDER },
        { col: "message_id", op: "eq", val: MESSAGE },
        { col: "failure_reason", op: "is", val: null },
        { col: "acknowledged_at", op: "is", val: null },
        { col: "undone_at", op: "is", val: null },
      ]),
    );
  });
});

// --- T11 / T12b ----------------------------------------------------------------

describe("a committed write whose page was lost to a retry (T11, T12b)", () => {
  it("attempt 0, zero rows → no report and no re-read", async () => {
    row().failure_reason = "leader_internal_error"; // a concurrent persistFailure wrote it
    await agentOnSpawnSettleHandler({ event: orphanedEnvelope(), step: makeSettleStep(), attempt: 0 } as never);
    expect(deadLetters()).toHaveLength(0);
    const ops = db.ops as DbOp[];
    const updateAt = ops.findIndex((o) => o.mode === "update");
    expect(ops.slice(updateAt + 1).filter((o) => o.mode === "select")).toHaveLength(0);
  });

  it("attempt > 0, zero rows, re-read shows the same reason → exactly one report", async () => {
    row().failure_reason = "leader_internal_error";
    await agentOnSpawnSettleHandler({ event: orphanedEnvelope(), step: makeSettleStep(), attempt: 2 } as never);
    expect(deadLetters()).toHaveLength(1);
  });

  it("attempt > 0 on ANOTHER founder's row carrying the same reason → no report (the re-read is scoped)", async () => {
    db.rows = [fixtureRow({ user_id: OTHER_FOUNDER, failure_reason: "leader_internal_error" })];
    await agentOnSpawnSettleHandler({ event: orphanedEnvelope(), step: makeSettleStep(), attempt: 2 } as never);
    expect(deadLetters()).toHaveLength(0);
  });

  it("attempt > 0, zero rows, re-read shows a DIFFERENT reason → no report", async () => {
    row().failure_reason = "leader_tool_invalid";
    await agentOnSpawnSettleHandler({ event: orphanedEnvelope(), step: makeSettleStep(), attempt: 2 } as never);
    expect(deadLetters()).toHaveLength(0);
  });
});

// --- T12 / T21 (through the real step boundary) --------------------------------

describe("replay and retry through the real step boundary (T12, T21)", () => {
  it("T21: a forwarded failure settles with exactly ONE report across every invocation", async () => {
    const out = await runLikeInngest(
      ({ step, attempt }) => agentOnSpawnSettleHandler({ event: orphanedEnvelope(), step, attempt } as never),
      { maxAttempts: 4 },
    );
    expect(out.outcome).toBe("returned");
    expect(out.invocations).toBeGreaterThan(1);
    expect(row().failure_reason).toBe("leader_internal_error");
    expect(deadLetters()).toHaveLength(1);
  });

  it("T12: the settle step's DB call fails on every attempt → never throws, exactly one (settle_failed) page", async () => {
    db.failAll = { code: "08006", message: "connection failure" };
    const out = await runLikeInngest(
      ({ step, attempt }) => agentOnSpawnSettleHandler({ event: orphanedEnvelope(), step, attempt } as never),
      { maxAttempts: 4 },
    );
    expect(out.outcome).toBe("returned");
    const sent = deadLetters();
    expect(sent).toHaveLength(1);
    expect(sent[0][0]).toBe(`agent-on-spawn deadlettered: leader_internal_error [${CLASS}] (settle_failed)`);
    expect(sent[0][1].level).toBe("error");
    expect(sent[0][1].extra.failedRunId).toBe(FAILED_RUN);
    // The code only: a PostgREST message can echo a value.
    expect(sent[0][1].extra.err?.message).toBe("settle-orphaned-spawn: action_sends update failed (code 08006)");
  });
});

// --- T14 ----------------------------------------------------------------------

describe("envelope validation (T14)", () => {
  const FORGED = "not-a-uuid-attacker-value";
  it.each([
    ["a foreign event name", orphanedEnvelope({ orig: { ...original(), name: "some.other.event" } })],
    ["a non-UUID actionSendId", orphanedEnvelope({ orig: original({ actionSendId: FORGED }) })],
    ["a non-UUID founderId", orphanedEnvelope({ orig: original({ founderId: FORGED }) })],
    ["a missing messageId", orphanedEnvelope({ orig: original({ messageId: undefined }) })],
    ["a non-UUID messageId", orphanedEnvelope({ orig: original({ messageId: FORGED }) })],
    ["a missing run_id", { name: "agent.spawn.orphaned", data: { event: original() } }],
    ["a non-ULID run_id", { name: "agent.spawn.orphaned", data: { event: original(), run_id: FORGED } }],
    ["no original event at all", { name: "agent.spawn.orphaned", data: { run_id: FAILED_RUN, lifecycle: "failed" } }],
  ])("%s → no DB call, one (settle_failed) page with a fixed message", async (_label, event) => {
    await agentOnSpawnSettleHandler({ event, step: makeSettleStep(), attempt: 0 } as never);
    expect(db.ops).toHaveLength(0);
    const sent = deadLetters();
    expect(sent).toHaveLength(1);
    expect(sent[0][0].endsWith("(settle_failed)")).toBe(true);
    expect(sent[0][1].extra.err?.message).toBe(
      "agent-on-spawn-settle: lifecycle envelope failed validation",
    );
    expect(allSentryText()).not.toContain(FORGED);
    // A well-formed run id is carried; a missing or forged one is not.
    const runId = (event.data as { run_id?: unknown }).run_id;
    expect(sent[0][1].extra.failedRunId).toBe(runId === FAILED_RUN ? FAILED_RUN : null);
  });

  it("an unknown actionClass is carried as [unknown] and still settles", async () => {
    await agentOnSpawnSettleHandler({
      event: orphanedEnvelope({ orig: original({ actionClass: "forged.class-x" }) }),
      step: makeSettleStep(),
      attempt: 0,
    } as never);
    const [[message]] = deadLetters();
    expect(message).toBe("agent-on-spawn deadlettered: leader_internal_error [unknown] (failed)");
    expect(allSentryText()).not.toContain("forged.class-x");
  });

  it("an envelope with extra unknown fields settles normally (must-PASS)", async () => {
    const event = orphanedEnvelope();
    (event.data as Record<string, unknown>).correlation_id = "c-1";
    (event.data as Record<string, unknown>).events = [original()];
    await agentOnSpawnSettleHandler({ event, step: makeSettleStep(), attempt: 0 } as never);
    expect(row().failure_reason).toBe("leader_internal_error");
  });
});

// --- T22 ----------------------------------------------------------------------

describe("a settled row leaves 'Working' (T22)", () => {
  it("leader_internal_error on a row mid-turn renders the failure card: no Stop, no Retry", async () => {
    await agentOnSpawnSettleHandler({ event: orphanedEnvelope(), step: makeSettleStep(), attempt: 0 } as never);
    const state = deriveTodayCardState(row());
    expect(state.kind).toBe("failure_no_artifact");
    expect(state.copy).toBe(`Failed — ${FAILURE_REASON_COPY.leader_internal_error.copy}`);
    expect(state.showStop).toBe(false);
    expect(state.showRetry).toBe(false);
  });

  it("a pre-timeout cancel after Stop renders the Stopped copy", async () => {
    row().cancellation_requested_at = "2026-09-25T10:01:00.000Z";
    await agentOnSpawnSettleHandler({ event: cancelledEnvelope(), step: makeSettleStep(), attempt: 0 } as never);
    const state = deriveTodayCardState(row());
    expect(state.kind).toBe("failure_no_artifact");
    expect(state.copy).toContain("Stopped.");
    expect(state.showStop).toBe(false);
  });
});

// --- T23 ----------------------------------------------------------------------

describe("the lifecycle handlers never touch the Inngest ctx logger (T23)", () => {
  it("the lifecycle block references no `logger`", () => {
    const src = readFileSync(
      join(__dirname, "../../../server/inngest/functions/agent-on-spawn-requested.ts"),
      "utf8",
    );
    const start = src.indexOf("// --- Lifecycle settle (#8803) ---");
    const end = src.indexOf("// --- end lifecycle settle ---");
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    const block = stripComments(src.slice(start, end));
    for (const fn of [
      "agentOnSpawnRequestedOnFailure",
      "agentOnSpawnSettleHandler",
      "settleOrphanedSpawn",
    ]) {
      expect(block).toContain(`function ${fn}`);
    }
    expect(block).not.toMatch(/\blogger\b/);
  });
});

// --- T15 / T16 (registration, the SDK's own config) ----------------------------

type ConfigFn = {
  opts: Record<string, unknown>;
  getConfig(a: { baseUrl: URL; appPrefix: string }): Array<{
    id: string;
    triggers: Array<{ event: string; expression?: string }>;
  }>;
};
// The SDK prefixes every function id with the client id, so derive it; a
// hard-coded app id would pass here while production stopped matching.
const BASE = { baseUrl: new URL("http://localhost:3000/api/inngest"), appPrefix: inngest.id };

describe("registration (T15, T16)", () => {
  it("T15: agentOnSpawnRequested declares onFailure and yields the -failure function; finish derives from FINISH_TIMEOUT_MS", () => {
    const fn = agentOnSpawnRequested as unknown as ConfigFn;
    expect(fn.opts.onFailure).toBe(agentOnSpawnRequestedOnFailure);
    expect(fn.getConfig(BASE).map((c) => c.id)).toEqual([
      `${inngest.id}-agent-on-spawn-requested`,
      `${inngest.id}-agent-on-spawn-requested-failure`,
    ]);
    expect(FINISH_TIMEOUT_MS).toBe(10 * 60_000);
    expect((fn.getConfig(BASE)[0] as unknown as { timeouts: unknown }).timeouts).toEqual({ finish: "10m" });
  });

  it("T16: agentOnSpawnSettle has exactly the two triggers, the cancel filter equal to the SDK's own failure filter", () => {
    const requested = agentOnSpawnRequested as unknown as ConfigFn;
    const sdkFilter = requested.getConfig(BASE)[1].triggers[0].expression;
    expect(sdkFilter).toBe(`event.data.function_id == '${inngest.id}-agent-on-spawn-requested'`);

    const settle = agentOnSpawnSettle as unknown as ConfigFn;
    const [cfg] = settle.getConfig(BASE);
    expect(cfg.id).toBe(`${inngest.id}-agent-on-spawn-settle`);
    expect(cfg.triggers).toEqual([
      { event: "inngest/function.cancelled", expression: sdkFilter },
      { event: "agent.spawn.orphaned" },
    ]);
    const built = cfg as unknown as { idempotency?: unknown; steps: Record<string, { retries?: unknown }> };
    expect(built.idempotency).toBe("event.data.run_id");
    expect(Object.values(built.steps).map((st) => st.retries)).toEqual([{ attempts: 3 }]);
  });
});
