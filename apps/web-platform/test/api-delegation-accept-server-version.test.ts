import { describe, test, expect, vi, beforeEach } from "vitest";

// Phase 1 (feat-byok-delegation-consent, #4625): the accept route must
// stamp the SERVER-OWNED canonical side-letter version, never trust the
// request body. side_letter_version is a client-supplied field today
// (accept/route.ts:65), which lets a grantee accept a stale version and
// fail OPEN at the resolver gate. AC3.

const {
  mockGetUser,
  mockUserFrom,
  mockServiceFrom,
  mockValidateOrigin,
  mockRejectCsrf,
  mockIsByokDelegationsEnabled,
  mockResolveCurrentOrganizationId,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockUserFrom: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  mockRejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
  mockIsByokDelegationsEnabled: vi.fn(async () => true),
  mockResolveCurrentOrganizationId: vi.fn(async () => "org-1"),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockUserFrom,
  })),
  createServiceClient: vi.fn(() => ({ from: mockServiceFrom })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: mockRejectCsrf,
}));

vi.mock("@/lib/feature-flags/server", () => ({
  isByokDelegationsEnabled: mockIsByokDelegationsEnabled,
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentOrganizationId: mockResolveCurrentOrganizationId,
}));

import { POST } from "@/app/api/workspace/delegations/accept/route";
import { BYOK_SIDE_LETTER_VERSION } from "@/server/byok-side-letter";

const USER_ID = "grantee-uuid";
const DELEGATION_ID = "delegation-uuid";

function makeRequest(body: Record<string, unknown>): Request {
  return new Request("https://app.soleur.ai/api/workspace/delegations/accept", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

// Capture the insert payload sent to byok_delegation_acceptances.
let lastInsertPayload: Record<string, unknown> | null = null;

beforeEach(() => {
  vi.clearAllMocks();
  lastInsertPayload = null;
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockRejectCsrf.mockReturnValue(
    new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  );
  mockIsByokDelegationsEnabled.mockResolvedValue(true);
  mockResolveCurrentOrganizationId.mockResolvedValue("org-1");
  mockGetUser.mockResolvedValue({ data: { user: { id: USER_ID, email: "g@example.com" } } });

  // Service client: from("byok_delegations").select().eq().maybeSingle()
  mockServiceFrom.mockImplementation((table: string) => {
    if (table === "byok_delegations") {
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: () =>
              Promise.resolve({
                data: { id: DELEGATION_ID, grantee_user_id: USER_ID, revoked_at: null },
                error: null,
              }),
          }),
        }),
      };
    }
    throw new Error(`unexpected service.from(${table})`);
  });

  // User client: from("byok_delegation_acceptances").insert(payload)
  mockUserFrom.mockImplementation((table: string) => {
    if (table === "byok_delegation_acceptances") {
      return {
        insert: (payload: Record<string, unknown>) => {
          lastInsertPayload = payload;
          return Promise.resolve({ error: null });
        },
      };
    }
    throw new Error(`unexpected user.from(${table})`);
  });
});

describe("POST /api/workspace/delegations/accept — server-owned version (AC3)", () => {
  test("stamps BYOK_SIDE_LETTER_VERSION even when body supplies a different version", async () => {
    const res = await POST(makeRequest({ delegationId: DELEGATION_ID, sideLetterVersion: "9.9.9" }));
    expect(res.status).toBe(200);
    expect(lastInsertPayload).not.toBeNull();
    expect(lastInsertPayload!.side_letter_version).toBe(BYOK_SIDE_LETTER_VERSION);
    expect(lastInsertPayload!.side_letter_version).not.toBe("9.9.9");
  });

  test("succeeds with NO sideLetterVersion field in the body (client no longer sends it)", async () => {
    const res = await POST(makeRequest({ delegationId: DELEGATION_ID }));
    expect(res.status).toBe(200);
    expect(lastInsertPayload!.side_letter_version).toBe(BYOK_SIDE_LETTER_VERSION);
  });

  test("still 400s when delegationId is missing", async () => {
    const res = await POST(makeRequest({}));
    expect(res.status).toBe(400);
  });
});
