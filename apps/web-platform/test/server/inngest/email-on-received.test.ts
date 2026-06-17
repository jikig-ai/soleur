import { beforeEach, describe, expect, it, vi } from "vitest";

// feat-operator-inbox-delegation Phase 4 — email-on-received pipeline.
//
// Handler-direct invocation with an eager mock `step` (precedent
// cfo-on-payment-failed.test.ts + event-scheduled-reminder.test.ts:46-66).
// The Anthropic SDK is mocked at the module boundary
// (agent-on-spawn-requested-leader-loop.test.ts:198-203 precedent) and the
// body fetch sits behind its OWN mocked module
// (@/server/email-triage/fetch-received-email) — NEVER a shared global
// fetch mock, so statutory short-circuit tests can prove the fetch module
// was structurally unreachable independent of the LLM mock.

const {
  anthropicCreateSpy,
  fetchReceivedEmailSpy,
  notifyOfflineUserSpy,
  reportSilentFallbackSpy,
  warnSilentFallbackSpy,
  captureExceptionSpy,
  captureMessageSpy,
  loggerSpies,
  dbHolder,
} = vi.hoisted(() => {
  const loggerSpies = {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  };
  return {
    anthropicCreateSpy: vi.fn(),
    fetchReceivedEmailSpy: vi.fn(),
    // Typed with the 2-arg shape so `mock.calls[i][j]` indices resolve
    // under strict TS (agent-on-spawn-requested-leader-loop.test.ts pattern).
    notifyOfflineUserSpy: vi.fn(
      async (
        _userId: string,
        _payload: Record<string, unknown>,
      ): Promise<void> => undefined,
    ),
    reportSilentFallbackSpy: vi.fn(),
    warnSilentFallbackSpy: vi.fn(),
    captureExceptionSpy: vi.fn(),
    captureMessageSpy: vi.fn(),
    loggerSpies,
    dbHolder: { current: null as null | { from: (table: string) => unknown } },
  };
});

vi.mock("@anthropic-ai/sdk", () => {
  class AnthropicMock {
    messages = { create: anthropicCreateSpy };
    constructor(public opts: { apiKey: string }) {}
  }
  return { default: AnthropicMock, __esModule: true };
});

vi.mock("@/server/email-triage/fetch-received-email", () => ({
  fetchReceivedEmail: fetchReceivedEmailSpy,
}));

vi.mock("@/server/notifications", () => ({
  notifyOfflineUser: notifyOfflineUserSpy,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: warnSilentFallbackSpy,
  APP_URL_FALLBACK: "https://app.soleur.ai",
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: captureExceptionSpy,
  captureMessage: captureMessageSpy,
}));

vi.mock("@/server/logger", () => ({
  default: loggerSpies,
  createChildLogger: () => loggerSpies,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { createFunction: vi.fn(() => ({})), send: vi.fn() },
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => {
    if (!dbHolder.current) throw new Error("test db not configured");
    return dbHolder.current;
  },
}));

import {
  emailOnReceivedHandler,
  resetOwnerValidationMemo,
  EMAIL_TRIAGE_DAILY_LLM_CEILING,
} from "@/server/inngest/functions/email-on-received";
import { MAIL_CLASS_ALLOWLIST } from "@/server/email-triage/summarize";

// --- Supabase service-client fake -------------------------------------------

interface DbFilter {
  kind: "eq" | "neq" | "not" | "gte" | "is";
  col: string;
  val?: unknown;
}

interface DbOp {
  table: string;
  method: "insert" | "select" | "update";
  payload?: unknown;
  filters: DbFilter[];
  countExact: boolean;
  head: boolean;
}

interface DbResult {
  data?: unknown;
  error?: { code?: string; message?: string } | null;
  count?: number | null;
}

function makeDb(script: (op: DbOp) => DbResult) {
  const ops: DbOp[] = [];
  const client = {
    from(table: string) {
      const op: DbOp = {
        table,
        method: "select",
        filters: [],
        countExact: false,
        head: false,
      };
      const finish = () => {
        ops.push(op);
        return { data: null, error: null, count: null, ...script(op) };
      };
      const builder: Record<string, unknown> = {};
      const chain =
        (fn: (...a: unknown[]) => void) =>
        (...a: unknown[]) => {
          fn(...a);
          return builder;
        };
      Object.assign(builder, {
        insert: chain((payload) => {
          op.method = "insert";
          op.payload = payload;
        }),
        update: chain((payload) => {
          op.method = "update";
          op.payload = payload;
        }),
        select: chain((_cols?, opts?) => {
          const o = opts as { count?: string; head?: boolean } | undefined;
          if (o?.count === "exact") op.countExact = true;
          if (o?.head) op.head = true;
        }),
        eq: chain((col, val) =>
          op.filters.push({ kind: "eq", col: col as string, val }),
        ),
        neq: chain((col, val) =>
          op.filters.push({ kind: "neq", col: col as string, val }),
        ),
        not: chain((col, _o, val) =>
          op.filters.push({ kind: "not", col: col as string, val }),
        ),
        gte: chain((col, val) =>
          op.filters.push({ kind: "gte", col: col as string, val }),
        ),
        // supabase-js `.is(col, null)` — the disjoint-column WORM race guard
        // on the degraded finalize (AC7) filters on statutory_class IS NULL
        // AND mail_class IS NULL.
        is: chain((col, val) =>
          op.filters.push({ kind: "is", col: col as string, val }),
        ),
        limit: chain(() => undefined),
        single: () => Promise.resolve(finish()),
        maybeSingle: () => Promise.resolve(finish()),
        then: (
          onFulfilled: (v: unknown) => unknown,
          onRejected?: (e: unknown) => unknown,
        ) => Promise.resolve(finish()).then(onFulfilled, onRejected),
      });
      return builder;
    },
  };
  return { client, ops };
}

