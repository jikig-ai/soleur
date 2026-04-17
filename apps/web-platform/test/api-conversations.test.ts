import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it, expect, vi, beforeEach } from "vitest";

// Phase 0 RED — GET /api/conversations?context_path=<path>
// Contract:
//   - 200 + JSON { conversationId, context_path, last_active, message_count }
//     when a row exists
//   - 200 + JSON null when no row matches (not an error state)
//   - 400 on missing/invalid path
//   - 401 when unauthenticated
//   - 500 on internal lookup error (mirrors to reportSilentFallback)
//
// Also asserts the route DELEGATES to server/lookup-conversation-for-path
// (negative-space test: imports AND invokes AND branches on result).

// --- Mock infrastructure --------------------------------------------------

const { mockGetUser, mockLookup, mockReportSilentFallback } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockLookup: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({})),
}));

vi.mock("@/server/lookup-conversation-for-path", () => ({
  lookupConversationForPath: (...args: unknown[]) => mockLookup(...args),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) => mockReportSilentFallback(...args),
}));

async function importRoute() {
  return await import("@/app/api/conversations/route");
}

function makeRequest(url: string): Request {
  return new Request(url, { method: "GET" });
}

describe("GET /api/conversations", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const { GET } = await importRoute();
    const res = await GET(
      makeRequest(
        "https://app.soleur.ai/api/conversations?context_path=knowledge-base/x.md",
      ),
    );
    expect(res.status).toBe(401);
    expect(mockLookup).not.toHaveBeenCalled();
  });

  it("returns 400 when context_path is missing", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    const { GET } = await importRoute();
    const res = await GET(makeRequest("https://app.soleur.ai/api/conversations"));
    expect(res.status).toBe(400);
  });

  it("returns 400 when context_path is invalid (no knowledge-base prefix)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    const { GET } = await importRoute();
    const res = await GET(
      makeRequest(
        "https://app.soleur.ai/api/conversations?context_path=not-a-kb-path.md",
      ),
    );
    expect(res.status).toBe(400);
  });

  it("returns 200 with full row shape when a conversation exists", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockLookup.mockResolvedValue({
      ok: true,
      row: {
        id: "conv-123",
        context_path: "knowledge-base/product/roadmap.md",
        last_active: "2026-04-15T10:00:00Z",
        message_count: 7,
      },
    });
    const { GET } = await importRoute();
    const res = await GET(
      makeRequest(
        "https://app.soleur.ai/api/conversations?context_path=knowledge-base/product/roadmap.md",
      ),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({
      conversationId: "conv-123",
      context_path: "knowledge-base/product/roadmap.md",
      last_active: "2026-04-15T10:00:00Z",
      message_count: 7,
    });
    expect(mockLookup).toHaveBeenCalledWith(
      "u1",
      "knowledge-base/product/roadmap.md",
    );
  });

  it("returns 200 with null when no row matches (miss)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockLookup.mockResolvedValue({ ok: true, row: null });
    const { GET } = await importRoute();
    const res = await GET(
      makeRequest(
        "https://app.soleur.ai/api/conversations?context_path=knowledge-base/product/roadmap.md",
      ),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toBeNull();
  });

  it("returns 500 when the lookup helper errors (and mirrors to Sentry)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockLookup.mockResolvedValue({ ok: false, error: "lookup_failed" });
    const { GET } = await importRoute();
    const res = await GET(
      makeRequest(
        "https://app.soleur.ai/api/conversations?context_path=knowledge-base/product/roadmap.md",
      ),
    );
    expect(res.status).toBe(500);
    expect(mockReportSilentFallback).toHaveBeenCalled();
  });

  // ---------------------------------------------------------------------
  // Negative-space test (per learning
  // 2026-04-15-negative-space-tests-must-follow-extracted-logic):
  // Prove the route IMPORTS, INVOKES, and BRANCHES on the helper's result.
  // Without this, a future regression that silently inlines a query without
  // calling the helper would still pass the positive-path behavioral tests
  // if the query shape happened to match.
  // ---------------------------------------------------------------------
  it("source: route imports, invokes, AND branches on lookupConversationForPath", () => {
    const routePath = join(
      __dirname,
      "..",
      "app",
      "api",
      "conversations",
      "route.ts",
    );
    const source = readFileSync(routePath, "utf-8");
    // 1. Imports the helper
    expect(source).toMatch(
      /import\s*\{[^}]*lookupConversationForPath[^}]*\}\s*from\s*["']@\/server\/lookup-conversation-for-path["']/,
    );
    // 2. Invokes the helper
    expect(source).toMatch(/lookupConversationForPath\(/);
    // 3. Branches on `.ok`
    expect(source).toMatch(/\.ok/);
  });
});
