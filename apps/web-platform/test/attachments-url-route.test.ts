import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// POST /api/attachments/url — returns a signed URL the client renders as
// <img src> (attachment-display.tsx). The signed URL must be on the public
// Supabase host so it passes CSP img-src (same class as the workspace-logo
// proxy, #4996→#5012).

const { mockGetUser, mockCreateSignedUrl } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockCreateSignedUrl: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser } })),
  createServiceClient: vi.fn(() => ({
    storage: { from: () => ({ createSignedUrl: mockCreateSignedUrl }) },
    // .from("conversations")… is only reached for the cross-user branch; the
    // happy-path test uses an own-folder storagePath so it is never called.
    from: () => ({ select: () => ({ eq: () => ({ single: async () => ({ data: null }) }) }) }),
    rpc: vi.fn(),
  })),
}));
vi.mock("@/server/observability", async () => {
  const actual = await vi.importActual<typeof import("@/server/observability")>(
    "@/server/observability",
  );
  return { ...actual, reportSilentFallback: vi.fn() };
});

import { POST } from "@/app/api/attachments/url/route";

const USER = "11111111-1111-1111-1111-111111111111";
// No Origin header → validateOrigin treats as a non-browser client and passes.
const req = (storagePath: string, filename?: string) =>
  new Request("http://localhost/api/attachments/url", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(filename === undefined ? { storagePath } : { storagePath, filename }),
  });

beforeEach(() => {
  vi.clearAllMocks();
  mockGetUser.mockResolvedValue({ data: { user: { id: USER } } });
  mockCreateSignedUrl.mockResolvedValue({
    data: {
      signedUrl:
        "https://ifsccnjhymdmidffkzhl.supabase.co/storage/v1/object/sign/chat-attachments/x?token=abc",
    },
    error: null,
  });
});
afterEach(() => vi.unstubAllEnvs());

describe("POST /api/attachments/url — CSP host rewrite", () => {
  it("returns a signed URL on the NEXT_PUBLIC_SUPABASE_URL host (not the raw signing host)", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://api.soleur.ai");
    const res = await POST(req(`${USER}/conv/file.webp`));
    expect(res.status).toBe(200);
    const json = (await res.json()) as { url: string };
    expect(new URL(json.url).host).toBe("api.soleur.ai");
    expect(json.url).toContain("/storage/v1/object/sign/chat-attachments/x");
    expect(json.url).toContain("token=abc");
  });

  it("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(req(`${USER}/conv/file.webp`));
    expect(res.status).toBe(401);
  });
});

describe("POST /api/attachments/url — forced download for non-image types", () => {
  it.each([
    ["md", "2026-01-01-notes.md"],
    ["txt", "notes.txt"],
    ["pdf", "report.pdf"],
  ])("a .%s path is signed with { download: <filename> }", async (ext, filename) => {
    const res = await POST(req(`${USER}/conv/uuid.${ext}`, filename));
    expect(res.status).toBe(200);
    // Content-Disposition: attachment — the storage origin never renders the
    // file inline, and the chip downloads as its real name, not <uuid>.<ext>.
    expect(mockCreateSignedUrl).toHaveBeenCalledWith(
      `${USER}/conv/uuid.${ext}`,
      3_600,
      { download: filename },
    );
  });

  it.each(["png", "jpeg", "gif", "webp"])(
    "a .%s path is signed WITHOUT a download option (rendered as <img>)",
    async (ext) => {
      const res = await POST(req(`${USER}/conv/uuid.${ext}`, `x.${ext}`));
      expect(res.status).toBe(200);
      expect(mockCreateSignedUrl).toHaveBeenCalledTimes(1);
      expect(mockCreateSignedUrl.mock.calls[0]).toHaveLength(2);
    },
  );

  it("falls back to the path basename when no filename is sent", async () => {
    await POST(req(`${USER}/conv/uuid.md`));
    expect(mockCreateSignedUrl).toHaveBeenCalledWith(
      `${USER}/conv/uuid.md`,
      3_600,
      { download: "uuid.md" },
    );
  });

  it("strips separators, quotes and control characters from the download name", async () => {
    await POST(req(`${USER}/conv/uuid.md`, 'a/b\\c"d\ne\u0085f.md'));
    const opts = mockCreateSignedUrl.mock.calls[0]![2] as { download: string };
    expect(opts.download).not.toMatch(/[/\\"\n\u0085]/);
    expect(opts.download.endsWith(".md")).toBe(true);
  });
});