const OWNER = "11111111-1111-4111-8111-111111111111";
const ITEM_ID = "22222222-2222-4222-8222-222222222222";

function hasFilter(op: DbOp, kind: DbFilter["kind"], col: string): boolean {
  return op.filters.some((f) => f.kind === kind && f.col === col);
}

/** Baseline behavior for every table the pipeline touches. */
function baseScript(op: DbOp): DbResult {
  if (op.table === "users") return { data: { id: OWNER } };
  if (op.table === "workspace_members") return { data: { user_id: OWNER } };
  if (op.table === "probe_tokens") return { data: null };
  if (op.table === "email_triage_items") {
    if (op.method === "insert") return { data: { id: ITEM_ID } };
    if (op.method === "update") {
      // Degraded finalize (AC7) does `.update(...).eq().is().is().select("id")`
      // and reads data.length to learn whether the guarded write hit a row.
      // Default: the guard passes (both class columns NULL) → 1 row written.
      if (hasFilter(op, "is", "statutory_class")) {
        return { data: [{ id: ITEM_ID }], error: null };
      }
      return { error: null };
    }
    // LLM daily ceiling count (summary IS NOT NULL + created_at gte)
    if (op.countExact && hasFilter(op, "not", "summary")) return { count: 0 };
    // unacknowledged statutory count (status = new)
    if (op.countExact && hasFilter(op, "eq", "status")) return { count: 1 };
    // statutory coalescing window (neq this id)
    if (hasFilter(op, "neq", "id")) return { data: [] };
    return { data: null };
  }
  return { data: null };
}

// --- Fixtures -----------------------------------------------------------------
// Synthesized only (cq-test-fixtures-synthesized-only). Control char \u0007
// embedded so the sanitizer assertion can prove sanitizePromptString ran
// BEFORE the mocked Anthropic client saw the strings. The body fixture
// carries a unique token (REMIT-7741-UNIQUE) for the parse-and-discard scan.

const SUBJECT_FIXTURE = "ACME invoice\u0007 March cycle";
const SENDER_FIXTURE = "billing\u0007@acme-fixture.example";
const BODY_FIXTURE =
  "Quarterly vendor invoice REMIT-7741-UNIQUE.\u0007 Please remit payment " +
  "within 30 days to ACME Tools for the March cycle of synthetic services.";
const STATUTORY_SUBJECT = "Data Subject Access Request — my personal data";

function makeEvent(overrides?: Record<string, unknown>) {
  return {
    data: {
      v: "1",
      svixId: "svix-fixture-1",
      resendEmailId: "re-fixture-123",
      messageId: "<m1@acme-fixture.example>",
      sender: SENDER_FIXTURE,
      subject: SUBJECT_FIXTURE,
      receivedAt: "2026-06-11T08:00:00.000Z",
      receivedAtSource: "payload",
      attachments: [],
      ...overrides,
    },
  };
}

function makeStep() {
  const calls: { name: string }[] = [];
  // Step returns are CHECKPOINTED by Inngest — captured here so every test
  // can scan them for raw-body leakage (T3), not just one dedicated test.
  const returns: unknown[] = [];
  return {
    calls,
    returns,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      calls.push({ name });
      const out = await cb();
      returns.push(out);
      return out;
    },
  };
}

async function runHandler(
  eventOverrides?: Record<string, unknown>,
  script: (op: DbOp) => DbResult = baseScript,
  ctx?: { attempt?: number; maxAttempts?: number },
) {
  const db = makeDb(script);
  dbHolder.current = db.client;
  const step = makeStep();
  // attempt/maxAttempts come off Inngest's BaseContext (the handler arg) — see
  // _cron-shared.ts:107-108. Omitted here → attempt=0/maxAttempts=1 →
  // isFinalAttempt=true (legacy/eager shape, identical to pre-degraded-tail).
  const result = await emailOnReceivedHandler({
    event: makeEvent(eventOverrides),
    step,
    logger: loggerSpies,
    ...(ctx ?? {}),
  } as never);
  return { step, result, ops: db.ops, stepReturns: step.returns };
}

/**
 * TR3 sweep (T2): no log call, Sentry call, or observability mirror may
 * carry body/sender/subject content — run at the end of error-path tests
 * too, not just the happy path. `extraTokens` lets statutory/probe tests
 * add their own subject fixtures.
 */
function expectNoPiiInObservability(extraTokens: string[] = []) {
  const allObservability = JSON.stringify([
    loggerSpies.info.mock.calls,
    loggerSpies.warn.mock.calls,
    loggerSpies.error.mock.calls,
    loggerSpies.debug.mock.calls,
    captureExceptionSpy.mock.calls.map((c) => String(c[0])),
    captureMessageSpy.mock.calls,
    reportSilentFallbackSpy.mock.calls,
    warnSilentFallbackSpy.mock.calls,
  ]);
  for (const token of [
    "REMIT-7741-UNIQUE",
    "acme-fixture.example",
    "ACME invoice",
    ...extraTokens,
  ]) {
    expect(allObservability).not.toContain(token);
  }
}

beforeEach(() => {
  vi.clearAllMocks();
  dbHolder.current = null;
  resetOwnerValidationMemo();
  vi.stubEnv("EMAIL_TRIAGE_OWNER_USER_ID", OWNER);
  vi.stubEnv("ANTHROPIC_API_KEY", "sk-ant-test");
  notifyOfflineUserSpy.mockResolvedValue(undefined);
  fetchReceivedEmailSpy.mockResolvedValue({ text: BODY_FIXTURE, html: null });
  anthropicCreateSpy.mockResolvedValue({
    content: [
      {
        type: "text",
        text: JSON.stringify({
          summary: "Vendor invoice for the March cycle.",
          mail_class: "billing",
        }),
      },
    ],
    usage: { input_tokens: 10, output_tokens: 10 },
  });
});

