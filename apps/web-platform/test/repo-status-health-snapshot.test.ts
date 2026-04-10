import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mock Supabase before importing the route
// ---------------------------------------------------------------------------

const mockSelect = vi.fn();
const mockEq = vi.fn();
const mockSingle = vi.fn();

vi.mock("@/lib/supabase/server", () => {
  const mockFrom = vi.fn(() => ({
    select: mockSelect,
  }));
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

  it("includes healthSnapshot in response when stored in user record", async () => {
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

    const { GET } = await import(
      "@/app/api/repo/status/route"
    );

    const res = await GET();
    const body = await res.json();

    expect(body.healthSnapshot).toEqual(snapshot);
    expect(body.status).toBe("ready");
  });

  it("returns healthSnapshot as null when not stored", async () => {
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

    const { GET } = await import(
      "@/app/api/repo/status/route"
    );

    const res = await GET();
    const body = await res.json();

    expect(body.healthSnapshot).toBeNull();
  });
});
