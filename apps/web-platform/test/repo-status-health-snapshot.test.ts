import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mock Supabase before importing the route
// ---------------------------------------------------------------------------

const mockSelect = vi.fn();
const mockEq = vi.fn();
const mockSingle = vi.fn();
const mockMaybeSingle = vi.fn();

vi.mock("@/lib/supabase/server", () => {
  // Chain builder for conversations query (select → eq → eq → eq → order → limit → maybeSingle)
  const convChain = {
    select: vi.fn(() => convChain),
    eq: vi.fn(() => convChain),
    order: vi.fn(() => convChain),
    limit: vi.fn(() => convChain),
    maybeSingle: mockMaybeSingle,
  };

  const mockFrom = vi.fn((table: string) => {
    if (table === "conversations") return convChain;
    // Default: users table chain
    return { select: mockSelect };
  });
  mockSelect.mockReturnValue({ eq: mockEq });
  mockEq.mockReturnValue({ single: mockSingle });

  return {
    createClient: vi.fn(async () => ({
      auth: {
        getUser: vi.fn(async () => ({
          data: { user: { id: "user-123" } },
        })),
      },
    })),
    createServiceClient: vi.fn(() => ({
      from: mockFrom,
    })),
  };
});

vi.mock("fs", async () => {
  const actual = await vi.importActual<typeof import("fs")>("fs");
  return { ...actual, existsSync: vi.fn(() => false) };
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("GET /api/repo/status — health_snapshot", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("includes healthSnapshot and syncConversationId in response when stored", async () => {
    const snapshot = {
      scannedAt: "2026-04-10T00:00:00.000Z",
      category: "developing",
      signals: {
        detected: [{ id: "tests", label: "Test suite" }],
        missing: [{ id: "ci", label: "CI/CD" }],
      },
      recommendations: ["Set up CI/CD."],
      kbExists: false,
    };

    mockSingle.mockResolvedValue({
      data: {
        repo_url: "https://github.com/user/repo",
        repo_status: "ready",
        repo_last_synced_at: "2026-04-10T00:00:00.000Z",
        workspace_path: "/workspaces/user-123",
        repo_error: null,
        health_snapshot: snapshot,
      },
      error: null,
    });

    // Active sync conversation exists
    mockMaybeSingle.mockResolvedValue({
      data: { id: "conv-abc" },
      error: null,
    });

    const { GET } = await import(
      "@/app/api/repo/status/route"
    );

    const res = await GET();
    const body = await res.json();

    expect(body.healthSnapshot).toEqual(snapshot);
    expect(body.syncConversationId).toBe("conv-abc");
    expect(body.status).toBe("ready");
  });

  it("returns syncConversationId as null when no active sync conversation (#1816)", async () => {
    mockSingle.mockResolvedValue({
      data: {
        repo_url: "https://github.com/user/repo",
        repo_status: "ready",
        repo_last_synced_at: "2026-04-10T00:00:00.000Z",
        workspace_path: "/workspaces/user-123",
        repo_error: null,
        health_snapshot: null,
      },
      error: null,
    });

    // No active sync conversation
    mockMaybeSingle.mockResolvedValue({
      data: null,
      error: null,
    });

    const { GET } = await import(
      "@/app/api/repo/status/route"
    );

    const res = await GET();
    const body = await res.json();

    expect(body.healthSnapshot).toBeNull();
    expect(body.syncConversationId).toBeNull();
  });
});
