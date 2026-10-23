// #8211: POST /api/workspace maps the typed "workspace is being deleted" refusal to the calm,
// retryable 409 (not a 500 and not a Sentry incident).
import { describe, test, expect, vi, beforeEach } from "vitest";

const { mockProvision, mockReport, mockFrom } = vi.hoisted(() => ({
  mockProvision: vi.fn(),
  mockReport: vi.fn(),
  mockFrom: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({ createServiceClient: () => ({ from: mockFrom }) }));
vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: () => ({ valid: true, origin: "https://app.soleur.ai" }),
  rejectCsrf: () => new Response("no", { status: 403 }),
}));
vi.mock("@/server/request-auth", () => ({ verifiedUserId: async () => "user-1" }));
vi.mock("@/server/workspace", () => ({ provisionWorkspace: (...a: unknown[]) => mockProvision(...a) }));
vi.mock("@/server/observability", () => ({ reportSilentFallback: (...a: unknown[]) => mockReport(...a) }));
vi.mock("@/server/userid-pseudonymize", () => ({ hashUserIdValue: (s: string) => s }));
vi.mock("@sentry/nextjs", () => ({
  withIsolationScope: (fn: () => void) => fn(),
  getCurrentScope: () => ({ setUser: vi.fn() }),
}));

import { POST } from "../app/api/workspace/route";
import { WorkspaceReapInProgressError } from "../server/workspace-reap-error";

const req = () =>
  new Request("https://app.soleur.ai/api/workspace", { method: "POST", headers: { Origin: "https://app.soleur.ai" } });

beforeEach(() => {
  vi.clearAllMocks();
  mockFrom.mockImplementation(() => ({
    select: () => ({ eq: () => ({ single: async () => ({ data: { workspace_status: "none" }, error: null }) }) }),
    update: () => ({ eq: async () => ({ error: null }) }),
  }));
});

describe("POST /api/workspace while the workspace is being reaped", () => {
  test("409 + Retry-After + the existing in-progress message; not reported as an incident", async () => {
    mockProvision.mockRejectedValue(new WorkspaceReapInProgressError());

    const res = await POST(req());

    expect(res.status).toBe(409);
    expect(res.headers.get("Retry-After")).toBe("5");
    expect(await res.json()).toEqual({ error: "Setup already in progress" });
    expect(mockReport).not.toHaveBeenCalled();
  });

  test("any OTHER provisioning failure is still a reported 500", async () => {
    mockProvision.mockRejectedValue(new Error("disk full"));

    const res = await POST(req());

    expect(res.status).toBe(500);
    expect(mockReport).toHaveBeenCalledTimes(1);
  });
});
