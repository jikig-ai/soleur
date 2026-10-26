/**
 * #10543 — founder re-click replay on POST /api/dashboard/today/[id]/send.
 *
 * Contract under test (plan: fix-dashboard-send-enqueue-retry-replay, CTO rulings D1-D6, R1-R4, S1-S4):
 *   - an `action_sends` row already exists for the draft (the WORM approval survived an exhausted enqueue):
 *     the route does NOT insert a second row, re-dispatches the ROW's id, and archives only on success;
 *   - the lookup runs BEFORE the gates for the arms that dispatch nothing (terminal row, no-dispatch source_ref,
 *     expired approval), and the draft-hash / class / tier refusals run before the template gate;
 *   - a replay is capped at 23h from `clicked_at` and fails closed on a garbage or future timestamp;
 *   - response bodies carry constant fields only.
 *
 * Cases that already pass against the pre-fix route are labelled `[guard]`: they are characterization, not RED.
 * The pending row's id deliberately differs from AS_ID so a replay that dispatched the INSERT's id goes red.
 */

import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { createHash } from "node:crypto";

import {
  createActionSendsStore,
  pendingActionSendRow,
  type ActionSendRowShape,
  type ActionSendsStore,
} from "../../../helpers/action-sends-row-mock";

const {
  mockGetUser,
  mockFrom,
  mockRpc,
  mockIsGranted,
  mockWriteActionSend,
  mockValidateOrigin,
  mockInngestSend,
  mockReportSilentFallback,
  mockWarnSilentFallback,
  mockRunTemplateGate,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockRpc: vi.fn(async () => ({ data: null, error: null })),
  mockIsGranted: vi.fn(),
  mockWriteActionSend: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({
    valid: true,
    origin: "https://app.soleur.ai",
  })),
  mockInngestSend: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
  mockRunTemplateGate: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
    rpc: mockRpc,
  })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/server/scope-grants/is-granted", () => ({
  isGranted: mockIsGranted,
}));

vi.mock("@/server/action-sends/write-action-send", () => ({
  writeActionSend: mockWriteActionSend,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,
  hashUserId: vi.fn(() => "founder-hash-stub"),
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { send: mockInngestSend },
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
}));

vi.mock("@/server/templates/template-registry", () => ({
  getTemplateHash: vi.fn(() => "template-hash-stub"),
}));

vi.mock("@/server/templates/run-template-gate", () => ({
  runTemplateGate: mockRunTemplateGate,
}));

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
  captureException: vi.fn(),
}));

import { POST } from "@/app/api/dashboard/today/[id]/send/route";

const FOUNDER_A = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa";
const FOUNDER_B = "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb";
const MSG_ID = "11111111-1111-4111-aaaa-111111111111";
const GRANT_ID = "22222222-2222-4222-aaaa-222222222222";
const AS_ID = "33333333-3333-4333-aaaa-333333333333";
const ROW_ID = "44444444-4444-4444-aaaa-444444444444";
const ACTION_CLASS = "engineering.pr_review_pending";
const SOURCE_REF = "pr-acme:repo:7";
const DRAFT_PREVIEW = "approved draft text";
const DRAFT_HASH = createHash("sha256").update(DRAFT_PREVIEW).digest("hex");
const HOUR = 60 * 60 * 1000;
const NOW = new Date("2026-10-26T12:00:00.000Z");

