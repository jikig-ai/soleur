// #5399 — legacy-leader repo-readiness gate (AC10 follow-up to #5395).
//
// #5395 gated the Concierge / `/soleur:go` dispatch path (cc-dispatcher.ts) on
// `repo_status`. The legacy leader path — `startAgentSession` in
// agent-runner.ts, reached from ws-handler `pendingLeader` AND `sendUserMessage`
// — was explicitly deferred (the "No outer repo_status gate" seam). This wiring
// test pins the same gate at the top of `startAgentSession`, REUSING the
// already-shipped primitives (`getCurrentRepoStatus`, `evaluateRepoReadiness`):
// a `cloning`/`error` workspace blocks BEFORE the BYOK lease / agent spawn /
// clone, emits the honest `{ type: "error" }` frame, SKIPS the Sentry mirror,
// and does NOT mark the conversation failed.
//
// RED on origin/main: there is no gate, so cases 1/2/5 fail (the SDK `query` is
// spawned on a cloning/error workspace, and a status-read throw escapes uncaught
// without `reportSilentFallback`).
//
// Harness lifted from agent-runner-reprovision.test.ts (same hoisted-mock set);
// the only additions are `getCurrentRepoStatus` on the `current-repo-url` mock,
// `hashUserId` on the `observability` mock, and the REAL `repo-readiness`
// evaluator (not mocked) so the emitted message/errorCode shapes are validated.

import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";
process.env.WORKSPACES_ROOT = "/tmp/soleur-repo-readiness-gate-root";

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
  mockGetCurrentRepoStatus,
  mockResolveEffectiveInstallationId,
  mockSyncPull,
  mockSendToClient,
  mockCaptureException,
  mockReportSilentFallback,
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
  mockGetCurrentRepoStatus: vi.fn(),
  mockResolveEffectiveInstallationId: vi.fn(),
  mockSyncPull: vi.fn(),
  mockSendToClient: vi.fn(),
  mockCaptureException: vi.fn(),
  mockReportSilentFallback: vi.fn(),
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

vi.mock("@sentry/nextjs", () => ({ captureException: mockCaptureException }));
vi.mock("../server/ws-handler", () => ({ sendToClient: mockSendToClient }));
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
  reportSilentFallback: mockReportSilentFallback,
  reportSilentFallbackWarning: vi.fn(),
  warnSilentFallback: vi.fn(),
  hashUserId: vi.fn(() => "hashed-user-id"),
}));
vi.mock("../server/vision-helpers", () => ({
  tryCreateVision: vi.fn().mockResolvedValue(undefined),
  buildVisionEnhancementPrompt: vi.fn().mockResolvedValue(""),
}));
vi.mock("../server/ensure-workspace-repo", () => ({
  ensureWorkspaceRepoCloned: mockEnsureWorkspaceRepoCloned,
  ensureWorkspaceDirExists: mockEnsureWorkspaceDirExists,
}));
vi.mock("../server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
}));
// The gate under test reads `getCurrentRepoStatus`; the reprovision block still
// reads `getCurrentRepoUrl`. Mock BOTH so neither hits supabase.
vi.mock("../server/current-repo-url", () => ({
  getCurrentRepoUrl: mockGetCurrentRepoUrl,
  getCurrentRepoStatus: mockGetCurrentRepoStatus,
}));
vi.mock("../server/cc-effective-installation", () => ({
  resolveEffectiveInstallationId: mockResolveEffectiveInstallationId,
}));

import { startAgentSession } from "../server/agent-runner";
// REAL evaluator + copy — validates the emitted message/errorCode shapes.
import { REPO_CLONING_MSG } from "../server/repo-readiness";
import { createApiKeysMock, createQueryMock } from "./helpers/agent-runner-mocks";

const MEMBER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ACTIVE_WS_ID = "44444444-4444-4444-8444-444444444444";
const ROOT = "/tmp/soleur-repo-readiness-gate-root";
const ACTIVE_DIR = `${ROOT}/${ACTIVE_WS_ID}`;
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

/** Did `sendToClient` receive the gate's OWN error frame (the block emit)?
 *  Scoped to the gate's specific copy so a downstream/dispatch `type:"error"`
 *  frame (which a no-op case may still emit further down the path) is NOT
 *  miscounted as a gate block. */
