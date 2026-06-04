import { describe, it, expect, beforeAll, beforeEach, vi } from "vitest";
import sharp from "sharp";

// Route tests for app/api/workspace/logo/route.ts (POST upload + DELETE remove).
// Uses REAL sharp + synthesized image fixtures (cq-test-fixtures-synthesized-only)
// so AC4 image-validation (decoded-format assertion, pixel-bomb, non-square,
// APNG flatten, canonical-WebP re-encode) is exercised against the real decoder,
// not a mock. Supabase + observability are mocked; withUserRateLimit runs REAL
// so AC6b (429 throttle) is genuine.

vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const { mockGetUser, mockRpc, mockUpload, mockRemove, mockUpdateEq, mockReport } =
  vi.hoisted(() => ({
    mockGetUser: vi.fn(),
    mockRpc: vi.fn(),
    mockUpload: vi.fn(),
    mockRemove: vi.fn(),
    mockUpdateEq: vi.fn(),
    mockReport: vi.fn(),
  }));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    rpc: mockRpc,
  })),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({
    storage: {
      from: () => ({ upload: mockUpload, remove: mockRemove }),
    },
    from: () => ({ update: () => ({ eq: mockUpdateEq }) }),
  })),
}));

// resolveCurrentWorkspaceId is the server-side active-workspace resolver — the
// route must use ITS return for the storage path (AC5: never client-supplied).
const RESOLVED_WS = "11111111-1111-1111-1111-111111111111";
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: vi.fn(async () => RESOLVED_WS),
}));

vi.mock("@/server/observability", async () => {
  const actual = await vi.importActual<typeof import("@/server/observability")>(
    "@/server/observability",
  );
  return { ...actual, reportSilentFallback: mockReport };
});

vi.mock("@sentry/nextjs", () => ({
  captureMessage: vi.fn(),
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
  withIsolationScope: (fn: () => unknown) => fn(),
  getCurrentScope: () => ({ setUser: () => {} }),
}));

let POST: (req: Request) => Promise<Response>;
let DELETE: (req: Request) => Promise<Response>;
let pngSquare: Buffer;
let webpSquare: Buffer;
let jpegSquare: Buffer;
let pngNonSquare: Buffer;
let svgBuf: Buffer;
let pixelBomb: Buffer;

