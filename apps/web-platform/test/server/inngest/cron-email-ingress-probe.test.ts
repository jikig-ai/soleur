// cron-email-ingress-probe — handler-direct unit tests (Phase 6,
// feat-operator-inbox-delegation).
//
// Eager mock step (run executes the callback immediately) + a no-op `sleep`
// that RECORDS the duration — the event-scheduled-reminder.test.ts makeStep
// precedent lacks `sleep`, and without recording it the 15-min await-ingress
// gap (the probe's whole SLA) would be untestable.
//
// Covered contracts:
//   - step ORDER: retention-purge → deadline-repin → send-probe →
//     sleep("await-ingress","15m") → assert-probe-row (purge FIRST — a broken
//     ingress chain must not starve Art. 5(1)(e)).
//   - purge RPC called; an RPC error FAILS THE RUN (no try/catch swallow).
//   - deadline re-pin fires at floor-days-until-due === 7 (heads-up) and
//     DAILY from 2 through overdue (2/1/0/-1) — never 8/6/3 (dsar-art15
//     calendar-month fixtures, fake clock). Scan bounded to 60d (C2).
//   - probe_tokens insert happens BEFORE the Resend send (an unrecorded
//     token would make our own probe classify as forgeable-shape 'other').
//   - subject carries SOLEUR-PROBE-<uuid>.
//   - probe row found → OK check-in; absent → failed check-in + throw.
//   - function config pins `retries: 0` (default retries would turn a
//     late-landing probe into a retry-then-green run that never alarms).
//   - zero Anthropic involvement (grep assert on the source file — the probe
//     is NOT a statutory class; AC3c's statutory-path assertion misses it).

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Hoisted spies ----------------------------------------------------------

