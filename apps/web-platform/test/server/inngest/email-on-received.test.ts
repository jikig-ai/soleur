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
  EMAIL_TRIAGE_DAILY_LLM_CEILING,
} from "@/server/inngest/functions/email-on-received";
import { MAIL_CLASS_ALLOWLIST } from "@/server/email-triage/summarize";

// --- Supabase service-client fake -------------------------------------------

interface DbFilter {
  kind: "eq" | "neq" | "not" | "gte";
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
    if (op.method === "update") return { error: null };
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
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      calls.push({ name });
      return cb();
    },
  };
}

async function runHandler(
  eventOverrides?: Record<string, unknown>,
  script: (op: DbOp) => DbResult = baseScript,
) {
  const db = makeDb(script);
  dbHolder.current = db.client;
  const step = makeStep();
  const result = await emailOnReceivedHandler({
    event: makeEvent(eventOverrides),
    step,
    logger: loggerSpies,
  } as never);
  return { step, result, ops: db.ops };
}

beforeEach(() => {
  vi.clearAllMocks();
  dbHolder.current = null;
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
    expect(payload.claim_key).toBe("<m1@acme-fixture.example>");
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

  it("statutory notify failure mirrors to Sentry.captureException and does not throw", async () => {
    notifyOfflineUserSpy.mockRejectedValue(new Error("push transport down"));
    await runHandler({ subject: STATUTORY_SUBJECT });
    expect(captureExceptionSpy).toHaveBeenCalled();
  });

  it("statutory coalescing: skips the ping when another statutory item arrived within 10 min", async () => {
    await runHandler({ subject: STATUTORY_SUBJECT }, (op) => {
      if (op.table === "email_triage_items" && hasFilter(op, "neq", "id")) {
        return { data: [{ id: "earlier-statutory" }] };
      }
      return baseScript(op);
    });
    expect(notifyOfflineUserSpy).not.toHaveBeenCalled();
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

  it("valid recent token → mail_class probe, zero LLM, zero fetch, NO notify", async () => {
    const { step, ops } = await runHandler({ subject: PROBE_SUBJECT }, (op) => {
      if (op.table === "probe_tokens") {
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

  it("probe shape WITHOUT a valid token → other + Sentry warn + normal notify", async () => {
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

  it("body statutory pass: keyword in body finalizes statutory_class via the deterministic rule", async () => {
    fetchReceivedEmailSpy.mockResolvedValue({
      text: "I hereby make a subject access request for all my personal data.",
      html: null,
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
    expect(notifyOfflineUserSpy.mock.calls[0][1]).toMatchObject({
      isStatutory: true,
    });
  });

  it("thin body + attachments → legal-review with deterministic summary, zero LLM", async () => {
    fetchReceivedEmailSpy.mockResolvedValue({ text: "See attached.", html: null });
    const { ops } = await runHandler({
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
});

// --- TR3 / parse-and-discard --------------------------------------------------

describe("PII discipline (TR3)", () => {
  it("no log call and no Sentry/observability call carries body, sender, or subject fixtures", async () => {
    await runHandler();
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
    expect(allObservability).not.toContain("REMIT-7741-UNIQUE");
    expect(allObservability).not.toContain("acme-fixture.example");
    expect(allObservability).not.toContain("ACME invoice");
  });

  it("the raw body never appears in any DB write payload and is never a step return value", async () => {
    const db = makeDb(baseScript);
    dbHolder.current = db.client;
    const step = makeStep();
    const stepReturns: unknown[] = [];
    const wrappedStep = {
      async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
        const out = await step.run(name, cb);
        stepReturns.push(out);
        return out;
      },
    };
    await emailOnReceivedHandler({
      event: makeEvent(),
      step: wrappedStep,
      logger: loggerSpies,
    } as never);
    const writes = db.ops.filter(
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
