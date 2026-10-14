import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// POST /api/attachments/url — returns a signed URL the client renders as
// <img src> (attachment-display.tsx). The signed URL must be on the public
// Supabase host so it passes CSP img-src (same class as the workspace-logo
// proxy, #4996→#5012).

const { mockGetUser, mockCreateSignedUrl, mockInfo } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockCreateSignedUrl: vi.fn(),
  mockInfo: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser } })),
  createServiceClient: vi.fn(() => ({
    storage: { from: () => ({ createSignedUrl: mockCreateSignedUrl, info: mockInfo }) },
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
  // Default: the stored Content-Type agrees with the suffix (what presign mints).
  mockInfo.mockImplementation(async (path: string) => {
    const ext = path.split(".").pop();
    const contentType = ext === "pdf" ? "application/pdf" : `image/${ext}`;
    return { data: { contentType }, error: null };
  });
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

describe("POST /api/attachments/url — inline vs download", () => {
  const download = async (storagePath: string, filename?: string) => {
    const res = await POST(req(storagePath, filename));
    expect(res.status).toBe(200);
    const { url } = (await res.json()) as { url: string };
    return new URL(url).searchParams.get("download");
  };

  // Default-deny: inline is the short allowlist (images + PDF); everything
  // else, including an unrecognised or missing suffix, is a forced download.
  it.each(["md", "txt", "html", "svg", "bin", "js"])(
    "a .%s path is signed for DOWNLOAD under the given filename",
    async (ext) => {
      expect(await download(`${USER}/conv/uuid.${ext}`, `report.${ext}`)).toBe(
        `report.${ext}`,
      );
    },
  );

  it("does not spend a Storage lookup on downloads (only inline candidates are verified)", async () => {
    await download(`${USER}/conv/uuid.md`, "a.md");
    expect(mockInfo).not.toHaveBeenCalled();
  });

  describe("the STORED type must agree with an inline suffix", () => {
    it.each([
      ["png", "text/html"],
      ["jpeg", "application/pdf"],
      ["webp", ""],
      ["pdf", "text/html"],
      ["pdf", "image/png"],
      ["pdf", "application/octet-stream"],
    ])("a .%s path holding %j is a forced download", async (ext, stored) => {
      mockInfo.mockResolvedValue({ data: { contentType: stored }, error: null });
      expect(await download(`${USER}/conv/uuid.${ext}`, `x.${ext}`)).toBe(`x.${ext}`);
    });

    it("accepts the snake_case field name the SDK types declare", async () => {
      mockInfo.mockResolvedValue({ data: { content_type: "image/png" }, error: null });
      expect(await download(`${USER}/conv/uuid.png`, "x.png")).toBeNull();
    });

    it("fails closed to a download when the lookup errors or returns nothing", async () => {
      mockInfo.mockResolvedValue({ data: null, error: { message: "Object not found" } });
      expect(await download(`${USER}/conv/uuid.png`, "x.png")).toBe("x.png");
      mockInfo.mockResolvedValue({ data: null, error: null });
      expect(await download(`${USER}/conv/uuid.pdf`, "x.pdf")).toBe("x.pdf");
    });
  });

  it("an extension-less path is also a forced download", async () => {
    expect(await download(`${USER}/conv/uuid`, "notes")).toBe("notes");
  });

  it.each(["png", "jpeg", "gif", "webp", "pdf"])(
    "a .%s path is served inline (no download parameter)",
    async (ext) => {
      expect(await download(`${USER}/conv/uuid.${ext}`, `x.${ext}`)).toBeNull();
    },
  );

  it("signs with the plain two-argument createSignedUrl (download is added to the URL)", async () => {
    await POST(req(`${USER}/conv/uuid.md`, "a.md"));
    expect(mockCreateSignedUrl).toHaveBeenCalledWith(`${USER}/conv/uuid.md`, 3_600);
    expect(mockCreateSignedUrl.mock.calls[0]).toHaveLength(2);
  });

  it("falls back to the path basename when no filename is sent", async () => {
    expect(await download(`${USER}/conv/uuid.md`)).toBe("uuid.md");
  });

  it.each(["Q&A #1 + notes = final ? v2;.md", "R&D plan.md", "todo #2.txt", "a+b.md"])(
    "keeps %j intact: & # + = ? ; are percent-encoded, not query syntax",
    async (name) => {
      const res = await POST(req(`${USER}/conv/uuid.md`, name));
      const { url } = (await res.json()) as { url: string };
      const parsed = new URL(url);
      expect(parsed.searchParams.get("download")).toBe(name);
      // The original signature parameter must not be shadowed or duplicated.
      expect(parsed.searchParams.getAll("token")).toEqual(["abc"]);
    },
  );

  const cp = (n: number) => String.fromCharCode(n);
  it.each([
    ["path separator", "a/b.md"],
    ["backslash", "a" + cp(0x5c) + "b.md"],
    ["quote", 'a"b.md'],
    ["LF", "a" + cp(0x0a) + "b.md"],
    ["DEL", "a" + cp(0x7f) + "b.md"],
    ["NEL", "a" + cp(0x85) + "b.md"],
    ["LS", "a" + cp(0x2028) + "b.md"],
    ["PS", "a" + cp(0x2029) + "b.md"],
    ["RLO", "a" + cp(0x202e) + "b.md"],
    ["RLI", "a" + cp(0x2067) + "b.md"],
    ["LRM", "a" + cp(0x200e) + "b.md"],
    ["RLM", "a" + cp(0x200f) + "b.md"],
    ["ZWNJ", "a" + cp(0x200c) + "b.md"],
    ["ALM", "a" + cp(0x061c) + "b.md"],
    ["ZWSP", "a" + cp(0x200b) + "b.md"],
    ["word joiner", "a" + cp(0x2060) + "b.md"],
    ["BOM", "a" + cp(0xfeff) + "b.md"],
  ])("neutralises %s in the download name", async (_label, name) => {
    const got = await download(`${USER}/conv/uuid.md`, name);
    expect(got).toBe("a_b.md");
  });

  it("caps the download name at 255 characters", async () => {
    const got = await download(`${USER}/conv/uuid.md`, "a".repeat(400) + ".md");
    expect(got!.length).toBe(255);
  });
});