const {
  rpcSpy,
  notifySpy,
  resendSendSpy,
  heartbeatSpy,
  warnSilentFallbackSpy,
  reportSilentFallbackSpy,
  infoSilentFallbackSpy,
  ioOrder,
  dbState,
} = vi.hoisted(() => {
  const ioOrder: string[] = [];
  const dbState: {
    purgeResult: { data: unknown; error: { message: string } | null };
    repinRows: Array<Record<string, unknown>>;
    repinError: { code?: string } | null;
    tokenInsertError: { code?: string } | null;
    assertRows: Array<{ id: string; subject?: string | null }>;
    assertError: { code?: string } | null;
  } = {
    purgeResult: { data: { probe_deleted: 0 }, error: null },
    repinRows: [],
    repinError: null,
    tokenInsertError: null,
    assertRows: [{ id: "probe-row-1" }],
    assertError: null,
  };
  return {
    rpcSpy: vi.fn(),
    notifySpy: vi.fn(async (..._args: unknown[]) => undefined),
    resendSendSpy: vi.fn(),
    heartbeatSpy: vi.fn(async (..._args: unknown[]) => undefined),
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

vi.mock("@/server/observability", () => ({
  warnSilentFallback: warnSilentFallbackSpy,
  reportSilentFallback: reportSilentFallbackSpy,
  // The repin sweep counter (#6781) goes through the observability layer, not
  // pino stdout — Vector keeps only level_int >= 40, so an info-level stdout
  // line would never reach Better Stack.
  infoSilentFallback: infoSilentFallbackSpy,
}));

vi.mock("@/server/notifications", () => ({
  notifyOfflineUser: notifySpy,
}));

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

vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return { ...actual, postSentryHeartbeat: heartbeatSpy };
});

// Chainable thenable supabase query mock. Distinguishes the two
// email_triage_items reads by their .eq() args (repin keys on status=
// acknowledged; assert keys on mail_class=probe). Records gte/like calls
// per-query into `recordedQueries` so the bounded-scan (C2) and
// index-friendly-assert (C3) shapes are assertable. Assert rows without an
// explicit subject get the actually-sent probe subject filled in, since
// the token is minted inside the handler.
interface RecordedQuery {
  table: string;
  eqArgs: Array<[string, unknown]>;
  gteArgs: Array<[string, unknown]>;
  likeCalls: number;
}

const recordedQueries: RecordedQuery[] = [];

function sentProbeSubject(): string | undefined {
  const sendArg = resendSendSpy.mock.calls[0]?.[0] as
    | { subject?: string }
    | undefined;
  return sendArg?.subject;
}

function makeBuilder(table: string) {
  const record: RecordedQuery = {
    table,
    eqArgs: [],
    gteArgs: [],
    likeCalls: 0,
  };
  recordedQueries.push(record);
  const eqArgs = record.eqArgs;
  let inserting = false;
  const builder: Record<string, unknown> = {};
  const chain = () => builder;
  for (const m of ["select", "not", "ilike", "limit"]) {
    builder[m] = vi.fn(chain);
  }
  builder.like = vi.fn(() => {
    record.likeCalls += 1;
    return builder;
  });
  builder.gte = vi.fn((col: string, val: unknown) => {
    record.gteArgs.push([col, val]);
    return builder;
  });
  builder.eq = vi.fn((col: string, val: unknown) => {
    eqArgs.push([col, val]);
    return builder;
  });
  builder.insert = vi.fn(() => {
    inserting = true;
    return builder;
  });
  builder.then = (
    onFulfilled: (v: unknown) => unknown,
    onRejected?: (e: unknown) => unknown,
  ) => {
    let result: unknown;
    if (table === "statutory_repin_send" && inserting) {
      // Send-marker insert (#6781). The guard uses a PLAIN `.insert()` with no
      // `.select()` (the table has no `id` column to return), so this lands on
      // the awaited path, not `.single()`. Always a clean insert here: this
      // suite covers step order and the probe chain; the dedicated
      // cron-email-ingress-probe-repin-idempotency.test.ts owns 23505 behavior.
      ioOrder.push("repin-marker-insert");
      result = { data: null, error: null };
    } else if (table === "probe_tokens" && inserting) {
      ioOrder.push("probe-token-insert");
      result = { data: null, error: dbState.tokenInsertError };
    } else if (eqArgs.some(([c, v]) => c === "status" && v === "acknowledged")) {
      result = { data: dbState.repinRows, error: dbState.repinError };
    } else if (eqArgs.some(([c, v]) => c === "mail_class" && v === "probe")) {
      const rows = dbState.assertRows.map((r) =>
        "subject" in r ? r : { ...r, subject: sentProbeSubject() ?? null },
      );
      result = { data: rows, error: dbState.assertError };
    } else {
      result = { data: [], error: null };
    }
    return Promise.resolve(result).then(onFulfilled, onRejected);
  };
  return builder;
}

const fromSpy = vi.fn((table: string) => makeBuilder(table));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({
    rpc: rpcSpy,
    from: fromSpy,
  })),
}));

import {
  cronEmailIngressProbeHandler,
  SENTRY_MONITOR_SLUG,
} from "@/server/inngest/functions/cron-email-ingress-probe";
import { inngest } from "@/server/inngest/client";

// --- Helpers ------------------------------------------------------------------

interface StepCall {
  kind: "run" | "sleep";
  name: string;
  duration?: string;
}

/**
 * Eager mock step. Unlike the event-scheduled-reminder precedent this ADDS a
 * no-op `sleep` that records its duration so the 15-min await window is
 * assertable, and interleaves run/sleep into ONE calls array so step ORDER
 * (purge before probe, sleep before assert) is provable.
 */
function makeStep() {
  const calls: StepCall[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      calls.push({ kind: "run", name });
      return cb();
    },
    async sleep(name: string, duration: string): Promise<void> {
      calls.push({ kind: "sleep", name, duration });
    },
  };
}

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

function runHandler() {
  const step = makeStep();
  return {
    step,
    result: cronEmailIngressProbeHandler({ step, logger } as never),
  };
}

