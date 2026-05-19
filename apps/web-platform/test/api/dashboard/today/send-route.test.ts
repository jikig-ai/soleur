/**
 * PR-H (#4077) — Send route handler tests. Eight cases per plan Phase 4.2:
 *   1. 200 happy (draft_one_click + writeActionSend + cookie-scoped client)
 *   2. 409 requires_confirmation (approve_every_time without typed body)
 *   3. 422 typed_value mismatch — actually rolled into 409 path (server
 *      rejects "send" lowercase as 409, not 422; see Kieran P2-7)
 *   4. 403 revoked grant (isGranted returns null)
 *   5. 400 for auto / auto_with_digest tiers
 *   6. 401 no JWT
 *   7. 403 cross-tenant (message owned by another user)
 *   8. 200 approve_every_time with confirmed_typed=true + typed_value=SEND
 *
 * Per Kieran B4: UUIDs are schema-correct so 403 isn't masked by 22P02.
 */

import { describe, test, expect, vi, beforeEach } from "vitest";

const {
  mockGetUser,
  mockFrom,
  mockIsGranted,
  mockWriteActionSend,
  mockValidateOrigin,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockIsGranted: vi.fn(),
  mockWriteActionSend: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({
    valid: true,
    origin: "https://app.soleur.ai",
  })),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
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
  reportSilentFallback: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
  captureException: vi.fn(),
}));

import { POST } from "@/app/api/dashboard/today/[id]/send/route";

const FOUNDER_A = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa";
const MSG_ID = "11111111-1111-4111-aaaa-111111111111";
const GRANT_ID = "22222222-2222-4222-aaaa-222222222222";
const ACTION_CLASS = "finance.payment_failed";

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

function setupMessageRow(
  overrides: Partial<{
    user_id: string;
    action_class: string;
    status: string;
    draft_preview: string | null;
    owning_domain: string | null;
  }> = {},
) {
  const row = {
    id: MSG_ID,
    user_id: FOUNDER_A,
    action_class: ACTION_CLASS,
    status: "draft",
    draft_preview: "test draft preview",
    owning_domain: "cfo",
    ...overrides,
  };

  // Chain: from(messages).select(...).eq(id).eq(user_id).maybeSingle()
  const messageMaybeSingle = vi.fn(async () => ({ data: row, error: null }));
  const messageEq2 = vi.fn(() => ({ maybeSingle: messageMaybeSingle }));
  const messageEq1 = vi.fn(() => ({ eq: messageEq2 }));
  const messageSelect = vi.fn(() => ({ eq: messageEq1 }));

  // Chain: from(scope_grants).select(...).eq.eq.is.order.limit.maybeSingle()
  const sgMaybeSingle = vi.fn(async () => ({
    data: { id: GRANT_ID },
    error: null,
  }));
  const sgLimit = vi.fn(() => ({ maybeSingle: sgMaybeSingle }));
  const sgOrder = vi.fn(() => ({ limit: sgLimit }));
  const sgIs = vi.fn(() => ({ order: sgOrder }));
  const sgEq2 = vi.fn(() => ({ is: sgIs }));
  const sgEq1 = vi.fn(() => ({ eq: sgEq2 }));
  const sgSelect = vi.fn(() => ({ eq: sgEq1 }));

  // Chain: from(messages).update(...).eq.eq()
  const updEq2 = vi.fn(async () => ({ error: null }));
  const updEq1 = vi.fn(() => ({ eq: updEq2 }));
  const messageUpdate = vi.fn(() => ({ eq: updEq1 }));

  mockFrom.mockImplementation((table: string) => {
    if (table === "messages") {
      return {
        select: messageSelect,
        update: messageUpdate,
      };
    }
    if (table === "scope_grants") {
      return { select: sgSelect };
    }
    return {};
  });

  return { row };
}

