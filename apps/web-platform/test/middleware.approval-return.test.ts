/**
 * #4672: a signed-out tap on an approval push is bounced to sign-in WITH a return target, so the Owner lands on the same
 * request after sign-in and MFA. Only the exact approval landing path carries it; every other dashboard path keeps the
 * bare /login redirect.
 */
import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

const { mockGetUser, mockGetSession, mockRpc, mockFrom } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockGetSession: vi.fn(),
  mockRpc: vi.fn(),
  mockFrom: vi.fn(),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn(() => ({
    auth: { getUser: mockGetUser, getSession: mockGetSession },
    rpc: (...a: unknown[]) => ({ abortSignal: () => mockRpc(...a) }),
    from: mockFrom,
  })),
}));
vi.mock("@/lib/observability-edge", () => ({ reportEdgeSilentFallback: vi.fn() }));

import { middleware } from "@/middleware";

const ID = "00000000-0000-4000-8000-000000000006";
const req = (pathname: string) =>
  new NextRequest(new URL(`https://app.soleur.ai${pathname}`), { method: "GET", headers: { host: "app.soleur.ai" } });

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon-key");
  mockGetUser.mockReset().mockResolvedValue({ data: { user: null }, error: null });
  mockGetSession.mockReset().mockResolvedValue({ data: { session: null }, error: null });
});

const location = (res: Response) => new URL(res.headers.get("location") ?? "", "https://app.soleur.ai");

describe("signed-out redirect from the approval landing path", () => {
  test("carries the exact path as redirectTo", async () => {
    const res = await middleware(req(`/dashboard/approvals/${ID}`));
    expect(res.status).toBe(307);
    const loc = location(res);
    expect(loc.pathname).toBe("/login");
    expect(loc.searchParams.get("redirectTo")).toBe(`/dashboard/approvals/${ID}`);
  });

  test("the carried value is accepted by the login form's own validator (round trip)", async () => {
    const { safeReturnTo } = await import("@/lib/safe-return-to");
    const res = await middleware(req(`/dashboard/approvals/${ID}`));
    expect(safeReturnTo(location(res).searchParams.get("redirectTo"))).toBe(`/dashboard/approvals/${ID}`);
  });

  test("a non-UUID approval path, a trailing segment and a look-alike keep the bare /login redirect", async () => {
    for (const p of ["/dashboard/approvals/not-a-uuid", `/dashboard/approvals/${ID}/extra`, `/dashboard/approvalsx/${ID}`, "/dashboard/approvals"]) {
      const loc = location(await middleware(req(p)));
      expect(loc.pathname, p).toBe("/login");
      expect(loc.search, p).toBe("");
    }
  });

  test("other dashboard paths keep the bare /login redirect (no new return-target surface)", async () => {
    const loc = location(await middleware(req("/dashboard/inbox")));
    expect(loc.pathname).toBe("/login");
    expect(loc.search).toBe("");
  });
});