// Fixed clock for the deadline-repin boundary fixtures.
const NOW = "2026-06-11T12:00:00.000Z";

function dsarRow(id: string, receivedAt: string): Record<string, unknown> {
  return {
    id,
    user_id: "owner-user-1",
    received_at: receivedAt,
    rule_id: "dsar-art15",
    statutory_class: "dsar",
  };
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(NOW));
  process.env.RESEND_API_KEY = "re_test_key";
  ioOrder.length = 0;
  dbState.purgeResult = { data: { probe_deleted: 0 }, error: null };
  dbState.repinRows = [];
  dbState.repinError = null;
  dbState.tokenInsertError = null;
  dbState.assertRows = [{ id: "probe-row-1" }];
  dbState.assertError = null;
  rpcSpy.mockReset();
  rpcSpy.mockImplementation(async (name: string) =>
    name === "purge_statutory_repin_send"
      ? { data: 0, error: null }
      : dbState.purgeResult,
  );
  notifySpy.mockClear();
  resendSendSpy.mockReset();
  resendSendSpy.mockResolvedValue({ data: { id: "email-1" }, error: null });
  heartbeatSpy.mockClear();
  warnSilentFallbackSpy.mockClear();
  reportSilentFallbackSpy.mockClear();
  fromSpy.mockClear();
  recordedQueries.length = 0;
});

afterEach(() => {
  vi.useRealTimers();
});

// --- Tests ----------------------------------------------------------------

describe("cron-email-ingress-probe — step order", () => {
  it("runs purge → repin → send-probe → sleep(15m) → assert, in that exact order", async () => {
    const { step, result } = runHandler();
    await result;
    expect(step.calls).toEqual([
      { kind: "run", name: "retention-purge" },
      { kind: "run", name: "deadline-repin" },
      { kind: "run", name: "send-probe" },
      { kind: "sleep", name: "await-ingress", duration: "15m" },
      { kind: "run", name: "assert-probe-row" },
    ]);
  });

  it("sleeps exactly 15m between send and assert", async () => {
    const { step, result } = runHandler();
    await result;
    const sleep = step.calls.find((c) => c.kind === "sleep");
    expect(sleep?.duration).toBe("15m");
    const sendIdx = step.calls.findIndex((c) => c.name === "send-probe");
    const sleepIdx = step.calls.findIndex((c) => c.kind === "sleep");
    const assertIdx = step.calls.findIndex((c) => c.name === "assert-probe-row");
    expect(sendIdx).toBeLessThan(sleepIdx);
    expect(sleepIdx).toBeLessThan(assertIdx);
  });
});

describe("cron-email-ingress-probe — retention purge (Art. 5(1)(e) first)", () => {
  it("calls the purge_email_triage_items RPC", async () => {
    const { result } = runHandler();
    await result;
    expect(rpcSpy).toHaveBeenCalledWith("purge_email_triage_items");
  });

  it("a purge RPC error FAILS THE RUN — not swallowed, no later steps, no check-in", async () => {
    dbState.purgeResult = { data: null, error: { message: "boom" } };
    const { step, result } = runHandler();
    await expect(result).rejects.toThrow(/purge/i);
    // Purge failure must abort before the probe send — the step breadcrumb
    // (retention-purge) is what disambiguates purge-broken from
    // ingress-broken in the Layer 1 capture.
    expect(step.calls).toEqual([{ kind: "run", name: "retention-purge" }]);
    expect(resendSendSpy).not.toHaveBeenCalled();
    expect(heartbeatSpy).not.toHaveBeenCalled();
  });
});

