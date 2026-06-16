// #5340 / #5240 design item #2 — deterministic workspace re-provision on
// reconnect, LEADER half. The Concierge (cc) path already calls the session-
// start self-heal `ensureWorkspaceRepoCloned`; the leader path
// (`startAgentSession` in agent-runner.ts) NEVER did. After a sandbox/host
// reclaim the resolved active-workspace path can be a fresh filesystem with no
// repo, and the leader had no recovery — every turn dead-ended.
//
// This adds the missing recovery: when the resolved workspace has NO `.git`,
// lazily resolve the membership-scoped installation + repo and clone, BEFORE
// `patchWorkspacePermissions` / `syncPull` (both of which need a real repo).
//
// Placement (LOAD-BEARING, learning 2026-06-14-short-circuit-guard-must-sit-
// after-the-recovery-it-gates.md): the leader gains the RECOVERY only — NO
// bespoke honest "it's gone" message (the leader has no `worktree_enter_failed`
// guardrail; a failed recovery rides the existing `startAgentSession` catch).
// The honest message is a Concierge-path post-recovery-failure concept.
//
// RED on origin/main: the leader never imports/calls `ensureWorkspaceRepoCloned`
// → the recovery assertion fails.

import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";
process.env.WORKSPACES_ROOT = "/tmp/soleur-leader-reprovision-root";

const {
  mockFrom,
  mockRpc,
  mockQuery,
  mockReadFileSync,
  mockExistsSync,
  mockEnsureWorkspaceRepoCloned,
  mockEnsureWorkspaceDirExists,
  mockResolveInstallationId,
  mockGetCurrentRepoUrl,
  mockResolveEffectiveInstallationId,
  mockSyncPull,
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
  mockExistsSync: vi.fn(),
  mockEnsureWorkspaceRepoCloned: vi.fn(),
  mockEnsureWorkspaceDirExists: vi.fn(),
  mockResolveInstallationId: vi.fn(),
  mockGetCurrentRepoUrl: vi.fn(),
  mockResolveEffectiveInstallationId: vi.fn(),
  mockSyncPull: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn(
    (name: string, _desc: string, _schema: unknown, handler: Function) => ({
      name,
      handler,
    }),
  ),
  createSdkMcpServer: vi.fn((opts: { name: string; tools: unknown[] }) => ({
    type: "sdk",
    name: opts.name,
    instance: { tools: opts.tools },
  })),
}));

vi.mock("fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("fs")>();
  return { ...actual, readFileSync: mockReadFileSync, existsSync: mockExistsSync };
});

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockFrom })),
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockFrom, rpc: mockRpc })),
  mintFounderJwt: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {
    cause: string;
    constructor(cause: string, msg: string) {
      super(msg);
      this.name = "RuntimeAuthError";
      this.cause = cause;
    }
  },
}));

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: vi.fn() }));
vi.mock("../server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));
vi.mock("../server/byok", () => ({
  decryptKey: vi.fn(() => Buffer.from("sk-test-key", "utf8")),
  decryptKeyLegacy: vi.fn(() => Buffer.from("sk-test-key", "utf8")),
  zeroize: vi.fn(),
  encryptKey: vi.fn(),
}));
vi.mock("../server/error-sanitizer", () => ({
  sanitizeErrorForClient: vi.fn(() => "error"),
}));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: vi.fn(() => true) }));
vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [],
  extractToolPath: vi.fn(),
  isFileTool: vi.fn(() => false),
  isSafeTool: vi.fn(() => false),
}));
vi.mock("../server/agent-env", () => ({ buildAgentEnv: vi.fn(() => ({})) }));
vi.mock("../server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => vi.fn()),
}));
vi.mock("../server/review-gate", () => ({
  abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
  validateSelection: vi.fn(),
  extractReviewGateInput: vi.fn(),
  buildReviewGateResponse: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => {
  const leaders = [
    { id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" },
  ];
  return { DOMAIN_LEADERS: leaders, ROUTABLE_DOMAIN_LEADERS: leaders };
});
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({ syncPull: mockSyncPull, syncPush: vi.fn() }));
vi.mock("../server/github-api", () => ({
  githubApiGet: vi.fn().mockResolvedValue({ default_branch: "main" }),
  githubApiGetText: vi.fn().mockResolvedValue(""),
  githubApiPost: vi.fn().mockResolvedValue(null),
}));
vi.mock("../server/service-tools", () => ({
  plausibleCreateSite: vi.fn(),
  plausibleAddGoal: vi.fn(),
  plausibleGetStats: vi.fn(),
}));
vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  reportSilentFallbackWarning: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
vi.mock("../server/vision-helpers", () => ({
  tryCreateVision: vi.fn().mockResolvedValue(undefined),
  buildVisionEnhancementPrompt: vi.fn().mockResolvedValue(""),
}));
// The recovery under test + its lazily-resolved inputs.
vi.mock("../server/ensure-workspace-repo", () => ({
  ensureWorkspaceRepoCloned: mockEnsureWorkspaceRepoCloned,
  ensureWorkspaceDirExists: mockEnsureWorkspaceDirExists,
}));
vi.mock("../server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
}));
vi.mock("../server/current-repo-url", () => ({
  getCurrentRepoUrl: mockGetCurrentRepoUrl,
}));
vi.mock("../server/cc-effective-installation", () => ({
  resolveEffectiveInstallationId: mockResolveEffectiveInstallationId,
}));

