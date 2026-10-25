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
  mockMakeAuthModeResolver,
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
  mockApplyPrefillGuard: vi.fn(),
  mockSendToClient: vi.fn(),
  mockResolveUnixDeny: vi.fn(),
  mockBuildAgentEnv: vi.fn(),
  mockMakeAuthModeResolver: vi.fn(),
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
// The diagnostic's authMode resolver pulls the Supabase graph; stub it (the real resolver has its own test).
vi.mock("../server/agent-auth-mode", () => ({ makeAuthModeResolver: mockMakeAuthModeResolver }));

import { startAgentSession } from "../server/agent-runner";
import { reportSilentFallback } from "../server/observability";
import { __resetAgentAuthDedupeForTests } from "../server/agent-auth-failure";
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

// Agent auth-failure diagnostic (plan Phase 1 item 5): the legacy runner feeds its SDK stream to the shared probe. The probe,
// matcher, context derivation and the real buildAgentQueryOptions are all real here; the observability emit is the mocked
// seam, and the resolver module is stubbed so the Supabase graph stays out.
describe("startAgentSession — agent auth-failure diagnostic wiring", () => {
  const SEP = "\u00B7";
  const USER = "22222222-2222-4222-8222-222222222222";
  const authEmits = () =>
    vi.mocked(reportSilentFallback).mock.calls.filter((c) => (c[1] as { feature?: string })?.feature === "agent-auth");

  const streamOf = (messages: unknown[]) =>
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        for (const m of messages) yield m;
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as never);
  const authFailureStream = () => [
    { type: "system", subtype: "init", apiKeySource: "none", session_id: "sess-1" },
    {
      type: "assistant",
      message: { model: "<synthetic>", content: [{ type: "text", text: `Not logged in ${SEP} Please run /login` }] },
      error: "authentication_failed",
      is_api_error_message: true,
      session_id: "sess-1",
    },
    { type: "result", session_id: "sess-1" },
  ];

  beforeEach(() => {
    vi.clearAllMocks();
    __resetAgentAuthDedupeForTests();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) return JSON.stringify({ mcpServers: {} });
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
    mockApplyPrefillGuard.mockImplementation(async ({ resumeSessionId }) => ({ safeResumeSessionId: resumeSessionId }));
    mockBuildAgentEnv.mockReturnValue({ ANTHROPIC_API_KEY: "sk-test-key" });
    mockResolveUnixDeny.mockResolvedValue(false);
    mockMakeAuthModeResolver.mockImplementation(() => async () => "api-key");
    createSupabaseMockImpl(mockFrom, { userData: BASE_USER_DATA, mockRpc });
  });

  test("an auth-failure stream emits exactly ONE reportSilentFallback(null, ...) with the legacy runner and real context tags", async () => {
    streamOf(authFailureStream());
    await startAgentSession(USER, "conv-auth", "cpo", "session-s");
    await vi.waitFor(() => expect(authEmits()).toHaveLength(1));
    const [first, opts] = authEmits()[0] as [unknown, { feature: string; op: string; tags: Record<string, string> }];
    expect(first).toBeNull();
    expect(opts).toMatchObject({ feature: "agent-auth", op: "cli-auth-failure" });
    // Not `unknown`: a runner that skipped bindOptions (or the resolver) would still emit, but with unknown context.
    expect(opts.tags).toMatchObject({
      runner: "legacy",
      credential_scheme: "api_key",
      auth_env_present: "true",
      auth_mode: "api-key",
      cli_key_source: "none",
      seccomp_artifact: "base",
      has_egress: "false",
      sandbox: "on",
      outer_wrap: "false",
      match_kind: "not_logged_in",
    });
    // The resolver is built for THIS user and conversation.
    expect(mockMakeAuthModeResolver).toHaveBeenCalledWith(USER, "conv-auth");
    // Settle any trailing work, then confirm it stayed one.
    await new Promise((r) => setTimeout(r, 20));
    expect(authEmits()).toHaveLength(1);
  });

  test("the leased scheme reaches the probe: an oauth_token lease reports credential_scheme=oauth_token and reads the OAuth variable", async () => {
    vi.stubEnv("CC_OAUTH_ENABLED", "1");
    try {
      mockBuildAgentEnv.mockReturnValue({ CLAUDE_CODE_OAUTH_TOKEN: "sk-test-oauth" });
      streamOf(authFailureStream());
      await startAgentSession(USER, "conv-oauth", "cpo", "session-s");
      await vi.waitFor(() => expect(authEmits()).toHaveLength(1));
      const opts = authEmits()[0][1] as { tags: Record<string, string> };
      // A hard-coded api_key scheme would read ANTHROPIC_API_KEY (absent here) and report auth_env_present=false.
      expect(opts.tags).toMatchObject({ credential_scheme: "oauth_token", auth_env_present: "true" });
    } finally {
      vi.unstubAllEnvs();
    }
  });

  test("the debounce is per USER: two users with the same tuple each emit once", async () => {
    const OTHER = "33333333-3333-4333-8333-333333333333";
    streamOf(authFailureStream());
    await startAgentSession(USER, "conv-user-a", "cpo", "session-s");
    await vi.waitFor(() => expect(authEmits()).toHaveLength(1));
    streamOf(authFailureStream());
    await startAgentSession(OTHER, "conv-user-b", "cpo", "session-s");
    await vi.waitFor(() => expect(authEmits()).toHaveLength(2));
    await new Promise((r) => setTimeout(r, 20));
    expect(authEmits()).toHaveLength(2);
  });

  test("a clean stream emits nothing and never builds a lookup", async () => {
    streamOf([{ type: "system", subtype: "init", apiKeySource: "ANTHROPIC_API_KEY" }, { type: "result", session_id: "sess-1" }]);
    await startAgentSession(USER, "conv-clean", "cpo", "session-s");
    await new Promise((r) => setTimeout(r, 20));
    expect(authEmits()).toHaveLength(0);
  });

  test("source pins: the runner imports the module, creates the probe, wraps the builder, and observes at the loop top", async () => {
    const { readFileSync: realRead } = await vi.importActual<typeof import("fs")>("fs");
    const src = realRead(new URL("../server/agent-runner.ts", import.meta.url), "utf8");
    expect(src).toMatch(/from "\.\/agent-auth-failure"/);
    expect(src).toContain("createAgentAuthFailureProbe(");
    expect(src).toMatch(/options: authProbe\.bindOptions\(buildAgentQueryOptions\(/);
    expect(src).toMatch(/for await \(const message of q\) \{\s*if \(controller\.signal\.aborted\) break;\s*void authProbe\.observe\(message\);/);
    // The construction-failure fallback is visible, not silent.
    expect(src).toMatch(/\} catch \{[^}]*warnAgentAuthProbeUnavailable\(\);/);
  });
});