// --- Allowlist contract -------------------------------------------------------

describe("MAIL_CLASS_ALLOWLIST", () => {
  it("excludes every statutory class and probe (structural forgery bar)", () => {
    for (const forbidden of [
      "breach",
      "service-of-process",
      "dsar",
      "regulator",
      "probe",
    ]) {
      expect(MAIL_CLASS_ALLOWLIST).not.toContain(forbidden);
    }
    expect(MAIL_CLASS_ALLOWLIST).toEqual([
      "vendor",
      "billing",
      "security",
      "newsletter",
      "legal-review",
      "other",
    ]);
  });
});

// --- Owner resolution -----------------------------------------------------------

describe("owner resolution", () => {
  it("EMAIL_TRIAGE_OWNER_USER_ID unset → plain retriable Error before any step", async () => {
    vi.stubEnv("EMAIL_TRIAGE_OWNER_USER_ID", "");
    const db = makeDb(baseScript);
    dbHolder.current = db.client;
    const step = makeStep();
    await expect(
      emailOnReceivedHandler({
        event: makeEvent(),
        step,
        logger: loggerSpies,
      } as never),
    ).rejects.toThrow(/EMAIL_TRIAGE_OWNER_USER_ID/);
    // Retriable: plain Error, never NonRetriableError — Sentry fires via
    // Layer 1 (sentry-correlation transformOutput) on exhaustion.
    const err = await emailOnReceivedHandler({
      event: makeEvent(),
      step: makeStep(),
      logger: loggerSpies,
    } as never).catch((e: unknown) => e);
    expect((err as Error).constructor.name).toBe("Error");
    expect(step.calls).toHaveLength(0);
  });

  it("owner not matching a users row → retriable throw (never skip)", async () => {
    await expect(
      runHandler(undefined, (op) => {
        if (op.table === "users") return { data: null };
        return baseScript(op);
      }),
    ).rejects.toThrow(/users row/);
  });

  it("owner without workspace_members owner row → retriable throw", async () => {
    await expect(
      runHandler(undefined, (op) => {
        if (op.table === "workspace_members") return { data: null };
        return baseScript(op);
      }),
    ).rejects.toThrow(/owner/);
  });

  it("owner validation is memoized (1h TTL): second run skips the users/workspace_members queries", async () => {
    const first = await runHandler();
    const ownerOps = (ops: DbOp[]) =>
      ops.filter((o) => o.table === "users" || o.table === "workspace_members");
    expect(ownerOps(first.ops)).toHaveLength(2);

    const second = await runHandler();
    expect(ownerOps(second.ops)).toHaveLength(0);

    // Reset helper restores the validating behavior (test hygiene contract).
    resetOwnerValidationMemo();
    const third = await runHandler();
    expect(ownerOps(third.ops)).toHaveLength(2);
  });
});

// --- Claim-insert semantics -------------------------------------------------