function gateErrorEmits() {
  return mockSendToClient.mock.calls.filter(([, payload]) => {
    if (!payload || typeof payload !== "object") return false;
    const p = payload as { type?: string; message?: string };
    if (p.type !== "error" || typeof p.message !== "string") return false;
    return p.message === REPO_CLONING_MSG || p.message.startsWith("Repository setup failed:");
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockReadFileSync.mockImplementation((filePath: string) => {
    if (String(filePath).includes("plugin.json")) return JSON.stringify({ mcpServers: {} });
    throw new Error(`ENOENT: no such file ${filePath}`);
  });
  mockExistsSync.mockReturnValue(true);
  mockEnsureWorkspaceRepoCloned.mockResolvedValue("ok");
  mockEnsureWorkspaceDirExists.mockResolvedValue(undefined);
  mockResolveInstallationId.mockResolvedValue(INSTALL);
  mockGetCurrentRepoUrl.mockResolvedValue(REPO);
  mockResolveEffectiveInstallationId.mockImplementation(
    async ({ installationId }: { installationId: number | null }) => installationId,
  );
  // Default: ready (the gate no-ops). Each test overrides as needed.
  mockGetCurrentRepoStatus.mockResolvedValue({ repoStatus: "ready", repoError: null });
});

describe("agent-runner leader — repo-readiness gate (#5399)", () => {
  test("AC1: cloning workspace blocks — emits REPO_CLONING_MSG, spawns no agent, no Sentry", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    mockGetCurrentRepoStatus.mockResolvedValue({ repoStatus: "cloning", repoError: null });

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    expect(mockSendToClient).toHaveBeenCalledWith(MEMBER_ID, {
      type: "error",
      message: REPO_CLONING_MSG,
    });
    // No agent spawned, no clone, no Sentry mirror.
    expect(mockQuery).not.toHaveBeenCalled();
    expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
    expect(mockCaptureException).not.toHaveBeenCalled();
    // AC4 + AC10: the gate is the FIRST statement and early-returns, so a block
    // performs ZERO DB side effects — no conversation marked failed, no
    // session-state mutation (getSession/registerSession run below the gate and
    // touch no table here). `getCurrentRepoStatus` is fully mocked, so any
    // mockFrom call would mean execution fell through past the gate.
    expect(mockFrom).not.toHaveBeenCalled();
  });

  test("AC2: error workspace blocks — emits repo_setup_failed errorCode, spawns no agent, no Sentry", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    mockGetCurrentRepoStatus.mockResolvedValue({
      repoStatus: "error",
      repoError: "fatal: could not read Username for 'https://github.com'",
    });

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    const emits = gateErrorEmits();
    expect(emits).toHaveLength(1);
    const [, payload] = emits[0] as [string, { message: string; errorCode?: string }];
    expect(payload.errorCode).toBe("repo_setup_failed");
    expect(payload.message).toMatch(/^Repository setup failed:/);
    expect(mockQuery).not.toHaveBeenCalled();
    expect(mockCaptureException).not.toHaveBeenCalled();
    // AC4 + AC10: zero DB side effects on a block (see AC1 for rationale).
    expect(mockFrom).not.toHaveBeenCalled();
  });

  test("AC5a: ready workspace is a no-op — gate emits nothing, dispatch proceeds", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    mockGetCurrentRepoStatus.mockResolvedValue({ repoStatus: "ready", repoError: null });

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    expect(gateErrorEmits()).toHaveLength(0);
    expect(mockQuery).toHaveBeenCalled();
  });

  test("AC5b: not_connected workspace is a no-op (fail-open default) — dispatch proceeds", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    mockGetCurrentRepoStatus.mockResolvedValue({ repoStatus: "not_connected", repoError: null });

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    expect(gateErrorEmits()).toHaveLength(0);
    expect(mockQuery).toHaveBeenCalled();
  });

  test("AC11: status-read throw fails OPEN — reportSilentFallback fires, gate emits nothing, dispatch proceeds", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    mockGetCurrentRepoStatus.mockRejectedValue(new Error("unexpected status-read blip"));

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "repo-readiness-gate.read" }),
    );
    expect(gateErrorEmits()).toHaveLength(0);
    expect(mockQuery).toHaveBeenCalled();
  });
});
