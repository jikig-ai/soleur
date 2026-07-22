// cron-email-ingress-probe — deadline-repin idempotency guard (#6781).
//
// THE HARNESS CONTRACT IS THE POINT OF THIS FILE. It deliberately does NOT
// mock `@/server/notifications`. That module is the fixture seam the issue is
// about: the unguarded path runs
//
//   deadline-repin  →  notifyOfflineUser  →  sendEmailTriageEmailNotification
//                   →  resend.emails.send
//
// and a test that stubs `notifyOfflineUser` would assert "the cron called a
// function" while proving nothing about whether a duplicate EMAIL goes out.
// That is the same defect shape the guard exists to prevent — a check that
// looks like coverage while being structurally incapable of failing on the
// path that matters. So the seam here is one level DOWN: the `resend` package
// itself. Every "N emails" assertion below counts real send calls made by the
// real notifications module.
//
// Covered contracts:
//   T1  double-fire same day                     → 1 email, repinSuppressed 1
//   T2  T-7 straddle across two UTC dates        → 1 email  (the 'headsup' key)
//   T3  two consecutive danger-band days         → 2 emails (the daily key)
//   T4  two distinct items, same/different user  → 2 emails each
//   T5  fail-open on a non-23505 {error} return  → email still sent + Sentry
//   T6  fail-open on a THROWN insert             → all 10 dispatch, incl. #3
//   T7  DDL pin on the migration text
//   T7b gated live-DB tier: real 23505
//   T8  harness negative control (the fake really enforces uniqueness)
//   T9  a run crossing UTC midnight mid-loop     → ONE tick_key
//   T10 rows hitting a pre-existing guard        → NO marker written
//   T11 push-subscribed user, double-fire        → exactly one webpush send
//   T9b a run spanning BOTH cadences             → each keyed by its cadence
//   T9c an OVERDUE item                          → still pings daily
//   T12 single-recipient send path               → R7 tripwire (CPO C5)
//   T13 the marker insert names no absent column → 42703 tripwire

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Hoisted spies ------------------------------------------------------------

const {
  resendSendSpy,
  webpushSendSpy,
  warnSilentFallbackSpy,
  reportSilentFallbackSpy,
  infoSilentFallbackSpy,
  ioOrder,
  dbState,
} = vi.hoisted(() => {
  const ioOrder: string[] = [];
  const dbState: {
    repinRows: Array<Record<string, unknown>>;
    /** Rows the fake has already accepted, as `${item_id}::${tick_key}`. */
    markers: Set<string>;
    /**
     * created_at (ISO) recorded per marker at insert time, so the M11
     * `.select("created_at")` disambiguation on a `headsup` 23505 can read it.
     * Populated from the fake clock (`new Date()` under `vi.setSystemTime`).
     */
    markerCreatedAt: Map<string, string>;
    /** Every marker insert attempted, in order (incl. rejected ones). */
    markerAttempts: Array<{ item_id: string; tick_key: string }>;
    /** Force a non-23505 `{error}` return on the Nth attempt (1-based). */
    markerErrorOnAttempt: number | null;
    /** Force a THROW on the Nth attempt (1-based). */
    markerThrowOnAttempt: number | null;
    /** Force the #6801 excluded-count query to return an error (T16c). */
    excludedQueryError: boolean;
    /** Rollback DELETEs issued against statutory_repin_send (#6802 D4c). */
    markerDeletes: Array<{ item_id: string; tick_key: string }>;
    /** Force the rollback DELETE to THROW (T-rollback-throws, M7). */
    markerDeleteThrows: boolean;
    /** Force the rollback DELETE to return an error (markerRollbackFailed). */
    markerDeleteError: boolean;
    /** user_id → push subscription rows. */
    pushSubs: Record<string, Array<Record<string, unknown>>>;
    /** user_id → email address. */
    userEmails: Record<string, string>;
    /** Owner rows a fan-out implementation would discover (see T12). */
    workspaceOwners: Array<Record<string, unknown>>;
  } = {
    repinRows: [],
    markers: new Set<string>(),
    markerCreatedAt: new Map<string, string>(),
    markerAttempts: [],
    markerErrorOnAttempt: null,
    markerThrowOnAttempt: null,
    excludedQueryError: false,
    markerDeletes: [],
    markerDeleteThrows: false,
    markerDeleteError: false,
    pushSubs: {},
    userEmails: {},
    workspaceOwners: [],
  };
  return {
    resendSendSpy: vi.fn(
      async (..._args: unknown[]): Promise<{ error: { message: string } | null }> => ({
        error: null,
      }),
    ),
    webpushSendSpy: vi.fn(async (..._args: unknown[]) => ({ statusCode: 201 })),
    warnSilentFallbackSpy: vi.fn(),
    reportSilentFallbackSpy: vi.fn(),
    infoSilentFallbackSpy: vi.fn(),
    ioOrder,
    dbState,
  };
});

vi.mock("@/server/inngest/client", () => ({
  inngest: { createFunction: vi.fn((...args: unknown[]) => ({ __args: args })) },
}));

// PARTIAL, not wholesale: notifications.ts also imports APP_URL_FALLBACK from
// this module. A wholesale factory would drop it and break the real module we
// are deliberately exercising.
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  warnSilentFallback: warnSilentFallbackSpy,
  reportSilentFallback: reportSilentFallbackSpy,
  infoSilentFallback: infoSilentFallbackSpy,
}));

// `function` keyword (not an arrow) — the real module does `new Resend(...)`.
vi.mock("resend", () => ({
  Resend: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    this.emails = {
      send: (...args: unknown[]) => {
        ioOrder.push("resend-send");
        return resendSendSpy(...args);
      },
    };
  }),
}));

vi.mock("web-push", () => ({
  default: {
    setVapidDetails: vi.fn(),
    sendNotification: (...args: unknown[]) => {
      ioOrder.push("webpush-send");
      return webpushSendSpy(...args);
    },
  },
}));

// --- Supabase fake ------------------------------------------------------------
//
// Routes every table the real send path touches. The load-bearing behavior is
// UNIQUENESS on (item_id, tick_key): without it, T1/T2/T11 would pass against
// a codebase with no guard at all, and the whole file would be vacuous. T8 is
// the negative control that proves this fake can actually reject.

function markerKey(itemId: string, tickKey: string): string {
  return `${itemId}::${tickKey}`;
}

/**
 * Subject of the MOST RECENT probe email (the token is minted inside the
 * handler, and several tests run the handler twice — returning the first
 * token would fail the second run's assert-probe-row for an unrelated reason).
 */
function sentProbeSubject(): string | undefined {
  const subjects = resendSendSpy.mock.calls
    .map((c) => (c[0] as { subject?: string } | undefined)?.subject)
    .filter((s): s is string => !!s && s.includes("SOLEUR-PROBE-"));
  return subjects[subjects.length - 1];
}

/**
 * Column sets the REAL tables expose, so `.select()` can be validated the way
 * PostgREST validates it.
 *
 * This exists because of a live defect this file originally shipped green over.
 * The guard was written as `.insert(...).select("id").single()`, cloned from
 * `notifyInboxItem` — but `inbox_item` has an `id uuid PRIMARY KEY` and
 * `statutory_repin_send` does NOT (its PK is the composite `(item_id,
 * tick_key)`). PostgREST turns `.select("id")` into a RETURNING clause, so the
 * real statement fails with 42703 "column does not exist", the guard reads a
 * non-23505 error, fails open, dispatches — and never writes a marker. Inert
 * in production, 20/20 green here, because the fake happily answered a select
 * for a column that does not exist.
 *
 * A fake that cannot reject is not a test seam, it is a rubber stamp.
 */
