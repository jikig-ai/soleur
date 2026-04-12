import { describe, test, expect, vi, beforeEach } from "vitest";
import { mockQueryChain } from "./helpers/mock-supabase";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockGetUser, mockFrom, mockCreateSignedUploadUrl } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockCreateSignedUploadUrl: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
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

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { POST } from "@/app/api/attachments/presign/route";
import { validateOrigin } from "@/lib/auth/validate-origin";

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

function setupConversationOwnership(owned: boolean) {
  mockFrom.mockImplementation((table: string) => {
    if (table === "conversations") {
      return mockQueryChain(owned ? { id: TEST_CONVERSATION_ID } : null);
    }
    return {};
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("POST /api/attachments/presign", () => {
  beforeEach(() => {
    vi.clearAllMocks();
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

  test("returns 404 when user does not own the conversation", async () => {
    setupAuthenticatedUser();
    setupConversationOwnership(false);

    const res = await POST(makeRequest());
    expect(res.status).toBe(404);

    const body = await res.json();
    expect(body.error).toBe("conversation_not_found");
  });

  test("returns 400 for unsupported file type", async () => {
    setupAuthenticatedUser();
    setupConversationOwnership(true);

    const res = await POST(makeRequest({ contentType: "application/exe", filename: "virus.exe" }));
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toBe("unsupported_file_type");
  });

  test("returns 400 when file exceeds 20 MB", async () => {
    setupAuthenticatedUser();
    setupConversationOwnership(true);

    const res = await POST(makeRequest({ sizeBytes: 21 * 1024 * 1024 }));
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toBe("file_too_large");
  });

  test("returns 400 when sizeBytes is zero or negative", async () => {
    setupAuthenticatedUser();
    setupConversationOwnership(true);

    const res = await POST(makeRequest({ sizeBytes: 0 }));
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toBeDefined();
  });

  test("returns 200 with uploadUrl and storagePath on success", async () => {
    setupAuthenticatedUser();
    setupConversationOwnership(true);
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

  test("accepts all allowed content types", async () => {
    const allowedTypes = ["image/png", "image/jpeg", "image/gif", "image/webp", "application/pdf"];

    for (const contentType of allowedTypes) {
      vi.clearAllMocks();
      setupAuthenticatedUser();
      setupConversationOwnership(true);
      mockCreateSignedUploadUrl.mockResolvedValue({
        data: { signedUrl: "https://storage.supabase.co/upload/signed/abc123" },
        error: null,
      });

      const ext = contentType === "application/pdf" ? "pdf" : contentType.split("/")[1];
      const res = await POST(makeRequest({ contentType, filename: `file.${ext}` }));
      expect(res.status).toBe(200);
    }
  });

  test("returns 500 when Storage createSignedUploadUrl fails", async () => {
    setupAuthenticatedUser();
    setupConversationOwnership(true);
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
});
