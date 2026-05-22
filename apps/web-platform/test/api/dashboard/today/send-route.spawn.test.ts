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
 *   3. Inngest enqueue failure → 200 with degraded:"enqueue_failed";
 *      action_sends row stays committed; reportSilentFallback fires
 *   4. The route does NOT return 500 on enqueue failure (orphan-prevention)
 *
 * A separate file from send-route.test.ts because the spawn dispatch is
 * a new surface — the existing matrix tests the pre-PR-A behavioral
 * contract; this file tests the additive contract.
 */

import { describe, test, expect, vi, beforeEach } from "vitest";

const {
  mockGetUser,
  mockFrom,
  mockRpc,
  mockIsGranted,
  mockWriteActionSend,
  mockValidateOrigin,
  mockInngestSend,
  mockReportSilentFallback,
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
  warnSilentFallback: vi.fn(),
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

function setupMessageRow(
  action_class: string,
  source_ref: string,
): void {
  const row = {
    id: MSG_ID,
    user_id: FOUNDER_A,
    action_class,
    status: "draft",
    draft_preview: "test draft preview",
    owning_domain: "engineering",
    template_id: "default_legacy",
    source_ref,
  };

  const messageMaybeSingle = vi.fn(async () => ({ data: row, error: null }));
  const messageEq2 = vi.fn(() => ({ maybeSingle: messageMaybeSingle }));
  const messageEq1 = vi.fn(() => ({ eq: messageEq2 }));
  const messageSelect = vi.fn(() => ({ eq: messageEq1 }));

  // messages.update — track ordering
  const updEq2 = vi.fn(async () => {
    callOrder.push("messages-archive");
    return { error: null };
  });
  const updEq1 = vi.fn(() => ({ eq: updEq2 }));
  const messageUpdate = vi.fn(() => ({ eq: updEq1 }));

  mockFrom.mockImplementation((table: string) => {
    if (table === "messages") {
      return { select: messageSelect, update: messageUpdate };
    }
    return {};
  });
}

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
  test("(1) kb_drift draft_one_click → 200 with action_send_id + artifact_view_url + inngest.send called once", async () => {
    setupMessageRow("knowledge.kb_drift", "link-acme/repo#5");
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
    expect(json.artifact_view_url).toBe(
      "https://github.com/acme/repo/issues/5",
    );
    expect(json.degraded).toBeUndefined();

    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    const sent = mockInngestSend.mock.calls[0][0] as {
      name: string;
      data: Record<string, unknown>;
    };
    expect(sent.name).toBe("agent.spawn.requested");
    expect(sent.data).toMatchObject({
      founderId: FOUNDER_A,
      messageId: MSG_ID,
      actionClass: "knowledge.kb_drift",
      sourceRef: "link-acme/repo#5",
      actionSendId: AS_ID,
    });
    // The event payload MUST NOT carry installationId (cross-tenant guard).
    expect(sent.data).not.toHaveProperty("installationId");
  });

  test("(2) engineering.pr_review_pending → inngest.send dispatched AFTER writeActionSend AND BEFORE archive flip", async () => {
    setupMessageRow("engineering.pr_review_pending", "pr-acme/repo#7");
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

  test("(3) inngest.send throws → 200 with degraded:'enqueue_failed'; reportSilentFallback fires", async () => {
    setupMessageRow("engineering.pr_review_pending", "pr-acme/repo#7");
    mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });
    mockInngestSend.mockImplementationOnce(async () => {
      callOrder.push("inngest.send-throw");
      throw new Error("inngest dev mode unreachable");
    });

    const res = await POST(makeRequest({}), ctx());
    expect(res.status).toBe(200);
    const json = (await res.json()) as {
      action_send_id?: string;
      degraded?: string;
    };
    // The action_sends row IS the durable artifact — it stays committed.
    expect(json.action_send_id).toBe(AS_ID);
    expect(json.degraded).toBe("enqueue_failed");

    // archive still runs (action_sends row exists; archiving the message
    // matches the row's WORM-committed reality).
    expect(callOrder).toEqual([
      "writeActionSend",
      "inngest.send-throw",
      "messages-archive",
    ]);

    // Sentry mirror fired for the enqueue failure.
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [, ctx0] = mockReportSilentFallback.mock.calls[0];
    expect(ctx0).toMatchObject({
      feature: "spawn-agent",
      op: "inngest-enqueue",
    });
  });

  test("(4) inngest.send throws → route does NOT return 500 (orphan-prevention)", async () => {
    setupMessageRow("triage.p0p1_issue", "issue-acme/repo#42");
    mockIsGranted.mockResolvedValue({ id: GRANT_ID, tier: "draft_one_click" });
    mockInngestSend.mockRejectedValueOnce(new Error("substrate down"));

    const res = await POST(makeRequest({}), ctx());
    // Critical: action_sends row is already written. A 500 would suggest
    // retry to the operator and create orphan rows on every retry.
    expect(res.status).not.toBe(500);
    expect(res.status).toBe(200);
  });
});