const TABLE_COLUMNS: Record<string, readonly string[]> = {
  statutory_repin_send: ["item_id", "tick_key", "created_at"],
  push_subscriptions: ["id", "endpoint", "p256dh", "auth", "user_id", "last_used_at"],
  email_triage_items: [
    "id",
    "user_id",
    "received_at",
    "acknowledged_at",
    "rule_id",
    "statutory_class",
    "status",
    "mail_class",
    "subject",
    "created_at",
  ],
  probe_tokens: ["id", "token", "created_at"],
};

/** Mirrors PostgREST's error for a RETURNING clause naming a missing column. */
function undefinedColumnError(table: string, column: string) {
  return {
    data: null,
    error: {
      code: "42703",
      message: `column ${table}.${column} does not exist`,
    },
  };
}

function makeBuilder(table: string) {
  const eqArgs: Array<[string, unknown]> = [];
  const builder: Record<string, unknown> = {};
  const chain = () => builder;
  let insertPayload: Record<string, unknown> | null = null;
  let deleting = false;
  let selectError: { data: null; error: { code: string; message: string } } | null = null;
  // Range constraints the scan / excluded-count queries apply (#6801).
  const gteArgs: Array<[string, string]> = [];
  const ltArgs: Array<[string, string]> = [];
  let isCountHead = false;

  for (const m of ["not", "ilike", "like", "limit", "update", "in"]) {
    builder[m] = vi.fn(chain);
  }
  builder.gte = vi.fn((col: string, val: string) => {
    gteArgs.push([col, val]);
    return builder;
  });
  builder.lt = vi.fn((col: string, val: string) => {
    ltArgs.push([col, val]);
    return builder;
  });
  builder.select = vi.fn((cols?: string, opts?: { head?: boolean; count?: string }) => {
    if (opts?.head) isCountHead = true;
    const known = TABLE_COLUMNS[table];
    if (known && typeof cols === "string" && cols !== "*") {
      for (const raw of cols.split(",")) {
        const col = raw.trim();
        if (col && col !== "*" && !known.includes(col)) {
          selectError = undefinedColumnError(table, col);
          break;
        }
      }
    }
    return builder;
  });
  builder.eq = vi.fn((col: string, val: unknown) => {
    eqArgs.push([col, val]);
    return builder;
  });
  builder.delete = vi.fn(() => {
    deleting = true;
    return builder;
  });
  builder.insert = vi.fn((payload: Record<string, unknown>) => {
    insertPayload = payload;
    return builder;
  });

  builder.single = async () => {
    if (selectError) return selectError;
    if (table === "statutory_repin_send" && insertPayload) {
      return resolveMarkerInsert(insertPayload);
    }
    return { data: null, error: null };
  };

  // M11: the disambiguation read `.select("created_at").eq().eq().maybeSingle()`
  // on a `headsup` 23505. Returns the stored created_at for the (item, tick).
  builder.maybeSingle = async () => {
    if (selectError) return selectError;
    if (table === "statutory_repin_send" && !insertPayload && !deleting) {
      const itemId = eqArgs.find(([c]) => c === "item_id")?.[1] as
        | string
        | undefined;
      const tickKey = eqArgs.find(([c]) => c === "tick_key")?.[1] as
        | string
        | undefined;
      if (itemId && tickKey) {
        const created = dbState.markerCreatedAt.get(markerKey(itemId, tickKey));
        return { data: created ? { created_at: created } : null, error: null };
      }
    }
    return { data: null, error: null };
  };

  builder.then = (
    onFulfilled: (v: unknown) => unknown,
    onRejected?: (e: unknown) => unknown,
  ) => {
    let result: unknown;
    if (selectError) {
      return Promise.resolve(selectError).then(onFulfilled, onRejected);
    } else if (table === "statutory_repin_send" && insertPayload) {
      return Promise.resolve(resolveMarkerInsert(insertPayload)).then(
        onFulfilled,
        onRejected,
      );
    } else if (table === "statutory_repin_send" && deleting) {
      // #6802 rollback DELETE: honor forced throw/error, otherwise actually
      // remove the (item_id, tick_key) marker so a subsequent tick re-sends.
      const itemId = eqArgs.find(([c]) => c === "item_id")?.[1] as string;
      const tickKey = eqArgs.find(([c]) => c === "tick_key")?.[1] as string;
      dbState.markerDeletes.push({ item_id: itemId, tick_key: tickKey });
      if (dbState.markerDeleteThrows) {
        return Promise.reject(new Error("simulated rollback DELETE throw")).then(
          onFulfilled,
          onRejected,
        );
      }
      if (dbState.markerDeleteError) {
        return Promise.resolve({ data: null, error: { code: "XX000", message: "delete failed" } }).then(
          onFulfilled,
          onRejected,
        );
      }
      const key = markerKey(itemId, tickKey);
      dbState.markers.delete(key);
      dbState.markerCreatedAt.delete(key);
      return Promise.resolve({ data: null, error: null }).then(onFulfilled, onRejected);
    } else if (table === "workspace_members" || table === "workspace_member") {
      // Deliberately populated. T12 claims to red on a fan-out, but the most
      // likely fan-out implementation DISCOVERS co-Owners by querying
      // membership first — and an unrouted table falls through to `[]`, so the
      // fan-out would find nobody, send once, and T12 would stay green having
      // proven nothing. Giving it three Owners to find is what makes the
      // tripwire able to fire.
      result = { data: dbState.workspaceOwners, error: null };
    } else if (table === "push_subscriptions" && !deleting) {
      const userId = eqArgs.find(([c]) => c === "user_id")?.[1] as string;
      result = { data: dbState.pushSubs[userId] ?? [], error: null };
    } else if (
      table === "email_triage_items" &&
      isCountHead &&
      eqArgs.some(([c, v]) => c === "status" && v === "acknowledged")
    ) {
      // #6801 excluded-count query: `.select("id",{count,head}).lt("acknowledged_at",floor)`.
      // Either honor an explicitly forced error (T16c) or count repinRows whose
      // acknowledged_at is BELOW the lt floor (rows the scan excludes).
      if (dbState.excludedQueryError) {
        result = { data: null, count: null, error: { code: "XX000", message: "count failed" } };
      } else {
        const ltFloor = ltArgs.find(([c]) => c === "acknowledged_at")?.[1];
        const count = ltFloor
          ? dbState.repinRows.filter(
              (r) =>
                typeof r.acknowledged_at === "string" &&
                (r.acknowledged_at as string) < ltFloor,
            ).length
          : 0;
        result = { data: null, count, error: null };
      }
    } else if (
      table === "email_triage_items" &&
      eqArgs.some(([c, v]) => c === "status" && v === "acknowledged")
    ) {
      // Scan query: apply the actual `.gte(col, floor)` bound to repinRows, so a
      // row outside the window is genuinely NOT scanned (makes the received_at →
      // acknowledged_at re-anchor test non-vacuous — RED on the old bound).
      const rows = dbState.repinRows.filter((r) =>
        gteArgs.every(
          ([col, floor]) =>
            typeof r[col] === "string" && (r[col] as string) >= floor,
        ),
      );
      result = { data: rows, error: null };
    } else if (
      table === "email_triage_items" &&
      eqArgs.some(([c, v]) => c === "mail_class" && v === "probe")
    ) {
      // Satisfy the handler's assert-probe-row step. The probe token is minted
      // inside the handler, so echo back whatever subject the probe send used
      // — otherwise every test in this file dies on the unrelated
      // "ingress probe row absent" throw before its own assertions run.
      result = { data: [{ id: "probe-row-1", subject: sentProbeSubject() ?? null }], error: null };
    } else {
      result = { data: [], error: null };
    }
    return Promise.resolve(result).then(onFulfilled, onRejected);
  };
  return builder;
}

