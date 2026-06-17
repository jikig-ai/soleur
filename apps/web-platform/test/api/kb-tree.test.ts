import { describe, test, expect, vi, beforeEach } from "vitest";
import { mockQueryChain } from "../helpers/mock-supabase";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockFrom, mockResolveInstallationId } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockResolveInstallationId: vi.fn(),
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

// #4712 follow-up — the route now derives needsReconnect via the async
// `resolveNeedsReconnect`, which (for ready + NULL user install) resolves the
// workspace-scoped credential. Mock that read so a `ready + null` row no longer
// reaches the real Supabase client.
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
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
    // Default: no workspace-scoped credential resolves (the #4706 silent-freeze
    // shape). Individual tests override to exercise the workspace-shared case.
    mockResolveInstallationId.mockResolvedValue(null);
  });

  test("needsReconnect=true for ready repo with null user install AND no workspace credential (#4706 freeze)", async () => {
    mockFrom.mockReturnValue(
      mockQueryChain({ ...BASE_USER, github_installation_id: null }),
    );
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.needsReconnect).toBe(true);
    expect(body.tree).toBeTruthy();
    expect(mockResolveInstallationId).toHaveBeenCalledWith(TEST_USER.id);
  });

  test("needsReconnect=false for ready repo with null user install but a resolvable workspace credential (the bug fix)", async () => {
    mockResolveInstallationId.mockResolvedValue(424242);
    mockFrom.mockReturnValue(
      mockQueryChain({ ...BASE_USER, github_installation_id: null }),
    );
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.needsReconnect).toBe(false);
  });

  test("needsReconnect=false for ready repo with an installation id", async () => {
    // ADR-044 PR-2 (#5462): the install id moved off `users` — the route reads
    // only `kb_sync_history` there and resolves the credential via the
    // membership-checked RPC. A resolvable install id (here from the
    // workspace-scoped RPC) short-circuits resolveNeedsReconnect to false.
    mockResolveInstallationId.mockResolvedValue(98765);
    mockFrom.mockReturnValue(mockQueryChain({ ...BASE_USER }));
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.needsReconnect).toBe(false);
    expect(mockResolveInstallationId).toHaveBeenCalledWith(
      TEST_USER.id,
      TEST_USER.id,
    );
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
