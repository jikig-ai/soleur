import { describe, it, expect, beforeEach, vi } from "vitest";

// GET /api/workspace/[id]/logo — the stable proxy route (AC6). Membership-gates
// then 302-redirects to a freshly-minted short-TTL signed URL. The <img src> is
// this stable path (no signature) → browser-cacheable across focus re-polls.

const { mockGetUser, mockRpc, mockSelectMaybeSingle, mockCreateSignedUrl, mockReport } =
  vi.hoisted(() => ({
    mockGetUser: vi.fn(),
    mockRpc: vi.fn(),
    mockSelectMaybeSingle: vi.fn(),
    mockCreateSignedUrl: vi.fn(),
    mockReport: vi.fn(),
  }));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser }, rpc: mockRpc })),
}));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: mockSelectMaybeSingle }) }) }),
    storage: { from: () => ({ createSignedUrl: mockCreateSignedUrl }) },
  })),
}));
vi.mock("@/server/observability", async () => {
  const actual = await vi.importActual<typeof import("@/server/observability")>(
    "@/server/observability",
  );
  return { ...actual, reportSilentFallback: mockReport };
});

import { GET } from "@/app/api/workspace/[id]/logo/route";

const WS = "22222222-2222-2222-2222-222222222222";
const req = () => new Request(`http://localhost/api/workspace/${WS}/logo`);
const ctx = () => ({ params: Promise.resolve({ id: WS }) });

beforeEach(() => {
  vi.clearAllMocks();
  mockGetUser.mockResolvedValue({ data: { user: { id: "viewer" } } });
  mockRpc.mockResolvedValue({ data: true, error: null });
  mockSelectMaybeSingle.mockResolvedValue({ data: { logo_path: `${WS}/logo.webp` }, error: null });
  mockCreateSignedUrl.mockResolvedValue({
    data: { signedUrl: "https://proj.supabase.co/storage/v1/object/sign/workspace-logos/x?token=abc" },
    error: null,
  });
});

describe("GET /api/workspace/[id]/logo (AC6)", () => {
  it("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET(req(), ctx());
    expect(res.status).toBe(401);
  });

  it("403 for a non-member (is_workspace_member=false)", async () => {
    mockRpc.mockResolvedValue({ data: false, error: null });
    const res = await GET(req(), ctx());
    expect(res.status).toBe(403);
    expect(mockCreateSignedUrl).not.toHaveBeenCalled();
  });

  it("404 when the workspace has no logo (logo_path null)", async () => {
    mockSelectMaybeSingle.mockResolvedValue({ data: { logo_path: null }, error: null });
    const res = await GET(req(), ctx());
    expect(res.status).toBe(404);
    expect(mockCreateSignedUrl).not.toHaveBeenCalled();
  });

  it("302 → signed URL with short-TTL cache headers + nosniff for a member with a logo", async () => {
    const res = await GET(req(), ctx());
    expect(res.status).toBe(302);
    expect(res.headers.get("Location")).toContain("token=abc");
    expect(res.headers.get("Cache-Control")).toBe("private, max-age=300");
    expect(res.headers.get("X-Content-Type-Options")).toBe("nosniff");
    // mints with TTL=300
    expect(mockCreateSignedUrl).toHaveBeenCalledWith(`${WS}/logo.webp`, 300);
  });

  it("rewrites the signed-URL host to NEXT_PUBLIC_SUPABASE_URL so the 302 target matches CSP img-src (#4996 follow-up)", async () => {
    // The service client signs against SUPABASE_URL (the raw <ref>.supabase.co
    // host in prod). CSP img-src is built from NEXT_PUBLIC_SUPABASE_URL (the
    // public custom domain), so a 302 to the raw host is blocked by the browser
    // → <img> onError → monogram. The proxy must rewrite the origin to the
    // public host (token is host-agnostic; both hosts route to the same project).
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://public.soleur.test");
    mockCreateSignedUrl.mockResolvedValue({
      data: {
        signedUrl:
          "https://ifsccnjhymdmidffkzhl.supabase.co/storage/v1/object/sign/workspace-logos/x?token=abc",
      },
      error: null,
    });
    const res = await GET(req(), ctx());
    expect(res.status).toBe(302);
    const loc = res.headers.get("Location")!;
    expect(new URL(loc).host).toBe("public.soleur.test");
    // path + token preserved (only the origin is rewritten)
    expect(loc).toContain("/storage/v1/object/sign/workspace-logos/x");
    expect(loc).toContain("token=abc");
    vi.unstubAllEnvs();
  });

  it("502 + reportSilentFallback when signed-URL mint fails", async () => {
    mockCreateSignedUrl.mockResolvedValue({ data: null, error: { message: "mint failed" } });
    const res = await GET(req(), ctx());
    expect(res.status).toBe(502);
    expect(mockReport).toHaveBeenCalled();
  });

  // Review finding (security-sentinel P3 + architecture-strategist): the proxy
  // mints a signed URL + runs an RPC per cache-miss; without a per-user limit a
  // member can loop it. 429 caps the amplification (browser cache covers steady).
  it("throttles a cache-busting burst from the same user with 429", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "burst-viewer" } } });
    let got429 = false;
    for (let i = 0; i < 90; i++) {
      const res = await GET(req(), ctx());
      if (res.status === 429) {
        got429 = true;
        expect(res.headers.get("Retry-After")).toBe("60");
        break;
      }
    }
    expect(got429).toBe(true);
  });
});
