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
//   T12 single-recipient send path               → R7 tripwire (CPO C5)

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
    /** Every marker insert attempted, in order (incl. rejected ones). */
    markerAttempts: Array<{ item_id: string; tick_key: string }>;
    /** Force a non-23505 `{error}` return on the Nth attempt (1-based). */
    markerErrorOnAttempt: number | null;
    /** Force a THROW on the Nth attempt (1-based). */
    markerThrowOnAttempt: number | null;
    /** user_id → push subscription rows. */
    pushSubs: Record<string, Array<Record<string, unknown>>>;
    /** user_id → email address. */
    userEmails: Record<string, string>;
  } = {
    repinRows: [],
    markers: new Set<string>(),
    markerAttempts: [],
    markerErrorOnAttempt: null,
    markerThrowOnAttempt: null,
    pushSubs: {},
    userEmails: {},
  };
  return {
    resendSendSpy: vi.fn(async (..._args: unknown[]) => ({ error: null })),
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

  for (const m of ["not", "gte", "ilike", "like", "limit", "update", "in"]) {
    builder[m] = vi.fn(chain);
  }
  builder.select = vi.fn((cols?: string) => {
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
    } else if (table === "push_subscriptions" && !deleting) {
      const userId = eqArgs.find(([c]) => c === "user_id")?.[1] as string;
      result = { data: dbState.pushSubs[userId] ?? [], error: null };
    } else if (
      table === "email_triage_items" &&
      eqArgs.some(([c, v]) => c === "status" && v === "acknowledged")
    ) {
      result = { data: dbState.repinRows, error: null };
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
  return { data: { item_id: itemId, tick_key: tickKey }, error: null };
}

const rpcSpy = vi.fn(async (name: string) => {
  ioOrder.push(`rpc:${name}`);
  if (name === "purge_email_triage_items") {
    return { data: { probe_deleted: 0 }, error: null };
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
} from "@/server/inngest/functions/cron-email-ingress-probe";

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

function runHandler() {
  const step = makeStep();
  return cronEmailIngressProbeHandler({ step, logger } as never);
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
  dbState.markerAttempts = [];
  dbState.markerErrorOnAttempt = null;
  dbState.markerThrowOnAttempt = null;
  dbState.pushSubs = {};
  dbState.userEmails = {};
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

    const keys = new Set(dbState.markerAttempts.map((a) => a.tick_key));
    expect(keys.size).toBe(1);
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
    ];

    await runHandler();

    expect(dbState.markerAttempts).toHaveLength(0);
    expect(statutoryEmailCalls()).toHaveLength(0);
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

    // And exactly one marker, at item grain.
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
    expect(up).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/);
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
      if (!item) return; // nothing to key against in this environment

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
