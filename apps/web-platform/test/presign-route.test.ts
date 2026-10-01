import { describe, test, expect, vi, beforeEach } from "vitest";
import { mockQueryChain } from "./helpers/mock-supabase";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockGetUser, mockFrom, mockCreateSignedUploadUrl, mockRpc, mockReportSilentFallback } =
  vi.hoisted(() => ({
    mockGetUser: vi.fn(),
    mockFrom: vi.fn(),
    mockRpc: vi.fn(),
    mockCreateSignedUploadUrl: vi.fn(),
    mockReportSilentFallback: vi.fn(),
  }));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
    rpc: mockRpc,
    storage: {
      from: vi.fn(() => ({
        createSignedUploadUrl: mockCreateSignedUploadUrl,
      })),
    },
  })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  rejectCsrf: vi.fn(
    (_route: string, _origin: string | null) =>
      new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@/server/observability", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/observability")>();
  return { ...actual, reportSilentFallback: mockReportSilentFallback };
});

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { POST } from "@/app/api/attachments/presign/route";
import { validateOrigin } from "@/lib/auth/validate-origin";
import {
  ALLOWED_ATTACHMENT_TYPES,
  ATTACHMENT_EXTENSION_BY_TYPE,
} from "@/lib/attachment-constants";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TEST_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const TEST_CONVERSATION_ID = "11111111-2222-3333-4444-555555555555";

function makeRequest(body: Record<string, unknown> = {}): Request {
  return new Request("https://app.soleur.ai/api/attachments/presign", {
    method: "POST",
    headers: {
      origin: "https://app.soleur.ai",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      filename: "screenshot.png",
      contentType: "image/png",
      sizeBytes: 1024,
      conversationId: TEST_CONVERSATION_ID,
      ...body,
    }),
  });
}

function setupAuthenticatedUser() {
  mockGetUser.mockResolvedValue({
    data: { user: { id: TEST_USER_ID } },
  });
}

const OTHER_USER_ID = "99999999-8888-7777-6666-555555555555";
const OTHER_WORKSPACE_ID = "77777777-6666-5555-4444-333333333333";

function wireConversations(chain: ReturnType<typeof mockQueryChain>) {
  mockFrom.mockImplementation((table: string) => (table === "conversations" ? chain : {}));
  // Default is_workspace_member to false; tests covering the co-member
  // branch override per-test via mockRpc.mockResolvedValueOnce.
  mockRpc.mockResolvedValue({ data: false, error: null });
  return chain;
}

function setupOwnedConversation() {
  // mig 068 #4318: route also reads user_id + workspace_id and falls back to
  // is_workspace_member RPC when conv.user_id !== caller. Owned-conv shape so
  // the RPC is NOT invoked (own-folder branch).
  return wireConversations(
    mockQueryChain({
      id: TEST_CONVERSATION_ID,
      user_id: TEST_USER_ID,
      workspace_id: TEST_USER_ID,
    }),
  );
}

/**
 * Fresh (deferred) conversation: no row exists yet. PostgREST-faithful:
 * `.single()` on zero rows is an ERROR (PGRST116), `.maybeSingle()` is
 * `{ data: null, error: null }`. A route that kept `.single()` would 500
 * every fresh conversation once it checks `error` first.
 */
function setupNoConversationRow() {
  const chain = mockQueryChain(null);
  chain.single.mockImplementation(() =>
    Promise.resolve({ data: null, error: { code: "PGRST116", message: "0 rows" } }),
  );
  chain.maybeSingle.mockImplementation(() => Promise.resolve({ data: null, error: null }));
  return wireConversations(chain);
}

function setupForeignConversation() {
  return wireConversations(
    mockQueryChain({
      id: TEST_CONVERSATION_ID,
      user_id: OTHER_USER_ID,
      workspace_id: OTHER_WORKSPACE_ID,
    }),
  );
}