function resolveMarkerInsert(payload: Record<string, unknown>) {
  const itemId = payload.item_id as string;
  const tickKey = payload.tick_key as string;
  dbState.markerAttempts.push({ item_id: itemId, tick_key: tickKey });
  ioOrder.push(`marker-insert:${itemId}:${tickKey}`);

  const n = dbState.markerAttempts.length;
  if (dbState.markerThrowOnAttempt === n) {
    throw new Error("simulated marker insert throw");
  }
  if (dbState.markerErrorOnAttempt === n) {
    return { data: null, error: { code: "42P01", message: "relation missing" } };
  }

  const key = markerKey(itemId, tickKey);
  if (dbState.markers.has(key)) {
    // Postgres unique_violation — the ONLY code the guard may suppress on.
    return {
      data: null,
      error: {
        code: "23505",
        message:
          'duplicate key value violates unique constraint "statutory_repin_send_pkey"',
      },
    };
  }
  dbState.markers.add(key);
  // Record created_at from the fake clock so the M11 disambiguation read can
  // tell a same-day double-fire from an earlier-day band re-hit.
  dbState.markerCreatedAt.set(key, new Date().toISOString());
  return { data: { item_id: itemId, tick_key: tickKey }, error: null };
}

const rpcSpy = vi.fn(async (name: string, args?: Record<string, unknown>) => {
  ioOrder.push(`rpc:${name}`);
  if (name === "purge_email_triage_items") {
    return { data: { probe_deleted: 0 }, error: null };
  }
  if (name === "purge_statutory_repin_send" && args?.p_item_id) {
    // Targeted release: drop that item's markers from the fake's store and
    // report how many went, mirroring the RPC's ROW_COUNT return.
    const prefix = `${args.p_item_id as string}::`;
    const hit = [...dbState.markers].filter((k) => k.startsWith(prefix));
    hit.forEach((k) => dbState.markers.delete(k));
    return { data: hit.length, error: null };
  }
  return { data: 0, error: null };
});

const getUserByIdSpy = vi.fn(async (userId: string) => ({
  data: { user: { email: dbState.userEmails[userId] ?? `${userId}@example.test` } },
  error: null,
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({
    rpc: rpcSpy,
    from: vi.fn((table: string) => makeBuilder(table)),
    auth: { admin: { getUserById: getUserByIdSpy } },
  })),
}));

import {
  cronEmailIngressProbeHandler,
  DEADLINE_REPIN_HEADS_UP_DAY,
  DEADLINE_REPIN_DANGER_THRESHOLD_DAYS,
} from "@/server/inngest/functions/cron-email-ingress-probe";
import { STATUTORY_RULES } from "@/lib/email-triage/statutory-rules";

/** Sum a field across every `deadline-repin-sweep-complete` emit so far. */
function sweepExtraSum(field: string): number {
  return infoSilentFallbackSpy.mock.calls
    .concat(warnSilentFallbackSpy.mock.calls)
    .filter((c) => (c[1] as { op?: string })?.op === "deadline-repin-sweep-complete")
    .reduce(
      (acc, c) =>
        acc + Number(((c[1] as { extra?: Record<string, number> }).extra ?? {})[field] ?? 0),
      0,
    );
}

// --- Helpers ------------------------------------------------------------------

function makeStep() {
  const calls: string[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      calls.push(name);
      return cb();
    },
    async sleep(): Promise<void> {},
  };
}

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

function runHandler(event?: { data?: Record<string, unknown> }) {
  const step = makeStep();
  return cronEmailIngressProbeHandler({ step, logger, event } as never);
}

/**
 * `received_at` such that the row lands exactly `days` from due under the
 * dsar-art15 rule. That rule is ONE CALENDAR MONTH from receipt, not 30 days
 * (lib/email-triage/statutory-rules.ts computeDueDate), so this subtracts a
 * month — a 30-day helper drifts by 1-3 days depending on the month and
 * silently lands rows outside the band under test. The clock is faked by the
 * caller, so this is deterministic.
 */
function receivedAtForDaysUntilDue(days: number): string {
  const due = new Date(Date.now() + days * 86_400_000);
  return new Date(
    Date.UTC(
      due.getUTCFullYear(),
      due.getUTCMonth() - 1,
      due.getUTCDate(),
      due.getUTCHours(),
      due.getUTCMinutes(),
      due.getUTCSeconds(),
      due.getUTCMilliseconds(),
    ),
  ).toISOString();
}

function statutoryRow(overrides: Record<string, unknown> = {}) {
  return {
    id: "item-1",
    user_id: "user-1",
    received_at: receivedAtForDaysUntilDue(1),
    // #6801: the scan now bounds on `acknowledged_at`; default it to "now"
    // (under the fake clock) so it is inside the 60-day window unless a test
    // overrides it to probe the re-anchor / excluded-count behavior.
    acknowledged_at: new Date().toISOString(),
    rule_id: "dsar-art15",
    statutory_class: "dsar",
    ...overrides,
  };
}

/** Emails the REAL notifications module sent down the statutory branch. */
function statutoryEmailCalls(): Array<{ to: string[]; subject: string }> {
  return resendSendSpy.mock.calls
    .map((c) => c[0] as { to: string[]; subject: string })
    .filter((a) => a?.subject?.startsWith("Statutory item in your Soleur inbox"));
}