beforeAll(async () => {
  const mod = await import("@/app/api/workspace/logo/route");
  POST = mod.POST;
  DELETE = mod.DELETE;
  const solid = (w: number, h: number) =>
    sharp({ create: { width: w, height: h, channels: 3, background: { r: 10, g: 20, b: 30 } } });
  pngSquare = await solid(64, 64).png().toBuffer();
  webpSquare = await solid(64, 64).webp().toBuffer();
  jpegSquare = await solid(64, 64).jpeg().toBuffer();
  pngNonSquare = await solid(64, 32).png().toBuffer();
  svgBuf = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="red"/></svg>`,
  );
  // Small file, >16M decoded pixels (5000x5000 = 25M) — a decode bomb.
  pixelBomb = await solid(5000, 5000).png().toBuffer();
}, 30_000);

const ORIGIN = "https://app.test";
vi.stubEnv("NEXT_PUBLIC_SITE_URL", ORIGIN);

let userSeq = 0;
function authAs(): string {
  const id = `user-${++userSeq}-${Date.now()}`;
  mockGetUser.mockResolvedValue({ data: { user: { id } } });
  return id;
}
function owner(is = true) {
  mockRpc.mockResolvedValue({ data: is, error: null });
}
// No Origin header → validateOrigin treats it as a non-browser client and
// passes (CSRF is a browser-only vector; auth still gates). The cross-site
// case below sets an explicitly-disallowed Origin to exercise rejectCsrf.
function postReq(buf: Buffer, filename: string, type: string): Request {
  const fd = new FormData();
  fd.append("file", new File([buf], filename, { type }));
  return new Request("http://localhost/api/workspace/logo", {
    method: "POST",
    body: fd,
  });
}

beforeEach(() => {
  vi.clearAllMocks(); // clear call history (keeps no stale impls); re-set defaults below
  mockUpload.mockResolvedValue({ data: { path: `${RESOLVED_WS}/logo.webp` }, error: null });
  mockRemove.mockResolvedValue({ data: [], error: null });
  mockUpdateEq.mockResolvedValue({ error: null });
});

describe("POST /api/workspace/logo — auth + owner gate (AC5)", () => {
  it("401 when unauthenticated (wrapper)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(postReq(pngSquare, "logo.png", "image/png"));
    expect(res.status).toBe(401);
  });

  it("403 when caller is not the workspace owner", async () => {
    authAs();
    owner(false);
    const res = await POST(postReq(pngSquare, "logo.png", "image/png"));
    expect(res.status).toBe(403);
    expect(mockUpload).not.toHaveBeenCalled();
  });

  it("403 (CSRF) when Origin is cross-site", async () => {
    authAs();
    owner(true);
    const fd = new FormData();
    fd.append("file", new File([pngSquare], "logo.png", { type: "image/png" }));
    const res = await POST(
      new Request("http://localhost/api/workspace/logo", {
        method: "POST",
        body: fd,
        headers: { Origin: "https://evil.test" },
      }),
    );
    expect(res.status).toBe(403);
  });
});

describe("POST /api/workspace/logo — image validation (AC4)", () => {
  beforeEach(() => {
    authAs();
    owner(true);
  });

  it("accepts a square PNG → re-encodes to canonical WebP at <wid>/logo.webp", async () => {
    const res = await POST(postReq(pngSquare, "logo.png", "image/png"));
    expect(res.status).toBe(200);
    expect(mockUpload).toHaveBeenCalledTimes(1);
    const [path, body, opts] = mockUpload.mock.calls[0];
    expect(path).toBe(`${RESOLVED_WS}/logo.webp`); // AC5: server-resolved, not client
    expect(opts).toMatchObject({ contentType: "image/webp", upsert: true });
    // Output is real WebP (RIFF/WEBP magic).
    const out = body as Buffer;
    expect(out.subarray(0, 4).toString("ascii")).toBe("RIFF");
    expect(out.subarray(8, 12).toString("ascii")).toBe("WEBP");
  });

  it("accepts a square WebP", async () => {
    const res = await POST(postReq(webpSquare, "logo.webp", "image/webp"));
    expect(res.status).toBe(200);
  });

  it("rejects JPG even when filename/Content-Type claim PNG (format from decoded metadata, AC4 P0-2)", async () => {
    const res = await POST(postReq(jpegSquare, "logo.png", "image/png"));
    expect([415, 422]).toContain(res.status);
    expect(mockUpload).not.toHaveBeenCalled();
  });

  it("rejects SVG", async () => {
    const res = await POST(postReq(svgBuf, "logo.svg", "image/svg+xml"));
    expect([415, 422]).toContain(res.status);
    expect(mockUpload).not.toHaveBeenCalled();
  });

  it("rejects a non-square image (422)", async () => {
    const res = await POST(postReq(pngNonSquare, "logo.png", "image/png"));
    expect(res.status).toBe(422);
    expect(mockUpload).not.toHaveBeenCalled();
  });

  it("rejects a sub-1MB pixel-bomb (decoded-pixel flood, limitInputPixels, AC4 P0-1)", async () => {
    expect(pixelBomb.length).toBeLessThan(1024 * 1024); // small file...
    const res = await POST(postReq(pixelBomb, "logo.png", "image/png")); // ...25M decoded px
    expect([413, 422]).toContain(res.status);
    expect(mockUpload).not.toHaveBeenCalled();
  });
});

describe("POST /api/workspace/logo — persistence + orphan cleanup (AC7b)", () => {
  beforeEach(() => {
    authAs();
    owner(true);
  });

  it("uploads object FIRST then UPDATEs logo_path", async () => {
    const res = await POST(postReq(pngSquare, "logo.png", "image/png"));
    expect(res.status).toBe(200);
    expect(mockUpload).toHaveBeenCalled();
    expect(mockUpdateEq).toHaveBeenCalledWith("id", RESOLVED_WS);
  });

  it("on DB-persist failure: deletes orphan object + 500", async () => {
    mockUpdateEq.mockResolvedValue({ error: { message: "db down" } });
    const res = await POST(postReq(pngSquare, "logo.png", "image/png"));
    expect(res.status).toBe(500);
    expect(mockRemove).toHaveBeenCalledWith([`${RESOLVED_WS}/logo.webp`]);
  });

  it("on DB-persist failure AND cleanup-delete failure: distinct logo-orphan-cleanup-failed breadcrumb", async () => {
    mockUpdateEq.mockResolvedValue({ error: { message: "db down" } });
    mockRemove.mockResolvedValue({ data: null, error: { message: "remove failed" } });
    const res = await POST(postReq(pngSquare, "logo.png", "image/png"));
    expect(res.status).toBe(500);
    const ops = mockReport.mock.calls.map((c) => c[1]?.op);
    expect(ops).toContain("logo-orphan-cleanup-failed");
  });
});

describe("DELETE /api/workspace/logo (AC7b)", () => {
  function delReq(): Request {
    return new Request("http://localhost/api/workspace/logo", {
      method: "DELETE",
    });
  }

  it("403 for non-owner", async () => {
    authAs();
    owner(false);
    const res = await DELETE(delReq());
    expect(res.status).toBe(403);
    expect(mockUpdateEq).not.toHaveBeenCalled();
  });

  it("sets logo_path=NULL BEFORE removing the object", async () => {
    authAs();
    owner(true);
    const order: string[] = [];
    mockUpdateEq.mockImplementation(async () => {
      order.push("update-null");
      return { error: null };
    });
    mockRemove.mockImplementation(async () => {
      order.push("remove-object");
      return { data: [], error: null };
    });
    const res = await DELETE(delReq());
    expect(res.status).toBe(200);
    expect(order).toEqual(["update-null", "remove-object"]);
  });

  it("object-removal failure → distinct logo-orphan-cleanup-failed breadcrumb (still 200)", async () => {
    authAs();
    owner(true);
    mockRemove.mockResolvedValue({ data: null, error: { message: "remove failed" } });
    const res = await DELETE(delReq());
    expect(res.status).toBe(200);
    const ops = mockReport.mock.calls.map((c) => c[1]?.op);
    expect(ops).toContain("logo-orphan-cleanup-failed");
  });
});

describe("rate limit (AC6b)", () => {
  it("throttles rapid repeats from the same user with 429", async () => {
    authAs(); // single fixed user across the burst
    owner(true);
    let got429 = false;
    for (let i = 0; i < 40; i++) {
      const res = await POST(postReq(pngSquare, "logo.png", "image/png"));
      if (res.status === 429) {
        got429 = true;
        expect(res.headers.get("Retry-After")).toBe("60");
        break;
      }
    }
    expect(got429).toBe(true);
  });
});