describe("claim-insert", () => {
  it("stub insert populates hard-frozen columns and SQL NULL (never '') one-time-set columns", async () => {
    const { ops } = await runHandler();
    const insert = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "insert",
    );
    expect(insert).toBeDefined();
    const payload = insert!.payload as Record<string, unknown>;
    expect(payload.user_id).toBe(OWNER);
    // claim_key is sender-scoped (P1f): a sender-controlled Message-ID
    // alone must not be able to pre-claim/suppress another sender's mail.
    expect(payload.claim_key).toBe(`${SENDER_FIXTURE}|<m1@acme-fixture.example>`);
    expect(payload.message_id).toBe("<m1@acme-fixture.example>");
    expect(payload.resend_email_id).toBe("re-fixture-123");
    expect(payload.sender).toBe(SENDER_FIXTURE);
    expect(payload.subject).toBe(SUBJECT_FIXTURE);
    expect(payload.received_at).toBe("2026-06-11T08:00:00.000Z");
    expect(payload.received_at_source).toBe("payload");
    // One-time-set columns: SQL NULL, never "" — an empty-string stub makes
    // the WORM freeze trigger reject the finalize.
    for (const col of ["summary", "mail_class", "statutory_class", "rule_id"]) {
      expect(payload[col], col).toBeNull();
      expect(payload[col], col).not.toBe("");
    }
  });

  it("claim_key falls back to resend:<id> when messageId is null", async () => {
    const { ops } = await runHandler({ messageId: null });
    const insert = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "insert",
    );
    const payload = insert!.payload as Record<string, unknown>;
    expect(payload.claim_key).toBe("resend:re-fixture-123");
    expect(payload.message_id).toBeNull();
  });

  it("claim_key falls back to resend:<id> when sender is null (no sender scope available)", async () => {
    const { ops } = await runHandler({ sender: null });
    const insert = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "insert",
    );
    const payload = insert!.payload as Record<string, unknown>;
    expect(payload.claim_key).toBe("resend:re-fixture-123");
  });

  it("23505 vs FINALIZED row → short-circuit, no further steps, no notify", async () => {
    const { step, result, ops } = await runHandler(undefined, (op) => {
      if (op.table === "email_triage_items" && op.method === "insert") {
        return { error: { code: "23505", message: "duplicate key" } };
      }
      if (
        op.table === "email_triage_items" &&
        op.method === "select" &&
        hasFilter(op, "eq", "claim_key")
      ) {
        return {
          data: { id: "existing-1", mail_class: "vendor", statutory_class: null },
        };
      }
      return baseScript(op);
    });
    expect(result).toMatchObject({ shortCircuit: true });
    expect(step.calls.map((c) => c.name)).toEqual(["claim-insert"]);
    expect(notifyOfflineUserSpy).not.toHaveBeenCalled();
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    expect(fetchReceivedEmailSpy).not.toHaveBeenCalled();
    expect(
      ops.filter((o) => o.table === "email_triage_items" && o.method === "update"),
    ).toHaveLength(0);
  });

  it("23505 vs UNFINALIZED stub → adopts the stub id and finalizes it", async () => {
    const STUB_ID = "33333333-3333-4333-8333-333333333333";
    const { result, ops } = await runHandler(undefined, (op) => {
      if (op.table === "email_triage_items" && op.method === "insert") {
        return { error: { code: "23505", message: "duplicate key" } };
      }
      if (
        op.table === "email_triage_items" &&
        op.method === "select" &&
        hasFilter(op, "eq", "claim_key")
      ) {
        return { data: { id: STUB_ID, mail_class: null, statutory_class: null } };
      }
      return baseScript(op);
    });
    expect(result).not.toMatchObject({ shortCircuit: true });
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize).toBeDefined();
    expect(finalize!.filters).toContainEqual({
      kind: "eq",
      col: "id",
      val: STUB_ID,
    });
  });

  it("non-23505 insert error → retriable throw carrying only the code (TR3)", async () => {
    await expect(
      runHandler(undefined, (op) => {
        if (op.table === "email_triage_items" && op.method === "insert") {
          return { error: { code: "08006", message: "conn lost" } };
        }
        return baseScript(op);
      }),
    ).rejects.toThrow(/claim insert failed: 08006/);
    expectNoPiiInObservability();
  });

  it("23505 conflict whose re-select errors → retriable throw (redelivery resolves it)", async () => {
    await expect(
      runHandler(undefined, (op) => {
        if (op.table === "email_triage_items" && op.method === "insert") {
          return { error: { code: "23505", message: "duplicate key" } };
        }
        if (
          op.table === "email_triage_items" &&
          op.method === "select" &&
          hasFilter(op, "eq", "claim_key")
        ) {
          return { error: { code: "57014" } };
        }
        return baseScript(op);
      }),
    ).rejects.toThrow(/claim conflict lookup failed: 57014/);
    expectNoPiiInObservability();
  });

  it("adopt-race loser: finalize P0001 vs an already-finalized row → graceful short-circuit, no throw", async () => {
    // Two runs adopt the same stub; the loser's finalize UPDATE trips the
    // WORM freeze trigger (P0001). The re-select shows the winner already
    // finalized — the loser must complete instead of dying unhandled.
    const { result, ops } = await runHandler(undefined, (op) => {
      if (op.table === "email_triage_items" && op.method === "update") {
        return { error: { code: "P0001", message: "frozen" } };
      }
      if (
        op.table === "email_triage_items" &&
        op.method === "select" &&
        hasFilter(op, "eq", "id")
      ) {
        return { data: { mail_class: "billing", statutory_class: null } };
      }
      return baseScript(op);
    });
    expect(result).toMatchObject({ triaged: "summarized" });
    // The P0001 path re-selected the row by id.
    const reSelect = ops.find(
      (o) =>
        o.table === "email_triage_items" &&
        o.method === "select" &&
        hasFilter(o, "eq", "id"),
    );
    expect(reSelect).toBeDefined();
  });

  it("finalize P0001 vs a STILL-unfinalized row → retriable throw (not a race win)", async () => {
    await expect(
      runHandler(undefined, (op) => {
        if (op.table === "email_triage_items" && op.method === "update") {
          return { error: { code: "P0001", message: "frozen" } };
        }
        if (
          op.table === "email_triage_items" &&
          op.method === "select" &&
          hasFilter(op, "eq", "id")
        ) {
          return { data: { mail_class: null, statutory_class: null } };
        }
        return baseScript(op);
      }),
    ).rejects.toThrow(/finalize failed: P0001/);
  });
});

// --- Statutory metadata fast-path ---------------------------------------------