describe("cron-email-ingress-probe — deadline re-pin (acknowledge ≠ legal resolution)", () => {
  it("pings at floor 7 (heads-up) and DAILY from floor 2 through overdue — never 8/6/3", async () => {
    // dsar-art15 is calendar-month: due = received_at + 1 month (clamped).
    // Now = 2026-06-11T12:00Z. received 2026-05-DD T00:00Z → due 2026-06-DD
    // T00:00Z → days-until-due = (DD - 11) - 0.5 → floor (DD - 12).
    // The overdue/danger bucket (floor <= 2, incl. negative) fires DAILY —
    // an exact-day match would go silent on an already-overdue item or any
    // day skipped by a missed cron run.
    dbState.repinRows = [
      dsarRow("due-in-8", "2026-05-20T00:00:00.000Z"), // floor 8 — no ping
      dsarRow("due-in-7", "2026-05-19T00:00:00.000Z"), // floor 7 — PING (heads-up)
      dsarRow("due-in-6", "2026-05-18T00:00:00.000Z"), // floor 6 — no ping
      dsarRow("due-in-3", "2026-05-15T00:00:00.000Z"), // floor 3 — no ping
      dsarRow("due-in-2", "2026-05-14T00:00:00.000Z"), // floor 2 — PING (daily)
      dsarRow("due-in-1", "2026-05-13T00:00:00.000Z"), // floor 1 — PING (daily)
      dsarRow("due-in-0", "2026-05-12T00:00:00.000Z"), // floor 0 — PING (daily)
      dsarRow("overdue-1", "2026-05-11T00:00:00.000Z"), // floor -1 — PING (daily)
    ];
    const { result } = runHandler();
    const resolved = await result;

    expect(notifySpy).toHaveBeenCalledTimes(5);

    // #6781: the send-marker guard surfaces a suppression counter on the
    // handler result. Every insert is clean in this suite's fake, so the
    // count is 0 here — a NON-zero value in production is the signal that a
    // second scheduler is live and double-firing.
    expect(resolved.repinSuppressed).toBe(0);
    expect(resolved.repinged).toBe(5);
    // And each ping wrote its marker before dispatching.
    expect(ioOrder.filter((e) => e === "repin-marker-insert")).toHaveLength(5);
    const pingedIds = notifySpy.mock.calls.map(
      (c) => (c[1] as { emailId: string }).emailId,
    );
    expect(pingedIds.sort()).toEqual([
      "due-in-0",
      "due-in-1",
      "due-in-2",
      "due-in-7",
      "overdue-1",
    ]);
  });

  it("bounds the repin scan to received_at >= now - 60 days (C2)", async () => {
    const { result } = runHandler();
    await result;
    const repinQuery = recordedQueries.find((q) =>
      q.eqArgs.some(([c, v]) => c === "status" && v === "acknowledged"),
    );
    expect(repinQuery).toBeDefined();
    expect(repinQuery!.gteArgs).toContainEqual([
      "received_at",
      new Date(Date.parse(NOW) - 60 * 24 * 60 * 60 * 1000).toISOString(),
    ]);
  });

  it("ping payload is the email_triage statutory shape with a formatted due date", async () => {
    dbState.repinRows = [dsarRow("due-in-7", "2026-05-19T00:00:00.000Z")];
    const { result } = runHandler();
    await result;

    expect(notifySpy).toHaveBeenCalledWith("owner-user-1", {
      type: "email_triage",
      emailId: "due-in-7",
      // #6798 (M2): the verb is now state-accurate ("(computed) approaching"
      // for a future due date), and the rule's clock-origin excerpt rides in
      // `statutoryExcerpt` for the email body.
      title: expect.stringMatching(
        /^Statutory deadline \(computed\) approaching — due 19 Jun 2026/,
      ),
      isStatutory: true,
      statutoryExcerpt: expect.stringContaining("one calendar month of receipt"),
    });
  });
});

