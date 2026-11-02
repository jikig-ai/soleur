import { describe, test, expect, vi, beforeEach } from "vitest";

// #8211 quiet-window (CTO ruling) — POST /api/repo/setup is a NEW-session-class
// write: it clones a working tree onto the web host. With the kill-switch on it
// must answer 503 + the maintenance message BEFORE resolving the workspace,
// flipping repo_status to "cloning" or provisioning anything. Flag off/absent:
// unchanged behaviour. Harness mirrors setup-route-connect-block.test.ts; the
// flag is driven through the real feature-flag module's env-fallback path.

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
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));
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
import { QUIET_WINDOW_MESSAGE } from "@/server/quiet-window";
import { __resetFeatureFlagsForTests } from "@/lib/feature-flags/server";
import { runExclusiveReap } from "@/server/workspace-reap-guard";
import { WorkspaceReapInProgressError } from "@/server/workspace-reap-error";
import * as SentryMod from "@sentry/nextjs";
import { reportSilentFallback } from "@/server/observability";

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


describe("POST /api/repo/setup — quiet-window kill-switch (#8211)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
    delete process.env.FLAG_NEW_SESSIONS_PAUSED;
    __resetFeatureFlagsForTests();
    mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
    mockGetUser.mockResolvedValue({ data: { user: { id: "user-1", email: "u@example.com" } } });
    mockRpc.mockResolvedValue({ data: true, error: null });
    mockResolveActiveWorkspace.mockResolvedValue({ ok: true, workspaceId: "user-1" });
    mockResolveReachable.mockResolvedValue([122213433]);
    mockResolveOwning.mockResolvedValue(122213433);
    mockProvisionWorkspaceWithRepo.mockResolvedValue("/workspaces/user-1");
    mockWriteRepoColsToWorkspace.mockResolvedValue(undefined);
    mockEvaluateRepoConnect.mockResolvedValue({ outcome: "ok" });
    setupServiceClient();
  });

  test("flag ON -> 503 + maintenance message + Retry-After; nothing resolved, locked or cloned", async () => {
    process.env.FLAG_NEW_SESSIONS_PAUSED = "1";
    __resetFeatureFlagsForTests();

    const res = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));

    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("300");
    expect(await res.json()).toEqual({ error: QUIET_WINDOW_MESSAGE, code: "quiet_window" });
    expect(mockResolveActiveWorkspace).not.toHaveBeenCalled();
    expect(cloningFlipCalled).toBe(false);
    expect(mockProvisionWorkspaceWithRepo).not.toHaveBeenCalled();
    expect(mockServiceFrom).not.toHaveBeenCalled();
  });

  test("flag ON + the configured exempt account proceeds (200); another account is still 503", async () => {
    const EXEMPT = "0b8f6f1e-3c1d-4a53-9a55-5b6f7c8d9e01";
    const OTHER = "1c9a7a2f-4d2e-4b64-8b66-6c7a8d9e0f12";
    process.env.FLAG_NEW_SESSIONS_PAUSED = "1";
    process.env.QUIET_WINDOW_EXEMPT_USER_ID = EXEMPT;
    __resetFeatureFlagsForTests();
    try {
      mockGetUser.mockResolvedValue({ data: { user: { id: EXEMPT, email: "s@example.com" } } });
      mockResolveActiveWorkspace.mockResolvedValue({ ok: true, workspaceId: EXEMPT });
      const ok = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
      expect(ok.status).toBe(200);

      vi.clearAllMocks();
      mockGetUser.mockResolvedValue({ data: { user: { id: OTHER, email: "o@example.com" } } });
      const refused = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
      expect(refused.status).toBe(503);
      expect(mockResolveActiveWorkspace).not.toHaveBeenCalled();
    } finally {
      delete process.env.QUIET_WINDOW_EXEMPT_USER_ID;
    }
  });

  test("unauthenticated still 401 (the gate does not precede auth)", async () => {
    process.env.FLAG_NEW_SESSIONS_PAUSED = "1";
    __resetFeatureFlagsForTests();
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const res = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));

    expect(res.status).toBe(401);
  });

  test("flag absent -> unchanged: 200 cloning, flip reached, clone started", async () => {
    const res = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
    expect(res.status).toBe(200);
    expect(cloningFlipCalled).toBe(true);
    expect(mockProvisionWorkspaceWithRepo).toHaveBeenCalledTimes(1);
  });

  test("flag explicitly 0 -> sessions allowed", async () => {
    process.env.FLAG_NEW_SESSIONS_PAUSED = "0";
    __resetFeatureFlagsForTests();
    const res = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
    expect(res.status).toBe(200);
  });

  test("a reap of THIS workspace in flight -> calm retryable 409 (the cloning response), lock and clone untouched; after it settles -> 200 (#8211)", async () => {
    let release!: () => void;
    const reaping = runExclusiveReap("user-1", () => new Promise<void>((r) => (release = r)));

    const res = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));

    expect(res.status).toBe(409);
    expect(res.headers.get("Retry-After")).toBe("5");
    expect(await res.json()).toEqual({ error: "Setup already in progress" });
    expect(cloningFlipCalled).toBe(false);
    expect(mockProvisionWorkspaceWithRepo).not.toHaveBeenCalled();

    release();
    await reaping;
    const after = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
    expect(after.status).toBe(200);
    expect(mockProvisionWorkspaceWithRepo).toHaveBeenCalledTimes(1);
  });

  test("a reap that registers AFTER the guard check (provision refuses in the background): calm, no Sentry, no error status, the disconnect state is restored", async () => {
    mockProvisionWorkspaceWithRepo.mockRejectedValue(new WorkspaceReapInProgressError());

    const res = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
    expect(res.status).toBe(200); // the clone started as far as the route can tell
    await new Promise((r) => setTimeout(r, 20)); // let the background .catch run

    expect(vi.mocked(reportSilentFallback)).not.toHaveBeenCalled();
    expect(vi.mocked(SentryMod.captureException)).not.toHaveBeenCalled();
    const writes = mockWriteRepoColsToWorkspace.mock.calls.map((c) => c[2] as Record<string, unknown>);
    expect(writes).toHaveLength(1);
    expect(writes[0]).toEqual({
      github_installation_id: null,
      repo_url: null,
      repo_status: "not_connected",
      repo_last_synced_at: null,
      repo_error: null,
    });
    expect(writes.some((w) => w.repo_status === "error")).toBe(false);
  });

  test("any OTHER background provisioning failure is still reported and written as `error`", async () => {
    mockProvisionWorkspaceWithRepo.mockRejectedValue(new Error("clone blew up"));

    await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
    await new Promise((r) => setTimeout(r, 20));

    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledTimes(1);
    const writes = mockWriteRepoColsToWorkspace.mock.calls.map((c) => c[2] as Record<string, unknown>);
    expect(writes[0].repo_status).toBe("error");
  });

  test("a reap of ANOTHER workspace does not block this one", async () => {
    let release!: () => void;
    const reaping = runExclusiveReap("someone-else", () => new Promise<void>((r) => (release = r)));
    const res = await POST(makeRequest({ repoUrl: "https://github.com/octo/repo" }));
    expect(res.status).toBe(200);
    release();
    await reaping;
  });
});