describe("metadata statutory path", () => {
  it("finalizes statutory row + notifies; body fetch and LLM structurally unreachable", async () => {
    const { step, ops } = await runHandler({ subject: STATUTORY_SUBJECT });
    expect(step.calls.map((c) => c.name)).toEqual([
      "claim-insert",
      "finalize-statutory",
      "notify",
    ]);
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({
      statutory_class: "dsar",
      rule_id: "dsar-art15",
    });
    expect(fetchReceivedEmailSpy).not.toHaveBeenCalled();
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    expect(notifyOfflineUserSpy).toHaveBeenCalledTimes(1);
    const [userId, payload] = notifyOfflineUserSpy.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ];
    expect(userId).toBe(OWNER);
    expect(payload).toMatchObject({
      type: "email_triage",
      emailId: ITEM_ID,
      isStatutory: true,
    });
  });

  it("body-fetch terminal failure cannot drop a DSAR — metadata path returned before any fetch", async () => {
    // Even a hard-down body-fetch dependency must not affect the statutory
    // row: step (2) returns before step (4) is reachable.
    fetchReceivedEmailSpy.mockRejectedValue(new Error("resend API down"));
    const { step, ops } = await runHandler({ subject: STATUTORY_SUBJECT });
    expect(step.calls.map((c) => c.name)).toEqual([
      "claim-insert",
      "finalize-statutory",
      "notify",
    ]);
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({ statutory_class: "dsar" });
    expect(fetchReceivedEmailSpy).not.toHaveBeenCalled();
  });

  it("notify failures are NOT double-mirrored here — the single Sentry mirror lives in notifications.ts", async () => {
    // notifyOfflineUser never throws in production (its body is wrapped in
    // notifications.ts, which mirrors statutory failures via
    // mirrorStatutoryNotifyFailure with the same tags). The pipeline adds
    // NO catch of its own: if the contract were ever broken the error
    // propagates as a retriable step failure rather than being eaten.
    notifyOfflineUserSpy.mockRejectedValue(new Error("push transport down"));
    await expect(runHandler({ subject: STATUTORY_SUBJECT })).rejects.toThrow(
      /push transport down/,
    );
    expect(captureExceptionSpy).not.toHaveBeenCalled();
    expectNoPiiInObservability(["Data Subject Access Request"]);
  });

  it("statutory coalescing: skips the ping when another statutory item exists in the CURRENT 10-min bucket", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-06-11T08:07:30.000Z"));
    try {
      const { ops } = await runHandler({ subject: STATUTORY_SUBJECT }, (op) => {
        if (op.table === "email_triage_items" && hasFilter(op, "neq", "id")) {
          return { data: [{ id: "earlier-statutory" }] };
        }
        return baseScript(op);
      });
      expect(notifyOfflineUserSpy).not.toHaveBeenCalled();
      // Wall-clock bucket anchor (P4f): the lower bound is floor(now/10min),
      // NOT now-10min — and the lookup is owner-scoped (P3f).
      const recentQuery = ops.find(
        (o) => o.table === "email_triage_items" && hasFilter(o, "neq", "id"),
      );
      expect(recentQuery!.filters).toContainEqual({
        kind: "gte",
        col: "created_at",
        val: "2026-06-11T08:00:00.000Z",
      });
      expect(recentQuery!.filters).toContainEqual({
        kind: "eq",
        col: "user_id",
        val: OWNER,
      });
    } finally {
      vi.useRealTimers();
    }
  });

  it("a sustained drip still pings once per bucket: a row from the PREVIOUS bucket does not suppress", async () => {
    // The DB-side gte(created_at, bucketStart) excludes the previous
    // bucket's row, so the recent-lookup comes back empty and the ping
    // fires — chain-suppression (each ping resetting a rolling 10-min
    // window forever) is structurally impossible with a wall-clock anchor.
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-06-11T08:10:05.000Z"));
    try {
      const bucketStart = "2026-06-11T08:10:00.000Z";
      const { ops } = await runHandler({ subject: STATUTORY_SUBJECT }, (op) => {
        if (op.table === "email_triage_items" && hasFilter(op, "neq", "id")) {
          // Simulate the DB filter: the only other statutory row was
          // created at 08:09:59 — before this bucket — so the filtered
          // result is empty.
          return { data: [] };
        }
        return baseScript(op);
      });
      const recentQuery = ops.find(
        (o) => o.table === "email_triage_items" && hasFilter(o, "neq", "id"),
      );
      expect(recentQuery!.filters).toContainEqual({
        kind: "gte",
        col: "created_at",
        val: bucketStart,
      });
      expect(notifyOfflineUserSpy).toHaveBeenCalledTimes(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it("coalescing lookup is fail-OPEN: a recent-query error still pings (missed ping > duplicate ping)", async () => {
    await runHandler({ subject: STATUTORY_SUBJECT }, (op) => {
      if (op.table === "email_triage_items" && hasFilter(op, "neq", "id")) {
        return { error: { code: "57014" } };
      }
      return baseScript(op);
    });
    expect(notifyOfflineUserSpy).toHaveBeenCalledTimes(1);
    expect(notifyOfflineUserSpy.mock.calls[0][1]).toMatchObject({
      isStatutory: true,
    });
  });

  it("statutory ping with N>1 unacknowledged statutory items appends (+N-1 more) to the title", async () => {
    await runHandler({ subject: STATUTORY_SUBJECT }, (op) => {
      if (
        op.table === "email_triage_items" &&
        op.countExact &&
        hasFilter(op, "eq", "status")
      ) {
        return { count: 3 };
      }
      return baseScript(op);
    });
    expect(notifyOfflineUserSpy).toHaveBeenCalledTimes(1);
    const payload = notifyOfflineUserSpy.mock.calls[0][1] as { title: string };
    expect(payload.title).toMatch(/\(\+2 more\)$/);
  });
});

// --- Probe path ----------------------------------------------------------------

describe("probe path", () => {
  const PROBE_UUID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
  const PROBE_SUBJECT = `SOLEUR-PROBE-${PROBE_UUID}`;

  it("valid recent token → mail_class probe, zero LLM, zero fetch, NO notify; lookup is freshness-gated", async () => {
    const { step, ops } = await runHandler({ subject: PROBE_SUBJECT }, (op) => {
      if (op.table === "probe_tokens") {
        // The freshness gate must be ON the query (T1): a token row older
        // than 24h must be filtered DB-side, not trusted client-side.
        expect(hasFilter(op, "gte", "created_at")).toBe(true);
        expect(hasFilter(op, "eq", "token")).toBe(true);
        return {
          data: { token: PROBE_UUID, created_at: new Date().toISOString() },
        };
      }
      return baseScript(op);
    });
    expect(step.calls.map((c) => c.name)).toEqual([
      "claim-insert",
      "probe-classify",
    ]);
    const tokenLookup = ops.find((o) => o.table === "probe_tokens");
    expect(tokenLookup).toBeDefined();
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({
      mail_class: "probe",
      summary: "synthetic ingress probe",
    });
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    expect(fetchReceivedEmailSpy).not.toHaveBeenCalled();
    expect(notifyOfflineUserSpy).not.toHaveBeenCalled();
  });

  it("STALE token (recorded but expired — freshness filter excludes it) → 'other' + Sentry warn", async () => {
    // The probe_tokens row exists but is >24h old: the gte(created_at)
    // filter returns no row, so the pipeline must treat the marker as a
    // forgeable probe SHAPE, not a valid probe.
    const { ops } = await runHandler({ subject: PROBE_SUBJECT }, (op) => {
      if (op.table === "probe_tokens") {
        expect(hasFilter(op, "gte", "created_at")).toBe(true);
        return { data: null }; // DB-side freshness filter excluded the row
      }
      return baseScript(op);
    });
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({ mail_class: "other" });
    expect(warnSilentFallbackSpy).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ op: "probe-token-mismatch" }),
    );
    expect(notifyOfflineUserSpy).toHaveBeenCalledTimes(1);
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
  });

  it("probe shape WITHOUT a valid token → other + Sentry warn + normal notify (no PII in the warn)", async () => {
    const { ops } = await runHandler({ subject: PROBE_SUBJECT });
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({ mail_class: "other" });
    expect((finalize!.payload as { summary: string }).summary).toContain(
      "probe-shaped marker without a valid token",
    );
    expect(warnSilentFallbackSpy).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ op: "probe-token-mismatch" }),
    );
    expect(notifyOfflineUserSpy).toHaveBeenCalledTimes(1);
    expect(notifyOfflineUserSpy.mock.calls[0][1]).toMatchObject({
      type: "email_triage",
      isStatutory: false,
    });
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    // T2: the mismatch warn itself must not carry the subject/sender.
    expectNoPiiInObservability([PROBE_SUBJECT]);
  });
});

