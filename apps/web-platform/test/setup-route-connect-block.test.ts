import { describe, test, expect, vi, beforeEach } from "vitest";

// feat-repo-connect-block-offer-join — route-level mapping of the connect-time
// guard's outcome to the HTTP contract. The guard's BRANCH logic is unit-tested
// in test/repo-connect-guard.test.ts; here the guard is mocked and we assert
// that repo/setup/route.ts maps:
//   ok      → 200 { status: "cloning" }       (cloning flip reached)
//   switch  → 409 { outcome: "switch", existingWorkspaceId, ... } (flip NOT reached)
//   decline → 409 { outcome: "decline", ... }  (flip NOT reached, no id leak)
// and that the decline body is byte-identical across decline sub-cases (AC4).

const mockGetUser = vi.fn();
const mockRpc = vi.fn();
const mockServiceFrom = vi.fn();
const mockValidateOrigin = vi.fn();
const mockProvisionWorkspaceWithRepo = vi.fn();
const mockWriteRepoColsToWorkspace = vi.fn();
const mockResolveReachable = vi.fn();
const mockResolveOwning = vi.fn();
const mockResolveActiveWorkspace = vi.fn();
const mockEvaluateRepoConnect = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: mockGetUser },
    rpc: mockRpc,
  }),
  createServiceClient: () => ({ from: mockServiceFrom }),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: (...a: unknown[]) => mockValidateOrigin(...a),
  rejectCsrf: () =>
    new Response(JSON.stringify({ error: "forbidden" }), { status: 403 }),
}));

vi.mock("@/server/workspace", () => ({
  provisionWorkspaceWithRepo: (...a: unknown[]) =>
    mockProvisionWorkspaceWithRepo(...a),
}));
vi.mock("@/server/project-scanner", () => ({
  scanProjectHealth: vi.fn(() => null),
}));
vi.mock("@/server/agent-runner", () => ({
  startAgentSession: vi.fn(async () => {}),
}));
vi.mock("@/lib/repo-url", () => ({ normalizeRepoUrl: (u: string) => u }));
vi.mock("@/server/workspace-repo-mirror", () => ({
  writeRepoColsToWorkspace: (...a: unknown[]) =>
    mockWriteRepoColsToWorkspace(...a),
}));
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspace: (...a: unknown[]) => mockResolveActiveWorkspace(...a),
  resolveCurrentWorkspaceId: vi.fn(async (userId: string) => userId),
}));
vi.mock("@/server/git-auth", () => ({
  GitOperationError: class extends Error {},
  sanitizeGitStderr: (s: string) => s,
}));
vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));
vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn() }));
vi.mock("@/server/userid-pseudonymize", () => ({
  hashUserIdValue: (id: string) => id,
}));
vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
  withIsolationScope: (fn: () => void) => fn(),
  getCurrentScope: () => ({ setUser: vi.fn() }),
}));
vi.mock("@/server/reachable-installations", () => ({
  resolveReachableInstallationIds: (...a: unknown[]) =>
    mockResolveReachable(...a),
  resolveOwningInstallationForRepo: (...a: unknown[]) => mockResolveOwning(...a),
}));
vi.mock("@/server/auto-sync-trigger", () => ({
  triggerHeadlessSync: vi.fn(async () => {}),
}));
vi.mock("@/server/github-login", () => ({
  resolveGithubLogin: vi.fn(async () => "octo"),
}));
vi.mock("@/server/repo-connect-guard", () => ({
  evaluateRepoConnect: (...a: unknown[]) => mockEvaluateRepoConnect(...a),
}));

import { POST } from "../app/api/repo/setup/route";

const OTHER_USER = "99999999-9999-9999-9999-999999999999";
// Tracks whether the cloning-flip UPDATE on `workspaces` was issued.
let cloningFlipCalled = false;

