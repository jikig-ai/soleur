/**
 * #10543 (CTO Q2) — POST /api/dashboard/today/[id]/edit refuses once an approval row exists.
 *
 * The WORM action_sends row pins the draft body by hash and cannot be replaced, so editing a draft
 * that already has an approval would strand it behind draft_changed_since_approval. The edit is
 * refused (409 draft_already_approved) BEFORE any update; a lookup error fails closed (500); the
 * pre-existing behaviors (200 on a plain edit, 403 on a draft the caller does not own, 400 on a bad
 * body) are unchanged.
 */

import { describe, test, expect, vi, beforeEach } from "vitest";

const { mockGetUser, mockFrom, mockValidateOrigin, mockReport } = vi.hoisted(
  () => ({
    mockGetUser: vi.fn(),
    mockFrom: vi.fn(),
    mockValidateOrigin: vi.fn(() => ({
      valid: true,
      origin: "https://app.soleur.ai",
    })),
    mockReport: vi.fn(),
  }),
);

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

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: vi.fn(),
  hashUserId: vi.fn(() => "founder-hash-stub"),
}));

import { POST } from "@/app/api/dashboard/today/[id]/edit/route";

const FOUNDER = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa";
const MSG = "11111111-1111-4111-aaaa-111111111111";

function req(body?: unknown): Request {
  return new Request(`https://app.soleur.ai/api/dashboard/today/${MSG}/edit`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: "https://app.soleur.ai",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
const ctx = () => ({ params: Promise.resolve({ id: MSG }) });

interface Wiring {
  approval?: { id: string } | null;
  approvalError?: { message: string } | null;
  updated?: { id: string; draft_preview: string } | null;
}

function wire({
  approval = null,
  approvalError = null,
  updated = { id: MSG, draft_preview: "new text" },
}: Wiring = {}) {
  const calls = { approvalFilters: [] as Array<[string, unknown]>, updates: 0 };

  const approvalChain = {
    eq(col: string, val: unknown) {
      calls.approvalFilters.push([col, val]);
      return approvalChain;
    },
    maybeSingle: async () => ({ data: approval, error: approvalError }),
  };
  const updateChain = {
    eq: () => updateChain,
    select: () => updateChain,
    maybeSingle: async () => ({ data: updated, error: null }),
  };

  mockFrom.mockImplementation((table: string) => {
    if (table === "action_sends") return { select: () => approvalChain };
    if (table === "messages") {
      return {
        update: () => {
          calls.updates += 1;
          return updateChain;
        },
      };
    }
    return {};
  });
  return calls;
}

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({
    valid: true,
    origin: "https://app.soleur.ai",
  });
  mockGetUser.mockResolvedValue({ data: { user: { id: FOUNDER } } });
});

describe("POST /api/dashboard/today/[id]/edit", () => {
  test("no approval row → the edit goes through (200) and the lookup is scoped to this message AND user", async () => {
    const calls = wire();

    const res = await POST(req({ draft_preview: "new text" }), ctx());
    expect(res.status).toBe(200);
    expect(await res.json()).toStrictEqual({
      id: MSG,
      draft_preview: "new text",
    });
    expect(calls.updates).toBe(1);
    expect(calls.approvalFilters).toContainEqual(["message_id", MSG]);
    expect(calls.approvalFilters).toContainEqual(["user_id", FOUNDER]);
  });

  test("an approval row exists → 409 draft_already_approved and NO update is attempted", async () => {
    const calls = wire({ approval: { id: "as-1" } });

    const res = await POST(req({ draft_preview: "new text" }), ctx());
    expect(res.status).toBe(409);
    expect(await res.json()).toStrictEqual({
      error: "draft_already_approved",
      message_id: MSG,
    });
    expect(calls.updates).toBe(0);
  });

  test("a lookup error fails closed: 500 internal_error, Sentry mirrored, NO update", async () => {
    const calls = wire({ approvalError: { message: "db down" } });

    const res = await POST(req({ draft_preview: "new text" }), ctx());
    expect(res.status).toBe(500);
    expect(((await res.json()) as { error: string }).error).toBe(
      "internal_error",
    );
    expect(calls.updates).toBe(0);
    expect(mockReport).toHaveBeenCalledTimes(1);
    expect(mockReport.mock.calls[0][1]).toMatchObject({
      feature: "dashboard-edit",
      op: "action-sends-lookup",
    });
  });

  test("[guard] a draft the caller does not own (update matches nothing) is still 403", async () => {
    wire({ updated: null });
    const res = await POST(req({ draft_preview: "x" }), ctx());
    expect(res.status).toBe(403);
  });

  test("[guard] a non-string draft_preview is still 400 before any lookup", async () => {
    const calls = wire();
    const res = await POST(req({ draft_preview: 7 }), ctx());
    expect(res.status).toBe(400);
    expect(calls.updates).toBe(0);
    expect(calls.approvalFilters).toEqual([]);
  });
});