// --- Fused fetch-sanitize-summarize step ---------------------------------------

describe("fetch-sanitize-summarize", () => {
  it("happy path: pinned step order, finalize carries summary + mailClass, notify last", async () => {
    const { step, ops } = await runHandler();
    expect(step.calls.map((c) => c.name)).toEqual([
      "claim-insert",
      "fetch-sanitize-summarize",
      "finalize-row",
      "notify",
    ]);
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({
      mail_class: "billing",
      summary: "Vendor invoice for the March cycle.",
    });
    expect(notifyOfflineUserSpy).toHaveBeenCalledTimes(1);
    expect(notifyOfflineUserSpy.mock.calls[0][1]).toMatchObject({
      type: "email_triage",
      emailId: ITEM_ID,
      isStatutory: false,
    });
  });

  it("sanitizes subject + sender + body via sanitizePromptString BEFORE the LLM sees them", async () => {
    await runHandler();
    expect(anthropicCreateSpy).toHaveBeenCalledTimes(1);
    const req = anthropicCreateSpy.mock.calls[0][0] as {
      system?: unknown;
      messages: { content: unknown }[];
    };
    const promptText = JSON.stringify(req);
    expect(promptText).not.toContain("\u0007");
    // Control chars stripped, not replaced — the cleaned variants survive.
    expect(promptText).toContain("ACME invoice March cycle");
    expect(promptText).toContain("billing@acme-fixture.example");
    expect(promptText).toContain("REMIT-7741-UNIQUE");
  });

  it("out-of-allowlist mail_class → coerced to other + reportSilentFallback(mail-class-coerced)", async () => {
    anthropicCreateSpy.mockResolvedValue({
      content: [
        {
          type: "text",
          text: JSON.stringify({ summary: "A DSAR maybe.", mail_class: "dsar" }),
        },
      ],
      usage: { input_tokens: 10, output_tokens: 10 },
    });
    const { ops } = await runHandler();
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({ mail_class: "other" });
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ op: "mail-class-coerced" }),
    );
  });

  it("body statutory pass: keyword in body finalizes statutory_class via the deterministic rule; body sentinel never escapes (T3)", async () => {
    // Unique sentinel embedded in the DSAR body: it must never cross a
    // step boundary (checkpointed) or land in any DB write payload.
    const DSAR_BODY =
      "I hereby make a subject access request for all my personal data. " +
      "SENTINEL-DSAR-9912-UNIQUE marker for the parse-and-discard scan.";
    fetchReceivedEmailSpy.mockResolvedValue({ text: DSAR_BODY, html: null });
    const { ops, stepReturns } = await runHandler();
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({
      statutory_class: "dsar",
      rule_id: "dsar-art15",
    });
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    expect(notifyOfflineUserSpy.mock.calls[0][1]).toMatchObject({
      isStatutory: true,
    });
    expect(JSON.stringify(stepReturns)).not.toContain("SENTINEL-DSAR-9912");
    const writes = ops.filter(
      (o) => o.method === "insert" || o.method === "update",
    );
    expect(JSON.stringify(writes.map((o) => o.payload))).not.toContain(
      "SENTINEL-DSAR-9912",
    );
  });

  it("empty-string text part does NOT bypass HTML normalization: HTML-only FR DSAR still trips the body pass", async () => {
    // text: "" must be treated as absent (P10f) — the FR DSAR keyword lives
    // only in the HTML part, interleaved with inline tags the normalizer
    // strips.
    fetchReceivedEmailSpy.mockResolvedValue({
      text: "",
      html:
        "<html><body><p>Bonjour,</p><p>Je formule une <b>demande " +
        "d&#8217;acc&egrave;s</b> &agrave; mes donn&eacute;es personnelles " +
        "(RGPD).</p></body></html>",
    });
    const { ops } = await runHandler();
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({
      statutory_class: "dsar",
      rule_id: "dsar-art15",
    });
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
  });

  it("thin body + attachments → legal-review with deterministic summary, zero LLM; body sentinel never escapes (T3)", async () => {
    fetchReceivedEmailSpy.mockResolvedValue({
      text: "See attached. SENTINEL-THIN-3307-UNIQUE",
      html: null,
    });
    const { ops, stepReturns } = await runHandler({
      attachments: [
        { filename: "contract_draft.pdf", contentType: "application/pdf" },
      ],
    });
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({ mail_class: "legal-review" });
    const summary = (finalize!.payload as { summary: string }).summary;
    expect(summary).toContain("contract_draft.pdf");
    expect(summary).toContain(
      "rules did not match — verify against the Proton original",
    );
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    expect(JSON.stringify(stepReturns)).not.toContain("SENTINEL-THIN-3307");
    const writes = ops.filter(
      (o) => o.method === "insert" || o.method === "update",
    );
    expect(JSON.stringify(writes.map((o) => o.payload))).not.toContain(
      "SENTINEL-THIN-3307",
    );
  });

  it("daily LLM ceiling breach → other + 'deferred — volume cap', no fetch, no LLM", async () => {
    const { ops } = await runHandler(undefined, (op) => {
      if (
        op.table === "email_triage_items" &&
        op.countExact &&
        hasFilter(op, "not", "summary")
      ) {
        return { count: EMAIL_TRIAGE_DAILY_LLM_CEILING };
      }
      return baseScript(op);
    });
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({
      mail_class: "other",
      summary: "deferred — volume cap",
    });
    expect(fetchReceivedEmailSpy).not.toHaveBeenCalled();
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
  });

  it("ceiling count is owner-scoped and excludes non-LLM rows (probe + volume-cap sentinels)", async () => {
    const { ops } = await runHandler();
    const ceiling = ops.find(
      (o) =>
        o.table === "email_triage_items" &&
        o.countExact &&
        hasFilter(o, "not", "summary"),
    );
    expect(ceiling).toBeDefined();
    // Owner scope (P3f).
    expect(ceiling!.filters).toContainEqual({
      kind: "eq",
      col: "user_id",
      val: OWNER,
    });
    // Probe rows carry a summary but cost no LLM call (P8f).
    expect(ceiling!.filters).toContainEqual({
      kind: "neq",
      col: "mail_class",
      val: "probe",
    });
    // "deferred — volume cap" sentinel rows likewise (P8f); thin-body
    // legal-review rows still count — conservative overcount, safe for spend.
    expect(ceiling!.filters).toContainEqual({
      kind: "not",
      col: "summary",
      val: "deferred — volume cap%",
    });
  });

  it("ceiling-count DB error → retriable throw carrying only the code; no PII in observability (T2)", async () => {
    await expect(
      runHandler(undefined, (op) => {
        if (
          op.table === "email_triage_items" &&
          op.countExact &&
          hasFilter(op, "not", "summary")
        ) {
          return { error: { code: "57014" } };
        }
        return baseScript(op);
      }),
    ).rejects.toThrow(/llm ceiling count failed: 57014/);
    expectNoPiiInObservability();
  });
});

