// #10455 (a) / A4 — the legacy runner threads the RESOLVED flag into the builders. A regex over the source cannot see a
// dropped or misplaced argument; this drives startAgentSession with the resolver mocked and reads what the real
// buildAgentQueryOptions hands to buildAgentEnv (the ONLY builder observed here: buildAgentEnv is the mocked seam). The
// sandbox-config side of the same argument is pinned in agent-sandbox-seccomp-selector.test.ts, which drives
// buildAgentQueryOptions end to end. Every legacy session is no-egress, so the resolver is always consulted here (the
// cc-dispatcher counterpart pins the egress short-circuit).

import { describe, test, expect, vi, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const {
  mockFrom,
  mockRpc,
  mockQuery,
  mockReadFileSync,
  mockApplyPrefillGuard,
  mockSendToClient,
  mockResolveUnixDeny,
  mockBuildAgentEnv,
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
  mockApplyPrefillGuard: vi.fn(),
  mockSendToClient: vi.fn(),
  mockResolveUnixDeny: vi.fn(),
  mockBuildAgentEnv: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn(
    (_name: string, _desc: string, _schema: unknown, handler: Function) => ({
      name: _name,
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
vi.mock("../server/ws-handler", () => ({ sendToClient: mockSendToClient }));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
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
vi.mock("../server/agent-env", () => ({ buildAgentEnv: mockBuildAgentEnv, ALLOWED_SERVICE_ENV_VARS: new Set(["GITHUB_TOKEN", "STRIPE_SECRET_KEY"]) }));
vi.mock("../server/resolve-sandbox-unix-deny", () => ({ resolveSandboxUnixDeny: mockResolveUnixDeny }));
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
    {
      id: "cpo",
      name: "CPO",
      title: "Chief Product Officer",
      description: "Product",
    },
  ];
  return { DOMAIN_LEADERS: leaders, ROUTABLE_DOMAIN_LEADERS: leaders };
});
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({
  syncPull: vi.fn(),
  syncPush: vi.fn(),
}));
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
  mirrorWarnWithDebounce: vi.fn(),
}));
vi.mock("../server/agent-prefill-guard", () => ({
  applyPrefillGuard: mockApplyPrefillGuard,
}));

import { startAgentSession } from "../server/agent-runner";
import {
  createSupabaseMockImpl,
  createQueryMock,
} from "./helpers/agent-runner-mocks";

const BASE_USER_DATA = {
  workspace_path: "/tmp/test-workspace",
  repo_status: null,
  github_installation_id: null,
  repo_url: null,
};

describe("startAgentSession — AF_UNIX-deny flag wiring (#10455 a, A4)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) return JSON.stringify({ mcpServers: {} });
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
    mockApplyPrefillGuard.mockImplementation(async ({ resumeSessionId }) => ({ safeResumeSessionId: resumeSessionId }));
    mockBuildAgentEnv.mockReturnValue({});
    createSupabaseMockImpl(mockFrom, { userData: BASE_USER_DATA, mockRpc });
    createQueryMock(mockQuery);
  });

  test.each([true, false])("the resolved flag (%s) reaches buildAgentEnv's options exactly once per query", async (resolved) => {
    mockResolveUnixDeny.mockResolvedValue(resolved);
    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", "session-s");
    expect(mockResolveUnixDeny).toHaveBeenCalledTimes(1);
    expect(mockBuildAgentEnv).toHaveBeenCalledTimes(1);
    const envOpts = mockBuildAgentEnv.mock.calls[0][2];
    expect(envOpts.sandboxUnixDeny).toBe(resolved);
    // The legacy runner never mints a GitHub token or a web-egress handle: a no-egress session.
    expect(envOpts.ghToken).toBeUndefined();
    expect(envOpts.egressProxy).toBeUndefined();
  });

  test("the resolver is awaited BEFORE the SDK query is created", async () => {
    mockResolveUnixDeny.mockResolvedValue(true);
    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", "session-s");
    expect(mockResolveUnixDeny.mock.invocationCallOrder[0]).toBeLessThan(mockQuery.mock.invocationCallOrder[0]);
  });
});