beforeEach(() => {
  vi.clearAllMocks();
  // clearAllMocks resets CALLS but NOT implementations. T9 installs a
  // clock-advancing resend implementation; without this re-init it leaks into
  // every later test, silently moving runDateUtc past UTC midnight and making
  // a correctly-suppressed second run look like a duplicate send.
  resendSendSpy.mockImplementation(async () => ({ error: null }));
  webpushSendSpy.mockImplementation(async () => ({ statusCode: 201 }));
  ioOrder.length = 0;
  dbState.repinRows = [];
  dbState.markers = new Set();
  dbState.markerCreatedAt = new Map();
  dbState.markerAttempts = [];
  dbState.markerErrorOnAttempt = null;
  dbState.markerThrowOnAttempt = null;
  dbState.excludedQueryError = false;
  dbState.markerDeletes = [];
  dbState.markerDeleteThrows = false;
  dbState.markerDeleteError = false;
  dbState.pushSubs = {};
  dbState.userEmails = {};
  dbState.workspaceOwners = [];
  vi.stubEnv("VAPID_PUBLIC_KEY", "test-public-key");
  vi.stubEnv("VAPID_PRIVATE_KEY", "test-private-key");
  vi.stubEnv("RESEND_API_KEY", "re_test_key");
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

// =============================================================================

describe("deadline-repin idempotency guard (#6781)", () => {
  it("T1: a double-fire on the same day sends ONE email and reports the suppression", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow()];

    const first = await runHandler();
    const second = await runHandler();

    expect(statutoryEmailCalls()).toHaveLength(1);
    expect(first.repinged).toBe(1);
    expect(first.repinSuppressed).toBe(0);
    expect(second.repinged).toBe(0);
    expect(second.repinSuppressed).toBe(1);

    // Marker-BEFORE-dispatch ordering. If the send happened first, a crash
    // between send and marker would re-send forever — the marker is only
    // meaningful if it is durable before the irreversible act.
    const firstMarker = ioOrder.findIndex((e) => e.startsWith("marker-insert:"));
    const firstSend = ioOrder.indexOf("resend-send");
    expect(firstMarker).toBeGreaterThanOrEqual(0);
    expect(firstSend).toBeGreaterThanOrEqual(0);
    expect(firstMarker).toBeLessThan(firstSend);
  });

  it("T2: the T-7 heads-up straddling two UTC dates still sends ONE email", async () => {
    // THE reason tick_key is not a bare calendar date.
    //
    // `daysUntilDue` is floor((due - now) / 1 day), so "exactly T-7" is a 24h
    // WINDOW, not an instant. Pick `due` so that two runs ~24h apart BOTH
    // floor to 7 while landing on DIFFERENT UTC dates:
    //
    //   due = 2026-03-18T05:55Z
    //   run A @ 2026-03-10T06:00Z → due-A = 7d 23h55m → floor 7   (date 03-10)
    //   run B @ 2026-03-11T05:50Z → due-B = 7d 00h05m → floor 7   (date 03-11)
    //
    // A `daily:YYYY-MM-DD` key would produce two DIFFERENT keys here and send
    // the heads-up twice. The constant 'headsup' key is what collapses them.
    // `due` inherits received_at's time-of-day, so received is exactly one
    // calendar month earlier.
    const received = "2026-02-18T05:55:00.000Z";

    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow({ received_at: received })];
    await runHandler();

    vi.setSystemTime(new Date("2026-03-11T05:50:00Z"));
    await runHandler();

    // Precondition self-check: if a future rule change moves the due-date
    // arithmetic, this test must fail as a FIXTURE error rather than silently
    // becoming a vacuous "0 emails, 0 markers" pass.
    expect(dbState.markerAttempts.length).toBeGreaterThan(0);

    const attempts = dbState.markerAttempts.map((a) => a.tick_key);
    expect(attempts.every((k) => k === "headsup")).toBe(true);
    expect(statutoryEmailCalls()).toHaveLength(1);
  });

  it("T3: two consecutive danger-band days send TWO emails", async () => {
    // The inverse guarantee: the guard must NOT silence the daily band. This
    // is the failure mode a naive "have we pinged this item" key would cause.
    vi.useFakeTimers();

    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow({ received_at: receivedAtForDaysUntilDue(2) })];
    await runHandler();

    vi.setSystemTime(new Date("2026-03-11T06:00:00Z"));
    dbState.repinRows = [statutoryRow({ received_at: receivedAtForDaysUntilDue(1) })];
    await runHandler();

    expect(statutoryEmailCalls()).toHaveLength(2);
    const keys = dbState.markerAttempts.map((a) => a.tick_key);
    expect(keys).toEqual(["daily:2026-03-10", "daily:2026-03-11"]);
  });

  // #6799 (AC6/D2/M6): the heads-up is a BAND, so jitter cannot step over it.
  it("heads-up band: two jittered runs straddling T-7 send exactly ONE heads-up (was ZERO on main)", async () => {
    // due = 2026-03-18T06:00Z, received one calendar month earlier.
    //   run A @ 2026-03-10T05:59:50Z → 8d 00h00m10s → floor 8 → not yet
    //   run B @ 2026-03-11T06:00:10Z → 6d 23h59m50s → floor 6 → in band → send
    // Under the OLD exact `=== 7`, run A (8) and run B (6) BOTH miss → ZERO
    // heads-ups. Under the band, run B sends exactly one.
    const received = "2026-02-18T06:00:00.000Z";
    vi.useFakeTimers();

    vi.setSystemTime(new Date("2026-03-10T05:59:50Z"));
    dbState.repinRows = [statutoryRow({ received_at: received })];
    await runHandler();

    vi.setSystemTime(new Date("2026-03-11T06:00:10Z"));
    dbState.repinRows = [statutoryRow({ received_at: received })];
    await runHandler();

    expect(statutoryEmailCalls()).toHaveLength(1);
    const keys = dbState.markerAttempts.map((a) => a.tick_key);
    expect(keys).toEqual(["headsup"]);
  });

  // #6799 (AC7/D2a/M11): five consecutive in-band days send ONE heads-up; the
  // re-hits count as `headsUpAlreadySent`, NOT `suppressed` — so the #6781
  // double-fire detector (repin_suppressed) survives the band.
  it("heads-up band: five consecutive in-band days → one email, suppressed 0, headsUpAlreadySent 4", async () => {
    // received 2026-02-15T12:00Z → due 2026-03-15T12:00Z (calendar month).
    // clock 03-08..03-12 → daysUntilDue 7,6,5,4,3 — all in the heads-up band.
    const received = "2026-02-15T12:00:00.000Z";
    const days = [
      "2026-03-08T12:00:00Z",
      "2026-03-09T12:00:00Z",
      "2026-03-10T12:00:00Z",
      "2026-03-11T12:00:00Z",
      "2026-03-12T12:00:00Z",
    ];
    vi.useFakeTimers();
    for (const t of days) {
      vi.setSystemTime(new Date(t));
      dbState.repinRows = [statutoryRow({ received_at: received })];
      await runHandler();
    }

    expect(statutoryEmailCalls()).toHaveLength(1);
    expect(dbState.markerAttempts.every((a) => a.tick_key === "headsup")).toBe(true);
    // suppressed stays 0 — a run in steady band state must NOT read as a live
    // second scheduler; the four re-hits land in headsUpAlreadySent.
    expect(sweepExtraSum("suppressed")).toBe(0);
    expect(sweepExtraSum("headsUpAlreadySent")).toBe(4);
  });

  // #6799 (AC8/D2b/M11): a genuine same-day double-fire on the heads-up key IS
  // still a `suppressed` (the detector must keep firing on the real condition).
  it("heads-up band: a SAME-day double-fire on the heads-up key counts as suppressed", async () => {
    const received = "2026-02-15T12:00:00.000Z"; // due 03-15, in-band on 03-10
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow({ received_at: received })];
    await runHandler(); // inserts headsup, created_at = 03-10
    dbState.repinRows = [statutoryRow({ received_at: received })];
    await runHandler(); // 23505 headsup, created_at 03-10 === runDateUtc → suppressed

    expect(statutoryEmailCalls()).toHaveLength(1);
    expect(sweepExtraSum("suppressed")).toBe(1);
    expect(sweepExtraSum("headsUpAlreadySent")).toBe(0);
  });

  // #6799 (AC8/D2b): breach-art33 never enters the heads-up band — its 72h clock
  // caps daysUntilDue at DANGER_THRESHOLD for any scanned (post-receipt) item.
  it("breach-art33: never writes a headsup marker, goes straight to the daily band", async () => {
    // received 03-10T00:00Z → due +72h = 03-13T00:00Z.
    const breachRow = statutoryRow({
      rule_id: "breach-art33",
      statutory_class: "breach",
      received_at: "2026-03-10T00:00:00.000Z",
    });
    vi.useFakeTimers();
    for (const t of ["2026-03-11T00:00:00Z", "2026-03-12T00:00:00Z"]) {
      vi.setSystemTime(new Date(t));
      dbState.repinRows = [{ ...breachRow }];
      await runHandler();
    }
    const keys = dbState.markerAttempts.map((a) => a.tick_key);
    expect(keys.length).toBeGreaterThan(0);
    expect(keys.some((k) => k === "headsup")).toBe(false);
    expect(keys.every((k) => k.startsWith("daily:"))).toBe(true);
  });

  // #6799 (M12): GENERIC guard — do not pin today's registry. Every hours-kind
  // rule whose entire post-receipt life is <= DANGER_THRESHOLD can never enter
  // the heads-up band. A future longer hours-rule (e.g. 96h → max 3) fails this
  // and forces a conscious decision instead of silently writing headsup markers.
  it("every hours-kind statutory rule stays within the daily band (no accidental heads-up)", () => {
    const DAY = 24 * 60 * 60 * 1000;
    const hoursRules = STATUTORY_RULES.filter((r) => r.dueRule.kind === "hours");
    expect(hoursRules.length).toBeGreaterThan(0); // non-vacuous
    for (const rule of hoursRules) {
      // Max daysUntilDue one ms after receipt (the earliest a scan can see it).
      const hours = (rule.dueRule as { hours: number }).hours;
      const maxScannable = Math.floor((hours * 3_600_000 - 1) / DAY);
      expect(maxScannable).toBeLessThanOrEqual(DEADLINE_REPIN_DANGER_THRESHOLD_DAYS);
    }
  });

  // #6801 (AC10/D3b): a row received 90 days ago but acknowledged yesterday IS
  // scanned and pinged. On the OLD `received_at` bound it was silently excluded.
  it("scan re-anchor: received 90d ago but acknowledged yesterday IS scanned + pinged", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [
      statutoryRow({
        received_at: "2025-12-10T06:00:00.000Z", // 90d ago — OUTSIDE a received_at window
        acknowledged_at: "2026-03-09T06:00:00.000Z", // yesterday — INSIDE the ack window
        // due date is computed from received_at; force an in-band due via a
        // recent-enough received? No — received is 90d ago so it is long overdue,
        // which still pings daily (the most dangerous bucket).
      }),
    ];
    const result = await runHandler();
    expect(result.repinged).toBe(1);
    expect(statutoryEmailCalls()).toHaveLength(1);
  });

  // #6801 (AC11/D3a): a row acknowledged 90 days ago is EXCLUDED from the scan
  // and counted; the sweep-complete emit carries a non-zero `excluded`.
  it("excluded count: a row acknowledged 90d ago is excluded and counted (excluded >= 1)", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [
      statutoryRow({
        id: "long-tail-1",
        received_at: "2025-12-10T06:00:00.000Z",
        acknowledged_at: "2025-12-10T07:00:00.000Z", // 90d ago — outside 60d window
      }),
    ];
    await runHandler();
    // Not scanned → not pinged.
    expect(statutoryEmailCalls()).toHaveLength(0);
    // But counted in the sweep-complete emit.
    expect(sweepExtraSum("excluded")).toBe(1);
  });

  // #6801 (AC/D3a): `excluded` is MONOTONIC, so it must NOT escalate the emit to
  // warn (that would page forever). A run with excluded>0 and no double-fire
  // stays on infoSilentFallback.
  it("excluded>0 alone does NOT escalate the sweep emit to warn", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [
      statutoryRow({
        id: "long-tail-2",
        acknowledged_at: "2025-12-10T07:00:00.000Z",
      }),
    ];
    await runHandler();
    const infoEmits = infoSilentFallbackSpy.mock.calls.filter(
      (c) => (c[1] as { op?: string })?.op === "deadline-repin-sweep-complete",
    );
    const warnEmits = warnSilentFallbackSpy.mock.calls.filter(
      (c) => (c[1] as { op?: string })?.op === "deadline-repin-sweep-complete",
    );
    expect(infoEmits).toHaveLength(1);
    expect(warnEmits).toHaveLength(0);
  });

  // #6801 (D3a): the excluded-count query failing must NOT fail the run;
  // `excluded` becomes null and the sweep still completes.
  it("excluded count query error → excluded:null, run still completes", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.excludedQueryError = true;
    dbState.repinRows = [statutoryRow()];
    const result = await runHandler();
    expect(result.ok).toBe(true);
    expect(result.repinged).toBe(1);
    const emit = infoSilentFallbackSpy.mock.calls
      .concat(warnSilentFallbackSpy.mock.calls)
      .find((c) => (c[1] as { op?: string })?.op === "deadline-repin-sweep-complete");
    expect((emit?.[1] as { extra?: { excluded?: unknown } })?.extra?.excluded).toBeNull();
  });

  // #6802 (AC16/D4c): push AND email both fail on a heads-up-band item → the
  // (item_id, tick_key) marker is rolled back, `pinged` is NOT incremented,
  // `undelivered === 1`. The rollback restores the pre-#6781 self-heal.
  it("delivery contract: total failure on a heads-up item rolls back the marker, does not count pinged", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    // received 2026-02-15T12:00Z → due 2026-03-15 → daysUntilDue 5 → heads-up band.
    const received = "2026-02-15T12:00:00.000Z";
    dbState.repinRows = [statutoryRow({ received_at: received })];
    dbState.pushSubs = {}; // no push → email path
    resendSendSpy.mockImplementation(async (arg) => {
      const a = arg as { subject?: string };
      // Fail ONLY the statutory notification email; the ingress
      // probe send (SOLEUR-PROBE-*) must still succeed.
      if (a?.subject?.startsWith("Statutory item")) return { error: { message: "resend down" } };
      return { error: null };
    });

    const result = await runHandler();

    expect(result.repinged).toBe(0); // NOT counted as pinged
    // The heads-up marker was rolled back.
    expect(dbState.markerDeletes).toEqual([{ item_id: "item-1", tick_key: "headsup" }]);
    expect(dbState.markers.has("item-1::headsup")).toBe(false);
    // undelivered surfaced in the sweep emit at WARN level.
    expect(sweepExtraSum("undelivered")).toBe(1);
    const warnEmits = warnSilentFallbackSpy.mock.calls.filter(
      (c) => (c[1] as { op?: string })?.op === "deadline-repin-sweep-complete",
    );
    expect(warnEmits).toHaveLength(1);
  });

  // #6802 (D4c/M6): the DAILY arm does NOT roll back — the key rotates daily so
  // the next tick re-arms for free; deleting there would only reopen the
  // same-day double-fire window. undelivered is still counted.
  it("delivery contract: total failure on a DAILY item does NOT roll back (key rotates)", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    // daysUntilDue 1 → daily band.
    dbState.repinRows = [statutoryRow({ received_at: receivedAtForDaysUntilDue(1) })];
    dbState.pushSubs = {};
    resendSendSpy.mockImplementation(async (arg) => {
      const a = arg as { subject?: string };
      // Fail ONLY the statutory notification email; the ingress
      // probe send (SOLEUR-PROBE-*) must still succeed.
      if (a?.subject?.startsWith("Statutory item")) return { error: { message: "resend down" } };
      return { error: null };
    });

    const result = await runHandler();

    expect(result.repinged).toBe(0);
    expect(dbState.markerDeletes).toHaveLength(0); // NO rollback on the daily arm
    expect(sweepExtraSum("undelivered")).toBe(1);
  });

  // #6802 (D4c/M11): a DELIVERED send keeps its marker (does NOT reintroduce the
  // #6781 defect). Rollback fires ONLY on provably-undelivered.
  it("delivery contract: a delivered send keeps its marker (no rollback)", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow({ received_at: "2026-02-15T12:00:00.000Z" })];
    dbState.pushSubs = {};
    resendSendSpy.mockImplementation(async () => ({ error: null })); // email lands

    const result = await runHandler();
    expect(result.repinged).toBe(1);
    expect(dbState.markerDeletes).toHaveLength(0);
    expect(dbState.markers.has("item-1::headsup")).toBe(true);
    expect(sweepExtraSum("undelivered")).toBe(0);
  });

  // #6802 (M6/self-heal): after a rollback, the SAME-day retry re-sends (the
  // marker is gone), and a delivered retry keeps the fresh marker.
  it("delivery contract: a rolled-back heads-up RE-SENDS on the next tick", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    const received = "2026-02-15T12:00:00.000Z";
    dbState.pushSubs = {};
    // Run 1: email fails → rollback.
    dbState.repinRows = [statutoryRow({ received_at: received })];
    resendSendSpy.mockImplementation(async (arg) => {
      const a = arg as { subject?: string };
      // Fail ONLY the statutory notification email; the ingress
      // probe send (SOLEUR-PROBE-*) must still succeed.
      if (a?.subject?.startsWith("Statutory item")) return { error: { message: "resend down" } };
      return { error: null };
    });
    await runHandler();
    expect(dbState.markers.has("item-1::headsup")).toBe(false);

    // Run 2 (same day): email now lands → re-sends and keeps the marker.
    dbState.repinRows = [statutoryRow({ received_at: received })];
    resendSendSpy.mockImplementation(async () => ({ error: null }));
    const r2 = await runHandler();
    expect(r2.repinged).toBe(1); // re-sent
    expect(dbState.markers.has("item-1::headsup")).toBe(true);
  });

  // #6802 (M5): on a FAIL-OPEN dispatch (a non-23505 marker error → no marker
  // claimed here) that then fails to deliver, the rollback must NOT fire — an
  // unconditional DELETE would remove a marker a CONCURRENT run wrote, reopening
  // the #6781 window. Pins the `markerClaimedHere &&` guard (review): dropping
  // it would issue a spurious delete and this test goes RED.
  it("delivery contract: a fail-open (unclaimed) heads-up item does NOT roll back on non-delivery", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow({ received_at: "2026-02-15T12:00:00.000Z" })]; // heads-up band
    dbState.pushSubs = {};
    dbState.markerErrorOnAttempt = 1; // non-23505 → fail-open, markerClaimedHere=false
    resendSendSpy.mockImplementation(async (arg) => {
      const a = arg as { subject?: string };
      if (a?.subject?.startsWith("Statutory item")) return { error: { message: "down" } };
      return { error: null };
    });

    const result = await runHandler();
    // Dispatched (fail-open) and undelivered, but NO marker was claimed here, so
    // no rollback DELETE may be issued.
    expect(dbState.markerDeletes).toHaveLength(0);
    expect(sweepExtraSum("undelivered")).toBe(1);
    expect(result.ok).toBe(true);
  });

  // #6802 (M7): a THROWN rollback DELETE must not escape the loop (retries:0
  // would kill the ingress probe). Counted as markerRollbackFailed; run survives.
  it("delivery contract: a THROWN rollback DELETE is caught, run still completes", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow({ received_at: "2026-02-15T12:00:00.000Z" })];
    dbState.pushSubs = {};
    dbState.markerDeleteThrows = true;
    resendSendSpy.mockImplementation(async (arg) => {
      const a = arg as { subject?: string };
      // Fail ONLY the statutory notification email; the ingress
      // probe send (SOLEUR-PROBE-*) must still succeed.
      if (a?.subject?.startsWith("Statutory item")) return { error: { message: "resend down" } };
      return { error: null };
    });

    const result = await runHandler();
    expect(result.ok).toBe(true); // probe survived
    expect(sweepExtraSum("markerRollbackFailed")).toBe(1);
  });

  it.each([
    ["the same user", "user-1"],
    ["different users", "user-2"],
  ])("T4: two distinct items for %s send two emails", async (_label, secondUser) => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [
      statutoryRow({ id: "item-1", user_id: "user-1" }),
      statutoryRow({ id: "item-2", user_id: secondUser }),
    ];

    const result = await runHandler();

    expect(statutoryEmailCalls()).toHaveLength(2);
    expect(result.repinged).toBe(2);
    expect(result.repinSuppressed).toBe(0);
  });

  it("T5: a non-23505 error return FAILS OPEN — the email still goes out", async () => {
    // AC5. Over-suppression is strictly worse than duplication on a statutory
    // clock, so anything that is not a clean unique-violation must dispatch.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow()];
    dbState.markerErrorOnAttempt = 1;

    const result = await runHandler();

    expect(statutoryEmailCalls()).toHaveLength(1);
    expect(result.repinged).toBe(1);
    expect(result.repinSuppressed).toBe(0);
    expect(warnSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "deadline-repin-marker-insert-failed" }),
    );
  });

  it("T6: a THROWN insert fails open for that item too — all 10 dispatch", async () => {
    // Deliberately asserts ALL TEN including item 3, not "items 4-10".
    // Asserting only 4-10 would pass even if the throwing item were silently
    // suppressed — precisely the fail-CLOSED direction AC5 forbids.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = Array.from({ length: 10 }, (_, i) =>
      statutoryRow({ id: `item-${i + 1}`, user_id: `user-${i + 1}` }),
    );
    dbState.markerThrowOnAttempt = 3;

    const result = await runHandler();

    expect(statutoryEmailCalls()).toHaveLength(10);
    expect(result.repinged).toBe(10);

    // ...and item 3 specifically is among them.
    const recipients = statutoryEmailCalls().flatMap((c) => c.to);
    expect(recipients).toContain("user-3@example.test");

    // The run survived: later steps still executed.
    expect(result.ok).toBe(true);
  });

  it("T8: NEGATIVE CONTROL — the fake itself enforces (item_id, tick_key)", async () => {
    // Without this, every "1 email" assertion above could pass against a
    // codebase with no guard at all. This proves the harness can reject.
    dbState.markers = new Set();
    dbState.markerAttempts = [];

    const first = resolveMarkerInsert({ item_id: "i1", tick_key: "headsup" });
    expect(first.error).toBeNull();

    const repeat = resolveMarkerInsert({ item_id: "i1", tick_key: "headsup" });
    expect(repeat.error?.code).toBe("23505");

    // Distinct item, same tick → allowed.
    expect(
      resolveMarkerInsert({ item_id: "i2", tick_key: "headsup" }).error,
    ).toBeNull();
    // Same item, distinct tick → allowed.
    expect(
      resolveMarkerInsert({ item_id: "i1", tick_key: "daily:2026-03-10" }).error,
    ).toBeNull();
  });

  it("T9: a run crossing UTC midnight mid-loop uses ONE tick_key", async () => {
    // runDateUtc is computed once, before the loop, so a long run cannot
    // straddle two dates and re-send the tail of its own item list.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T23:59:59Z"));
    dbState.repinRows = Array.from({ length: 3 }, (_, i) =>
      statutoryRow({ id: `item-${i + 1}`, user_id: `user-${i + 1}` }),
    );

    // Advance the clock past midnight while the loop is running.
    resendSendSpy.mockImplementation(async () => {
      vi.setSystemTime(new Date("2026-03-11T00:00:05Z"));
      return { error: null };
    });

    await runHandler();

    // Restated: the invariant is ONE runDateUtc per run, not one KEY per run.
    // `keys.size === 1` would be WRONG for a run containing both cadences (a
    // T-7 item keys 'headsup' while band items key 'daily:...'), and it is also
    // satisfied by an implementation that hardcodes any constant.
    const dailyKeys = dbState.markerAttempts
      .map((a) => a.tick_key)
      .filter((k) => k.startsWith("daily:"));
    expect(dailyKeys.length).toBeGreaterThan(0);
    expect(new Set(dailyKeys)).toEqual(new Set(["daily:2026-03-10"]));
  });

  it("T9b: a run spanning BOTH cadences keys each by its own cadence", async () => {
    // The mixed-cadence case T9 cannot cover. Also the only fixture in this
    // file that instantiates more than one cadence in a single run.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [
      statutoryRow({ id: "band", user_id: "u-band", received_at: receivedAtForDaysUntilDue(1) }),
      statutoryRow({
        id: "heads",
        user_id: "u-heads",
        received_at: receivedAtForDaysUntilDue(DEADLINE_REPIN_HEADS_UP_DAY),
      }),
    ];

    await runHandler();

    const byItem = Object.fromEntries(
      dbState.markerAttempts.map((a) => [a.item_id, a.tick_key]),
    );
    expect(byItem).toEqual({ band: "daily:2026-03-10", heads: "headsup" });
  });

  it("T9c: an OVERDUE item still pings daily (the most dangerous bucket)", async () => {
    // D6 gap: every other fixture in this file uses a non-negative
    // daysUntilDue, so the overdue path — the one the SUT's own comment calls
    // "the most dangerous bucket ... must never be silent" — was untested.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [
      statutoryRow({ id: "overdue", user_id: "u-od", received_at: receivedAtForDaysUntilDue(-5) }),
    ];

    const result = await runHandler();

    expect(result.repinged).toBe(1);
    expect(dbState.markerAttempts).toEqual([
      { item_id: "overdue", tick_key: "daily:2026-03-10" },
    ]);
  });

  it("T10: rows hitting a pre-existing guard write NO marker", async () => {
    // Marker placement is AFTER every pre-existing `continue`. A marker
    // written before them would permanently suppress a row that was never
    // actually sent — silence on a statutory clock, reported as success.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [
      statutoryRow({ id: "anon", user_id: null }),
      statutoryRow({ id: "unknown-rule", rule_id: "no-such-rule" }),
      // POSITIVE CONTROL. Without a valid row here, both assertions below are
      // satisfied by "the loop never ran" — a fixture that drifts out of the
      // band, a renamed status column, or a routing change in the fake all
      // produce 0 markers and 0 emails and this test stays green having proven
      // nothing. T2 already carries this defence; T10 needs it too.
      statutoryRow({ id: "valid", user_id: "user-valid" }),
    ];

    await runHandler();

    // The loop DID run and DID reach the marker site — for the valid row only.
    expect(dbState.markerAttempts).toEqual([
      { item_id: "valid", tick_key: "daily:2026-03-10" },
    ]);
    expect(statutoryEmailCalls()).toHaveLength(1);
    expect(statutoryEmailCalls()[0].to).toEqual(["user-valid@example.test"]);
  });

  it("T11: a push-subscribed user double-firing gets exactly ONE push", async () => {
    // The guard has to hold on the push branch too, not just the email
    // fallback — otherwise the duplicate simply moves to the other channel.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow()];
    dbState.pushSubs["user-1"] = [
      { id: "sub-1", endpoint: "https://push.example/1", p256dh: "k", auth: "a" },
    ];

    await runHandler();
    await runHandler();

    expect(webpushSendSpy).toHaveBeenCalledTimes(1);
    expect(statutoryEmailCalls()).toHaveLength(0); // push path, not email
  });

  it("T11b: a statutory push that reaches ZERO devices is surfaced", async () => {
    // The guard removes an accidental self-heal. Before it, a failed push left
    // the subscription un-pruned and the NEXT tick retried. Now the marker is
    // already written, so nothing retries — an all-fail push is permanent
    // silence on a legal clock while the step reports `pinged`. That must not
    // be inferable only from a missing email; it has to page.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow()];
    dbState.pushSubs["user-1"] = [
      { id: "sub-1", endpoint: "https://push.example/1", p256dh: "k", auth: "a" },
    ];
    // Non-410: no prune, no self-heal.
    webpushSendSpy.mockRejectedValue({ statusCode: 500 });

    await runHandler();

    expect(warnSilentFallbackSpy).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ op: "statutory-notify-zero-delivery" }),
    );
  });

  it("T13: the marker insert requests NO column the table lacks (42703 tripwire)", async () => {
    // REGRESSION. This file originally shipped 20/20 green over a guard that
    // could not work in production: it used `.select("id").single()`, cloned
    // from notifyInboxItem, but statutory_repin_send has no `id` column (its
    // PK is composite). PostgREST turns that into a RETURNING clause and the
    // real statement fails 42703 → non-23505 → fail open → dispatch, with no
    // marker ever written. The guard would have been inert, forever, and this
    // suite would have kept certifying it.
    //
    // The fake now validates selected columns (TABLE_COLUMNS), so re-adding a
    // bad `.select()` reddens T1/T2/T11 too. This test states the invariant
    // directly so the NEXT reader sees the reason rather than a mystery.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow()];

    const result = await runHandler();

    // The insert succeeded and suppressed on the second run — i.e. it really
    // wrote, rather than erroring into the fail-open path.
    expect(result.repinged).toBe(1);
    const second = await runHandler();
    expect(second.repinSuppressed).toBe(1);

    // And no 42703 was surfaced on either run.
    const marker42703 = warnSilentFallbackSpy.mock.calls.filter(
      ([err]) => (err as { code?: string } | null)?.code === "42703",
    );
    expect(marker42703).toHaveLength(0);
  });

  it("T13b: the fake itself rejects an unknown column (negative control for T13)", () => {
    // Without this, T13 could pass against a fake that cannot reject at all.
    const b = makeBuilder("statutory_repin_send") as Record<string, unknown>;
    (b.insert as (p: unknown) => unknown)({ item_id: "x", tick_key: "headsup" });
    (b.select as (c: string) => unknown)("id");
    return (b.single as () => Promise<{ error: { code: string } | null }>)().then(
      (res) => {
        expect(res.error?.code).toBe("42703");
      },
    );
  });

  it("T14: the operator release verb clears markers and re-arms the item", async () => {
    // The recovery path the plan required and that must not need prod SQL.
    // Without it, the statutory-notify-zero-delivery alarm names a problem the
    // operator has no lever to fix.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    const uuid = "3f2504e0-4f89-11d3-9a0c-0305e82c3301";
    dbState.repinRows = [statutoryRow({ id: uuid })];

    await runHandler();
    const suppressed = await runHandler();
    expect(suppressed.repinSuppressed).toBe(1);
    expect(statutoryEmailCalls()).toHaveLength(1);

    // Release, then the SAME tick can send again — proving a real re-arm, not
    // just a row count.
    const rel = await runHandler({ data: { release_item_id: uuid } });
    expect(rel.released).toEqual({ itemId: uuid, cleared: 1 });
    expect(statutoryEmailCalls()).toHaveLength(2);
  });

  it("T14b: a non-uuid release_item_id is refused, not passed to the RPC", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [];

    const result = await runHandler({ data: { release_item_id: "'; DROP TABLE --" } });

    expect(result.released).toBeNull();
    expect(
      rpcSpy.mock.calls.filter(
        ([name, args]) =>
          name === "purge_statutory_repin_send" &&
          (args as Record<string, unknown> | undefined)?.p_item_id !== undefined,
      ),
    ).toHaveLength(0);
    expect(warnSilentFallbackSpy).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ op: "statutory-repin-release-invalid-id" }),
    );
  });

  it("T14c: a scheduled run (no event) performs no release", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));
    dbState.repinRows = [statutoryRow()];

    const result = await runHandler();

    expect(result.released).toBeNull();
    expect(ioOrder).not.toContain("rpc:purge_statutory_repin_send:targeted");
  });

  it("T12: the send path is SINGLE-RECIPIENT (R7 tripwire — do not delete)", async () => {
    // ─────────────────────────────────────────────────────────────────────
    // CONSTRAINT: statutory_repin_send is keyed (item_id, tick_key) — ITEM
    // grain. That equals RECIPIENT grain only because this send path pings
    // `row.user_id` and nobody else. It is a property of the send path, NOT
    // a structural guarantee: migration 111 already makes an item visible to
    // every workspace Owner.
    //
    // IF THIS TEST GOES RED because the repin now fans out to multiple
    // recipients: do NOT relax the assertion. Re-key the marker table to
    // recipient grain first (see migration 135 header note 4 and the ADR-035
    // recipient-grain clause). Leaving it item-grained under a fan-out means
    // the first Owner's marker suppresses every other Owner — N-1 people get
    // SILENCE on a statutory deadline while the run reports success.
    // ─────────────────────────────────────────────────────────────────────
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-10T06:00:00Z"));

    // An item whose workspace has three Owners. Only the ledger row's own
    // user_id may be pinged.
    dbState.userEmails = {
      "owner-primary": "primary@example.test",
      "owner-second": "second@example.test",
      "owner-third": "third@example.test",
    };
    dbState.repinRows = [statutoryRow({ id: "shared-item", user_id: "owner-primary" })];
    // Discoverable co-Owners: a membership-querying fan-out finds these.
    dbState.workspaceOwners = [
      { user_id: "owner-primary", role: "owner" },
      { user_id: "owner-second", role: "owner" },
      { user_id: "owner-third", role: "owner" },
    ];

    const result = await runHandler();

    const emails = statutoryEmailCalls();
    expect(emails).toHaveLength(1);
    expect(emails[0].to).toEqual(["primary@example.test"]);
    expect(result.repinged).toBe(1);

    // The other Owners were never even looked up — proof the fan-out does not
    // exist yet, at the exact site the constraint governs.
    const lookedUp = getUserByIdSpy.mock.calls.map((c) => c[0]);
    expect(lookedUp).toEqual(["owner-primary"]);
    expect(lookedUp).not.toContain("owner-second");
    expect(lookedUp).not.toContain("owner-third");

    // Branch-agnostic: a fan-out that routes to PUSH instead of email would
    // not move statutoryEmailCalls() at all, so assert the other channel is
    // silent too. Without this the tripwire only catches an email-shaped
    // fan-out — the less likely variant.
    expect(webpushSendSpy).toHaveBeenCalledTimes(0);

    // And exactly one marker, at item grain. NOTE: this assertion alone does
    // NOT discriminate — one item-grain marker is exactly what the BUGGY
    // fan-out produces. It is the recipient assertions above that red.
    expect(dbState.markerAttempts).toEqual([
      { item_id: "shared-item", tick_key: "daily:2026-03-10" },
    ]);
  });
});