// --- Degraded-finalize tail (fetch/summarize failure, #5468) ------------------
// A body-fetch or summarizer egress drop must not strand the row at a permanent
// NULL (silently eating a possibly-body-only Art. 12 clock). On the FINAL
// Inngest attempt only, the pipeline degrades: mail_class='other' + a fixed
// sentinel summary + a (statutory-grade, when the body was never fetched)
// notify + a Sentry mirror. On a NON-final attempt it re-throws so Inngest
// retries — the degraded write must be structurally skipped, never run-and-no-op.

const DEGRADED_SENTINEL_PREFIX = "fetch/summarize failed";

describe("degraded-finalize tail (fetch/summarize failure)", () => {
  it("AC4: non-final attempt re-throws and the finalize-row step is structurally absent; the final attempt's recovery wins (not degraded)", async () => {
    // (a)+(b) attempt 0 of 2 (NON-final): body fetch throws → the handler must
    // re-throw so Inngest retries, and finalize-row must NEVER enter the step
    // memo (a run-and-no-op step would replay an empty result on attempt 1 and
    // mask recovery — learning 2026-06-12).
    fetchReceivedEmailSpy.mockRejectedValueOnce(
      new Error("fetch-received-email failed: restricted_api_key"),
    );
    const attempt0 = makeDb(baseScript);
    dbHolder.current = attempt0.client;
    const step0 = makeStep();
    await expect(
      emailOnReceivedHandler({
        event: makeEvent(),
        step: step0,
        logger: loggerSpies,
        attempt: 0,
        maxAttempts: 2,
      } as never),
    ).rejects.toThrow(/restricted_api_key/);
    expect(step0.calls.map((c) => c.name)).toEqual([
      "claim-insert",
      "fetch-sanitize-summarize",
    ]);
    expect(step0.calls.map((c) => c.name)).not.toContain("finalize-row");
    // No degraded write happened on the non-final attempt.
    expect(
      attempt0.ops.filter(
        (o) => o.table === "email_triage_items" && o.method === "update",
      ),
    ).toHaveLength(0);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();

    // attempt 1 of 2 (FINAL): the body fetch now RECOVERS — the real
    // classification must win, NOT a degraded 'other' row.
    resetOwnerValidationMemo();
    fetchReceivedEmailSpy.mockResolvedValue({ text: BODY_FIXTURE, html: null });
    const { result, ops } = await runHandler(undefined, baseScript, {
      attempt: 1,
      maxAttempts: 2,
    });
    expect(result).toMatchObject({ triaged: "summarized" });
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({ mail_class: "billing" });
    expect((finalize!.payload as { summary: string }).summary).not.toContain(
      DEGRADED_SENTINEL_PREFIX,
    );
  });

  it("AC5: a summarizer failure AFTER a body statutory marker still finalizes statutory_class — the LLM is never reached", async () => {
    // The deterministic body pass runs BEFORE the LLM, so a DSAR body short-
    // circuits to bodyStatutory and the (rejecting) summarizer is unreachable.
    const DSAR_BODY =
      "I hereby make a subject access request for all my personal data.";
    fetchReceivedEmailSpy.mockResolvedValue({ text: DSAR_BODY, html: null });
    anthropicCreateSpy.mockRejectedValue(new Error("529 overloaded"));
    const { ops } = await runHandler(undefined, baseScript, {
      attempt: 1,
      maxAttempts: 2,
    });
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize!.payload).toMatchObject({
      statutory_class: "dsar",
      rule_id: "dsar-art15",
    });
    expect(finalize!.payload).not.toHaveProperty("mail_class");
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
  });

  it("AC5 (symmetric negative): a body-fetch failure degrades to 'other' and does NOT write statutory_class", async () => {
    fetchReceivedEmailSpy.mockRejectedValue(
      new Error("fetch-received-email failed: restricted_api_key"),
    );
    const { ops } = await runHandler(undefined, baseScript, {
      attempt: 1,
      maxAttempts: 2,
    });
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(finalize).toBeDefined();
    expect((finalize!.payload as { mail_class: string }).mail_class).toBe(
      "other",
    );
    expect((finalize!.payload as { summary: string }).summary).toContain(
      DEGRADED_SENTINEL_PREFIX,
    );
    // The body never arrived → the statutory body pass could not run → the
    // degraded write must NOT set statutory_class (it pins the wrap boundary).
    expect(finalize!.payload).not.toHaveProperty("statutory_class");
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
  });

  it("AC5: a summarizer-only failure (body fetched, no statutory marker) degrades to 'other' with an ORDINARY notify", async () => {
    anthropicCreateSpy.mockRejectedValue(new Error("529 overloaded"));
    const { ops } = await runHandler(undefined, baseScript, {
      attempt: 1,
      maxAttempts: 2,
    });
    const finalize = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect((finalize!.payload as { mail_class: string }).mail_class).toBe(
      "other",
    );
    // Body WAS fetched and the statutory pass already ran clean → ordinary ping.
    expect(notifyOfflineUserSpy).toHaveBeenCalledTimes(1);
    expect(notifyOfflineUserSpy.mock.calls[0][1]).toMatchObject({
      isStatutory: false,
    });
  });

  it("AC6: degraded finalize mirrors op:fetch-summarize-degraded with only { itemId } extra, no PII", async () => {
    fetchReceivedEmailSpy.mockRejectedValue(
      new Error("fetch-received-email failed: restricted_api_key"),
    );
    await runHandler(undefined, baseScript, { attempt: 1, maxAttempts: 2 });
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "email-triage",
        op: "fetch-summarize-degraded",
        extra: { itemId: ITEM_ID },
      }),
    );
    // A body-fetch failure means the body could be a body-only DSAR that was
    // never scanned → statutory-grade notify (Phase 3 P1 decision).
    expect(notifyOfflineUserSpy).toHaveBeenCalledTimes(1);
    expect(notifyOfflineUserSpy.mock.calls[0][1]).toMatchObject({
      isStatutory: true,
    });
    expectNoPiiInObservability();
  });

  it("AC7: degraded write is a no-op when a sibling already set statutory_class — guarded by .is(...null), no notify", async () => {
    // A concurrent statutory finalize set statutory_class WITHOUT raising P0001
    // against this disjoint mail_class write (mig 102:189-203). The degraded
    // UPDATE's .is("statutory_class", null).is("mail_class", null) guard makes
    // it hit ZERO rows; that zero-row result must suppress the degraded notify
    // (the race winner already pinged statutory-grade).
    fetchReceivedEmailSpy.mockRejectedValue(
      new Error("fetch-received-email failed: restricted_api_key"),
    );
    const { result } = await runHandler(undefined, (op) => {
      if (
        op.table === "email_triage_items" &&
        op.method === "update" &&
        hasFilter(op, "is", "statutory_class")
      ) {
        // The guarded UPDATE matched no row — a sibling won the race.
        return { data: [] };
      }
      return baseScript(op);
    }, { attempt: 1, maxAttempts: 2 });
    expect(result).toMatchObject({ triaged: "fetchFailed" });
    expect(notifyOfflineUserSpy).not.toHaveBeenCalled();
  });

  it("AC7: the degraded UPDATE carries the disjoint-column race guard (.is statutory_class null AND .is mail_class null)", async () => {
    fetchReceivedEmailSpy.mockRejectedValue(
      new Error("fetch-received-email failed: restricted_api_key"),
    );
    const { ops } = await runHandler(undefined, baseScript, {
      attempt: 1,
      maxAttempts: 2,
    });
    const degraded = ops.find(
      (o) => o.table === "email_triage_items" && o.method === "update",
    );
    expect(degraded!.filters).toContainEqual({
      kind: "is",
      col: "statutory_class",
      val: null,
    });
    expect(degraded!.filters).toContainEqual({
      kind: "is",
      col: "mail_class",
      val: null,
    });
  });

  it("AC8: the degraded sentinel is excluded from the daily-LLM-ceiling count (zero Anthropic spend)", async () => {
    const { ops } = await runHandler();
    const ceiling = ops.find(
      (o) =>
        o.table === "email_triage_items" &&
        o.countExact &&
        hasFilter(o, "not", "summary"),
    );
    expect(ceiling).toBeDefined();
    // The degraded sentinel rows carry a non-NULL summary but cost no LLM call,
    // so the ceiling query must exclude them via a verbatim LIKE prefix.
    expect(ceiling!.filters).toContainEqual({
      kind: "not",
      col: "summary",
      val: `${DEGRADED_SENTINEL_PREFIX}%`,
    });
  });
});

// --- TR3 / parse-and-discard --------------------------------------------------

describe("PII discipline (TR3)", () => {
  it("no log call and no Sentry/observability call carries body, sender, or subject fixtures", async () => {
    await runHandler();
    expectNoPiiInObservability();
  });

  it("the raw body never appears in any DB write payload and is never a step return value", async () => {
    const { ops, stepReturns } = await runHandler();
    const writes = ops.filter(
      (o) => o.method === "insert" || o.method === "update",
    );
    expect(JSON.stringify(writes.map((o) => o.payload))).not.toContain(
      "REMIT-7741-UNIQUE",
    );
    // Inngest checkpoints step.run returns in its run store — the body
    // crossing a step boundary would persist it and defeat parse-and-discard.
    expect(JSON.stringify(stepReturns)).not.toContain("REMIT-7741-UNIQUE");
  });
});
