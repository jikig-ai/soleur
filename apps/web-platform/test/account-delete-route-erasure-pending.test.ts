import { describe, test, expect, vi, beforeEach } from "vitest";

// The client can only qualify its post-delete copy if the route relays the flag. Pins that
// POST /api/account/delete exposes gitDataErasurePending exactly when deleteAccount reports it.

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: () => ({ valid: true, origin: "https://app.example.test" }),
  rejectCsrf: vi.fn(),
}));
vi.mock("@/server/request-auth", () => ({ verifiedUserId: async () => "u1" }));
vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({ warn: vi.fn(), info: vi.fn(), error: vi.fn() }),
}));
vi.mock("@/server/observability", () => ({ hashUserId: () => "hash" }));
const mockDeleteAccount = vi.fn();
vi.mock("@/server/account-delete", () => ({ deleteAccount: (...a: unknown[]) => mockDeleteAccount(...a) }));

function req() {
  return new Request("https://app.example.test/api/account/delete", {
    method: "POST",
    headers: { "content-type": "application/json", cookie: "sb-x-auth-token=abc" },
    body: JSON.stringify({ confirmEmail: "t@example.test" }),
  });
}

describe("POST /api/account/delete relays the erasure-pending flag", () => {
  beforeEach(() => {
    vi.resetModules();
    mockDeleteAccount.mockReset();
  });

  test("flag present when the repository erasure is owed", async () => {
    mockDeleteAccount.mockResolvedValue({ success: true, gitDataErasurePending: true });
    const { POST } = await import("@/app/api/account/delete/route");
    const res = await POST(req());
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ success: true, gitDataErasurePending: true });
  });

  test("flag absent on a fully confirmed deletion", async () => {
    mockDeleteAccount.mockResolvedValue({ success: true });
    const { POST } = await import("@/app/api/account/delete/route");
    const res = await POST(req());
    expect(await res.json()).toEqual({ success: true });
  });
});
