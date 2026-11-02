/**
 * PR-A (#4124) — Spawn-extension to the /send route.
 *
 * The send route was extended to dispatch an `agent.spawn.requested`
 * Inngest event AFTER `writeActionSend` and BEFORE the `messages.status`
 * archive flip. Tests cover:
 *   1. kb_drift draft_one_click happy-path → 200 with action_send_id +
 *      artifact_view_url + inngest.send called exactly once
 *   2. PR review pending (engineering.pr_review_pending) → inngest.send
 *      dispatch ordering (after writeActionSend, before archive)
 *   3. Inngest enqueue exhausted → 503 enqueue_unavailable (#10543); the
 *      action_sends row stays committed, the draft is NOT archived, and
 *      reportSilentFallback fires once
 *   4. A transient enqueue failure is retried with the SAME event id and
 *      the route still answers 200
 *
 * A separate file from send-route.test.ts because the spawn dispatch is
 * a new surface — the existing matrix tests the pre-PR-A behavioral
 * contract; this file tests the additive contract.
 */

import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

import {
  createActionSendsStore,
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
  inngest: {
    send: mockInngestSend,
  },
}));

vi.mock("@/server/templates/is-template-authorized", async (importOriginal) => {
  const actual = (await importOriginal()) as Record<string, unknown>;
  return {
    ...actual,
    isTemplateAuthorized: vi.fn(async () => ({
      status: "authorized",
      rowId: "ta-1",
      sendsUsed: 0,
    })),
  };
});

vi.mock("@/server/templates/template-registry", () => ({
  getTemplateHash: vi.fn(() => "template-hash-stub"),
}));

vi.mock("@/server/templates/run-template-gate", () => ({
  runTemplateGate: vi.fn(async () => ({ kind: "allow" })),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
}));

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
  captureException: vi.fn(),
}));

import { POST } from "@/app/api/dashboard/today/[id]/send/route";

const FOUNDER_A = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa";
const MSG_ID = "11111111-1111-4111-aaaa-111111111111";
const GRANT_ID = "22222222-2222-4222-aaaa-222222222222";
const AS_ID = "33333333-3333-4333-aaaa-333333333333";

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

// Track the call order: writeActionSend → inngest.send → messages.update
const callOrder: string[] = [];

let store: ActionSendsStore;

function setupMessageRow(action_class: string, source_ref: string): void {
  store = createActionSendsStore({
    message: {
      id: MSG_ID,
      user_id: FOUNDER_A,
      action_class,
      status: "draft",
      draft_preview: "test draft preview",
      owning_domain: "engineering",
      template_id: "default_legacy",
      source_ref,
    },
    onEvent: (e) => callOrder.push(e),
  });
  mockFrom.mockImplementation((table: string) => store.from(table));
}

afterEach(() => {
  vi.useRealTimers();
});

beforeEach(() => {
  vi.clearAllMocks();
  callOrder.length = 0;
  mockValidateOrigin.mockReturnValue({
    valid: true,
    origin: "https://app.soleur.ai",
  });
  mockGetUser.mockResolvedValue({ data: { user: { id: FOUNDER_A } } });
  mockWriteActionSend.mockImplementation(async () => {
    callOrder.push("writeActionSend");
    return { id: AS_ID };
  });
  mockInngestSend.mockImplementation(async () => {
    callOrder.push("inngest.send");
    return { ids: ["evt-1"] };
  });
  mockRpc.mockResolvedValue({ data: null, error: null });
});