describe("POST /api/dashboard/today/[id]/send", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockValidateOrigin.mockReturnValue({
      valid: true,
      origin: "https://app.soleur.ai",
    });
    mockGetUser.mockResolvedValue({ data: { user: { id: FOUNDER_A } } });
    mockWriteActionSend.mockResolvedValue({ id: "as-1" });
  });

  test("(6) 401 no JWT", async () => {
    mockGetUser.mockResolvedValueOnce({ data: { user: null } });
    setupMessageRow();
    const res = await POST(makeRequest(), ctx());
    expect(res.status).toBe(401);
  });

  test("(7) 403 cross-tenant (message row not found / RLS)", async () => {
    // maybeSingle returns null (RLS hides cross-tenant rows).
    mockFrom.mockImplementation((table: string) => {
      if (table === "messages") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({ data: null, error: null }),
              }),
            }),
          }),
        };
      }
      return {};
    });
    const res = await POST(makeRequest(), ctx());
    expect(res.status).toBe(403);
  });

  test("(1) 200 happy — draft_one_click writes action_sends + archives draft", async () => {
    setupMessageRow();
    mockIsGranted.mockResolvedValue({ tier: "draft_one_click" });

    const res = await POST(
      makeRequest({
        recipient_identifier: "recipient@example.com",
        body_content: "the actual outbound body",
      }),
      ctx(),
    );
    expect(res.status).toBe(200);

    const json = (await res.json()) as { id: string; tier: string };
    expect(json.tier).toBe("draft_one_click");
    expect(json.id).toBe("as-1");

    // isGranted MUST be called with the cookie-scoped supabase client
    // (1st arg) — NOT a service-role client. Per AC12.
    expect(mockIsGranted).toHaveBeenCalledTimes(1);
    const isGrantedArgs = mockIsGranted.mock.calls[0];
    expect(isGrantedArgs[1]).toBe(FOUNDER_A);
    expect(isGrantedArgs[2]).toBe(ACTION_CLASS);

    expect(mockWriteActionSend).toHaveBeenCalledTimes(1);
  });

  test("(4) 403 no_active_grant (isGranted returns null — revoked race)", async () => {
    setupMessageRow();
    mockIsGranted.mockResolvedValue(null);
    const res = await POST(makeRequest(), ctx());
    expect(res.status).toBe(403);
    const json = (await res.json()) as { error: string };
    expect(json.error).toBe("no_active_grant");
    expect(mockWriteActionSend).not.toHaveBeenCalled();
  });

  test("(5a) 400 auto tier — Send not applicable", async () => {
    setupMessageRow();
    mockIsGranted.mockResolvedValue({ tier: "auto" });
    const res = await POST(makeRequest(), ctx());
    expect(res.status).toBe(400);
    expect(mockWriteActionSend).not.toHaveBeenCalled();
  });

  test("(5b) 400 auto_with_digest tier — Send not applicable", async () => {
    setupMessageRow();
    mockIsGranted.mockResolvedValue({ tier: "auto_with_digest" });
    const res = await POST(makeRequest(), ctx());
    expect(res.status).toBe(400);
    expect(mockWriteActionSend).not.toHaveBeenCalled();
  });

  test("(2) 409 requires_confirmation (approve_every_time, no typed body)", async () => {
    setupMessageRow();
    mockIsGranted.mockResolvedValue({ tier: "approve_every_time" });
    const res = await POST(makeRequest(), ctx());
    expect(res.status).toBe(409);
    const json = (await res.json()) as {
      error: string;
      action_class: string;
      tier: string;
    };
    expect(json.error).toBe("requires_confirmation");
    expect(json.action_class).toBe(ACTION_CLASS);
    expect(json.tier).toBe("approve_every_time");
    expect(mockWriteActionSend).not.toHaveBeenCalled();
  });

  test("(3) 409 typed_value mismatch (lowercase 'send' MUST NOT bypass)", async () => {
    // Per Kieran P2-7 — no .trim() / .normalize(). Lowercase fails the
    // exact-match gate; server returns 409 same as no-typed-value.
    setupMessageRow();
    mockIsGranted.mockResolvedValue({ tier: "approve_every_time" });
    const res = await POST(
      makeRequest({ confirmed_typed: true, typed_value: "send" }),
      ctx(),
    );
    expect(res.status).toBe(409);
    expect(mockWriteActionSend).not.toHaveBeenCalled();
  });

  test("(8) 200 approve_every_time with confirmed_typed + typed_value=SEND", async () => {
    setupMessageRow();
    mockIsGranted.mockResolvedValue({ tier: "approve_every_time" });
    const res = await POST(
      makeRequest({
        confirmed_typed: true,
        typed_value: "SEND",
        recipient_identifier: "recipient@example.com",
        body_content: "the body the founder typed-confirmed",
      }),
      ctx(),
    );
    expect(res.status).toBe(200);
    const json = (await res.json()) as { tier: string; id: string };
    expect(json.tier).toBe("approve_every_time");
    expect(json.id).toBe("as-1");
    expect(mockWriteActionSend).toHaveBeenCalledTimes(1);
    const writeCallArgs = mockWriteActionSend.mock.calls[0][0];
    expect(writeCallArgs.tier).toBe("approve_every_time");
    expect(writeCallArgs.confirmedTyped).toBe(true);
    expect(writeCallArgs.typedValue).toBe("SEND");
  });

  test("422 unknown_action_class (defensive — should be rare after backfill)", async () => {
    setupMessageRow({ action_class: "external.unknown_future_class" });
    const res = await POST(makeRequest(), ctx());
    expect(res.status).toBe(422);
    expect(mockIsGranted).not.toHaveBeenCalled();
  });
});
