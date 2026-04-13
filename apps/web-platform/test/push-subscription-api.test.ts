import { describe, test, expect, vi, beforeEach } from "vitest";

const { mockGetUser, mockFrom } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: mockGetUser },
  }),
  createServiceClient: () => ({ from: mockFrom }),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: () => ({ valid: true, origin: "https://app.soleur.ai" }),
  rejectCsrf: vi.fn(() => Response.json({ error: "Forbidden" }, { status: 403 })),
}));

vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

import { POST, DELETE } from "../app/api/push-subscription/route";

describe("push-subscription API route", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("POST (subscribe)", () => {
    test("saves subscription for authenticated user", async () => {
      mockGetUser.mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      });
      mockFrom.mockReturnValue({
        upsert: () => ({ error: null }),
      });

      const req = new Request("https://app.soleur.ai/api/push-subscription", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          endpoint: "https://push.example.com/sub/123",
          keys: { p256dh: "test-p256dh", auth: "test-auth" },
        }),
      });

      const res = await POST(req);
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.success).toBe(true);
    });

    test("rejects unauthenticated requests", async () => {
      mockGetUser.mockResolvedValue({
        data: { user: null },
        error: { message: "Not logged in" },
      });

      const req = new Request("https://app.soleur.ai/api/push-subscription", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          endpoint: "https://push.example.com/sub/123",
          keys: { p256dh: "test-p256dh", auth: "test-auth" },
        }),
      });

      const res = await POST(req);
      expect(res.status).toBe(401);
    });

    test("rejects missing endpoint", async () => {
      mockGetUser.mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      });

      const req = new Request("https://app.soleur.ai/api/push-subscription", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ keys: { p256dh: "test", auth: "test" } }),
      });

      const res = await POST(req);
      expect(res.status).toBe(400);
    });

    test("rejects missing keys", async () => {
      mockGetUser.mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      });

      const req = new Request("https://app.soleur.ai/api/push-subscription", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ endpoint: "https://push.example.com/sub/123" }),
      });

      const res = await POST(req);
      expect(res.status).toBe(400);
    });
  });

  describe("DELETE (unsubscribe)", () => {
    test("removes subscription for authenticated user", async () => {
      mockGetUser.mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      });
      mockFrom.mockReturnValue({
        delete: () => ({
          eq: () => ({
            eq: () => ({ error: null }),
          }),
        }),
      });

      const req = new Request("https://app.soleur.ai/api/push-subscription", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          endpoint: "https://push.example.com/sub/123",
        }),
      });

      const res = await DELETE(req);
      expect(res.status).toBe(200);
    });

    test("rejects unauthenticated DELETE", async () => {
      mockGetUser.mockResolvedValue({
        data: { user: null },
        error: { message: "Not logged in" },
      });

      const req = new Request("https://app.soleur.ai/api/push-subscription", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ endpoint: "https://push.example.com/sub/123" }),
      });

      const res = await DELETE(req);
      expect(res.status).toBe(401);
    });
  });
});