import { startAgentSession } from "../server/agent-runner";
import { createApiKeysMock, createQueryMock } from "./helpers/agent-runner-mocks";

const MEMBER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ACTIVE_WS_ID = "44444444-4444-4444-8444-444444444444";
const ROOT = "/tmp/soleur-leader-reprovision-root";
const ACTIVE_DIR = `${ROOT}/${ACTIVE_WS_ID}`;
const GIT_PATH = `${ACTIVE_DIR}/.git`;
const REPO = "https://github.com/acme/widget";
const INSTALL = 4242;

function singleRowChain(row: unknown) {
  const chain: Record<string, unknown> = {};
  chain.select = () => chain;
  chain.eq = () => chain;
  chain.single = () => ({ data: row, error: null });
  chain.maybeSingle = () => ({ data: row, error: null });
  return chain;
}

function setupSupabaseMock() {
  mockRpc.mockImplementation(() => Promise.resolve({ data: null, error: null }));
  mockFrom.mockImplementation((table: string) => {
    if (table === "api_keys") return createApiKeysMock();
    if (table === "users") {
      return singleRowChain({ workspace_path: ACTIVE_DIR, repo_status: null, email: "member@example.com" });
    }
    if (table === "user_session_state") {
      return singleRowChain({ current_workspace_id: ACTIVE_WS_ID });
    }
    if (table === "workspace_members") {
      return singleRowChain({ user_id: MEMBER_ID });
    }
    if (table === "workspaces") {
      return singleRowChain({ repo_url: REPO });
    }
    if (table === "conversations") {
      const sel: Record<string, unknown> = {
        eq: vi.fn(),
        single: vi.fn(() => ({
          data: { domain_leader: "cpo", session_id: null, workspace_id: ACTIVE_WS_ID },
          error: null,
        })),
      };
      (sel.eq as ReturnType<typeof vi.fn>).mockReturnValue(sel);
      const upd: Record<string, unknown> = {
        error: null,
        eq: vi.fn(),
        select: vi.fn(() => Promise.resolve({ data: [{ id: "mock" }], error: null })),
      };
      (upd.eq as ReturnType<typeof vi.fn>).mockReturnValue(upd);
      return { update: vi.fn(() => upd), select: vi.fn(() => sel) };
    }
    if (table === "messages") {
      return {
        insert: () => ({ error: null }),
        select: () => {
          const chain: Record<string, unknown> = {
            eq: () => chain,
            order: () => Promise.resolve({ data: [], error: null }),
            then: (resolve: (v: unknown) => void) => resolve({ data: [], error: null }),
          };
          return chain;
        },
      };
    }
    return singleRowChain(null);
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockReadFileSync.mockImplementation((filePath: string) => {
    if (String(filePath).includes("plugin.json")) return JSON.stringify({ mcpServers: {} });
    throw new Error(`ENOENT: no such file ${filePath}`);
  });
  // Default: every other existsSync probe delegates to "present" so unrelated
  // call sites are unaffected; the per-test override decides the `.git` probe.
  mockExistsSync.mockReturnValue(true);
  mockEnsureWorkspaceRepoCloned.mockResolvedValue("ok");
  mockEnsureWorkspaceDirExists.mockResolvedValue(undefined);
  mockResolveInstallationId.mockResolvedValue(INSTALL);
  mockGetCurrentRepoUrl.mockResolvedValue(REPO);
  // Effective-install promotion pass-through by default (stored === owner).
  mockResolveEffectiveInstallationId.mockImplementation(
    async ({ installationId }: { installationId: number | null }) => installationId,
  );
});

describe("agent-runner leader — deterministic workspace re-provision on reconnect", () => {
  test("workspace has NO .git → clones the connected repo BEFORE syncPull", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    // The leader's active-workspace `.git` is absent (host reclaim symptom).
    mockExistsSync.mockImplementation((p: unknown) => String(p) !== GIT_PATH);

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    // Recovery ran with the lazily-resolved, membership-scoped inputs.
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledTimes(1);
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith({
      userId: MEMBER_ID,
      workspacePath: ACTIVE_DIR,
      installationId: INSTALL,
      repoUrl: REPO,
    });

    // Ordering: the recovery must precede syncPull (which needs a real repo).
    // Guard non-vacuity — both mocks MUST have fired or the comparison is
    // meaningless (a NaN/undefined `toBeLessThan` would not read as "syncPull
    // never ran"). See test-design review.
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalled();
    expect(mockSyncPull).toHaveBeenCalled();
    const reprovOrder = mockEnsureWorkspaceRepoCloned.mock.invocationCallOrder[0];
    const syncOrder = mockSyncPull.mock.invocationCallOrder[0];
    expect(reprovOrder).toBeLessThan(syncOrder);
  });

  test("workspace HAS .git → recovery no-ops (never touches an existing repo)", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    // `.git` present → the recovery gate must not fire. (Default beforeEach
    // already returns true for every probe; this test pins that the gate
    // specifically probed the workspace `.git` path and then no-op'd.)
    mockExistsSync.mockReturnValue(true);

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    expect(mockExistsSync).toHaveBeenCalledWith(GIT_PATH);
    expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
  });

  // AC8 (feat-one-shot-warm-reprovision-ensure-dir-presandbox) — the leader
  // shares the Concierge conditional-mkdir gap: a reclaimed NOT-CONNECTED
  // workspace skips `ensureWorkspaceRepoCloned`'s clone-mkdir, so the leader must
  // ensure the dir UNCONDITIONALLY before its bwrap sandbox is built. RED on
  // origin/main: the leader never calls `ensureWorkspaceDirExists`.
  test("AC8: ensures the workspace dir BEFORE the sandbox build (unconditional, not-connected reclaimed fixture)", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    // Not-connected + `.git`-absent reclaimed workspace: the clone is skipped,
    // so only the unconditional dir-ensure protects the sandbox CWD.
    mockExistsSync.mockImplementation((p: unknown) => String(p) !== GIT_PATH);
    mockResolveInstallationId.mockResolvedValue(null);
    mockGetCurrentRepoUrl.mockResolvedValue(null);

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    // `objectContaining` on the ctx so adding a future breadcrumb field (e.g.
    // conversationId) does not break a test that is really about ordering.
    expect(mockEnsureWorkspaceDirExists).toHaveBeenCalledTimes(1);
    expect(mockEnsureWorkspaceDirExists).toHaveBeenCalledWith(
      ACTIVE_DIR,
      expect.objectContaining({ feature: "agent-runner", userId: MEMBER_ID }),
    );
    // Ordering: the dir guarantee must precede the SDK query() / sandbox build.
    // `toHaveBeenCalledTimes(1)` above already guards non-vacuity for the helper;
    // pin the query() side too so the invocationCallOrder comparison is real.
    expect(mockQuery).toHaveBeenCalled();
    const ensureOrder = mockEnsureWorkspaceDirExists.mock.invocationCallOrder[0];
    const queryOrder = mockQuery.mock.invocationCallOrder[0];
    expect(ensureOrder).toBeLessThan(queryOrder);
  });

  test("NO bespoke leader honest-message path — a failed recovery does NOT emit a reclaim message (rides the existing catch)", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    mockExistsSync.mockImplementation((p: unknown) => String(p) !== GIT_PATH);
    mockEnsureWorkspaceRepoCloned.mockResolvedValue("failed");

    // The leader does not build a second detection path: a failed recovery is
    // not converted into a bespoke reclaim message here. (The honest message is
    // Concierge-only — asserted in cc-workflow-end-messages.test.ts.) The turn
    // proceeds; a downstream failure rides the existing startAgentSession catch.
    await expect(
      startAgentSession(MEMBER_ID, "conv-1", "cpo"),
    ).resolves.not.toThrow();
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledTimes(1);
  });
});