// =============================================================================
// T7 — DDL pin. Asserts the shape of the migration text itself, so a later
// edit that drops the PK/FK/CHECK or replaces a pre-existing function is
// caught without needing a live database.

describe("T7: migration 135 DDL pin", () => {
  const migrationDir = resolve(__dirname, "../../../supabase/migrations");
  const up = readFileSync(
    resolve(migrationDir, "135_statutory_repin_send.sql"),
    "utf8",
  );
  const down = readFileSync(
    resolve(migrationDir, "135_statutory_repin_send.down.sql"),
    "utf8",
  );

  it("pins the composite primary key", () => {
    expect(up).toMatch(/PRIMARY\s+KEY\s*\(\s*item_id\s*,\s*tick_key\s*\)/);
  });

  it("pins the cascading FK to the parent ledger", () => {
    expect(up).toMatch(
      /REFERENCES\s+public\.email_triage_items\(id\)\s+ON\s+DELETE\s+CASCADE/,
    );
  });

  it("pins the tick_key CHECK to exactly the two legal shapes", () => {
    expect(up).toMatch(/CHECK\s*\(\s*tick_key\s*=\s*'headsup'/);
    expect(up).toMatch(/\^daily:\\d\{4\}-\\d\{2\}-\\d\{2\}\$/);
  });

  it("carries NO user_id column (Art. 17 lives on the parent row)", () => {
    // Anchored on the column-definition shape, not the bare token: the header
    // prose deliberately discusses `user_id` at length, and a bare-token grep
    // would match that comment and pass vacuously forever.
    expect(up).not.toMatch(/^\s*user_id\s+uuid/m);
  });

  it("enables RLS and grants the sweep RPC to service_role only", () => {
    expect(up).toMatch(
      /ALTER\s+TABLE\s+public\.statutory_repin_send\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/,
    );
    expect(up).toMatch(
      /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.purge_statutory_repin_send\(uuid\)\s*\n?\s*TO\s+service_role/,
    );
  });

  it("pins the SECURITY DEFINER search_path (cq-pg-security-definer-search-path-pin-pg-temp)", () => {
    // Anchored to the FUNCTION BODY, not the bare token. The migration header
    // says, in prose, "the RPC pins SET search_path = public, pg_temp" — so a
    // bare-token match passes even if the real SET is deleted from the
    // function. That is cq-assert-anchor-not-bare-token, and it is the same
    // trap that bit AC3 and AC9 in this PR's own acceptance criteria.
    expect(up).toMatch(
      /CREATE OR REPLACE FUNCTION public\.purge_statutory_repin_send[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp[\s\S]*?AS \$\$/,
    );
    // And the SET must be real SQL, never a commented-out line.
    expect(up).toMatch(/^\s*SET\s+search_path\s*=\s*public,\s*pg_temp/m);
  });

  it("does NOT replace either pre-existing email_triage function", () => {
    // Security attributes do not survive a CREATE OR REPLACE and both AP-018
    // guard tiers are blind to the drop.
    expect(up).not.toMatch(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.purge_email_triage_items/);
    expect(up).not.toMatch(
      /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_email_triage_items/,
    );
  });

  it("deletes its ledger row in the down file (required for re-apply)", () => {
    expect(down).toMatch(
      /DELETE\s+FROM\s+public\._schema_migrations\s+WHERE\s+filename\s*=\s*'135_statutory_repin_send\.sql'/,
    );
  });
});

// =============================================================================
// T7b — gated live-DB tier. Proves the REAL table rejects a duplicate with
// 23505, which is the assumption every mocked test above rests on.

describe.runIf(process.env.TENANT_INTEGRATION_TEST === "1")(
  "T7b: live-DB unique violation",
  () => {
    it("returns 23505 on a duplicate (item_id, tick_key)", async () => {
      const { createServiceClient: realClient } = await vi.importActual<
        typeof import("@/lib/supabase/service")
      >("@/lib/supabase/service");
      const sb = realClient();

      const { data: item } = await sb
        .from("email_triage_items")
        .select("id")
        .limit(1)
        .single();
      // No silent skip: an empty ledger in the target environment must fail as
      // a FIXTURE error, not report green. This tier exists to be the ground
      // truth for the mocked suite above; a silent pass reintroduces exactly
      // the trap tenant-integration.yml was built to close.
      if (!item) {
        expect.fail(
          "fixture precondition: no email_triage_items row to key a marker against",
        );
      }

      const tickKey = `daily:${new Date().toISOString().slice(0, 10)}`;
      await sb.from("statutory_repin_send").insert({ item_id: item.id, tick_key: tickKey });
      const { error } = await sb
        .from("statutory_repin_send")
        .insert({ item_id: item.id, tick_key: tickKey });

      expect(error?.code).toBe("23505");

      await sb.rpc("purge_statutory_repin_send", { p_item_id: item.id });
    });
  },
);
