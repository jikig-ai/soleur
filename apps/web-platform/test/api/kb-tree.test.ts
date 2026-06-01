import { describe, test, expect, vi, beforeEach } from "vitest";
import { mockQueryChain } from "../helpers/mock-supabase";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockFrom } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
}));

const TEST_USER = { id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" };

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: vi.fn(() => ({ from: mockFrom })),
}));

// Pass-through the rate-limit wrapper with a fixed authenticated user so the
// inner handler runs directly. The wrapper's auth/limiter behaviour is covered
// by test/with-user-rate-limit.test.ts.
vi.mock("@/server/with-user-rate-limit", () => ({
  withUserRateLimit:
    (handler: (req: Request, user: { id: string }) => Promise<Response>) =>
    (req: Request) =>
      handler(req, TEST_USER),
}));

vi.mock("@/server/kb-reader", () => ({
  buildTree: vi.fn(async () => ({ name: "knowledge-base", path: "", children: [] })),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

import { GET } from "@/app/api/kb/tree/route";

function makeRequest(): Request {
  return new Request("https://app.soleur.com/api/kb/tree");
}

const BASE_USER = {
  workspace_path: "/tmp/ws",
  workspace_status: "ready",
  repo_status: "ready",
  kb_sync_history: [],
};

describe("GET /api/kb/tree — needsReconnect", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("needsReconnect=true for ready repo with null installation id", async () => {
    mockFrom.mockReturnValue(
      mockQueryChain({ ...BASE_USER, github_installation_id: null }),
    );
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.needsReconnect).toBe(true);
    expect(body.tree).toBeTruthy();
  });

  test("needsReconnect=false for ready repo with an installation id", async () => {
    mockFrom.mockReturnValue(
      mockQueryChain({ ...BASE_USER, github_installation_id: 98765 }),
    );
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.needsReconnect).toBe(false);
  });

  test("not_connected short-circuits to 404 (no needsReconnect)", async () => {
    mockFrom.mockReturnValue(
      mockQueryChain({
        ...BASE_USER,
        repo_status: "not_connected",
        github_installation_id: null,
      }),
    );
    const res = await GET(makeRequest());
    expect(res.status).toBe(404);
  });
});