function makeRequest(body?: unknown): Request {
  return new Request(
    `https://app.soleur.ai/api/dashboard/today/${MSG_ID}/send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Origin: "https://app.soleur.ai",
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    },
  );
}

function ctx() {
  return { params: Promise.resolve({ id: MSG_ID }) };
}

let store: ActionSendsStore;

function setup(
  opts: {
    source_ref?: string;
    draft_preview?: string;
    row?: Partial<ActionSendRowShape> | null;
    rows?: ActionSendRowShape[];
  } = {},
): void {
  const row =
    opts.row === null
      ? undefined
      : pendingActionSendRow({
          id: ROW_ID,
          message_id: MSG_ID,
          user_id: FOUNDER_A,
          per_send_body_sha256: DRAFT_HASH,
          action_class: ACTION_CLASS,
          tier_at_send: "draft_one_click",
          clicked_at: new Date(NOW.getTime() - HOUR).toISOString(),
          ...opts.row,
        });
  store = createActionSendsStore({
    message: {
      id: MSG_ID,
      user_id: FOUNDER_A,
      action_class: ACTION_CLASS,
      status: "draft",
      draft_preview: opts.draft_preview ?? DRAFT_PREVIEW,
      owning_domain: "engineering",
      template_id: "default_legacy",
      source_ref: opts.source_ref ?? SOURCE_REF,
    },
    actionSends: opts.rows ?? (row ? [row] : []),
  });
  mockFrom.mockImplementation((table: string) => store.from(table));
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers({ toFake: ["setTimeout", "Date"] });
  vi.setSystemTime(NOW);
  mockValidateOrigin.mockReturnValue({
    valid: true,
    origin: "https://app.soleur.ai",
  });
  mockGetUser.mockResolvedValue({ data: { user: { id: FOUNDER_A } } });
  mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });
  mockWriteActionSend.mockResolvedValue({ id: AS_ID });
  mockInngestSend.mockResolvedValue({ ids: ["evt-1"] });
  mockRunTemplateGate.mockResolvedValue({ kind: "allow" });
  mockRpc.mockResolvedValue({ data: null, error: null });
});

afterEach(() => {
  vi.useRealTimers();
});

describe("replay: a pending approval row within 23h", () => {
  test("re-dispatches the ROW's id without a second insert, archives, and a re-click is then not_a_draft", async () => {
    setup();

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(200);
    const json = (await res.json()) as { action_send_id: string };

    expect(mockWriteActionSend).not.toHaveBeenCalled();
    expect(json.action_send_id).toBe(ROW_ID);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    const sent = mockInngestSend.mock.calls[0][0] as {
      id: string;
      data: { actionSendId: string };
    };
    expect(sent.id).toBe(`agent-spawn-${ROW_ID}`);
    expect(sent.data.actionSendId).toBe(ROW_ID);
    expect(store.messageStatus()).toBe("archived");
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockWarnSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "spawn-agent",
      op: "inngest-enqueue-replay",
    });

    // Real state transition: the draft is archived now.
    const again = await POST(makeRequest({}), ctx());
    expect(again.status).toBe(409);
    expect(((await again.json()) as { error: string }).error).toBe(
      "not_a_draft",
    );
  });

  test("a replay whose enqueue fails again → 503, draft still a draft, extra.replay === true", async () => {
    setup();
    mockInngestSend.mockRejectedValue(new Error("still down"));

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("5");
    expect(store.messageStatus()).toBe("draft");
    const [first, opts] = mockReportSilentFallback.mock.calls[0];
    expect(first).toBeNull();
    expect(opts.extra).toMatchObject({ replay: true });
  });

  test("an archive failure after a successful enqueue: the next click replays with the SAME id and archives", async () => {
    setup();
    store.failNextArchive();

    const first = await POST(makeRequest({}), ctx());
    expect(first.status).toBe(200);
    expect(store.messageStatus()).toBe("draft");

    const second = await POST(makeRequest({}), ctx());
    expect(second.status).toBe(200);
    expect(store.messageStatus()).toBe("archived");
    const ids = mockInngestSend.mock.calls.map(
      (c) => (c[0] as { id: string }).id,
    );
    expect(ids).toEqual([`agent-spawn-${ROW_ID}`, `agent-spawn-${ROW_ID}`]);
    expect(mockWriteActionSend).not.toHaveBeenCalled();
  });
});

describe("terminal rows are ungated: the lookup precedes the gates", () => {
  const TERMINAL: Array<[string, Partial<ActionSendRowShape>]> = [
    ["acknowledged_at", { acknowledged_at: "2026-10-26T11:30:00.000Z" }],
    ["failure_reason", { failure_reason: "boom" }],
    ["undone_at", { undone_at: "2026-10-26T11:30:00.000Z" }],
    [
      "cancellation_requested_at",
      { cancellation_requested_at: "2026-10-26T11:30:00.000Z" },
    ],
  ];

  test.each(TERMINAL)(
    "%s set → archive + 409 already_sent (constant body), no dispatch, even with a revoked grant",
    async (_name, over) => {
      setup({ row: over });
      mockIsGranted.mockResolvedValue(null);

      const res = await POST(makeRequest({}), ctx());
      expect(res.status).toBe(409);
      expect(await res.json()).toStrictEqual({
        error: "already_sent",
        message_id: MSG_ID,
      });
      expect(mockInngestSend).not.toHaveBeenCalled();
      expect(mockWriteActionSend).not.toHaveBeenCalled();
      expect(store.messageStatus()).toBe("archived");
    },
  );

  test("an acknowledged row older than 23h is already_sent, not approval_expired (arm order)", async () => {
    setup({
      row: {
        acknowledged_at: "2026-10-25T01:00:00.000Z",
        clicked_at: new Date(NOW.getTime() - 30 * HOUR).toISOString(),
      },
    });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(409);
    expect(((await res.json()) as { error: string }).error).toBe(
      "already_sent",
    );
  });

  test("an archive failure on a terminal row still answers 409", async () => {
    setup({ row: { acknowledged_at: "2026-10-26T11:30:00.000Z" } });
    store.failNextArchive();

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(409);
    expect(store.messageStatus()).toBe("draft");
  });
});

describe("gates still apply to the dispatch arm", () => {
  test("[guard] a pending row with a revoked grant → 403 no_active_grant, nothing dispatched or archived", async () => {
    setup();
    mockIsGranted.mockResolvedValue(null);

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(403);
    expect(((await res.json()) as { error: string }).error).toBe(
      "no_active_grant",
    );
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(store.messageStatus()).toBe("draft");
  });

  test("a template-gate denial on replay → 403, nothing dispatched or archived", async () => {
    setup();
    mockRunTemplateGate.mockResolvedValue({
      kind: "deny",
      denyReason: "template_revoked",
    });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(403);
    expect(((await res.json()) as { error: string }).error).toBe(
      "template_not_authorized",
    );
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(store.messageStatus()).toBe("draft");
  });

  test("approve_every_time replay without re-confirmation → 409 requires_confirmation; with it → replays", async () => {
    setup({ row: { tier_at_send: "approve_every_time" } });
    mockIsGranted.mockResolvedValue({
      id: GRANT_ID,
      tier: "approve_every_time",
    });

    const blocked = await POST(makeRequest({}), ctx());
    expect(blocked.status).toBe(409);
    expect(((await blocked.json()) as { error: string }).error).toBe(
      "requires_confirmation",
    );
    expect(mockInngestSend).not.toHaveBeenCalled();

    const ok = await POST(
      makeRequest({
        confirmed_typed: true,
        typed_value: "SEND",
        expected_draft_preview_hash: DRAFT_HASH,
      }),
      ctx(),
    );
    expect(ok.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    expect(mockWriteActionSend).not.toHaveBeenCalled();
  });
});

describe("a replay is bound to the whole approval", () => {
  test("edited draft → 409 draft_changed_since_approval BEFORE any gate; draft kept; replay-draft-changed op", async () => {
    setup({ draft_preview: "edited after approval" });
    // A revoked grant must NOT turn this into a 403: the hash check precedes isGranted.
    mockIsGranted.mockResolvedValue(null);

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(409);
    expect(await res.json()).toStrictEqual({
      error: "draft_changed_since_approval",
      message_id: MSG_ID,
    });
    expect(mockIsGranted).not.toHaveBeenCalled();
    expect(mockRunTemplateGate).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(store.messageStatus()).toBe("draft");
    expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "spawn-agent",
      op: "replay-draft-changed",
    });
  });

  test("a NULL stored hash counts as a mismatch", async () => {
    setup({ row: { per_send_body_sha256: null } });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(409);
    expect(((await res.json()) as { error: string }).error).toBe(
      "draft_changed_since_approval",
    );
    expect(mockIsGranted).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  test("tier drift (row written under draft_one_click, grant is now approve_every_time) → 409 after isGranted, before the template gate", async () => {
    setup({ row: { tier_at_send: "draft_one_click" } });
    mockIsGranted.mockResolvedValue({
      id: GRANT_ID,
      tier: "approve_every_time",
    });

    const res = await POST(
      makeRequest({
        confirmed_typed: true,
        typed_value: "SEND",
        expected_draft_preview_hash: DRAFT_HASH,
      }),
      ctx(),
    );
    expect(res.status).toBe(409);
    expect(((await res.json()) as { error: string }).error).toBe(
      "draft_changed_since_approval",
    );
    expect(mockIsGranted).toHaveBeenCalledTimes(1);
    expect(mockRunTemplateGate).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(store.messageStatus()).toBe("draft");
  });

  test("action_class drift → 409 draft_changed_since_approval, template gate not called", async () => {
    setup({ row: { action_class: "finance.payment_failed" } });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(409);
    expect(((await res.json()) as { error: string }).error).toBe(
      "draft_changed_since_approval",
    );
    expect(mockRunTemplateGate).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
  });
});

describe("the 23h replay age gate (server clock, fail-closed)", () => {
  test("22h59m old replays", async () => {
    setup({
      row: {
        clicked_at: new Date(NOW.getTime() - (23 * HOUR - 60_000)).toISOString(),
      },
    });
    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
  });

  test("23h01m old → archive + 409 approval_expired (constant body), op inngest-replay-stale, no dispatch", async () => {
    setup({
      row: {
        clicked_at: new Date(NOW.getTime() - (23 * HOUR + 60_000)).toISOString(),
      },
    });
    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(409);
    expect(await res.json()).toStrictEqual({
      error: "approval_expired",
      message_id: MSG_ID,
    });
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(store.messageStatus()).toBe("archived");
    expect(mockWarnSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "spawn-agent",
      op: "inngest-replay-stale",
    });
  });

  test.each([
    ["garbage", "not-a-timestamp"],
    ["null", null],
    ["future", "2027-01-01T00:00:00.000Z"],
  ])("a %s clicked_at fails closed to approval_expired", async (_n, value) => {
    setup({ row: { clicked_at: value } });
    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(409);
    expect(((await res.json()) as { error: string }).error).toBe(
      "approval_expired",
    );
    expect(mockInngestSend).not.toHaveBeenCalled();
  });
});

describe("pending rows with nothing to dispatch are ungated", () => {
  test("an unparseable non-empty source_ref archives and answers 200 degraded:'no_artifact_in_pr_a'", async () => {
    setup({ source_ref: "link-deadbeef00000000" });
    mockIsGranted.mockResolvedValue(null);

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(200);
    const json = (await res.json()) as { degraded?: string };
    expect(json.degraded).toBe("no_artifact_in_pr_a");
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(store.messageStatus()).toBe("archived");
  });

  test("an empty source_ref older than 23h with a revoked grant archives and answers 200 with no degraded marker", async () => {
    setup({
      source_ref: "",
      row: {
        clicked_at: new Date(NOW.getTime() - 30 * HOUR).toISOString(),
      },
    });
    mockIsGranted.mockResolvedValue(null);

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(200);
    expect(await res.json()).not.toHaveProperty("degraded");
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(store.messageStatus()).toBe("archived");
  });
});

describe("concurrency, scoping and failure arms", () => {
  test("[guard] a 23505 on the insert → 409 send_in_progress; no dispatch, no archive", async () => {
    setup({ row: null });
    mockWriteActionSend.mockRejectedValueOnce(
      Object.assign(new Error("duplicate key"), { code: "23505" }),
    );

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(409);
    expect(await res.json()).toStrictEqual({
      error: "send_in_progress",
      message_id: MSG_ID,
    });
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(store.messageStatus()).toBe("draft");
  });

  test("a non-23505 insert failure still answers 500 send_failed", async () => {
    setup({ row: null });
    mockWriteActionSend.mockRejectedValueOnce(new Error("db down"));

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(500);
    expect(((await res.json()) as { error: string }).error).toBe(
      "send_failed",
    );
  });

  test("a pending row owned by ANOTHER user is invisible: the no-row path inserts", async () => {
    setup({
      row: null,
      rows: [
        pendingActionSendRow({
          id: ROW_ID,
          message_id: MSG_ID,
          user_id: FOUNDER_B,
          per_send_body_sha256: DRAFT_HASH,
          action_class: ACTION_CLASS,
        }),
      ],
    });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(200);
    expect(mockWriteActionSend).toHaveBeenCalledTimes(1);
    const sent = mockInngestSend.mock.calls[0][0] as { id: string };
    expect(sent.id).toBe(`agent-spawn-${AS_ID}`);
  });

  test("the lookup selects exactly the columns the route needs (projection is pinned)", async () => {
    setup();
    await POST(makeRequest({}), ctx());
    expect(store.actionSendsSelects[0]).toEqual([
      "id",
      "per_send_body_sha256",
      "action_class",
      "tier_at_send",
      "clicked_at",
      "acknowledged_at",
      "failure_reason",
      "undone_at",
      "cancellation_requested_at",
    ]);
  });

  test("a lookup error → 500 internal_error, nothing dispatched or archived", async () => {
    setup();
    store.failLookup();

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(500);
    expect(((await res.json()) as { error: string }).error).toBe(
      "internal_error",
    );
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(store.messageStatus()).toBe("draft");
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });

  test("Sentry extra key sets are identifiers-only for the replay ops", async () => {
    setup();
    await POST(makeRequest({}), ctx());
    const replayExtra = mockWarnSilentFallback.mock.calls[0][1].extra as Record<
      string,
      unknown
    >;
    expect(Object.keys(replayExtra).sort()).toEqual(
      ["actionSendId", "messageId", "replay", "userId"].sort(),
    );
    expect(JSON.stringify(replayExtra)).not.toContain(DRAFT_PREVIEW);
    expect(JSON.stringify(replayExtra)).not.toContain(DRAFT_HASH);
  });
});