function setupServiceClient() {
  cloningFlipCalled = false;
  mockServiceFrom.mockImplementation((table: string) => {
    if (table === "users") {
      return {
        select: () => ({
          eq: () => ({
            single: async () => ({
              data: { email: "u@example.com", github_username: "octo" },
              error: null,
            }),
          }),
        }),
      };
    }
    if (table === "workspaces") {
      return {
        update: (patch: Record<string, unknown>) => {
          const chain: Record<string, unknown> = {
            eq: () => chain,
            neq: () => {
              if (patch.repo_status === "cloning") cloningFlipCalled = true;
              return chain;
            },
            select: () => chain,
            maybeSingle: async () => ({ data: { id: "user-1" }, error: null }),
          };
          return chain;
        },
      };
    }
    throw new Error(`unexpected table: ${table}`);
  });
}

function makeRequest(body: unknown) {
  return new Request("https://app.soleur.ai/api/repo/setup", {
    method: "POST",
    headers: { Origin: "https://app.soleur.ai" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/repo/setup — connect-time block mapping", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockValidateOrigin.mockReturnValue({
      valid: true,
      origin: "https://app.soleur.ai",
    });
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1", email: "u@example.com" } },
    });
    mockRpc.mockResolvedValue({ data: true, error: null }); // owner-gate
    mockResolveActiveWorkspace.mockResolvedValue({
      ok: true,
      workspaceId: "user-1",
    });
    mockResolveReachable.mockResolvedValue([122213433]);
    mockResolveOwning.mockResolvedValue(122213433);
    mockProvisionWorkspaceWithRepo.mockResolvedValue("/workspaces/user-1");
    mockWriteRepoColsToWorkspace.mockResolvedValue(undefined);
    setupServiceClient();
  });

  test("ok → 200 cloning, flip reached", async () => {
    mockEvaluateRepoConnect.mockResolvedValue({ outcome: "ok" });
    const res = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "cloning" });
    expect(cloningFlipCalled).toBe(true);
  });

  test("AC2 switch → 409 carries existingWorkspaceId, flip NOT reached", async () => {
    mockEvaluateRepoConnect.mockResolvedValue({
      outcome: "switch",
      code: "workspace_switch_required",
      existingWorkspaceId: "user-1",
      canRequestJoin: false,
    });
    const res = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
    expect(res.status).toBe(409);
    const body = await res.json();
    expect(body.outcome).toBe("switch");
    expect(body.code).toBe("workspace_switch_required");
    expect(body.existingWorkspaceId).toBe("user-1");
    expect(cloningFlipCalled).toBe(false);
  });

  test("AC1/AC4 decline → 409 generic, flip NOT reached, no id leak", async () => {
    mockEvaluateRepoConnect.mockResolvedValue({
      outcome: "decline",
      code: "repo_connect_blocked",
      canRequestJoin: false,
    });
    const res = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
    expect(res.status).toBe(409);
    const body = await res.json();
    expect(body).toEqual({
      outcome: "decline",
      code: "repo_connect_blocked",
      canRequestJoin: false,
      error: "This repository can't be connected.",
    });
    expect(cloningFlipCalled).toBe(false);
    // Security P1: the decline response never carries a workspace/user reference.
    const serialized = JSON.stringify(body);
    expect(serialized).not.toContain(OTHER_USER);
    expect(serialized).not.toContain("existingWorkspaceId");
    expect(serialized).not.toContain("founderId");
  });

  // AC4: the decline body is byte-identical regardless of which decline sub-case
  // the guard returned (different-user owner vs ambiguous vs db-error all map to
  // the SAME { outcome: "decline", code: "repo_connect_blocked", ... } guard
  // result, so the route response is identical). Asserts no sub-case widens it.
  test("AC4 decline body byte-identical across decline sub-cases", async () => {
    const declineResult = {
      outcome: "decline",
      code: "repo_connect_blocked",
      canRequestJoin: false,
    };
    const bodies: string[] = [];
    for (let i = 0; i < 3; i++) {
      mockEvaluateRepoConnect.mockResolvedValue(declineResult);
      const res = await POST(
        makeRequest({ repoUrl: "https://github.com/octo/repo" }),
      );
      bodies.push(await res.text());
    }
    expect(new Set(bodies).size).toBe(1);
  });
});
