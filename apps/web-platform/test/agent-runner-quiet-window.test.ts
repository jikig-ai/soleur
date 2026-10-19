// #8211 T2 build 1 — quiet-window kill-switch at the legacy-leader session start.
//
// `startAgentSession` is the single entry for a legacy-leader agent session. With
// the kill-switch on it must refuse BEFORE anything else: no repo-status read, no
// supersede-abort of an in-flight prior session, no registration, no lease, no
// spawn. With the flag absent/off the session proceeds exactly as before.
//
// Harness lifted from agent-runner-repo-readiness-gate.test.ts (same hoisted-mock
// set). The flag is driven through the REAL feature-flag module's env-fallback
// path (no FLAGSMITH_ENVIRONMENT_KEY), so the whole read path is exercised.

import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";
process.env.WORKSPACES_ROOT = "/tmp/soleur-quiet-window-root";

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
vi.mock("../server/agent-env", async () => {
  // feat-open-web-egress (#9534): keep the REAL exports —
  // agent-runner-sandbox-config derives the web-egress deny census
  // from ALLOWED_SERVICE_ENV_VARS at module init; a bare stub drops
  // it and crashes every transitive importer.
  const actual =
    await vi.importActual<typeof import("../server/agent-env")>("../server/agent-env");
  return { ...actual, buildAgentEnv: vi.fn(() => ({})) };
});
// feat-open-web-egress (#9534): entitlement read + forwarder lifecycle —
// default off; the factory must resolve the module (mocked) on every
// dispatch even when the grant is false.
vi.mock("@/server/resolve-web-egress", () => ({
  resolveWebEgress: vi.fn(async () => false),
  resolveWebEgressStrict: vi.fn(async () => false),
}));
vi.mock("@/server/egress-forwarder", () => ({
  spawnEgressForwarder: vi.fn(),
  teardownEgressForwarder: vi.fn(),
  reapOrphanEgressForwarders: vi.fn(),
  hasEgressForwarder: vi.fn(() => false),
  egressForwarderWorkspaceId: vi.fn(() => undefined),
}));

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

import { startAgentSession, sendUserMessage } from "../server/agent-runner";
import { createApiKeysMock, createQueryMock } from "./helpers/agent-runner-mocks";

const MEMBER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ACTIVE_WS_ID = "44444444-4444-4444-8444-444444444444";
const ROOT = "/tmp/soleur-quiet-window-root";
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


import { QUIET_WINDOW_MESSAGE } from "../server/quiet-window";
import { __resetFeatureFlagsForTests } from "@/lib/feature-flags/server";
import {
  registerSession,
  unregisterSession,
  getSession,
  activeLegacySessionCount,
} from "../server/agent-session-registry";

function quietWindowEmits() {
  return mockSendToClient.mock.calls.filter(([, payload]) => {
    const p = payload as { type?: string; message?: string } | null;
    return p?.type === "error" && p.message === QUIET_WINDOW_MESSAGE;
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
  delete process.env.FLAG_NEW_SESSIONS_PAUSED;
  __resetFeatureFlagsForTests();
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
  mockGetCurrentRepoStatus.mockResolvedValue({ repoStatus: "ready", repoError: null });
});

describe("agent-runner leader — quiet-window kill-switch (#8211)", () => {
  test("flag ON: refuses with the maintenance message and does nothing else", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    process.env.FLAG_NEW_SESSIONS_PAUSED = "1";
    __resetFeatureFlagsForTests();

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    expect(quietWindowEmits()).toHaveLength(1);
    expect(mockSendToClient).toHaveBeenCalledWith(MEMBER_ID, {
      type: "error",
      message: QUIET_WINDOW_MESSAGE,
    });
    // Above the repo-readiness read, the clone, the DB and the SDK spawn.
    expect(mockGetCurrentRepoStatus).not.toHaveBeenCalled();
    expect(mockQuery).not.toHaveBeenCalled();
    expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
    expect(mockFrom).not.toHaveBeenCalled();
    // An expected maintenance window is not an incident.
    expect(mockCaptureException).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  test("flag ON: an in-flight prior session for the same conversation is NOT aborted and stays registered", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    const prior = new AbortController();
    registerSession(MEMBER_ID, "conv-live", {
      abort: prior,
      reviewGateResolvers: new Map(),
      sessionId: null,
    }, "cpo");
    process.env.FLAG_NEW_SESSIONS_PAUSED = "1";
    __resetFeatureFlagsForTests();

    await startAgentSession(MEMBER_ID, "conv-live", "cpo");

    expect(prior.signal.aborted).toBe(false);
    expect(getSession(MEMBER_ID, "conv-live", "cpo")?.abort).toBe(prior);
    expect(quietWindowEmits()).toHaveLength(1);
  });

  test("flag absent: no maintenance frame, the session proceeds past the gate", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    expect(quietWindowEmits()).toHaveLength(0);
    expect(mockGetCurrentRepoStatus).toHaveBeenCalled();
  });

  test("flag explicitly 0: sessions allowed", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    process.env.FLAG_NEW_SESSIONS_PAUSED = "0";
    __resetFeatureFlagsForTests();

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    expect(quietWindowEmits()).toHaveLength(0);
    expect(mockGetCurrentRepoStatus).toHaveBeenCalled();
  });

  test("activeLegacySessionCount is a bare integer that tracks register/unregister", () => {
    const before = activeLegacySessionCount();
    registerSession(MEMBER_ID, "conv-count", {
      abort: new AbortController(),
      reviewGateResolvers: new Map(),
      sessionId: null,
    });
    expect(activeLegacySessionCount()).toBe(before + 1);
    unregisterSession(MEMBER_ID, "conv-count");
    expect(activeLegacySessionCount()).toBe(before);
  });
});

// Last on purpose: the flag-absent case lets sendUserMessage run past its gate, and the async tail it starts
// must not leak into a neighbouring test's mock-call assertions.
describe("sendUserMessage — refuses before ITS OWN writes (review P2)", () => {
  test("flag ON: no conversation read, no message INSERT, no status flip, no spawn; the prior session survives", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    const prior = new AbortController();
    registerSession(MEMBER_ID, "conv-send", {
      abort: prior,
      reviewGateResolvers: new Map(),
      sessionId: null,
    }, "cpo");
    process.env.FLAG_NEW_SESSIONS_PAUSED = "1";
    __resetFeatureFlagsForTests();

    await sendUserMessage(MEMBER_ID, "conv-send", "hello");

    expect(quietWindowEmits()).toHaveLength(1);
    expect(mockFrom).not.toHaveBeenCalled();
    expect(mockRpc).not.toHaveBeenCalled();
    expect(mockQuery).not.toHaveBeenCalled();
    expect(prior.signal.aborted).toBe(false);
    expect(getSession(MEMBER_ID, "conv-send", "cpo")?.abort).toBe(prior);
    unregisterSession(MEMBER_ID, "conv-send", "cpo");
  });

  test("flag absent: the message path reaches its conversation read as before", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);
    await sendUserMessage(MEMBER_ID, "conv-send2", "hello").catch(() => undefined);
    expect(quietWindowEmits()).toHaveLength(0);
    expect(mockFrom).toHaveBeenCalled();
  });
});