describe("POST /api/dashboard/today/[id]/send — spawn dispatch (PR-A)", () => {
  test("(1) kb_drift draft_one_click (unsupported shape) → 200 with degraded:'no_artifact_in_pr_a' and inngest.send NOT called", async () => {
    setupMessageRow("knowledge.kb_drift", "link-deadbeef00000000");
    mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(200);

    const json = (await res.json()) as {
      id: string;
      tier: string;
      action_send_id?: string;
      artifact_view_url?: string;
      degraded?: string;
    };
    expect(json.id).toBe(AS_ID);
    expect(json.tier).toBe("draft_one_click");
    expect(json.action_send_id).toBe(AS_ID);
    // kb_drift `link-<hash>` refs don't carry a (owner, repo, number)
    // GitHub target; the route surfaces `degraded:"no_artifact_in_pr_a"`
    // so the card renders an honest pill state. PR-B (#4360) handles
    // per-class resolution.
    expect(json.artifact_view_url).toBe("");
    expect(json.degraded).toBe("no_artifact_in_pr_a");
    // No Inngest event is enqueued for unsupported shapes — avoids the
    // malformed_source_ref deadletter + Sentry spam on every CVE/CI/
    // kb_drift click.
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  test("(1b) PR-shaped source ref → inngest.send carries the canonical envelope without installationId", async () => {
    setupMessageRow("engineering.pr_review_pending", "pr-acme:repo:7");
    mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(200);

    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    const sent = mockInngestSend.mock.calls[0][0] as {
      name: string;
      data: Record<string, unknown>;
    };
    expect(sent.name).toBe("agent.spawn.requested");
    // #10543: the event id derives from the action_sends row so a retry and a
    // founder re-click replay dedup on the same Inngest event.
    expect((sent as { id?: string }).id).toBe(`agent-spawn-${AS_ID}`);
    expect(sent.data).toMatchObject({
      founderId: FOUNDER_A,
      messageId: MSG_ID,
      actionClass: "engineering.pr_review_pending",
      sourceRef: "pr-acme:repo:7",
      actionSendId: AS_ID,
    });
    // The event payload MUST NOT carry installationId (cross-tenant guard).
    expect(sent.data).not.toHaveProperty("installationId");
  });

  test("(2) engineering.pr_review_pending → inngest.send dispatched AFTER writeActionSend AND BEFORE archive flip", async () => {
    setupMessageRow("engineering.pr_review_pending", "pr-acme:repo:7");
    mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(200);
    const json = (await res.json()) as {
      action_send_id?: string;
      artifact_view_url?: string;
    };
    expect(json.action_send_id).toBe(AS_ID);
    // PR-shaped source ref → artifact URL points to the PR page (the
    // deterministic stub posts a PR comment whose final URL is only
    // known post-comment; the view-URL is the upstream PR page).
    expect(json.artifact_view_url).toBe(
      "https://github.com/acme/repo/pull/7",
    );

    // Strict ordering: writeActionSend → inngest.send → messages-archive.
    expect(callOrder).toEqual([
      "writeActionSend",
      "inngest.send",
      "messages-archive",
    ]);
  });

  test("(3) inngest.send exhausted (non-transient) → 503 enqueue_unavailable, draft NOT archived, one Sentry mirror", async () => {
    setupMessageRow("engineering.pr_review_pending", "pr-acme:repo:7");
    mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });
    mockInngestSend.mockImplementationOnce(async () => {
      callOrder.push("inngest.send-throw");
      throw new Error("inngest dev mode unreachable");
    });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("5");
    expect(await res.json()).toStrictEqual({
      error: "enqueue_unavailable",
      action_send_id: AS_ID,
      retryable: true,
    });

    // The action_sends row IS the durable artifact and stays committed, but
    // the draft must stay visible: NO messages-archive.
    expect(callOrder).toEqual(["writeActionSend", "inngest.send-throw"]);
    expect(store.messageStatus()).toBe("draft");

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [first, opts] = mockReportSilentFallback.mock.calls[0];
    // null first argument: the pino mirror keeps the feature/op tags (#10542).
    expect(first).toBeNull();
    expect(opts).toMatchObject({ feature: "spawn-agent", op: "inngest-enqueue" });
    expect(opts.extra).toMatchObject({ replay: false, transient: false });
  });

  test("(3b) transient exhaustion → 503 with extra.transient === true", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout"] });
    setupMessageRow("engineering.pr_review_pending", "pr-acme:repo:7");
    mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });
    mockInngestSend.mockRejectedValue(new TypeError("fetch failed"));

    const pending = POST(makeRequest({}), ctx());
    await vi.advanceTimersByTimeAsync(5_000);
    const res = await pending;

    expect(res.status).toBe(503);
    expect(mockInngestSend).toHaveBeenCalledTimes(3);
    expect(store.messageStatus()).toBe("draft");
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.extra).toMatchObject({ replay: false, transient: true });
  });

  test("(4) a transient enqueue failure is retried with the SAME event id and the route still answers 200", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout"] });
    setupMessageRow("triage.p0p1_issue", "issue-acme:repo:42");
    mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });
    mockInngestSend
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockResolvedValueOnce({ ids: ["evt-2"] });

    const pending = POST(makeRequest({}), ctx());
    await vi.advanceTimersByTimeAsync(5_000);
    const res = await pending;

    expect(res.status).toBe(200);
    expect(store.messageStatus()).toBe("archived");
    expect(store.archiveCount()).toBe(1);
    expect(mockInngestSend).toHaveBeenCalledTimes(2);
    const ids = mockInngestSend.mock.calls.map(
      (c) => (c[0] as { id: string }).id,
    );
    expect(ids).toEqual([`agent-spawn-${AS_ID}`, `agent-spawn-${AS_ID}`]);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  test("(5) the archive update filters status = 'draft'", async () => {
    setupMessageRow("engineering.pr_review_pending", "pr-acme:repo:7");
    mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(200);
    expect(store.archiveFilters[0]).toContainEqual(["status", "draft"]);
  });

  test("(6) Sentry extra key set on the exhausted enqueue is identifiers-only (no draft text, hash or error message)", async () => {
    setupMessageRow("engineering.pr_review_pending", "pr-acme:repo:7");
    mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });
    mockInngestSend.mockRejectedValueOnce(new Error("secret-bearing message"));

    await POST(makeRequest({}), ctx());

    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(Object.keys(opts.extra as Record<string, unknown>).sort()).toEqual(
      [
        "actionSendId",
        "errorName",
        "messageId",
        "replay",
        "transient",
        "userId",
      ].sort(),
    );
    expect(JSON.stringify(opts)).not.toContain("secret-bearing message");
    expect(JSON.stringify(opts)).not.toContain("test draft preview");
  });
});