describe("cron-email-ingress-probe — probe send", () => {
  it("inserts the probe_tokens row BEFORE the Resend send", async () => {
    const { result } = runHandler();
    await result;
    expect(ioOrder).toEqual(["probe-token-insert", "resend-send"]);
  });

  it("subject carries SOLEUR-PROBE-<uuid>, from notifications@ to ops@", async () => {
    const { result } = runHandler();
    await result;
    expect(resendSendSpy).toHaveBeenCalledTimes(1);
    const sendArg = resendSendSpy.mock.calls[0][0] as {
      from: string;
      to: string[];
      subject: string;
    };
    expect(sendArg.subject).toMatch(
      /^SOLEUR-PROBE-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    );
    expect(sendArg.from).toContain("notifications@soleur.ai");
    expect(sendArg.to).toEqual(["ops@soleur.ai"]);
  });
});

describe("cron-email-ingress-probe — same-run assertion", () => {
  it("probe row found → OK Sentry check-in", async () => {
    const { result } = runHandler();
    await expect(result).resolves.toMatchObject({ ok: true });
    expect(heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatSpy.mock.calls[0][0]).toMatchObject({
      ok: true,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
    });
  });

  it("probe row ABSENT → failed check-in + throw (terminal under retries: 0)", async () => {
    dbState.assertRows = [];
    const { result } = runHandler();
    await expect(result).rejects.toThrow(/probe/i);
    expect(heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(heartbeatSpy.mock.calls[0][0]).toMatchObject({
      ok: false,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
    });
  });

  it("assert query is index-friendly (C3): eq mail_class + gte created_at, NO leading-wildcard LIKE", async () => {
    const { result } = runHandler();
    await result;
    const assertQuery = recordedQueries.find((q) =>
      q.eqArgs.some(([c, v]) => c === "mail_class" && v === "probe"),
    );
    expect(assertQuery).toBeDefined();
    expect(assertQuery!.likeCalls).toBe(0);
    expect(
      assertQuery!.gteArgs.some(([col]) => col === "created_at"),
    ).toBe(true);
  });

  it("token match stays EXACT in JS: a probe row carrying a different token does not satisfy the assertion", async () => {
    dbState.assertRows = [
      {
        id: "probe-row-other",
        subject: "SOLEUR-PROBE-ffffffff-ffff-4fff-8fff-ffffffffffff",
      },
    ];
    const { result } = runHandler();
    await expect(result).rejects.toThrow(/probe/i);
    expect(heartbeatSpy.mock.calls[0][0]).toMatchObject({ ok: false });
  });
});

describe("cron-email-ingress-probe — registration config", () => {
  it("pins retries: 0 — default retries turn a late probe into a green run", () => {
    const createFn = vi.mocked(inngest.createFunction);
    expect(createFn).toHaveBeenCalledTimes(1);
    const opts = createFn.mock.calls[0][0] as { id: string; retries: number };
    expect(opts.id).toBe("cron-email-ingress-probe");
    expect(opts.retries).toBe(0);
  });

  it("registers the cron schedule AND the derived manual-trigger event", () => {
    const createFn = vi.mocked(inngest.createFunction);
    const triggers = createFn.mock.calls[0][1] as Array<
      { cron: string } | { event: string }
    >;
    expect(triggers).toContainEqual({ cron: "0 6 * * *" });
    expect(triggers).toContainEqual({
      event: "cron/email-ingress-probe.manual-trigger",
    });
  });
});

describe("cron-email-ingress-probe — zero Anthropic involvement", () => {
  it("the probe source imports no Anthropic SDK (probe is NOT a statutory class — AC3c does not cover it)", () => {
    const src = readFileSync(
      resolve(
        __dirname,
        "../../../server/inngest/functions/cron-email-ingress-probe.ts",
      ),
      "utf8",
    );
    // Import-line grep (comments may legitimately mention the word): no
    // Anthropic SDK module, no summarizer module, anywhere in the imports.
    expect(src).not.toMatch(/from\s+["'][^"']*anthropic[^"']*["']/i);
    expect(src).not.toMatch(/require\(\s*["'][^"']*anthropic[^"']*["']\s*\)/i);
    expect(src).not.toMatch(/summarizeEmail|email-triage\/summarize/);
  });
});
