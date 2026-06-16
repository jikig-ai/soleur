// Regression: the LEADER agent session (`startAgentSession` in agent-runner.ts)
// must operate in the caller's ACTIVE workspace dir — the same source the UI KB
// file tree renders from (`resolveActiveWorkspaceKbRoot`) and the Concierge uses
// post-#4910 — NOT the legacy `users.workspace_path` column.
//
// Agent-native parity bug (ADR-044 / #4543 class), leader half: pre-fix
// agent-runner set `workspacePath = user.workspace_path` (the caller's SOLO
// column — empty for an invited member, stale post-relocation), so the leader's
// cwd / KB root / doc resolver / vision / sync all pointed at the wrong dir.
// #4910 converged the Concierge half via `fetchUserWorkspacePath`; this converges
// the leader half via `resolveActiveWorkspacePath`.
//
// RED on origin/main: `workspacePath = user.workspace_path` (the solo dir) → the
// SDK query cwd is the solo dir → assertion fails.
// GREEN after the fix: `workspacePath = resolveActiveWorkspacePath(...)` (the
// active workspace dir) → cwd is the active dir.

import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";
process.env.WORKSPACES_ROOT = "/tmp/soleur-leader-parity-root";

const { mockFrom, mockRpc, mockQuery, mockReadFileSync } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
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
  return { ...actual, readFileSync: mockReadFileSync };
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
vi.mock("../server/session-sync", () => ({ syncPull: vi.fn(), syncPush: vi.fn() }));
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
// Vision is fire-and-forget against the resolved workspacePath; stub it so the
// real fs is never touched.
vi.mock("../server/vision-helpers", () => ({
  tryCreateVision: vi.fn().mockResolvedValue(undefined),
  buildVisionEnhancementPrompt: vi.fn().mockResolvedValue(""),
}));

import { startAgentSession } from "../server/agent-runner";
import { syncPull } from "../server/session-sync";
import { createApiKeysMock, createQueryMock } from "./helpers/agent-runner-mocks";

const MEMBER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
// The member's ACTIVE workspace is a SHARED one, distinct from their solo
// workspace (= MEMBER_ID per the N2 invariant). The document/work lives here.
const ACTIVE_WS_ID = "44444444-4444-4444-8444-444444444444";
const ROOT = "/tmp/soleur-leader-parity-root";
const SOLO_DIR = `${ROOT}/${MEMBER_ID}`;
const ACTIVE_DIR = `${ROOT}/${ACTIVE_WS_ID}`;

// Recursive chain whose terminal single/maybeSingle resolve `row`.
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
      // Pre-fix source: the legacy column points at the SOLO dir. Post-fix this
      // is no longer read for the path (only repo_status / email are).
      return singleRowChain({
        workspace_path: SOLO_DIR,
        repo_status: null,
        email: "member@example.com",
      });
    }
    if (table === "user_session_state") {
      // Post-fix source: the member's ACTIVE workspace is the shared one.
      return singleRowChain({ current_workspace_id: ACTIVE_WS_ID });
    }
    if (table === "workspace_members") {
      // Membership self-heal probe: the member IS a member of the active ws, so
      // resolution stays on the active workspace (no solo fallback).
      return singleRowChain({ user_id: MEMBER_ID });
    }
    if (table === "workspaces") {
      return singleRowChain({ repo_url: null });
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

describe("agent-runner leader — active-workspace cwd parity", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({ mcpServers: {} });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
  });

  test("SDK query cwd is the ACTIVE workspace dir, not the legacy solo column", async () => {
    setupSupabaseMock();
    createQueryMock(mockQuery);

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.cwd).toBe(ACTIVE_DIR);
    expect(options.cwd).not.toBe(SOLO_DIR);
  });

  test("session-start sync targets the ACTIVE workspace and runs despite a null legacy repo_status", async () => {
    // The member's legacy solo `users.repo_status` is null (see the `users` mock),
    // yet their ACTIVE (shared) workspace is connected. Pre-fix the leader gated
    // syncPull/syncPush on the solo `repo_status` → an invited member's leader
    // edits were never pulled/pushed to the shared remote. The gate is dropped;
    // syncPull self-guards (hasRemote + active installation) and now targets the
    // ACTIVE dir.
    setupSupabaseMock();
    createQueryMock(mockQuery);

    await startAgentSession(MEMBER_ID, "conv-1", "cpo");

    expect(vi.mocked(syncPull)).toHaveBeenCalledWith(MEMBER_ID, ACTIVE_DIR);
  });
});
