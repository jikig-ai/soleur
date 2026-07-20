import { describe, test, expect, vi, beforeEach } from "vitest";
import { DASHBOARD_FOUNDATION_KB_PATHS } from "@/lib/kb-constants";

// Phase 2 of plan 2026-07-07-perf-dashboard-load-and-conversation-list.
//
// /api/dashboard/foundation-status returns existence+size for ONLY the known
// foundation KB paths (a targeted stat) — replacing the render-blocking
// `/api/kb/tree` whole-tree walk on cold dashboard load.

const { mockResolve, mockStatKnownPaths } = vi.hoisted(() => ({
  mockResolve: vi.fn(),
  mockStatKnownPaths: vi.fn(),
}));

const TEST_USER = { id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" };

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: vi.fn(() => ({ from: vi.fn() })),
}));

vi.mock("@/server/with-user-rate-limit", () => ({
  withUserRateLimit:
    (handler: (req: Request, user: { id: string }) => Promise<Response>) =>
    (req: Request) =>
      handler(req, TEST_USER),
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspaceKbRoot: mockResolve,
}));

vi.mock("@/server/kb-reader", () => ({
  statKnownPaths: mockStatKnownPaths,
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { GET } from "@/app/api/dashboard/foundation-status/route";

function makeRequest(): Request {
  return new Request("https://app.soleur.com/api/dashboard/foundation-status");
}

describe("GET /api/dashboard/foundation-status", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockResolve.mockResolvedValue({
      ok: true,
      kbRoot: "/tmp/ws/knowledge-base",
      activeWorkspaceId: TEST_USER.id,
      repoStatus: "ready",
    });
  });

  test("200 returns { paths } stat map for the known foundation paths only", async () => {
    mockStatKnownPaths.mockResolvedValue({
      "overview/vision.md": { exists: true, size: 1200 },
      "marketing/brand-guide.md": { exists: false, size: 0 },
    });
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.paths["overview/vision.md"]).toEqual({ exists: true, size: 1200 });
    // stats ONLY the known-path set — never a whole-tree buildTree walk.
    expect(mockStatKnownPaths).toHaveBeenCalledWith(
      "/tmp/ws/knowledge-base",
      DASHBOARD_FOUNDATION_KB_PATHS,
    );
  });

  test("404 when the workspace is not found", async () => {
    mockResolve.mockResolvedValue({ ok: false, status: 404 });
    const res = await GET(makeRequest());
    expect(res.status).toBe(404);
    expect(mockStatKnownPaths).not.toHaveBeenCalled();
  });

  test("503 when the workspace is not ready (provisioning)", async () => {
    mockResolve.mockResolvedValue({ ok: false, status: 503 });
    const res = await GET(makeRequest());
    expect(res.status).toBe(503);
  });

  test("500 (not a blank success) when the stat unexpectedly throws", async () => {
    mockStatKnownPaths.mockRejectedValue(new Error("boom"));
    const res = await GET(makeRequest());
    expect(res.status).toBe(500);
  });
});

describe("DASHBOARD_FOUNDATION_KB_PATHS coverage", () => {
  test("includes vision.md and is a non-empty known set", () => {
    expect(DASHBOARD_FOUNDATION_KB_PATHS).toContain("overview/vision.md");
    expect(DASHBOARD_FOUNDATION_KB_PATHS.length).toBeGreaterThanOrEqual(4);
  });

  test("is a SUPERSET of every kbPath the dashboard page derives cards from (drift guard)", async () => {
    // Read the page source and extract every `kbPath: "..."` literal from the
    // FOUNDATION_PATHS + OPERATIONAL_TASKS card definitions. A card whose kbPath
    // is missing from the constant would silently never complete (the endpoint
    // wouldn't stat it), so this guard fails the moment the two drift.
    const { readFileSync } = await import("node:fs");
    const path = await import("node:path");
    const src = readFileSync(
      path.join(__dirname, "../../app/(dashboard)/dashboard/page.tsx"),
      "utf8",
    );
    const kbPaths = [...src.matchAll(/kbPath:\s*"([^"]+)"/g)].map((m) => m[1]!);
    expect(kbPaths.length).toBeGreaterThanOrEqual(9);
    const known = new Set<string>(DASHBOARD_FOUNDATION_KB_PATHS);
    for (const p of kbPaths) {
      expect(known, `page kbPath "${p}" missing from DASHBOARD_FOUNDATION_KB_PATHS`).toContain(p);
    }
  });
});