function primeSignedUrl() {
  mockCreateSignedUploadUrl.mockResolvedValue({
    data: { signedUrl: "https://storage.supabase.co/upload/signed/abc123" },
    error: null,
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("POST /api/attachments/presign", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Revert prior per-test stubs, then pin the public host EMPTY so the
    // suite is ambient-env-independent: a dev shell that exports
    // NEXT_PUBLIC_SUPABASE_URL would otherwise flip the verbatim-URL
    // assertions red. Empty -> falsy -> toPublicStorageUrl passthrough.
    vi.unstubAllEnvs();
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
  });

  test("returns 403 on CSRF rejection", async () => {
    vi.mocked(validateOrigin).mockReturnValueOnce({
      valid: false,
      origin: "https://evil.com",
    });

    const res = await POST(makeRequest());
    expect(res.status).toBe(403);
  });

  test("returns 401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const res = await POST(makeRequest());
    expect(res.status).toBe(401);

    const body = await res.json();
    expect(body.error).toBe("unauthorized");
  });

  // ---- D1: presign tolerates an unmaterialized (fresh) conversation id ----
  describe("unmaterialized conversation id (deferred creation)", () => {
    test("valid lowercase UUID with NO row -> 200 + path under the caller's own folder (RED pre-fix: 404)", async () => {
      setupAuthenticatedUser();
      const chain = setupNoConversationRow();
      primeSignedUrl();

      const res = await POST(makeRequest());
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.uploadUrl).toBe("https://storage.supabase.co/upload/signed/abc123");
      expect(body.storagePath.startsWith(`${TEST_USER_ID}/${TEST_CONVERSATION_ID}/`)).toBe(true);
      // PostgREST fidelity: .single() on zero rows is PGRST116, so the route
      // must use .maybeSingle() (error-first) for this to be a 200.
      expect(chain.maybeSingle).toHaveBeenCalled();
      expect(chain.single).not.toHaveBeenCalled();
    });

    const tooShort = TEST_CONVERSATION_ID.slice(0, 8);
    test.each([
      ["the route sentinel 'new'", "new"],
      // One parent-directory segment only: two in a row (as a literal or as
      // consecutive quoted array members) would make repo-wide-containment
      // classify this app-local suite as repo-wide.
      ["a traversal string", "x/../etc/x"],
      ["a short uuid", tooShort],
      ["an UPPERCASE uuid", TEST_USER_ID.toUpperCase()],
      ["a valid uuid with a traversal suffix", `${TEST_CONVERSATION_ID}/../other`],
      ["a valid uuid with a trailing char", `${TEST_CONVERSATION_ID}x`],
      ["a valid uuid with a leading char", `x${TEST_CONVERSATION_ID}`],
      // Right length (36) but wrong grouping: `[0-9a-f-]{36}` would admit these.
      ["a 36-char wrong-grouping id", "0123456789abcdef-0123456789abcdef-0123"],
      ["a 36-char all-dash-free hex id", "0123456789abcdef0123456789abcdef0123"],
      ["a 32-hex id with no dashes", "0123456789abcdef0123456789abcdef"],
    ])("%s -> 404 conversation_not_found with NO lookup and NO storage call", async (_label, id) => {
      setupAuthenticatedUser();
      setupNoConversationRow();
      primeSignedUrl();

      const res = await POST(makeRequest({ conversationId: id }));
      expect(res.status).toBe(404);
      expect((await res.json()).error).toBe("conversation_not_found");
      // Shape check must run BEFORE the DB call: conversations.id is a uuid
      // column, so `.eq("id", "new")` is a Postgres 22P02 error (500), which
      // mockQueryChain(null) alone cannot show.
      expect(mockFrom).not.toHaveBeenCalled();
      expect(mockCreateSignedUploadUrl).not.toHaveBeenCalled();
    });

    test("a DB lookup error for a valid UUID -> 500 upload_failed, never the tolerant branch, mirrored to Sentry", async () => {
      setupAuthenticatedUser();
      const chain = wireConversations(mockQueryChain(null, { message: "db down" }));
      chain.maybeSingle.mockImplementation(() =>
        Promise.resolve({ data: null, error: { message: "db down" } }),
      );
      primeSignedUrl();

      const res = await POST(makeRequest());
      expect(res.status).toBe(500);
      expect((await res.json()).error).toBe("upload_failed");
      expect(mockCreateSignedUploadUrl).not.toHaveBeenCalled();
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ feature: "attachments", op: "presign-lookup" }),
      );
    });

    test("extra body fields (workspaceId, userId) never change the storage path", async () => {
      setupAuthenticatedUser();
      setupNoConversationRow();
      primeSignedUrl();

      const res = await POST(
        makeRequest({ workspaceId: OTHER_WORKSPACE_ID, userId: OTHER_USER_ID }),
      );
      expect(res.status).toBe(200);
      const { storagePath } = await res.json();
      expect(storagePath.startsWith(`${TEST_USER_ID}/${TEST_CONVERSATION_ID}/`)).toBe(true);
      expect(storagePath).not.toContain(OTHER_USER_ID);
      expect(storagePath).not.toContain(OTHER_WORKSPACE_ID);
    });
  });

  // CHARACTERIZATION (pass before the fix): the membership check on an
  // existing row is intact.
  describe("existing row owned by another user (characterization)", () => {
    test("non-member -> 403 not_a_workspace_member and the RPC is asked with the row's workspace", async () => {
      setupAuthenticatedUser();
      setupForeignConversation();
      primeSignedUrl();

      const res = await POST(makeRequest());
      expect(res.status).toBe(403);
      expect((await res.json()).error).toBe("not_a_workspace_member");
      expect(mockRpc).toHaveBeenCalledWith("is_workspace_member", {
        p_workspace_id: OTHER_WORKSPACE_ID,
        p_user_id: TEST_USER_ID,
      });
      expect(mockCreateSignedUploadUrl).not.toHaveBeenCalled();
    });

    test("membership RPC error -> 403 (fail closed)", async () => {
      setupAuthenticatedUser();
      setupForeignConversation();
      mockRpc.mockResolvedValue({ data: null, error: { message: "rpc down" } });
      primeSignedUrl();

      const res = await POST(makeRequest());
      expect(res.status).toBe(403);
      expect(mockCreateSignedUploadUrl).not.toHaveBeenCalled();
    });

    test("co-member -> 200", async () => {
      setupAuthenticatedUser();
      setupForeignConversation();
      mockRpc.mockResolvedValue({ data: true, error: null });
      primeSignedUrl();

      const res = await POST(makeRequest());
      expect(res.status).toBe(200);
    });
  });

  test("returns 400 for unsupported file type", async () => {
    setupAuthenticatedUser();
    setupOwnedConversation();

    const res = await POST(makeRequest({ contentType: "application/exe", filename: "virus.exe" }));
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toBe("unsupported_file_type");
  });

  test("returns 400 when file exceeds 20 MB", async () => {
    setupAuthenticatedUser();
    setupOwnedConversation();

    const res = await POST(makeRequest({ sizeBytes: 21 * 1024 * 1024 }));
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toBe("file_too_large");
  });

  test("returns 400 when sizeBytes is zero or negative", async () => {
    setupAuthenticatedUser();
    setupOwnedConversation();

    const res = await POST(makeRequest({ sizeBytes: 0 }));
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toBeDefined();
  });

  // Regression for #3332 review: NaN slipped past `typeof === "number"` and
  // `<= 0` before the Number.isFinite gate. Closes a defense-in-depth gap.
  test("returns 400 when sizeBytes is NaN", async () => {
    setupAuthenticatedUser();
    setupOwnedConversation();

    // JSON has no NaN literal; emulate via a body that round-trips NaN
    // through the route's number-coercion path. The simplest way is to
    // bypass JSON.stringify and hand-craft the body.
    const req = new Request("https://app.soleur.ai/api/attachments/presign", {
      method: "POST",
      headers: {
        origin: "https://app.soleur.ai",
        "content-type": "application/json",
      },
      body: '{"filename":"x.pdf","contentType":"application/pdf","sizeBytes":NaN,"conversationId":"' +
        TEST_CONVERSATION_ID +
        '"}',
    });
    const res = await POST(req);
    // NaN is not valid JSON — request.json() rejects, so the parse-guard
    // fires (400 invalid_request). If a future code path begins accepting
    // NaN through Number coercion, the Number.isFinite gate must catch it.
    expect(res.status).toBe(400);
  });

  test("returns 200 with uploadUrl and storagePath on success", async () => {
    setupAuthenticatedUser();
    setupOwnedConversation();
    mockCreateSignedUploadUrl.mockResolvedValue({
      data: { signedUrl: "https://storage.supabase.co/upload/signed/abc123" },
      error: null,
    });

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.uploadUrl).toBe("https://storage.supabase.co/upload/signed/abc123");
    expect(body.storagePath).toMatch(
      new RegExp(`^${TEST_USER_ID}/${TEST_CONVERSATION_ID}/[a-f0-9-]+\\.png$`),
    );
  });

  // CSP: prod splits SUPABASE_URL (raw <ref>.supabase.co, service-role signing
  // host) from NEXT_PUBLIC_SUPABASE_URL (api.soleur.ai, the only storage host
  // connect-src allows). The browser PUT must land on the public host — same
  // defect class as the #5020 download-URL rewrite (toPublicStorageUrl).
  test("rewrites uploadUrl onto NEXT_PUBLIC_SUPABASE_URL, preserving path and token", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://api.soleur.ai");
    setupAuthenticatedUser();
    setupOwnedConversation();
    mockCreateSignedUploadUrl.mockResolvedValue({
      data: {
        signedUrl:
          "https://ifsccnjhymdmidffkzhl.supabase.co/storage/v1/object/upload/sign/chat-attachments/u/c/f.md?token=abc123",
      },
      error: null,
    });

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);

    const body = await res.json();
    const rewritten = new URL(body.uploadUrl);
    expect(rewritten.host).toBe("api.soleur.ai");
    expect(rewritten.pathname).toBe(
      "/storage/v1/object/upload/sign/chat-attachments/u/c/f.md",
    );
    expect(rewritten.searchParams.get("token")).toBe("abc123");
    expect(body.uploadUrl).not.toContain("supabase.co");
  });

  test("leaves uploadUrl untouched when NEXT_PUBLIC_SUPABASE_URL matches the signed-URL host", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://storage.supabase.co");
    setupAuthenticatedUser();
    setupOwnedConversation();
    mockCreateSignedUploadUrl.mockResolvedValue({
      data: { signedUrl: "https://storage.supabase.co/upload/signed/abc123" },
      error: null,
    });

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.uploadUrl).toBe("https://storage.supabase.co/upload/signed/abc123");
  });

  test("accepts all allowed content types", async () => {
    const allowedTypes = [...ALLOWED_ATTACHMENT_TYPES];
    // Anti-vacuity: the loop must actually cover md + txt.
    expect(allowedTypes).toContain("text/markdown");
    expect(allowedTypes).toContain("text/plain");

    for (const contentType of allowedTypes) {
      vi.clearAllMocks();
      setupAuthenticatedUser();
      setupOwnedConversation();
      mockCreateSignedUploadUrl.mockResolvedValue({
        data: { signedUrl: "https://storage.supabase.co/upload/signed/abc123" },
        error: null,
      });

      const ext = ATTACHMENT_EXTENSION_BY_TYPE[contentType];
      const res = await POST(makeRequest({ contentType, filename: `file.${ext}` }));
      expect(res.status).toBe(200);
    }
  });

  test("returns 500 when Storage createSignedUploadUrl fails", async () => {
    setupAuthenticatedUser();
    setupOwnedConversation();
    mockCreateSignedUploadUrl.mockResolvedValue({
      data: null,
      error: { message: "Storage unavailable" },
    });

    const res = await POST(makeRequest());
    expect(res.status).toBe(500);

    const body = await res.json();
    expect(body.error).toBe("upload_failed");
  });

  test("returns 400 when required fields are missing", async () => {
    setupAuthenticatedUser();

    const req = new Request("https://app.soleur.ai/api/attachments/presign", {
      method: "POST",
      headers: {
        origin: "https://app.soleur.ai",
        "content-type": "application/json",
      },
      body: JSON.stringify({}),
    });

    const res = await POST(req);
    expect(res.status).toBe(400);
  });

  // Closes #3332: PDFs over the agent-readable cap (24 MB raw, sized to fit
  // Anthropic's 32 MB encoded request payload after ~33% base64 inflation)
  // must be rejected at the presign seam. Defense-in-depth alongside the
  // client-side validateFiles guard.
  describe("PDF size cap (#3332)", () => {
    test("rejects 25 MB application/pdf with 400 file_too_large", async () => {
      setupAuthenticatedUser();
      setupOwnedConversation();

      const res = await POST(
        makeRequest({
          contentType: "application/pdf",
          filename: "big.pdf",
          sizeBytes: 25 * 1024 * 1024,
        }),
      );
      expect(res.status).toBe(400);

      const body = await res.json();
      expect(body.error).toBe("file_too_large");
    });

    test("accepts 19 MB application/pdf with 200 (under both caps)", async () => {
      setupAuthenticatedUser();
      setupOwnedConversation();
      mockCreateSignedUploadUrl.mockResolvedValue({
        data: { signedUrl: "https://storage.supabase.co/upload/signed/abc123" },
        error: null,
      });

      const res = await POST(
        makeRequest({
          contentType: "application/pdf",
          filename: "ok.pdf",
          sizeBytes: 19 * 1024 * 1024,
        }),
      );
      expect(res.status).toBe(200);
    });
  });
  describe("markdown / plain-text attachments (server re-resolves the type)", () => {
    function primeSuccess() {
      setupAuthenticatedUser();
      setupOwnedConversation();
      mockCreateSignedUploadUrl.mockResolvedValue({
        data: { signedUrl: "https://storage.supabase.co/upload/signed/abc123" },
        error: null,
      });
    }

    test.each([
      ["text/markdown", "2026-01-01-onboarding-notes.md", "md"],
      ["text/plain", "notes.txt", "txt"],
      // Old cached clients still send the raw browser-reported type.
      ["", "a.md", "md"],
      ["application/octet-stream", "a.md", "md"],
      ["text/x-markdown", "a.md", "md"],
      ["application/x-genesis-rom", "a.md", "md"],
      ["", "NOTES.TXT", "txt"],
    ])("accepts contentType %j for %j and mints a .%s path", async (contentType, filename, ext) => {
      primeSuccess();
      const res = await POST(makeRequest({ contentType, filename }));
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.storagePath).toMatch(
        new RegExp(`^${TEST_USER_ID}/${TEST_CONVERSATION_ID}/[a-f0-9-]+\\.${ext}$`),
      );
    });

    test.each([
      ["application/x-msdownload", "evil.md"],
      ["text/html", "x.md"],
      ["text/plain", "x.py"],
      ["text/plain", "notes"],
      ["text/plain", "md"],
      ["application/octet-stream", "virus.exe"],
    ])("rejects contentType %j for %j with 400 unsupported_file_type", async (contentType, filename) => {
      primeSuccess();
      const res = await POST(makeRequest({ contentType, filename }));
      expect(res.status).toBe(400);
      expect((await res.json()).error).toBe("unsupported_file_type");
      expect(mockCreateSignedUploadUrl).not.toHaveBeenCalled();
    });

    test("a .pdf typed octet-stream is still rejected (the resolver does not widen PDFs)", async () => {
      primeSuccess();
      const res = await POST(
        makeRequest({ contentType: "application/octet-stream", filename: "doc.pdf" }),
      );
      expect(res.status).toBe(400);
      expect((await res.json()).error).toBe("unsupported_file_type");
    });

    test("a .md typed text/html with a charset parameter is rejected", async () => {
      primeSuccess();
      const res = await POST(
        makeRequest({ contentType: "text/html;charset=utf-8", filename: "x.md" }),
      );
      expect(res.status).toBe(400);
    });
  });
});
