// RED/GREEN tests for the cc-soleur-go `realSdkQueryFactory` closure
// (replaces the prior `realSdkQueryFactoryStub`). Covers T1–T7
// (factory option shape) + T15 (leaderId attribution) + T16 (sandbox
// substring → agent-sandbox tag) + T18 (env shape) + T19 (KeyInvalidError
// sanitization).
//
// Mocks the SDK's `query` per the same pattern used in
// `agent-runner-kb-share-preview.test.ts` so the factory can be invoked
// with a fully-typed `QueryFactoryArgs` and the captured `options`
// asserted against the canonical shape.
//
// See plan §"Test Scenarios" — T1–T19. The Bash review-gate E2E (T12–T14)
// lives in a sibling file (`cc-dispatcher-bash-gate.test.ts`).

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const {
  mockLogInfo,
  mockQuery,
  mockGetUserApiKey,
  mockGetUserServiceTokens,
  mockPatchWorkspacePermissions,
  mockReportSilentFallback,
  mockInfoSilentFallback,
  mockSendToClient,
  mockBuildAgentEnv,
  mockBuildAgentSandboxConfig,
  mockSupabaseFrom,
  mockResolveInstallationId,
  mockGenerateInstallationToken,
  mockResolveBashAutonomous,
  mockResolveWebEgress,
  mockResolveWebEgressStrict,
  mockSpawnEgressForwarder,
  mockTeardownEgressForwarder,
  mockResolveAutonomousAck,
  mockResolveIsWorkspaceOwner,
  mockWriteAskpassScriptTo,
  mockCleanupAskpassScript,
  mockResolveActiveWorkspacePath,
  mockResolveActiveWorkspace,
  mockGetCurrentRepoUrl,
  mockMirrorWarnWithDebounce,
  mockReadCurrentRepoUrlResult,
  mockGetCurrentRepoStatus,
  mockGetInstallationAccount,
  mockFindRepoOwnerInstallationForUser,
  mockEnsureWorkspaceRepoCloned,
  mockResolveC4FlagEnabled,
  mockWriteC4Diagram,
  mockGetSessionMessages,
  mockResolveSandboxUnixDeny,
  mockPushBranch,
  mockApprovalFlag,
  mockGithubApiGet,
  mockHeadSha,
  registrarOverride,
  readRegistrarOverride,
  conversationWriteOverride,
} = vi.hoisted(() => ({
  // #12469: the same for the READ registrar (null = the real one).
  readRegistrarOverride: { fn: null as null | ((a: Record<string, unknown>) => Promise<unknown>) },
  conversationWriteOverride: { fn: null as null | (() => Promise<unknown>) },
  // #11636: a per-test replacement for the registrar (null = the REAL one). Lets a test hand the dispatcher a result the real
  // registrar can never produce (a foreign name), to prove the dispatcher's own runtime assertion rejects it.
  registrarOverride: { fn: null as null | ((a: Record<string, unknown>) => Promise<unknown>) },
  // #11636: the github_push_branch registration. `pushBranch` is the handler's only side effect; the approval flag is a
  // per-test switch (default OFF = the dark path); the default-branch lookup and the workspace HEAD are canned.
  mockPushBranch: vi.fn(async (_o: Record<string, unknown>) => ({ branch: "feat-x", pushed: true })),
  mockApprovalFlag: vi.fn(async (): Promise<unknown> => false),
  mockGithubApiGet: vi.fn(async (..._args: unknown[]): Promise<unknown> => ({ default_branch: "trunk" })),
  mockHeadSha: vi.fn(async () => "d".repeat(40)),
  mockResolveSandboxUnixDeny: vi.fn(async () => false),
  mockResolveC4FlagEnabled: vi.fn(async () => false),
  mockWriteC4Diagram: vi.fn(),
  mockLogInfo: vi.fn(),
  mockQuery: vi.fn(),
  mockGetUserApiKey: vi.fn(),
  mockGetUserServiceTokens: vi.fn(),
  mockPatchWorkspacePermissions: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockInfoSilentFallback: vi.fn(),
  mockSendToClient: vi.fn(),
  mockBuildAgentEnv: vi.fn(),
  mockBuildAgentSandboxConfig: vi.fn(),
  mockSupabaseFrom: vi.fn(),
  mockResolveInstallationId: vi.fn(),
  mockGenerateInstallationToken: vi.fn(),
  mockResolveBashAutonomous: vi.fn(),
  mockResolveWebEgress: vi.fn(),
  mockResolveWebEgressStrict: vi.fn(),
  mockSpawnEgressForwarder: vi.fn(),
  mockTeardownEgressForwarder: vi.fn(),
  mockResolveAutonomousAck: vi.fn(),
  mockResolveIsWorkspaceOwner: vi.fn(),
  mockWriteAskpassScriptTo: vi.fn(),
  mockCleanupAskpassScript: vi.fn(),
  mockResolveActiveWorkspacePath: vi.fn(),
  mockResolveActiveWorkspace: vi.fn(),
  mockGetCurrentRepoUrl: vi.fn(),
  mockMirrorWarnWithDebounce: vi.fn(),
  mockReadCurrentRepoUrlResult: vi.fn(),
  mockGetCurrentRepoStatus: vi.fn(),
  mockGetInstallationAccount: vi.fn(),
  mockFindRepoOwnerInstallationForUser: vi.fn(),
  // Hoisted to a named spy (was an inline anonymous vi.fn) so the
  // installation-id the clone receives is inspectable — the load-bearing
  // assertion for the clone-consumes-self-healed-install fix.
  mockEnsureWorkspaceRepoCloned: vi.fn(async () => undefined),
  // #9538 — named so a test can override the default `[]`: since the cc
  // caller now passes `dropResumeOnEmptyHistory: true`, `[]` drops the
  // resume id, so a test that wants resume to survive supplies a live
  // user-terminated history instead.
  mockGetSessionMessages: vi.fn().mockResolvedValue([]),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  // Drift-guard for #3250: `realSdkQueryFactory` calls `getSessionMessages`
  // when `args.resumeSessionId` is set. `[]` exercises the guard's
  // empty-history branch — which, since #9538 added the cc caller's
  // `dropResumeOnEmptyHistory: true`, now DROPS the resume id; tests that
  // need resume to survive override with a user-terminated history.
  getSessionMessages: mockGetSessionMessages,
  // Return inspectable shapes so the soleur_platform always-build assertion
  // (#5370 T2) can read tool names off the registered server. `tool(name,…)`
  // → `{ name, handler }` — the handler passthrough lets the #8739 emit-seam
  // test invoke edit_c4_diagram's handler directly;
  // `createSdkMcpServer(cfg)` → cfg (passthrough).
  tool: vi.fn((name: string, _d: unknown, _s: unknown, handler: unknown) => ({
    name,
    handler,
  })),
  createSdkMcpServer: vi.fn((cfg: unknown) => cfg),
}));

vi.mock("@/server/agent-runner", () => ({
  getUserApiKey: mockGetUserApiKey,
  getUserServiceTokens: mockGetUserServiceTokens,
  patchWorkspacePermissions: mockPatchWorkspacePermissions,
}));

// #10455 (a): these suites replace both builders with mocks, so the spawn-time seccomp agreement
// assertion (which reads the posture the REAL buildAgentSandboxConfig records) is a no-op here. The
// real pairing is pinned by test/agent-sandbox-seccomp-selector.test.ts.
vi.mock("@/server/agent-sandbox-seccomp", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/agent-sandbox-seccomp")>()),
  checkSeccompAgreement: vi.fn(),
}));
vi.mock("@/server/agent-runner-sandbox-config", () => ({
  buildAgentSandboxConfig: mockBuildAgentSandboxConfig,
}));

vi.mock("@/server/agent-env", async (importOriginal) => ({
  buildAgentEnv: mockBuildAgentEnv,
  // The egress predicate is the real one (the dispatcher skips the flag read for an egress session with it).
  sessionHasEgress: (await importOriginal<typeof import("@/server/agent-env")>()).sessionHasEgress,
  // feat-open-web-egress (#9534): the sandbox-config deny census derives
  // from this set at module load — keep it non-empty.
  ALLOWED_SERVICE_ENV_VARS: new Set(["GITHUB_TOKEN", "STRIPE_SECRET_KEY"]),
}));

vi.mock("@/server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => async () => ({})),
}));

// Issue A — Concierge gh-auth. Default to "no connected repo" (null) so the
// pre-existing factory-shape tests dispatch with no GH_TOKEN; the dedicated
// describe block below drives the connected + mint-failure paths.
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
}));

// feat-one-shot-concierge-gh-403 self-heal: the heal is driven entirely by the
// GitHub App JWT path (getInstallationAccount + findRepoOwnerInstallationForUser)
// — NO Supabase service-role. Pre-existing factory-shape tests run with
// getCurrentRepoUrl=null so the self-heal branch never fires; the dedicated
// describe block drives it.
vi.mock("@/server/github-app", () => ({
  generateInstallationToken: mockGenerateInstallationToken,
  getInstallationAccount: mockGetInstallationAccount,
  findRepoOwnerInstallationForUser: mockFindRepoOwnerInstallationForUser,
}));

// Plan item 1 — cc-dispatcher now imports the in-sandbox askpass writer from
// git-auth. MUST be mocked here AND in cc-dispatcher-prefill-guard.test.ts or
// the cold-start suite throws on import (Phase 0.4 sweep).
// #5394 — keep the pure sanitizers real (repo-readiness.ts consumes
// parseErrorPayload + sanitizeGitStderr for the error-branch gate); override
// only the askpass writers (the in-sandbox FS side effects).
vi.mock("@/server/git-auth", async () => {
  const actual =
    await vi.importActual<typeof import("@/server/git-auth")>(
      "@/server/git-auth",
    );
  return {
    ...actual,
    writeAskpassScriptTo: mockWriteAskpassScriptTo,
    cleanupAskpassScript: mockCleanupAskpassScript,
  };
});

// Issue B part 2 — autonomous toggle. Default off (false) so factory-shape
// tests dispatch with the review-gate intact.
vi.mock("@/server/resolve-bash-autonomous", () => ({
  resolveBashAutonomous: mockResolveBashAutonomous,
}));

// #10455 (a) / A4 — the AF_UNIX-deny flag resolver. Default OFF; the wiring rows below flip it.
vi.mock("@/server/resolve-sandbox-unix-deny", () => ({
  resolveSandboxUnixDeny: mockResolveSandboxUnixDeny,
}));

// feat-open-web-egress (#9534) — default off (false): entitlement
// wiring is tested in web-egress.test.ts / dedicated factory cases;
// factory-shape tests dispatch with no forwarder spawn.
vi.mock("@/server/resolve-web-egress", () => ({
  resolveWebEgress: mockResolveWebEgress,
  resolveWebEgressStrict: mockResolveWebEgressStrict,
}));

// feat-open-web-egress (#9534) — never spawn a real forwarder in
// unit tests; the module lifecycle is covered by web-egress.test.ts.
vi.mock("@/server/egress-forwarder", () => ({
  spawnEgressForwarder: mockSpawnEgressForwarder,
  teardownEgressForwarder: mockTeardownEgressForwarder,
  reapOrphanEgressForwarders: vi.fn(),
  hasEgressForwarder: vi.fn(() => false),
  egressForwarderWorkspaceId: vi.fn(() => undefined),
}));

// feat-bash-autonomous-default-on — first-run consent soft-gate inputs. Default
// ack=null + owner=false so factory-shape tests dispatch with the review-gate
// intact (un-acked non-owner ⇒ not the soft-gate path).
vi.mock("@/server/resolve-autonomous-ack", () => ({
  resolveAutonomousAck: mockResolveAutonomousAck,
}));
vi.mock("@/server/resolve-workspace-owner", () => ({
  resolveIsWorkspaceOwner: mockResolveIsWorkspaceOwner,
}));

// Session-start ensure-repo self-heal (cold-path deps). Default no-op so the
// factory-shape tests are unaffected.
// ADR-044: fetchUserWorkspacePath now resolves the ACTIVE workspace via
// resolveActiveWorkspacePath. Override only that export (importActual keeps the
// rest of workspace-resolver real for any other consumer cc-dispatcher pulls).
vi.mock("@/server/workspace-resolver", async () => {
  const actual = await vi.importActual<typeof import("@/server/workspace-resolver")>(
    "@/server/workspace-resolver",
  );
  return {
    ...actual,
    resolveActiveWorkspacePath: mockResolveActiveWorkspacePath,
    // ADR-044 PR-1: the factory resolves this directly before the Promise.all.
    resolveActiveWorkspace: mockResolveActiveWorkspace,
  };
});

vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: mockGetCurrentRepoUrl,
  readCurrentRepoUrlResult: mockReadCurrentRepoUrlResult,
  getCurrentRepoStatus: mockGetCurrentRepoStatus,
}));
vi.mock("@/server/ensure-workspace-repo", () => ({
  ensureWorkspaceRepoCloned: mockEnsureWorkspaceRepoCloned,
  // Unconditional pre-sandbox dir guarantee — no-op here (these tests assert
  // option shape, not real dir existence). The dedicated invariant coverage
  // lives in cc-dispatcher-warm-presandbox-mkdir.test.ts (real mkdir).
  ensureWorkspaceDirExists: vi.fn(async () => undefined),
}));
// #5733 D2 — these tests assert SDK-binding / mint / egress shape on a fixture
// workspace path (`/tmp/cc-test-workspace`) that has no on-disk `.git`. D2 now
// honest-blocks an absent `.git` at the cold dispatch gate, so force the
// git-shape readiness to a ready dir-valid here (these tests do NOT exercise the
// readiness gate — that is owned by cc-dispatcher-repo-gate.test.ts +
// agent-ready-git-worktree.test.ts).
vi.mock("@/server/git-worktree-validity", async (orig) => {
  const actual = (await orig()) as Record<string, unknown>;
  return {
    ...actual,
    probeGitWorktreeShape: () => ({ kind: "dir-valid" }),
    isReadyGitWorkTree: () => true,
    isValidGitWorkTree: () => true,
    evaluateAgentReadiness: async () => "ready",
  };
});

vi.mock("@/server/permission-callback", () => ({
  // The factory composes a canUseTool from this — we capture the ctx
  // passed in via the spy returned here.
  createCanUseTool: vi.fn(() => async () => ({ behavior: "allow" })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
  infoSilentFallback: mockInfoSilentFallback,
  // #5733 — reportAgentReadinessSelfStop pre-hashes the workspace id via hashUserId.
  hashUserId: (s: string) => `hash-${s}`,
  // #3369: mirrorWithDebounce extracted to observability.
  // These dispatcher tests do not exercise the debounce TTL, so
  // the stub forwards every call straight through to the spy.
  mirrorWithDebounce: mockReportSilentFallback,
  // #12469: the read registrar's warning for an entitled session without a repo.
  mirrorWarnWithDebounce: mockMirrorWarnWithDebounce,
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockSupabaseFrom })),
}));

// PR-C §2.4 / §2.10 / §2.11 (#3244): tenant migration of conversation-
// writer + agent-runner + cc-dispatcher (BYOK lease wrap). Mock so the
// test does not pull `mintFounderJwt` or the lease's `fetchAndDecrypt`
// chain.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockSupabaseFrom })),
  mintFounderJwt: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/server/byok-lease", async () => {
  const actual = await vi.importActual<typeof import("@/server/byok-lease")>(
    "@/server/byok-lease",
  );
  return {
    ...actual,
    // Bridge legacy `mockGetUserApiKey` setups (which used to mock the
    // direct `getUserApiKey()` call in cc-dispatcher pre-PR-C) to the
    // new `lease.getApiKey()` surface. Tests that
    // `mockResolvedValue("sk-test")` / `mockRejectedValueOnce(KeyInvalidError)`
    // continue to drive the same code path.
    runWithByokLease: vi.fn(
      async <T>(
        args: { workspaceContextUserId: string; keyOwnerUserId: string },
        body: (lease: {
          workspaceContextUserId: string;
          keyOwnerUserId: string;
          getRestApiKey: () => string | Promise<string>;
          getAgentCredential: () => Promise<{ value: string; scheme: "api_key" | "oauth_token" }>;
        }) => Promise<T>,
      ) =>
        body({
          workspaceContextUserId: args.workspaceContextUserId,
          keyOwnerUserId: args.keyOwnerUserId,
          // cc-dispatcher is an Agent-SDK consumer → getAgentCredential.
          // Bridge the legacy mockGetUserApiKey value/rejection into the
          // new { value, scheme } shape (scheme=api_key for these tests).
          getRestApiKey: () => mockGetUserApiKey(),
          getAgentCredential: async () => ({
            value: await mockGetUserApiKey(),
            scheme: authDiag.scheme,
          }),
        }),
    ),
  };
});

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

vi.mock("@/server/ws-handler", () => ({
  sendToClient: mockSendToClient,
}));

// #8739: the flag resolver is real elsewhere — here it is a per-test switch so
// the c4 gate (repo + installation + flag) is reachable without a Flagsmith
// fixture. Defaults false: every pre-existing test's no-repo args never reach
// it, and resolveC4Eligible stays false so the advertising path is unchanged.
vi.mock("@/server/resolve-c4-eligible", () => ({
  resolveC4FlagEnabled: mockResolveC4FlagEnabled,
  resolveC4Eligible: vi.fn(async () => false),
}));

// #8739: the tool's persistence layer is never exercised from this file — the
// emit-seam test needs a controllable ok/false result, not a GitHub commit.
vi.mock("@/server/c4-writer", () => ({
  writeC4Diagram: mockWriteC4Diagram,
}));

// `info` routes to the shared hoisted spy so the egress-posture log payload
// is assertable (AC6-class: boolean only, never the token). Filter by
// message string in assertions — every module's child logger shares it.
vi.mock("@/server/logger", () => ({
  default: { info: mockLogInfo, error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: mockLogInfo,
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

vi.mock("@/server/notifications", () => ({ notifyOfflineUser: vi.fn() }));

// Agent auth-failure diagnostic: the authMode resolver module pulls the Supabase graph, so it is stubbed here (the real
// resolver has its own test). The probe factory is wrapped in a spy that defaults to the REAL implementation so one case
// can make construction throw.
const authDiag = vi.hoisted(() => ({
  makeResolver: vi.fn(),
  createProbe: vi.fn(),
  // The scheme the bridged lease reports; one case flips it to oauth_token to pin the wiring of `credentialScheme`.
  scheme: "api_key" as "api_key" | "oauth_token",
}));
vi.mock("@/server/agent-auth-mode", () => ({ makeAuthModeResolver: authDiag.makeResolver }));
vi.mock("@/server/agent-auth-failure", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/agent-auth-failure")>();
  authDiag.createProbe.mockImplementation(actual.createAgentAuthFailureProbe as never);
  return { ...actual, createAgentAuthFailureProbe: authDiag.createProbe };
});

// #11636: the push tool's side effect. Nothing here reaches a real remote.
vi.mock("@/server/push-branch", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/push-branch")>()),
  pushBranch: mockPushBranch,
}));

// #11636: the warm-turn dispatch test passes the dispatcher's conversation-ownership write through this seam; everything else (and
// every other test in this file) uses the REAL writer.
vi.mock("@/server/conversation-writer", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/conversation-writer")>();
  return {
    ...actual,
    updateConversationFor: (...a: Parameters<typeof actual.updateConversationFor>) =>
      conversationWriteOverride.fn ? conversationWriteOverride.fn() : actual.updateConversationFor(...a),
  };
});

// #11636: the registrar, delegating to the REAL one unless a test installs `registrarOverride.fn`.
vi.mock("@/server/cc-github-push", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/cc-github-push")>();
  return {
    ...actual,
    resolveCcGithubPushRegistration: (a: Parameters<typeof actual.resolveCcGithubPushRegistration>[0]) =>
      registrarOverride.fn ? registrarOverride.fn(a as unknown as Record<string, unknown>) : actual.resolveCcGithubPushRegistration(a),
  };
});

// #12469: the read registrar, delegating to the REAL one unless a test installs `readRegistrarOverride.fn`.
vi.mock("@/server/cc-github-read", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/cc-github-read")>();
  return {
    ...actual,
    resolveCcGithubReadRegistration: (a: Parameters<typeof actual.resolveCcGithubReadRegistration>[0]) =>
      readRegistrarOverride.fn ? readRegistrarOverride.fn(a as unknown as Record<string, unknown>) : actual.resolveCcGithubReadRegistration(a),
  };
});

// #11636: the approval-queue flag read, shared by the registrar and the gate's default seam. A per-test switch.
vi.mock("@/server/approval/flag", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/approval/flag")>()),
  isApprovalQueueEnabled: mockApprovalFlag,
}));

// #11636: the default-branch lookup. The file-wide github-app mock exposes only three exports, so the REAL github-api is kept
// (importOriginal) and only githubApiGet is replaced; GitHubApiError and the rest must survive.
vi.mock("@/server/github-api", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/github-api")>()),
  githubApiGet: mockGithubApiGet,
}));

// #11636: forwards to the REAL gate-deps factory but injects a `headSha` seam (the real `gitHeadSha` runs no git any more; it
// reads `<workspace>/.git/HEAD` as data and would refuse the fixture's nonexistent workspace with `git_dir_not_plain`). The wrapper is a spy, so the args the dispatcher passes (workspaceId, repoSlug,
// workspacePath, grants) are inspectable.
vi.mock("@/server/approval/gate", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/approval/gate")>();
  return {
    ...actual,
    createApprovalGateDeps: vi.fn((a: Parameters<typeof actual.createApprovalGateDeps>[0]) =>
      actual.createApprovalGateDeps({ ...a, headSha: mockHeadSha }),
    ),
  };
});

import {
  __resetDispatcherForTests,
  CC_REGISTERED_PLATFORM_TOOL_NAMES,
  cleanupCcBashGatesForConversation,
  crmLeadPermissionToolNames,
  dispatchSoleurGo,
  __setCcRunnerForTests,
  getCcRegisteredApprovalTools,
  getCcRegisteredReadTools,
  realSdkQueryFactory,
} from "@/server/cc-dispatcher";
import { ccPushPromptAddendum } from "@/server/cc-github-push";
import { createApprovalGateDeps } from "@/server/approval/gate";
import { recordSandboxPosture } from "@/server/agent-sandbox-seccomp";
import { __resetAgentAuthDedupeForTests } from "@/server/agent-auth-failure";
import { createCanUseTool } from "@/server/permission-callback";
import { ExecutionGrants, putGrant } from "@/server/approval/grants";
import { APPROVAL_REQUIRED_TOOLS } from "@/server/approval/tools";

// Helper: build a fake Query that the SDK mock returns.
function makeFakeQuery() {
  return {
    async *[Symbol.asyncIterator]() {
      // No messages — factory tests only assert the options shape.
    },
    close: vi.fn().mockResolvedValue(undefined),
    interrupt: vi.fn().mockResolvedValue(undefined),
    setPermissionMode: vi.fn().mockResolvedValue(undefined),
    setModel: vi.fn().mockResolvedValue(undefined),
    supportedCommands: vi.fn().mockResolvedValue([]),
    supportedModels: vi.fn().mockResolvedValue([]),
    mcpServerStatus: vi.fn().mockResolvedValue([]),
    next: vi.fn(),
    return: vi.fn(),
    throw: vi.fn(),
    // biome-ignore lint/suspicious/noExplicitAny: SDK Query stub
  } as any;
}

/**
 * The factory is now a real `async (args) => Promise<Query>`. Tests
 * await it directly — no proxy/deferred-build flush needed.
 */

const WORKSPACE_PATH = "/tmp/cc-test-workspace";

function setupSupabaseMockReturning(
  workspacePath: string | null = WORKSPACE_PATH,
) {
  // ADR-044: the workspace path is resolved via resolveActiveWorkspacePath
  // (active workspace), not the users.workspace_path read. A null workspacePath
  // models the legacy "not provisioned" throw the factory's error path expects.
  if (workspacePath) {
    mockResolveActiveWorkspacePath.mockResolvedValue(workspacePath);
  } else {
    mockResolveActiveWorkspacePath.mockRejectedValue(
      new Error("Workspace not provisioned"),
    );
  }
  mockSupabaseFrom.mockImplementation((table: string) => {
    if (table === "users") {
      return {
        select: () => ({
          eq: () => ({
            single: () => ({
              data: workspacePath ? { workspace_path: workspacePath } : null,
              error: workspacePath ? null : new Error("not found"),
            }),
            maybeSingle: () => ({
              data: workspacePath ? { workspace_path: workspacePath } : null,
              error: workspacePath ? null : new Error("not found"),
            }),
          }),
        }),
      };
    }
    return {
      select: () => ({ eq: () => ({ single: () => ({ data: null, error: null }) }) }),
      insert: () => ({ error: null }),
      update: () => ({ eq: () => ({ error: null }) }),
    };
  });
}

function makeArgs(overrides: Partial<Parameters<typeof realSdkQueryFactory>[0]> = {}) {
  // biome-ignore lint/suspicious/noExplicitAny: minimal AsyncIterable stub
  const promptStream = {
    async *[Symbol.asyncIterator]() {},
  } as any;
  return {
    prompt: promptStream,
    systemPrompt: "system",
    pluginPath: "/ignored", // factory recomputes from workspacePath
    cwd: "/ignored", // factory uses workspacePath
    userId: "user-1",
    conversationId: "conv-1",
    persona: "command_center" as const,
    ...overrides,
  };
}

describe("realSdkQueryFactory — cc-soleur-go SDK binding", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // #11636: the push registration's seams default to the dark path (flag OFF) so every pre-existing case is unaffected.
    registrarOverride.fn = null;
    readRegistrarOverride.fn = null;
    conversationWriteOverride.fn = null;
    mockApprovalFlag.mockReset().mockResolvedValue(false);
    mockGithubApiGet.mockReset().mockResolvedValue({ default_branch: "trunk" });
    mockHeadSha.mockReset().mockResolvedValue("d".repeat(40));
    mockPushBranch.mockReset().mockResolvedValue({ branch: "feat-x", pushed: true });
    mockGetUserApiKey.mockResolvedValue("sk-test");
    mockGetUserServiceTokens.mockResolvedValue({});
    mockBuildAgentEnv.mockReturnValue({ ANTHROPIC_API_KEY: "sk-test" });
    mockBuildAgentSandboxConfig.mockReturnValue({
      enabled: true,
      failIfUnavailable: true,
      autoAllowBashIfSandboxed: false,
      allowUnsandboxedCommands: false,
      enableWeakerNestedSandbox: true,
      network: { allowedDomains: [], allowManagedDomainsOnly: true },
      filesystem: {
        allowWrite: [WORKSPACE_PATH],
        denyRead: ["/workspaces", "/proc"],
      },
    });
    mockQuery.mockReturnValue(makeFakeQuery());
    // Issue A defaults: no connected repo (null) → no mint, no GH_TOKEN.
    mockResolveInstallationId.mockResolvedValue(null);
    mockGenerateInstallationToken.mockResolvedValue("ghs_default_test_token");
    mockResolveBashAutonomous.mockResolvedValue(false);
    mockResolveSandboxUnixDeny.mockResolvedValue(false);
    mockResolveWebEgress.mockResolvedValue(false);
    mockResolveAutonomousAck.mockResolvedValue(null);
    mockResolveIsWorkspaceOwner.mockResolvedValue(false);
    // ADR-044 PR-1: default to the solo workspace (= userId). Dispatch-path
    // tests that need a team/reset id override per-case.
    mockResolveActiveWorkspace.mockImplementation(async (userId: string) => ({
      ok: true,
      workspaceId: userId,
    }));
    // feat-one-shot-concierge-gh-403 self-heal defaults: no connected repo so
    // the self-heal branch is skipped for every pre-existing test. The
    // dedicated describe block overrides these per-test.
    mockGetCurrentRepoUrl.mockResolvedValue(null);
    // #9556 — the SUT calls the degrade-aware variant; delegate to the same
    // spy so the suite's existing url fixtures keep working (degraded=false;
    // the degraded arm's ccDeps emission is pinned in T15b below).
    mockReadCurrentRepoUrlResult.mockImplementation(
      async (userId: string, workspaceId: string) => ({
        url: await mockGetCurrentRepoUrl(userId, workspaceId),
        degraded: false,
      }),
    );
    // #5394 — default repo readiness is `ready` so the gate never blocks the
    // pre-existing factory-shape tests; the dedicated gate describe overrides it.
    mockGetCurrentRepoStatus.mockResolvedValue({
      repoStatus: "ready",
      repoError: null,
    });
    mockGetInstallationAccount.mockResolvedValue({ login: "owner", id: 1, type: "Organization" });
    mockFindRepoOwnerInstallationForUser.mockResolvedValue({ installationId: null, outcome: "not-member" });
    // Item 1 — in-sandbox askpass writer returns a deterministic path under
    // the workspace (the real writer uses a randomUUID suffix).
    mockWriteAskpassScriptTo.mockReturnValue(
      `${WORKSPACE_PATH}/.askpass-fixed-test.sh`,
    );
    setupSupabaseMockReturning(WORKSPACE_PATH);
  });

  // -------------------------------------------------------------------------
  // T1: factory called with valid user → returns Query
  // -------------------------------------------------------------------------
  it("T1: invokes SDK query() once with cwd=workspacePath and the canonical model", async () => {
    await realSdkQueryFactory(makeArgs());

    expect(mockQuery).toHaveBeenCalledOnce();
    const callArg = mockQuery.mock.calls[0][0];
    expect(callArg.options.cwd).toBe(WORKSPACE_PATH);
    expect(callArg.options.model).toBe("claude-sonnet-5-5");
  });

  // -------------------------------------------------------------------------
  // T2: factory options omit / empty mcpServers (V1; V2-13 widens)
  // -------------------------------------------------------------------------
  it("T2: soleur_platform server is ALWAYS built with narrate/summarize (#5370)", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    // feat-reasoning-chat-boxes (#5370): the soleur_platform server is now
    // built unconditionally so the always-on narrate/summarize tools are
    // reachable on every cc dispatch (was empty for V1; the C4 write tool is
    // still flag+repo-gated and merged into the SAME server when eligible).
    // makeArgs() has no connected repo / c4 flag, so ONLY narrate/summarize
    // are present — edit_c4_diagram is absent.
    expect(opts.mcpServers).toBeDefined();
    expect(Object.keys(opts.mcpServers)).toEqual(["soleur_platform"]);
    const toolNames = (opts.mcpServers.soleur_platform.tools ?? []).map(
      (t: { name: string }) => t.name,
    );
    expect(toolNames).toEqual(
      expect.arrayContaining(["narrate", "summarize"]),
    );
    expect(toolNames).not.toContain("edit_c4_diagram");
  });

  // #8739 — the emit seam: buildC4ConciergeTools' onDiagramSaved opt is wired
  // to defaultSendToClient INSIDE the factory. Without this test, deleting the
  // prop leaves the whole suite green and the feature emits nothing.
  it("a successful edit_c4_diagram emits c4_diagram_saved via sendToClient", async () => {
    mockGetCurrentRepoUrl.mockResolvedValueOnce(
      "https://github.com/acme/kb-repo",
    );
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockResolveC4FlagEnabled.mockResolvedValueOnce(true);

    await realSdkQueryFactory(makeArgs());
    const tools =
      mockQuery.mock.calls[0][0].options.mcpServers.soleur_platform.tools;
    const c4 = (tools ?? []).find(
      (t: { name: string }) => t.name === "edit_c4_diagram",
    );
    expect(c4).toBeDefined();

    mockWriteC4Diagram.mockResolvedValueOnce({
      ok: true,
      commitSha: "abc123",
      rerendered: true,
      rerenderDiagnostic: null,
    });
    const res = await c4.handler({
      relativePath: "engineering/architecture/diagrams/model.c4",
      content: "model {}",
    });
    expect(res.isError).toBeUndefined();

    await vi.waitFor(() =>
      expect(mockSendToClient).toHaveBeenCalledWith("user-1", {
        type: "c4_diagram_saved",
        dirPath: "engineering/architecture/diagrams",
        rerendered: true,
        diagnostic: null,
      }),
    );
    // #8966 — the emit is counted with its outcome: the silent-fallback
    // incidence is a rate, and a rate needs the success denominator.
    expect(mockInfoSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        feature: "c4-save-outcome",
        tags: { outcome: "rerendered" },
      }),
    );
  });

  // #8966 — the rerendered:false arm counts too (the numerator of the rate).
  it("a non-rerendered edit_c4_diagram counts outcome=rerendered-false on the same feature slug", async () => {
    mockGetCurrentRepoUrl.mockResolvedValueOnce(
      "https://github.com/acme/kb-repo",
    );
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockResolveC4FlagEnabled.mockResolvedValueOnce(true);

    await realSdkQueryFactory(makeArgs());
    const tools =
      mockQuery.mock.calls[0][0].options.mcpServers.soleur_platform.tools;
    const c4 = (tools ?? []).find(
      (t: { name: string }) => t.name === "edit_c4_diagram",
    );
    mockWriteC4Diagram.mockResolvedValueOnce({
      ok: true,
      commitSha: "abc123",
      rerendered: false,
      rerenderDiagnostic: "render failed",
    });
    await c4.handler({
      relativePath: "engineering/architecture/diagrams/model.c4",
      content: "model {}",
    });

    await vi.waitFor(() =>
      expect(mockInfoSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({
          feature: "c4-save-outcome",
          tags: { outcome: "rerendered-false" },
        }),
      ),
    );
  });

  // -------------------------------------------------------------------------
  // T3: plugins: [{ type: "local", path: <DEPLOYED plugin root> }]  (security fix)
  // -------------------------------------------------------------------------
  it("T3: plugins points at the DEPLOYED plugin root, not the workspace copy", async () => {
    // getPluginPath() default (no SOLEUR_PLUGIN_PATH set in test). A workspace whose
    // connected repo ships its own plugins/soleur/ must NOT shadow the deployed plugin
    // (security: loading the workspace copy would run its hooks.json in-process).
    // See knowledge-base/.../2026-07-06-connected-repo-shadows-deployed-plugin-*.md.
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.plugins).toEqual([
      { type: "local", path: "/app/shared/plugins/soleur" },
    ]);
  });

  // -------------------------------------------------------------------------
  // T4: sandbox includes failIfUnavailable=true and allowUnsandboxedCommands=false
  // -------------------------------------------------------------------------
  it("T4: sandbox is the canonical buildAgentSandboxConfig output", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.sandbox.failIfUnavailable).toBe(true);
    expect(opts.sandbox.allowUnsandboxedCommands).toBe(false);
    // W1 (#9601): the dispatcher passes the builder's object through UNCHANGED.
    // The builder is mocked here, so its `credentials` content is not the point;
    // identity is: a spread or override at the call site (which would drop the
    // credential deny the real builder returns) makes a new object.
    expect(opts.sandbox).toBe(mockBuildAgentSandboxConfig.mock.results[0].value);
    // Helper was called with the workspace path AND fail-closed egress —
    // this dispatch has no connected repo, so no GitHub egress (#5041
    // follow-up).
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH, {
      allowGithubEgress: false, sandboxUnixDeny: false,
      readOnly: false,
      // #9534 — entitlement-derived quarantine flag (unentitled → false).
      allowWebEgress: false,
    });
  });

  // -------------------------------------------------------------------------
  // T5: hooks include PreToolUse + SubagentStart
  // -------------------------------------------------------------------------
  it("T5: hooks include PreToolUse matcher AND SubagentStart audit hook", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.hooks?.PreToolUse).toBeDefined();
    expect(Array.isArray(opts.hooks.PreToolUse)).toBe(true);
    expect(opts.hooks.PreToolUse[0].matcher).toContain("Bash");
    expect(opts.hooks?.SubagentStart).toBeDefined();
    expect(Array.isArray(opts.hooks.SubagentStart)).toBe(true);
  });

  // -------------------------------------------------------------------------
  // T6: disallowedTools mirrors WebSearch + WebFetch from agent-runner
  // -------------------------------------------------------------------------
  it("T6: disallowedTools includes WebSearch and WebFetch (parity with agent-runner)", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.disallowedTools).toEqual(
      expect.arrayContaining(["WebSearch", "WebFetch"]),
    );
  });

  // -------------------------------------------------------------------------
  // T6b (#3338 + #3344): cc path HARD-BLOCKS Edit/Write via disallowedTools.
  //
  // Bash was originally hard-blocked alongside Edit/Write (#3338) to prevent
  // a `find . -name "*.pdf"` / `apt-get install poppler-utils` modal cascade.
  // Two structural mitigations (#3338 PDF Read 24 MB ceiling + #3430
  // page-count gate) eliminated those triggers, so #3344 removed Bash from
  // the hard-block list. Bash now routes through canUseTool + the legacy
  // path's safe-bash allowlist (auto-approve for read-only KB-exploration
  // verbs; review-gate fallback for everything else).
  //
  // The auto-approve `allowedTools` list pins read-only tools
  // (Read/Glob/Grep/LS/NotebookRead/TodoWrite/ExitPlanMode) so they bypass
  // canUseTool. SDK semantics per sdk.d.ts:855-892:
  //   - allowedTools = auto-approve (NOT restriction)
  //   - disallowedTools = hard-block (removes from model's context)
  // Pin BOTH invariants. Bash MUST NOT appear in disallowedTools (post-#3344)
  // so the cc-path can route Bash through safe-bash. Edit/Write MUST remain
  // in disallowedTools so the cc-router still cannot mutate files.
  // -------------------------------------------------------------------------
  it("T6b: disallowedTools HARD-BLOCKS Edit/Write on the cc path; Bash routes via canUseTool (#3338 + #3344)", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(Array.isArray(opts.disallowedTools)).toBe(true);
    expect(opts.disallowedTools).toEqual(
      expect.arrayContaining(["Edit", "Write", "WebSearch", "WebFetch"]),
    );
    // #3344: Bash MUST NOT be in disallowedTools — the model needs to emit
    // it so it routes through canUseTool → safe-bash auto-approve for
    // read-only verbs. Pinning the negative-space invariant.
    expect(opts.disallowedTools).not.toContain("Bash");
    // Auto-approve list narrows to read-only safe tools + the always-on
    // narrate/summarize emit tools (feat-reasoning-chat-boxes #5370 — pure
    // emit tools auto-approved so a narration never pays a canUseTool
    // round-trip / surfaces a review modal). Order-tolerant closed-set match
    // so widening the list requires an explicit test edit.
    expect(Array.isArray(opts.allowedTools)).toBe(true);
    const sorted = [...opts.allowedTools].sort();
    expect(sorted).toEqual(
      [
        "ExitPlanMode",
        "Glob",
        "Grep",
        "LS",
        "NotebookRead",
        "Read",
        "TodoWrite",
        "mcp__soleur_platform__narrate",
        "mcp__soleur_platform__summarize",
      ],
    );
  });

  // -------------------------------------------------------------------------
  // T7: settingSources: [] (defense-in-depth)
  // -------------------------------------------------------------------------
  it("T7: settingSources is the empty array (no project settings.json pre-approvals)", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.settingSources).toEqual([]);
  });

  // -------------------------------------------------------------------------
  // T15: leaderId: "cc_router" passed to createCanUseTool
  // -------------------------------------------------------------------------
  it('T15: createCanUseTool receives leaderId: "cc_router" (audit-log attribution)', async () => {
    await realSdkQueryFactory(makeArgs());
    expect(createCanUseTool).toHaveBeenCalledOnce();
    const ctx = (createCanUseTool as unknown as { mock: { calls: unknown[][] } }).mock.calls[0][0] as {
      leaderId: string;
      userId: string;
      conversationId: string;
    };
    expect(ctx.leaderId).toBe("cc_router");
    expect(ctx.userId).toBe("user-1");
    expect(ctx.conversationId).toBe("conv-1");
  });

  // -------------------------------------------------------------------------
  // T15b: ccDeps.repoConnected — url/degraded tri-state (#9556)
  // -------------------------------------------------------------------------
  it('T15b: ccDeps.repoConnected is true/false on the honest arms and undefined on a degraded read', async () => {
    const readDep = async () => {
      (createCanUseTool as unknown as { mockClear(): void }).mockClear();
      await realSdkQueryFactory(makeArgs());
      const ctx = (createCanUseTool as unknown as { mock: { calls: unknown[][] } }).mock.calls[0][0] as {
        deps: { repoConnected?: boolean };
      };
      return ctx.deps.repoConnected;
    };
    const REPO = "https://github.com/jikig-ai/soleur";

    mockReadCurrentRepoUrlResult.mockResolvedValueOnce({ url: REPO, degraded: false });
    expect(await readDep()).toBe(true);

    mockReadCurrentRepoUrlResult.mockResolvedValueOnce({ url: null, degraded: false });
    expect(await readDep()).toBe(false);

    // A transient resolve failure is NOT "not connected": the dep must be
    // undefined so the frame omits the field (legacy caveat arm) rather than
    // rendering connect-repo copy to a connected user.
    mockReadCurrentRepoUrlResult.mockResolvedValueOnce({ url: null, degraded: true });
    expect(await readDep()).toBeUndefined();
  });

  // -------------------------------------------------------------------------
  // Approval wiring (ADR-309 addendum): the live ccDeps object carries the gate dependency, one fresh grants object per
  // factory invocation, and the fail-closed switch. A source-text census cannot see the live object; this can.
  // -------------------------------------------------------------------------
  describe("approval wiring on the live canUseTool deps", () => {
    type CcApprovalDeps = {
      approval?: { grants: { enforcing: boolean }; workspaceId: string };
      approvalFailClosed?: boolean;
    };
    const capture = async (): Promise<CcApprovalDeps> => {
      const mock = createCanUseTool as unknown as { mockClear(): void; mock: { calls: unknown[][] } };
      mock.mockClear();
      await realSdkQueryFactory(makeArgs());
      const ctx = mock.mock.calls[0][0] as { deps: CcApprovalDeps };
      return ctx.deps;
    };

    it("carries the gate dependency, a grants object with enforcing off, and the fail-closed switch", async () => {
      const deps = await capture();
      expect(deps.approval).toBeDefined();
      expect(deps.approval?.grants).toBeInstanceOf(ExecutionGrants);
      expect(deps.approval?.grants.enforcing).toBe(false);
      expect(deps.approvalFailClosed).toBe(true);
    });

    it("binds the gate to the resolved active workspace, not to the user id", async () => {
      // A team workspace: its id differs from the user id, so binding to `args.userId` instead would be visible.
      const TEAM_WORKSPACE = "00000000-0000-4000-8000-0000000000aa";
      mockResolveActiveWorkspace.mockImplementation(async () => ({ ok: true, workspaceId: TEAM_WORKSPACE }));
      const deps = await capture();
      expect(deps.approval?.workspaceId).toBe(TEAM_WORKSPACE);
      expect(deps.approval?.workspaceId).not.toBe("user-1");
    });

    it("builds a distinct grants object per factory invocation (never module scope, so none leaks across Queries)", async () => {
      const first = await capture();
      const second = await capture();
      expect(first.approval?.grants).toBeDefined();
      expect(second.approval?.grants).toBeDefined();
      expect(second.approval?.grants).not.toBe(first.approval?.grants);
    });

    it("registers no approval-required tool in the final allowedTools", async () => {
      await realSdkQueryFactory(makeArgs());
      const opts = mockQuery.mock.calls[0][0].options;
      for (const tool of APPROVAL_REQUIRED_TOOLS) expect(opts.allowedTools).not.toContain(tool);
    });
  });


  // -------------------------------------------------------------------------
  // #11636 (ADR-309): github_push_branch is registered in the cc soleur_platform server ONLY when the approval-queue
  // flag, the workspace web-egress grant, a non-support persona, a connected repo and an installation all hold.
  // -------------------------------------------------------------------------
  describe("github_push_branch registration (#11636)", () => {
    const PUSH_FQN = "mcp__soleur_platform__github_push_branch";
    const HEAD = "d".repeat(40);
    const REPO_URL = "https://github.com/acme/kb-repo";
    // #12469: the read registrar's repository-visibility lookup goes through the same mocked `githubApiGet` (it is the only caller
    // passing `redirect: "manual"`). The push assertions below count the DEFAULT-BRANCH lookup only, so they filter it out; the
    // mock's answer has no `private` field, which the read registrar treats as private, so no read tool registers in these cases.
    const pushLookupCalls = () =>
      mockGithubApiGet.mock.calls.filter((c) => (c as unknown[])[2] === undefined || ((c as unknown[])[2] as { redirect?: string }).redirect !== "manual");
    // The default branch the mocked lookup answers with (see the hoisted `mockGithubApiGet` default).
    const ADDENDUM = ccPushPromptAddendum("trunk");

    /** Every precondition true (flag on, entitled, repo, installation); a test turns ONE off. */
    function eligible(over: { flag?: unknown; entitled?: boolean; repo?: boolean; forwarder?: boolean } = {}) {
      mockApprovalFlag.mockResolvedValue(over.flag === undefined ? true : over.flag);
      mockResolveWebEgress.mockResolvedValue(over.entitled ?? true);
      if (over.repo !== false) {
        mockGetCurrentRepoUrl.mockResolvedValue(REPO_URL);
        mockResolveInstallationId.mockResolvedValue(987654);
      } else {
        mockGetCurrentRepoUrl.mockResolvedValue(null);
        mockResolveInstallationId.mockResolvedValue(null);
      }
      if ((over.entitled ?? true) && over.forwarder !== false) {
        mockSpawnEgressForwarder.mockResolvedValue({ port: 28711, token: "tok-abc", pid: 4242 });
      } else {
        mockSpawnEgressForwarder.mockRejectedValue(new Error("bind boom"));
      }
    }

    const ccCtx = () => {
      const mock = createCanUseTool as unknown as { mock: { calls: unknown[][] } };
      return mock.mock.calls.at(-1)![0] as {
        platformToolNames: string[];
        deps: { approval: { grants: ExecutionGrants; workspaceId: string; resolveServerDerived: (t: string, s: Record<string, unknown>) => Promise<unknown> } };
      };
    };
    const platformTools = () => mockQuery.mock.calls.at(-1)![0].options.mcpServers.soleur_platform.tools as Array<{ name: string; handler: (a: Record<string, unknown>) => Promise<{ isError?: boolean; content: Array<{ text: string }> }> }>;
    const toolNames = () => platformTools().map((t) => t.name);
    const prompt = () => mockQuery.mock.calls.at(-1)![0].options.systemPrompt as string;
    const registrationEvents = () => mockInfoSilentFallback.mock.calls.filter(([, o]) => o?.feature === "cc-push-registration");

    beforeEach(() => {
      __resetDispatcherForTests();
      (createCanUseTool as unknown as { mockClear(): void }).mockClear();
      (createApprovalGateDeps as unknown as { mockClear(): void }).mockClear();
    });

    /** The dark-path baseline as LITERALS (vi.mock is hoisted file-wide, so a "baseline captured without the mock" would compare the new code with itself). */
    function expectDarkPath() {
      expect(toolNames()).toEqual(["narrate", "summarize"]);
      expect(ccCtx().platformToolNames).toEqual([]);
      expect(prompt()).not.toContain("github_push_branch");
      expect(prompt()).not.toContain(ADDENDUM);
      expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([]);
      const opts = mockQuery.mock.calls.at(-1)![0].options;
      expect(opts.allowedTools).not.toContain(PUSH_FQN);
    }

    it("flag OFF (everything else true): the tool set, platformToolNames and prompt are the pre-change LITERALS, the lookup is not called, the gate deps are unchanged", async () => {
      eligible({ flag: false });
      await realSdkQueryFactory(makeArgs());
      expectDarkPath();
      expect(pushLookupCalls()).toHaveLength(0);
      expect(prompt().startsWith("system\n\n## GitHub `gh` errors")).toBe(true);
      const deps = ccCtx().deps;
      expect(deps.approval.grants).toBeInstanceOf(ExecutionGrants);
      expect(deps.approval.grants.enforcing).toBe(false);
      // The normal dark states emit no outcome event (the registered case and the failures do).
      expect(registrationEvents()).toHaveLength(0);
    });

    it("flag read THROWS: not registered (fail closed), reported under cc-push-flag-resolve, dark-path literals hold", async () => {
      eligible();
      mockApprovalFlag.mockRejectedValue(new Error("flagsmith down"));
      await realSdkQueryFactory(makeArgs());
      expectDarkPath();
      expect(mockReportSilentFallback.mock.calls.some(([, o]) => o?.op === "cc-push-flag-resolve")).toBe(true);
      expect(pushLookupCalls()).toHaveLength(0);
    });

    it.each([
      ["a flag value that is not exactly true (undefined)", { flag: undefined as unknown, set: (): void => void mockApprovalFlag.mockResolvedValue(undefined) }],
      ["not entitled to web egress", { set: (): void => eligible({ entitled: false }) }],
      ["no connected repo", { set: (): void => eligible({ repo: false }) }],
    ])("%s: not registered, dark-path literals, the lookup is not called", async (_n, row) => {
      eligible();
      row.set();
      await realSdkQueryFactory(makeArgs());
      expectDarkPath();
      expect(pushLookupCalls()).toHaveLength(0);
    });

    it("a registrar that THROWS never breaks Query construction: the Query is built on the dark path and the failure is reported", async () => {
      eligible();
      mockInfoSilentFallback.mockImplementation((_e: unknown, o: { feature?: string }) => {
        if (o?.feature === "cc-push-registration") throw new Error("emit boom");
      });
      try {
        await realSdkQueryFactory(makeArgs());
      } finally {
        mockInfoSilentFallback.mockReset();
      }
      expectDarkPath();
      expect(mockReportSilentFallback.mock.calls.some(([, o]) => o?.op === "cc-push-registration-failed")).toBe(true);
    });

    it.each([
      ["a foreign toolName (not grant-wired)", { tools: [{ name: "github_push_branch" }], toolNames: ["mcp__soleur_platform__email_send"] }],
      ["a built tool whose name does not match its registered name", { tools: [{ name: "email_send" }], toolNames: [PUSH_FQN] }],
      ["tools and toolNames that do not correspond one-to-one", { tools: [], toolNames: [PUSH_FQN] }],
    ])("the dispatcher's wired-set assertion rejects %s: the Query is built on the dark path, nothing is published, and it is reported", async (_n, bad) => {
      eligible();
      // defaultBranch present: the prompt-addendum guard must not be what rejects it (the wired-set assertion is under test).
      registrarOverride.fn = async () => ({ registered: true, reason: "registered", defaultBranch: "trunk", ...bad });
      await realSdkQueryFactory(makeArgs());
      expectDarkPath();
      expect(mockReportSilentFallback.mock.calls.some(([, o]) => o?.op === "cc-push-registration-failed")).toBe(true);
    });

    it.each([
      ["a null defaultBranch", null],
      ["an unsafe defaultBranch", "a b"],
    ])("the prompt addendum THROWS (%s) after a valid wired result: nothing is published (no tool, no name, no Map entry, no addendum), the Query is built on the dark path, reported", async (_n, defaultBranch) => {
      eligible();
      registrarOverride.fn = async () => ({
        registered: true,
        reason: "registered",
        tools: [{ name: "github_push_branch" }],
        toolNames: [PUSH_FQN],
        defaultBranch,
      });
      await realSdkQueryFactory(makeArgs());
      // The addendum is computed BEFORE the first assignment, so the failed registration leaves no half-published set.
      expectDarkPath();
      expect(Object.keys(mockQuery.mock.calls.at(-1)![0].options.mcpServers)).toEqual(["soleur_platform"]);
      const call = mockReportSilentFallback.mock.calls.find(([, o]) => o?.op === "cc-push-registration-failed")!;
      expect(call[0]).toBeNull();
    });

    it("a registrar that throws is reported with a null first argument and the class name, never the Error (its message may embed a repo path)", async () => {
      eligible();
      registrarOverride.fn = async () => {
        throw new Error("boom GET /repos/acme/kb-repo");
      };
      await realSdkQueryFactory(makeArgs());
      expectDarkPath();
      const call = mockReportSilentFallback.mock.calls.find(([, o]) => o?.op === "cc-push-registration-failed")!;
      expect(call[0]).toBeNull();
      expect(call[1]).toMatchObject({ extra: { userId: "user-1", errName: "Error" } });
      expect(JSON.stringify(call[1])).not.toContain("kb-repo");
    });

    it("persona support with every other precondition true: not registered", async () => {
      eligible();
      await realSdkQueryFactory(makeArgs({ persona: "support" }));
      expectDarkPath();
      expect(pushLookupCalls()).toHaveLength(0);
    });

    it("default-branch lookup fails: not registered (fail closed, never a 'main' fallback), reported under cc-push-default-branch-resolve", async () => {
      eligible();
      mockGithubApiGet.mockRejectedValue(new Error("404"));
      await realSdkQueryFactory(makeArgs());
      expectDarkPath();
      expect(mockReportSilentFallback.mock.calls.some(([, o]) => o?.op === "cc-push-default-branch-resolve")).toBe(true);
    });

    it("all preconditions true: the tool is registered ONCE, its FQN is in platformToolNames, the addendum is in the prompt, the Map entry is published, and it is NOT in allowedTools", async () => {
      eligible();
      await realSdkQueryFactory(makeArgs());
      expect(toolNames()).toEqual(["narrate", "summarize", "github_push_branch"]);
      expect(toolNames().filter((n) => n === "github_push_branch")).toHaveLength(1);
      expect(ccCtx().platformToolNames).toEqual([PUSH_FQN]);
      // One server only (the sweep's blind spot, pinned on the live options), and what that server registers equals the base
      // list plus exactly the push FQN: the base names are the always-on narration tools, canUseTool's list carries the rest.
      expect(Object.keys(mockQuery.mock.calls.at(-1)![0].options.mcpServers)).toEqual(["soleur_platform"]);
      expect(toolNames().map((n) => `mcp__soleur_platform__${n}`)).toEqual([...CC_REGISTERED_PLATFORM_TOOL_NAMES, PUSH_FQN]);
      expect(prompt()).toContain(ADDENDUM);
      expect(prompt().split(ADDENDUM)).toHaveLength(2);
      expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([PUSH_FQN]);
      // ADR-305: a gated tool never enters allowedTools (canUseTool, i.e. the gate, is its only allow source).
      expect(mockQuery.mock.calls.at(-1)![0].options.allowedTools).not.toContain(PUSH_FQN);
      expect(pushLookupCalls()).toHaveLength(1);
      expect(registrationEvents()[0][1]).toMatchObject({ tags: { reason: "registered" } });
    });

    it("registered x crm-lead x c4 on: the server list is narration, c4, push, crm in that order, canUseTool's list is c4, push, crm, and NO approval-required tool is in allowedTools", async () => {
      eligible();
      mockResolveC4FlagEnabled.mockResolvedValueOnce(true);
      await realSdkQueryFactory(makeArgs({ crmLead: true }));
      const C4_FQN = "mcp__soleur_platform__edit_c4_diagram";
      const crm = crmLeadPermissionToolNames(true);
      expect(crm.length).toBeGreaterThan(0);
      expect(toolNames().map((n) => `mcp__soleur_platform__${n}`)).toEqual([...CC_REGISTERED_PLATFORM_TOOL_NAMES, C4_FQN, PUSH_FQN, ...crm]);
      expect(ccCtx().platformToolNames).toEqual([C4_FQN, PUSH_FQN, ...crm]);
      expect(Object.keys(mockQuery.mock.calls.at(-1)![0].options.mcpServers)).toEqual(["soleur_platform"]);
      // ADR-305: not one of the 8 approval-required tools (the push tool included) is pre-allowed.
      const allowed = mockQuery.mock.calls.at(-1)![0].options.allowedTools as string[];
      expect([...APPROVAL_REQUIRED_TOOLS]).toHaveLength(8);
      for (const tool of APPROVAL_REQUIRED_TOOLS) expect(allowed, tool).not.toContain(tool);
      expect(prompt()).toContain(ADDENDUM);
    });

    it("registered: none of the 8 approval-required tools is in allowedTools", async () => {
      eligible();
      await realSdkQueryFactory(makeArgs());
      expect(toolNames()).toContain("github_push_branch");
      const allowed = mockQuery.mock.calls.at(-1)![0].options.allowedTools as string[];
      for (const tool of APPROVAL_REQUIRED_TOOLS) expect(allowed, tool).not.toContain(tool);
    });

    it("the registered prompt equals the dark prompt plus exactly the addendum (nothing else moved)", async () => {
      eligible({ flag: false });
      await realSdkQueryFactory(makeArgs());
      const dark = prompt();
      eligible();
      await realSdkQueryFactory(makeArgs());
      expect(prompt().replace(`\n\n${ADDENDUM}`, "")).toBe(dark);
    });

    it("entitled with the forwarder DEGRADED (spawn failed, webEgress undefined): still registered (push is server-side)", async () => {
      eligible({ forwarder: false });
      await realSdkQueryFactory(makeArgs());
      expect(mockSpawnEgressForwarder).toHaveBeenCalled();
      expect(toolNames()).toContain("github_push_branch");
      expect(ccCtx().platformToolNames).toEqual([PUSH_FQN]);
    });

    it("identity: the grants object the gate deps carry IS the one the push handler checks (a gate-written grant releases the push)", async () => {
      eligible();
      await realSdkQueryFactory(makeArgs());
      const deps = ccCtx().deps;
      const gateArgs = (createApprovalGateDeps as unknown as { mock: { calls: Array<[{ grants: unknown }]> } }).mock.calls.at(-1)![0];
      expect(gateArgs.grants).toBe(deps.approval.grants);
      const handler = platformTools().find((t) => t.name === "github_push_branch")!.handler;
      // Before the gate ran (not enforcing) the strict handler refuses.
      const refused = await handler({ branch: "feat-x", force: false });
      expect(refused.isError).toBe(true);
      expect(mockPushBranch).not.toHaveBeenCalled();
      // A grant written on the gate's object releases the handler: they share one object.
      deps.approval.grants.enforcing = true;
      putGrant(deps.approval.grants, PUSH_FQN, { branch: "feat-x" }, { workspaceId: deps.approval.workspaceId, headSha: HEAD });
      const ok = await handler({ branch: "feat-x", force: false });
      expect(ok.isError).toBeUndefined();
      expect(mockPushBranch).toHaveBeenCalledTimes(1);
      expect(mockPushBranch.mock.calls[0][0]).toMatchObject({ commitSha: HEAD, defaultBranch: "trunk" });
    });

    it("workspace capture (brief ruling 1): the gate's workspaceId/repoSlug/workspacePath equal the tool closure's, and a mid-Query workspace switch cannot split them", async () => {
      const TEAM = "00000000-0000-4000-8000-0000000000aa";
      const OTHER = "00000000-0000-4000-8000-0000000000bb";
      mockResolveActiveWorkspace.mockImplementation(async () => ({ ok: true, workspaceId: TEAM }));
      eligible();
      await realSdkQueryFactory(makeArgs());

      const gateArgs = (createApprovalGateDeps as unknown as {
        mock: { calls: Array<[{ workspaceId: string; repoSlug: string; workspacePath: string; grants: ExecutionGrants }]> };
      }).mock.calls.at(-1)![0];
      // The id the gate binds is the id every workspace-keyed read received.
      expect(gateArgs.workspaceId).toBe(TEAM);
      expect(mockResolveActiveWorkspacePath.mock.calls.at(-1)).toContain(TEAM);
      expect(mockReadCurrentRepoUrlResult.mock.calls.at(-1)![1]).toBe(TEAM);
      expect(mockResolveInstallationId.mock.calls.at(-1)![1]).toBe(TEAM);

      // The tool closure's owner/repo/workspacePath, observed through the handler's call to pushBranch.
      const deps = ccCtx().deps;
      deps.approval.grants.enforcing = true;
      putGrant(deps.approval.grants, PUSH_FQN, { branch: "feat-x" }, { workspaceId: gateArgs.workspaceId, headSha: HEAD });
      // Switch the active workspace AFTER construction.
      mockResolveActiveWorkspace.mockImplementation(async () => ({ ok: true, workspaceId: OTHER }));
      const handler = platformTools().find((t) => t.name === "github_push_branch")!.handler;
      await handler({ branch: "feat-x", force: false });
      const pushed = mockPushBranch.mock.calls[0][0] as { owner: string; repo: string; workspacePath: string };
      expect(gateArgs.repoSlug).toBe(`${pushed.owner}/${pushed.repo}`);
      expect(gateArgs.repoSlug).toBe("acme/kb-repo");
      expect(gateArgs.workspacePath).toBe(pushed.workspacePath);
      expect(pushed.workspacePath).toBe(WORKSPACE_PATH);

      // The gate still binds the ORIGINAL workspace: resolveServerDerived reads the captured path/repo, not a re-resolve.
      const derived = await deps.approval.resolveServerDerived(PUSH_FQN, { branch: "feat-x", force: false });
      expect(derived).toEqual({ repo: "acme/kb-repo", headSha: HEAD });
      expect(mockHeadSha).toHaveBeenLastCalledWith(WORKSPACE_PATH);
      expect(deps.approval.workspaceId).toBe(TEAM);
    });

    it("two cold builds never share a grants object: a grant on build A's gate object does not release build B's handler", async () => {
      eligible();
      await realSdkQueryFactory(makeArgs({ conversationId: "conv-a" }));
      const a = { deps: ccCtx().deps, handler: platformTools().find((t) => t.name === "github_push_branch")!.handler };
      await realSdkQueryFactory(makeArgs({ conversationId: "conv-b" }));
      const b = { deps: ccCtx().deps, handler: platformTools().find((t) => t.name === "github_push_branch")!.handler };
      expect(a.deps.approval.grants).not.toBe(b.deps.approval.grants);
      a.deps.approval.grants.enforcing = true;
      b.deps.approval.grants.enforcing = true;
      putGrant(a.deps.approval.grants, PUSH_FQN, { branch: "feat-x" }, { workspaceId: a.deps.approval.workspaceId, headSha: HEAD });
      const resB = await b.handler({ branch: "feat-x", force: false });
      expect(resB.isError).toBe(true);
      expect(mockPushBranch).not.toHaveBeenCalled();
      const resA = await a.handler({ branch: "feat-x", force: false });
      expect(resA.isError).toBeUndefined();
      expect(mockPushBranch).toHaveBeenCalledTimes(1);
    });

    it("the registrar receives the gate's identity and the SAME installation the tool is closed over: flag seam {userId, workspaceId}, lookup (installationId, repo path, signal), pushBranch installationId", async () => {
      const TEAM = "00000000-0000-4000-8000-0000000000aa";
      mockResolveActiveWorkspace.mockImplementation(async () => ({ ok: true, workspaceId: TEAM }));
      eligible();
      await realSdkQueryFactory(makeArgs());
      // The flag is read for the same workspace identity the gate binds (the TEAM id, not the user id).
      expect(mockApprovalFlag.mock.calls[0]).toEqual([{ userId: "user-1", workspaceId: TEAM }]);
      expect(ccCtx().deps.approval.workspaceId).toBe(TEAM);
      // The default-branch lookup: the effective installation id, owner/repo in order, and an abort signal.
      expect(pushLookupCalls()).toHaveLength(1);
      expect(pushLookupCalls()[0]).toEqual([987654, "/repos/acme/kb-repo", { signal: expect.any(AbortSignal) }]);
      // The handler pushes with that same installation.
      const deps = ccCtx().deps;
      deps.approval.grants.enforcing = true;
      putGrant(deps.approval.grants, PUSH_FQN, { branch: "feat-x" }, { workspaceId: TEAM, headSha: HEAD });
      await platformTools().find((t) => t.name === "github_push_branch")!.handler({ branch: "feat-x", force: false });
      expect(mockPushBranch.mock.calls[0][0]).toMatchObject({ installationId: 987654, owner: "acme", repo: "kb-repo", hardened: true });
    });

    // The warm turn: the factory does not run, the per-dispatch re-resolve knows nothing about the push tool, and the
    // `onToolUse` mirror consults the set the cold build published. Driven through the REAL dispatch loop (a stub runner
    // delivers the tool_use block to the dispatcher's own `onToolUse`), so a regex-shaped line cannot stand in for the behaviour.
    describe("warm turn: a push tool_use through the real dispatch loop", () => {
      const unregisteredMirrors = () => mockReportSilentFallback.mock.calls.filter(([, o]) => o?.op === "unregistered-tool-invoked");

      /** A permissive tenant chain for the dispatcher's own persistence: every builder call chains, every await yields no error. */
      function permissiveTenantChain(): unknown {
        const q: unknown = new Proxy(function () {}, {
          get: (_t, p) => {
            if (p === "then") return undefined;
            if (p === "error" || p === "data") return null;
            if (p === "single" || p === "maybeSingle") return async () => ({ data: { workspace_id: "ws-warm", workspace_path: WORKSPACE_PATH }, error: null });
            return () => q;
          },
        });
        return q;
      }

      async function warmTurnWith(toolName: string, conversationId = "conv-1") {
        mockSupabaseFrom.mockImplementation(() => permissiveTenantChain());
        conversationWriteOverride.fn = async () => ({ ok: true });
        const runner = {
          dispatch: vi.fn(async (a: { events: { onToolUse: (b: { name: string; input: Record<string, unknown>; toolUseId: string }) => void } }) => {
            await Promise.resolve();
            a.events.onToolUse({ name: toolName, input: { branch: "feat-x" }, toolUseId: "tu-1" });
            return { queryReused: true };
          }),
          hasActiveQuery: () => true,
          activeQueriesSize: () => 1,
          reapIdle: () => 0,
          closeConversation: () => {},
          respondToToolUse: () => false,
          notifyAwaitingUser: () => {},
        };
        __setCcRunnerForTests(runner as never);
        mockReportSilentFallback.mockClear();
        await dispatchSoleurGo({
          persona: "command_center",
          userId: "user-1",
          conversationId,
          userMessage: "push my branch",
          currentRouting: { kind: "soleur_go_pending" },
          sendToClient: vi.fn().mockReturnValue(true),
          persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
        } as never);
      }

      it("after a REGISTERED cold build the push tool_use does not mirror as an unregistered platform tool", async () => {
        eligible();
        await realSdkQueryFactory(makeArgs());
        expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([PUSH_FQN]);
        await warmTurnWith(PUSH_FQN);
        expect(unregisteredMirrors()).toHaveLength(0);
      });

      it("control: another platform tool on the same conversation STILL mirrors", async () => {
        eligible();
        await realSdkQueryFactory(makeArgs());
        await warmTurnWith("mcp__soleur_platform__email_send");
        expect(unregisteredMirrors()).toHaveLength(1);
      });

      it("control: the push tool_use on a conversation whose cold build did NOT register it (flag off) STILL mirrors", async () => {
        eligible({ flag: false });
        await realSdkQueryFactory(makeArgs());
        expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([]);
        await warmTurnWith(PUSH_FQN);
        expect(unregisteredMirrors()).toHaveLength(1);
      });

      it("control: the set is per conversation (a registered conv-1 does not silence conv-other)", async () => {
        eligible();
        await realSdkQueryFactory(makeArgs());
        await warmTurnWith(PUSH_FQN, "conv-other");
        expect(unregisteredMirrors()).toHaveLength(1);
      });
    });

    it("both drain sites forget the published set: the conversation close hook and the test reset", async () => {
      eligible();
      await realSdkQueryFactory(makeArgs());
      expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([PUSH_FQN]);
      cleanupCcBashGatesForConversation("user-1", "conv-1");
      expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([]);
      await realSdkQueryFactory(makeArgs());
      expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([PUSH_FQN]);
      __resetDispatcherForTests();
      expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([]);
    });

    it("a factory throw AFTER registration drains the Map entry (no stale published set)", async () => {
      eligible();
      mockQuery.mockImplementationOnce(() => {
        throw new Error("sdk construction boom");
      });
      await expect(realSdkQueryFactory(makeArgs())).rejects.toThrow(/sdk construction boom/);
      expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([]);
    });

    it("a rebuild with the flag OFF deletes a stale entry from an earlier unclean build (publish happens on EVERY cold build)", async () => {
      eligible();
      await realSdkQueryFactory(makeArgs());
      expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([PUSH_FQN]);
      mockApprovalFlag.mockResolvedValue(false);
      await realSdkQueryFactory(makeArgs());
      expect(getCcRegisteredApprovalTools("user-1", "conv-1")).toEqual([]);
    });

    it("the Map is keyed per conversation: another conversation does not see the entry", async () => {
      eligible();
      await realSdkQueryFactory(makeArgs());
      expect(getCcRegisteredApprovalTools("user-1", "conv-other")).toEqual([]);
      expect(getCcRegisteredApprovalTools("user-2", "conv-1")).toEqual([]);
    });
  });

  // -------------------------------------------------------------------------
  // T8: KeyInvalidError from getUserApiKey rejects the factory promise.
  // The factory is now a real async function — KeyInvalidError surfaces
  // synchronously to the runner's `await deps.queryFactory(...)` catch
  // (tagged `op: "queryFactory"`), then `dispatchSoleurGo` maps it to
  // `errorCode: "key_invalid"`. T19 in cc-dispatcher.test.ts covers the
  // dispatcher-level mapping; here we pin the factory-level throw shape.
  // -------------------------------------------------------------------------
  it("T8: KeyInvalidError from getUserApiKey rejects the awaited factory call (runner catch tags op=queryFactory)", async () => {
    const { KeyInvalidError } = await import("@/lib/types");
    mockGetUserApiKey.mockRejectedValueOnce(new KeyInvalidError());

    await expect(realSdkQueryFactory(makeArgs())).rejects.toBeInstanceOf(
      KeyInvalidError,
    );
    // Inner sdkQuery never called because BYOK fetch threw upstream.
    expect(mockQuery).not.toHaveBeenCalled();
  });

  // -------------------------------------------------------------------------
  // T9 / T18: env shape — buildAgentEnv called with apiKey + serviceTokens;
  // resulting env contains only the allowlisted vars.
  // -------------------------------------------------------------------------
  it("T9/T18: buildAgentEnv is invoked with BYOK key + service tokens (no SUPABASE_SERVICE_ROLE_KEY leak)", async () => {
    mockGetUserServiceTokens.mockResolvedValueOnce({
      PLAUSIBLE_API_KEY: "plk-1",
    });
    mockBuildAgentEnv.mockReturnValueOnce({
      ANTHROPIC_API_KEY: "sk-test",
      PLAUSIBLE_API_KEY: "plk-1",
    });

    await realSdkQueryFactory(makeArgs());

    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      { PLAUSIBLE_API_KEY: "plk-1" },
      // Issue A: third opts arg always present; ghToken undefined here
      // because the default mock resolves no installation (null). Slice B:
      // pluginPath (getPluginPath() = deployed root) is always threaded.
      { ghToken: undefined, pluginPath: "/app/shared/plugins/soleur", claudeTmpDir: expect.stringMatching(/^\/tmp\/\.cs\/[0-9a-f]{16}$/), sandboxUnixDeny: false },
    );
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.env.ANTHROPIC_API_KEY).toBe("sk-test");
    // CWE-526: no service-role key in env.
    expect(opts.env.SUPABASE_SERVICE_ROLE_KEY).toBeUndefined();
    expect(opts.env.BYOK_ENCRYPTION_KEY).toBeUndefined();
  });

  // -------------------------------------------------------------------------
  // Issue A — Concierge gh-auth: mint + inject GH_TOKEN (AC1/AC4)
  // -------------------------------------------------------------------------
  it("AC1: connected repo → mints installation token and threads it as ghToken", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockResolvedValueOnce("ghs_minted_xyz");

    await realSdkQueryFactory(makeArgs());

    // ADR-044 PR-1: the factory threads the membership-verified activeWorkspaceId
    // (= "user-1" solo here) into resolveInstallationId as the 2nd arg, so the
    // install resolves to the SAME workspace as the agent CWD / repo (no second
    // divergent resolve).
    expect(mockResolveInstallationId).toHaveBeenCalledWith("user-1", "user-1");
    expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
      987654,
      expect.objectContaining({ minRemainingMs: expect.any(Number) }),
    );
    // buildAgentEnv receives the minted token via the opts param — plus the
    // in-sandbox askpass wiring (item 1): the helper path + the same token as
    // gitInstallationToken.
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      {},
      {
        ghToken: "ghs_minted_xyz",
        gitAskpassScriptPath: `${WORKSPACE_PATH}/.askpass-fixed-test.sh`,
        gitInstallationToken: "ghs_minted_xyz",
        pluginPath: "/app/shared/plugins/soleur",
        claudeTmpDir: expect.stringMatching(/^\/tmp\/\.cs\/[0-9a-f]{16}$/), sandboxUnixDeny: false,
      },
    );
  });

  // -------------------------------------------------------------------------
  // #12469: the six read-only GitHub tools are registered ONLY for a web-egress-entitled, non-support session whose connected
  // repository is verified PUBLIC. Every other state is byte-identical to a build without them.
  // -------------------------------------------------------------------------
  describe("github read tools registration (#12469)", () => {
    const READ_FQNS = [
      "mcp__soleur_platform__github_list_pull_requests",
      "mcp__soleur_platform__github_read_pr",
      "mcp__soleur_platform__github_read_issue",
      "mcp__soleur_platform__github_read_issue_comments",
      "mcp__soleur_platform__github_list_pr_comments",
      "mcp__soleur_platform__github_read_ci_status",
    ];
    const READ_SHORT = READ_FQNS.map((n) => n.replace("mcp__soleur_platform__", ""));
    const REPO_URL = "https://github.com/acme/kb-repo";

    /** A GitHub that answers the visibility lookup (the only `redirect: "manual"` caller) and anything else harmlessly. */
    function github(visibility: unknown) {
      mockGithubApiGet.mockImplementation(async (...a: unknown[]) => {
        const [, path, opts] = a as [number, string, { redirect?: string } | undefined];
        if (opts?.redirect === "manual" && path === "/repos/acme/kb-repo") return { private: visibility };
        return { default_branch: "trunk" };
      });
    }
    function entitled(over: { entitled?: boolean; repo?: boolean; forwarder?: boolean } = {}) {
      mockApprovalFlag.mockResolvedValue(false); // the push tool stays out of these cases
      mockResolveWebEgress.mockResolvedValue(over.entitled ?? true);
      if (over.repo !== false) {
        mockGetCurrentRepoUrl.mockResolvedValue(REPO_URL);
        mockResolveInstallationId.mockResolvedValue(987654);
      } else {
        mockGetCurrentRepoUrl.mockResolvedValue(null);
        mockResolveInstallationId.mockResolvedValue(null);
      }
      if ((over.entitled ?? true) && over.forwarder !== false) {
        mockSpawnEgressForwarder.mockResolvedValue({ port: 28711, token: "tok-abc", pid: 4242 });
      } else {
        mockSpawnEgressForwarder.mockRejectedValue(new Error("bind boom"));
      }
    }

    const ccCtx = () => {
      const mock = createCanUseTool as unknown as { mock: { calls: unknown[][] } };
      return mock.mock.calls.at(-1)![0] as { platformToolNames: string[] };
    };
    const tools = () =>
      mockQuery.mock.calls.at(-1)![0].options.mcpServers.soleur_platform.tools as Array<{ name: string; handler: (a: Record<string, unknown>) => Promise<{ isError?: boolean; content: Array<{ text: string }> }> }>;
    const toolNames = () => tools().map((t) => t.name);
    const prompt = () => mockQuery.mock.calls.at(-1)![0].options.systemPrompt as string;
    const outcome = () => mockInfoSilentFallback.mock.calls.filter(([, o]) => o?.feature === "cc-github-read-registration");
    const ADDENDUM_HEAD = "## GitHub access while Agent web access is on";

    beforeEach(() => {
      __resetDispatcherForTests();
      (createCanUseTool as unknown as { mockClear(): void }).mockClear();
    });

    function expectNoReadTools() {
      expect(toolNames()).toEqual(["narrate", "summarize"]);
      expect(ccCtx().platformToolNames).toEqual([]);
      expect(getCcRegisteredReadTools("user-1", "conv-1")).toEqual([]);
      expect(prompt()).not.toContain(ADDENDUM_HEAD);
      const allowed = mockQuery.mock.calls.at(-1)![0].options.allowedTools as string[];
      for (const n of READ_FQNS) expect(allowed).not.toContain(n);
    }

    it("entitled + public repo + live forwarder: the six tools are built, in canUseTool's list, in the published cell, NOT in allowedTools, and the addendum is in the prompt", async () => {
      entitled();
      github(false);
      await realSdkQueryFactory(makeArgs());
      expect(toolNames()).toEqual(["narrate", "summarize", ...READ_SHORT]);
      expect(ccCtx().platformToolNames).toEqual(READ_FQNS);
      expect([...getCcRegisteredReadTools("user-1", "conv-1")]).toEqual(READ_FQNS);
      const allowed = mockQuery.mock.calls.at(-1)![0].options.allowedTools as string[];
      for (const n of READ_FQNS) expect(allowed).not.toContain(n);
      expect(prompt()).toContain(ADDENDUM_HEAD);
      expect(prompt()).toContain("`github_list_pull_requests`");
      // ordered AFTER the web-egress addendum, and the web-egress addendum is unchanged
      expect(prompt().indexOf("## Web access enabled for this session")).toBeLessThan(prompt().indexOf(ADDENDUM_HEAD));
    });

    it("the base registered-platform-tool constant is NEVER seeded with the read names (seeding it would silence the genuine unregistered-tool mirror)", () => {
      for (const n of READ_FQNS) expect(CC_REGISTERED_PLATFORM_TOOL_NAMES).not.toContain(n);
    });

    it("exactly ONE outcome event per cold dispatch, with every discriminating field", async () => {
      entitled();
      github(false);
      await realSdkQueryFactory(makeArgs());
      const events = outcome();
      expect(events).toHaveLength(1);
      const [, ctx] = events[0];
      expect(ctx.message).toBe("cc github read tools outcome");
      expect(ctx.tags).toEqual({ reason: "registered", entitled: "true", persona: "command_center", toolCount: "6", forwarderLive: "true", repoPrivate: "false" });
      expect(JSON.stringify(ctx)).not.toMatch(/acme|kb-repo/);
    });

    it("entitled + DEGRADED forwarder: the tools are present (the grant holds) but the addendum is absent, because gh still works; the event says forwarderLive=false", async () => {
      entitled({ forwarder: false });
      mockResolveWebEgress.mockResolvedValue(true);
      github(false);
      await realSdkQueryFactory(makeArgs());
      expect(toolNames()).toEqual(["narrate", "summarize", ...READ_SHORT]);
      expect(prompt()).not.toContain(ADDENDUM_HEAD);
      expect(prompt()).not.toContain("GitHub tools are unavailable");
      expect(outcome()[0][1].tags.forwarderLive).toBe("false");
    });

    it("entitled + NO connected repo: no tools, the connect-a-repository line, a debounced warning with its OWN literal, no info event", async () => {
      entitled({ repo: false });
      github(false);
      await realSdkQueryFactory(makeArgs());
      expectNoReadTools();
      expect(prompt()).toContain("GitHub tools are unavailable in this session: connect a repository in Workspace settings.");
      expect(outcome()).toHaveLength(0);
      expect(mockMirrorWarnWithDebounce).toHaveBeenCalledTimes(1);
      expect(mockMirrorWarnWithDebounce.mock.calls[0][1].message).toBe("cc github read tools unavailable");
    });

    it("entitled + PRIVATE repo: no tools, the public-only line, an info event with repoPrivate=true", async () => {
      entitled();
      github(true);
      await realSdkQueryFactory(makeArgs());
      expectNoReadTools();
      expect(prompt()).toContain("GitHub reads are limited to public repositories while Agent web access is on");
      expect(outcome()).toHaveLength(1);
      expect(outcome()[0][1].tags).toMatchObject({ reason: "repo-private", repoPrivate: "true", toolCount: "0" });
    });

    it.each([
      ["the lookup errors", () => mockGithubApiGet.mockRejectedValue(new Error("boom"))],
      ["the answer has no `private` field", () => github(undefined)],
    ])("entitled + %s: fail closed => no tools, reason visibility-unknown (NOT claimed private), own prompt line", async (_n, arrange) => {
      entitled();
      arrange();
      await realSdkQueryFactory(makeArgs());
      expectNoReadTools();
      expect(outcome()[0][1].tags).toMatchObject({ reason: "visibility-unknown", repoPrivate: "null" });
      expect(prompt()).toContain("it could not be confirmed that the repository is public");
      expect(prompt()).not.toContain("limited to public repositories");
    });

    it("NOT entitled: the tool list, canUseTool list and prompt are today's literals, and no event is emitted", async () => {
      entitled({ entitled: false });
      github(false);
      await realSdkQueryFactory(makeArgs());
      expectNoReadTools();
      expect(prompt()).not.toContain("GitHub tools are unavailable");
      expect(prompt()).not.toContain("limited to public repositories");
      expect(outcome()).toHaveLength(0);
      expect(mockMirrorWarnWithDebounce).not.toHaveBeenCalled();
    });

    it("entitled + support persona: unchanged, no event (support never gets GitHub tools)", async () => {
      entitled();
      github(false);
      await realSdkQueryFactory(makeArgs({ persona: "support" }));
      expectNoReadTools();
      expect(outcome()).toHaveLength(0);
    });

    it("a registrar that REJECTS never breaks Query construction: the Query builds dark, the fault is reported under its own op, and the model still gets a truthful 'unavailable' line", async () => {
      entitled();
      github(false);
      readRegistrarOverride.fn = async () => {
        throw new Error("registrar boom for acme/kb-repo");
      };
      mockQuery.mockClear();
      await realSdkQueryFactory(makeArgs());
      expect(mockQuery).toHaveBeenCalledTimes(1);
      expectNoReadTools();
      const call = mockReportSilentFallback.mock.calls.find(([, o]) => o?.op === "cc-github-read-registration-failed")!;
      expect(call[0]).toBeNull();
      expect(JSON.stringify(call[1])).not.toMatch(/acme|kb-repo|boom/);
      expect(prompt()).toContain("GitHub tools are unavailable in this session because of a platform fault");
      expect(prompt()).toContain("Never ask the user for a token");
    });

    it("an emit that THROWS (telemetry fault) never breaks the dispatch either", async () => {
      entitled();
      github(false);
      mockInfoSilentFallback.mockImplementation((_e: unknown, o: { feature?: string }) => {
        if (o?.feature === "cc-github-read-registration") throw new Error("emit boom");
      });
      try {
        mockQuery.mockClear();
        await realSdkQueryFactory(makeArgs());
      } finally {
        mockInfoSilentFallback.mockReset();
      }
      expect(mockQuery).toHaveBeenCalledTimes(1);
      expect(toolNames()).toEqual(["narrate", "summarize", ...READ_SHORT]);
    });

    it("a registrar result with reason registration-failed gets the platform-fault line and emits NO outcome event", async () => {
      entitled();
      github(false);
      readRegistrarOverride.fn = async () => ({ registered: false, reason: "registration-failed", tools: [], toolNames: [], repoPrivate: false });
      await realSdkQueryFactory(makeArgs());
      expectNoReadTools();
      expect(prompt()).toContain("platform fault");
      expect(outcome()).toHaveLength(0);
    });

    it("a startup throw AFTER registration drains the read cell (no stale published set)", async () => {
      entitled();
      github(false);
      mockQuery.mockImplementationOnce(() => {
        throw new Error("sdk construction boom");
      });
      await expect(realSdkQueryFactory(makeArgs())).rejects.toThrow(/sdk construction boom/);
      expect(getCcRegisteredReadTools("user-1", "conv-1")).toEqual([]);
    });

    it("the cell is drained by the factory-entry reset, the conversation cleanup and the test reset (the same sites as the approval cell)", async () => {
      entitled();
      github(false);
      await realSdkQueryFactory(makeArgs());
      expect(getCcRegisteredReadTools("user-1", "conv-1")).toHaveLength(6);
      cleanupCcBashGatesForConversation("user-1", "conv-1");
      expect(getCcRegisteredReadTools("user-1", "conv-1")).toEqual([]);
      await realSdkQueryFactory(makeArgs());
      expect(getCcRegisteredReadTools("user-1", "conv-1")).toHaveLength(6);
      __resetDispatcherForTests();
      expect(getCcRegisteredReadTools("user-1", "conv-1")).toEqual([]);
    });

    it("a cold rebuild with the entitlement gone forgets the previously published set (no stale advertise)", async () => {
      entitled();
      github(false);
      await realSdkQueryFactory(makeArgs());
      expect(getCcRegisteredReadTools("user-1", "conv-1")).toHaveLength(6);
      entitled({ entitled: false });
      await realSdkQueryFactory(makeArgs());
      expect(getCcRegisteredReadTools("user-1", "conv-1")).toEqual([]);
    });

    // The production `revalidate` closure (not a seam): driven through a registered tool's handler.
    async function callReadIssue() {
      return tools().find((t) => t.name === "github_read_issue")!.handler({ issue_number: 1 });
    }
    const githubCalls = () => mockGithubApiGet.mock.calls.length;

    it("revalidate POSITIVE CONTROL: with the repo and installation unchanged the read goes through (a constant-false closure fails here)", async () => {
      entitled();
      github(false);
      await realSdkQueryFactory(makeArgs());
      const before = githubCalls();
      await callReadIssue().catch(() => undefined);
      expect(githubCalls()).toBeGreaterThan(before); // it reached GitHub (the mocked answer shape is irrelevant)
    });

    it.each([
      ["a different OWNER, same repo name", () => mockGetCurrentRepoUrl.mockResolvedValue("https://github.com/other-org/kb-repo")],
      ["the same owner, a different repo", () => mockGetCurrentRepoUrl.mockResolvedValue("https://github.com/acme/another-repo")],
      ["the same repo, a different installation", () => mockResolveInstallationId.mockResolvedValue(111222)],
    ])("revalidate refuses a REAL switch (%s): fixed text, no GitHub request, RepoChanged", async (_n, change) => {
      entitled();
      github(false);
      await realSdkQueryFactory(makeArgs());
      change();
      const before = githubCalls();
      const res = await callReadIssue();
      expect(res.isError).toBe(true);
      expect(res.content[0].text).toContain("the connected repository changed; start a new conversation");
      expect(githubCalls()).toBe(before);
    });

    it.each([
      ["a degraded repo read WITH a matching url (the url alone would pass)", () => mockReadCurrentRepoUrlResult.mockResolvedValue({ url: REPO_URL, degraded: true })],
      ["the installation lookup returns null", () => mockResolveInstallationId.mockResolvedValue(null)],
    ])("revalidate answers UNVERIFIABLE (not 'changed') for %s: its own text, no GitHub request", async (_n, blip) => {
      entitled();
      github(false);
      await realSdkQueryFactory(makeArgs());
      blip();
      const before = githubCalls();
      const res = await callReadIssue();
      expect(res.isError).toBe(true);
      expect(res.content[0].text).toContain("could not confirm the connected repository right now");
      expect(res.content[0].text).not.toContain("changed; start a new conversation");
      expect(githubCalls()).toBe(before);
    });

    it("concurrent tool calls of one turn share ONE in-flight revalidation (no parallel tenant mints)", async () => {
      entitled();
      github(false);
      await realSdkQueryFactory(makeArgs());
      mockReadCurrentRepoUrlResult.mockClear();
      mockResolveInstallationId.mockClear();
      await Promise.all([callReadIssue().catch(() => 0), callReadIssue().catch(() => 0), callReadIssue().catch(() => 0)]);
      expect(mockReadCurrentRepoUrlResult).toHaveBeenCalledTimes(1);
      expect(mockResolveInstallationId).toHaveBeenCalledTimes(1);
      // and the next call re-checks (the check is not cached beyond the in-flight window)
      await callReadIssue().catch(() => 0);
      expect(mockReadCurrentRepoUrlResult).toHaveBeenCalledTimes(2);
    });

    it("push registration and read registration compose: narrate, summarize, push, then the six reads", async () => {
      entitled();
      mockApprovalFlag.mockResolvedValue(true);
      github(false);
      await realSdkQueryFactory(makeArgs());
      expect(toolNames()).toEqual(["narrate", "summarize", "github_push_branch", ...READ_SHORT]);
      expect(ccCtx().platformToolNames).toEqual(["mcp__soleur_platform__github_push_branch", ...READ_FQNS]);
    });
  });

  // -------------------------------------------------------------------------
  // #10455 (a) / A4 — the AF_UNIX-deny flag reaches BOTH builders through buildAgentQueryOptions, and an egress session
  // never waits on the flag (the variant is no-egress only, so the answer cannot change its artifact).
  // -------------------------------------------------------------------------
  describe("AF_UNIX-deny flag wiring (A4)", () => {
    const envOpts = () => mockBuildAgentEnv.mock.calls[0][2];
    const sandboxOpts = () => mockBuildAgentSandboxConfig.mock.calls[0][1];

    it("no-egress dispatch + flag ON → sandboxUnixDeny:true reaches buildAgentEnv AND buildAgentSandboxConfig", async () => {
      mockResolveSandboxUnixDeny.mockResolvedValue(true);
      await realSdkQueryFactory(makeArgs());
      expect(mockResolveSandboxUnixDeny).toHaveBeenCalledTimes(1);
      expect(envOpts().sandboxUnixDeny).toBe(true);
      expect(sandboxOpts().sandboxUnixDeny).toBe(true);
    });

    it("no-egress dispatch + flag OFF → false in both", async () => {
      mockResolveSandboxUnixDeny.mockResolvedValue(false);
      await realSdkQueryFactory(makeArgs());
      expect(envOpts().sandboxUnixDeny).toBe(false);
      expect(sandboxOpts().sandboxUnixDeny).toBe(false);
    });

    it("GitHub-egress dispatch (minted token) → false in both, and the resolver is NEVER called", async () => {
      mockResolveSandboxUnixDeny.mockResolvedValue(true);
      mockResolveInstallationId.mockResolvedValueOnce(987654);
      mockGenerateInstallationToken.mockResolvedValueOnce("ghs_minted_xyz");
      await realSdkQueryFactory(makeArgs());
      expect(envOpts().ghToken).toBe("ghs_minted_xyz");
      expect(envOpts().sandboxUnixDeny).toBe(false);
      expect(sandboxOpts().sandboxUnixDeny).toBe(false);
      expect(mockResolveSandboxUnixDeny).not.toHaveBeenCalled();
    });

    it("web-egress dispatch (forwarder handle) → false in both, and the resolver is NEVER called", async () => {
      mockResolveSandboxUnixDeny.mockResolvedValue(true);
      mockResolveWebEgress.mockResolvedValue(true);
      mockSpawnEgressForwarder.mockResolvedValue({ port: 28711, token: "tok-abc", pid: 4242 });
      await realSdkQueryFactory(makeArgs());
      expect(envOpts().egressProxy).toMatchObject({ token: "tok-abc" });
      expect(envOpts().sandboxUnixDeny).toBe(false);
      expect(sandboxOpts().sandboxUnixDeny).toBe(false);
      expect(mockResolveSandboxUnixDeny).not.toHaveBeenCalled();
    });

    it("a degraded-to-zero-egress web dispatch (forwarder spawn failed) is a no-egress session and DOES read the flag", async () => {
      mockResolveSandboxUnixDeny.mockResolvedValue(true);
      mockResolveWebEgress.mockResolvedValue(true);
      mockSpawnEgressForwarder.mockRejectedValue(new Error("bind boom"));
      await realSdkQueryFactory(makeArgs());
      expect(mockResolveSandboxUnixDeny).toHaveBeenCalledTimes(1);
      expect(envOpts().sandboxUnixDeny).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // ADR-044 PR-1 (FR1/TR1) — unified-resolve threading. The membership-verified
  // activeWorkspaceId must reach ALL workspace-keyed consumers (path/install/
  // repo/status), so the agent CWD, repo, install, and self-heal key to ONE id.
  // -------------------------------------------------------------------------
  it("threads the resolved TEAM id into install + repo + status consumers (no second divergent resolve)", async () => {
    const teamWs = "team-ws-99";
    mockResolveActiveWorkspace.mockResolvedValueOnce({
      ok: true,
      workspaceId: teamWs,
    });
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockResolvedValueOnce("ghs_team");

    await realSdkQueryFactory(makeArgs());

    expect(mockResolveInstallationId).toHaveBeenCalledWith("user-1", teamWs);
    expect(mockGetCurrentRepoUrl).toHaveBeenCalledWith("user-1", teamWs);
    expect(mockGetCurrentRepoStatus).toHaveBeenCalledWith("user-1", teamWs);
  });

  it("db-error from resolveActiveWorkspace blocks dispatch (WorkspaceNotReadyError, no SDK query)", async () => {
    mockResolveActiveWorkspace.mockResolvedValueOnce({
      ok: false,
      reason: "db-error",
    });

    await expect(realSdkQueryFactory(makeArgs())).rejects.toMatchObject({
      name: "WorkspaceNotReadyError",
    });
    expect(mockQuery).not.toHaveBeenCalled();
  });

  // -------------------------------------------------------------------------
  // Item 1d/1e — in-sandbox git GIT_ASKPASS wiring (plan §Phase 1)
  // -------------------------------------------------------------------------
  it("item1d: connected repo → writes a fixed-name askpass helper under the workspace exactly once", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockResolvedValueOnce("ghs_minted_xyz");

    await realSdkQueryFactory(makeArgs());

    // The helper is written under the user's OWN workspace (the only verified
    // sandbox-readable allowWrite dir) — NOT $HOME/$TMPDIR — with a FIXED name
    // so it is reused per workspace (no accumulation, no cleanup lifecycle).
    // WORKSPACE_PATH/.git does not exist in the test, so the dir is the
    // workspace root; in prod with a cloned repo it is `<workspace>/.git`.
    expect(mockWriteAskpassScriptTo).toHaveBeenCalledTimes(1);
    expect(mockWriteAskpassScriptTo).toHaveBeenCalledWith(
      WORKSPACE_PATH,
      ".soleur-askpass.sh",
    );
    // And the writer's resolved path is threaded into buildAgentEnv (not a
    // vacuous "env exists" check — assert the askpass path actually flows).
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      expect.objectContaining({
        gitAskpassScriptPath: `${WORKSPACE_PATH}/.askpass-fixed-test.sh`,
        gitInstallationToken: "ghs_minted_xyz",
      }),
    );
  });

  it("item1d: no connected repo (null installation) → NO askpass write, gitAskpassScriptPath undefined", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(null);

    await realSdkQueryFactory(makeArgs());

    expect(mockWriteAskpassScriptTo).not.toHaveBeenCalled();
    // buildAgentEnv receives undefined askpass inputs (both-or-nothing → the
    // GIT_* set is never injected for a no-repo dispatch).
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      {},
      {
        ghToken: undefined,
        gitAskpassScriptPath: undefined,
        gitInstallationToken: undefined,
        pluginPath: "/app/shared/plugins/soleur",
        claudeTmpDir: expect.stringMatching(/^\/tmp\/\.cs\/[0-9a-f]{16}$/), sandboxUnixDeny: false,
      },
    );
  });

  it("item1d: mint failure → NO askpass write (no token to ride GIT_INSTALLATION_TOKEN)", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockRejectedValueOnce(new Error("mint boom"));

    await realSdkQueryFactory(makeArgs());

    expect(mockWriteAskpassScriptTo).not.toHaveBeenCalled();
  });

  it("item1e: the askpass-helper path is the ONLY place the credential is wired — token never embedded in a remote URL or argv", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockResolvedValueOnce("ghs_minted_xyz");

    await realSdkQueryFactory(makeArgs());

    // The minted token must NOT appear in the askpass-writer arguments (it
    // takes only the dir); it rides GIT_INSTALLATION_TOKEN env, set by
    // buildAgentEnv. Synthesized-fixture invariant per cq-test-fixtures-synthesized-only.
    for (const call of mockWriteAskpassScriptTo.mock.calls) {
      expect(JSON.stringify(call)).not.toContain("ghs_minted_xyz");
    }
    // The clone/remote URL path lives in ensure-workspace-repo (mocked here);
    // git-auth's own suite pins "token NEVER appears in execFile args". This
    // assertion pins that the cc wiring passes only the workspace dir + the
    // fixed helper name — never the token.
    expect(mockWriteAskpassScriptTo).toHaveBeenCalledWith(
      WORKSPACE_PATH,
      ".soleur-askpass.sh",
    );
  });

  it("AC1: no connected repo (null installation) → no mint, ghToken undefined, dispatch proceeds", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(null);

    await realSdkQueryFactory(makeArgs());

    expect(mockGenerateInstallationToken).not.toHaveBeenCalled();
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      {},
      { ghToken: undefined, pluginPath: "/app/shared/plugins/soleur", claudeTmpDir: expect.stringMatching(/^\/tmp\/\.cs\/[0-9a-f]{16}$/), sandboxUnixDeny: false },
    );
    expect(mockQuery).toHaveBeenCalledOnce();
  });

  it("AC4: mint failure mirrors to Sentry (op:mint-gh-token) and dispatch continues without GH_TOKEN", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockRejectedValueOnce(new Error("mint boom"));

    await realSdkQueryFactory(makeArgs());

    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "cc-dispatcher", op: "mint-gh-token" }),
    );
    // Non-fatal: dispatch still happens, ghToken undefined.
    expect(mockQuery).toHaveBeenCalledOnce();
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      {},
      { ghToken: undefined, pluginPath: "/app/shared/plugins/soleur", claudeTmpDir: expect.stringMatching(/^\/tmp\/\.cs\/[0-9a-f]{16}$/), sandboxUnixDeny: false },
    );
  });

  // -------------------------------------------------------------------------
  // feat-one-shot-concierge-gh-403 — installation self-heal (the load-bearing
  // fix). Stored install is a cross-account personal install; the dispatch
  // mints for the ENTITLED repo-owner install via the GitHub-App-JWT path only
  // (NO service-role). The user's login is derived from the stored personal
  // install's account; no persist (in-memory override per dispatch).
  // -------------------------------------------------------------------------
  describe("installation self-heal", () => {
    const REPO = "https://github.com/jikig-ai/soleur";
    const STORED = 130018654; // personal install (issues:read)
    const OWNER = 122213433; // org install (issues:write)

    it("mismatch (personal stored install) → mints the entitled owner install for this dispatch", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      // Stored is the user's PERSONAL install — its login IS the user's GH login.
      mockGetInstallationAccount.mockResolvedValueOnce({ login: "Elvalio", id: STORED, type: "User" });
      mockFindRepoOwnerInstallationForUser.mockResolvedValueOnce({ installationId: OWNER, outcome: "member" });

      await realSdkQueryFactory(makeArgs());

      // The user's login passed to the entitlement gate is derived from the
      // stored install's account (no service-role admin lookup).
      expect(mockFindRepoOwnerInstallationForUser).toHaveBeenCalledWith(
        "jikig-ai",
        "Elvalio",
      );
      // Load-bearing: GH_TOKEN minted for the OWNER install, not the stored one.
      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        OWNER,
        expect.anything(),
      );
      expect(mockGenerateInstallationToken).not.toHaveBeenCalledWith(
        STORED,
        expect.anything(),
      );
      // AC1 (regression): the workspace CLONE must also receive the self-healed
      // OWNER install — not the stored one. Before the fix the clone ran with
      // STORED, 403'd on the org repo, and left the workspace `.git`-less
      // ("No Git Repository in Workspace"). This is the load-bearing assertion.
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: OWNER }),
      );
      expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalledWith(
        expect.objectContaining({ installationId: STORED }),
      );
    });

    it("negative control: stored install already owns the repo → NO owner probe, mints stored", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(OWNER);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      // Stored account already matches the owner → cheap guard short-circuits.
      mockGetInstallationAccount.mockResolvedValueOnce({ login: "jikig-ai", id: OWNER, type: "Organization" });

      await realSdkQueryFactory(makeArgs());

      expect(mockFindRepoOwnerInstallationForUser).not.toHaveBeenCalled();
      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        OWNER,
        expect.anything(),
      );
      // AC3 + AC5: the no-op (already-owning) path is unaffected — here the
      // stored install IS the owner (resolveInstallationId → OWNER), so clone +
      // mint both use OWNER and no promotion probe runs.
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: OWNER }),
      );
    });

    it("entitlement denied (findRepoOwnerInstallationForUser → null) → keeps stored install + mirrors the skip (Bug B)", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      mockGetInstallationAccount.mockResolvedValueOnce({ login: "outside-user", id: STORED, type: "User" });
      mockFindRepoOwnerInstallationForUser.mockResolvedValueOnce({ installationId: null, outcome: "not-member" }); // not an org member

      await realSdkQueryFactory(makeArgs());

      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        STORED,
        expect.anything(),
      );
      // The deny is a QUERYABLE Sentry event (null err → captureMessage), with
      // the 4-field payload (Bug B, AC4).
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({
          feature: "cc-dispatcher",
          op: "self-heal-skip",
          extra: expect.objectContaining({
            storedInstallationId: STORED,
            owner: "jikig-ai",
            membershipProbeOutcome: "not-member",
            effectiveInstallationId: STORED,
          }),
        }),
      );
      // AC2 (fail-closed proof): promotion was DENIED, so the clone gets the
      // STORED install — exactly what it used before the fix. The hoist can
      // never widen the clone's access beyond the existing entitlement gate.
      // The mint (asserted above) gets STORED too — clone + mint in lockstep.
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: STORED }),
      );
    });

    it("org-type stored install (login != owner) → keeps stored (fail-safe, no probe) + mirrors the skip", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      // Stored is an ORG install for a DIFFERENT org → user login not derivable
      // without a service-role admin lookup → keep stored, never probe.
      mockGetInstallationAccount.mockResolvedValueOnce({ login: "some-other-org", id: STORED, type: "Organization" });

      await realSdkQueryFactory(makeArgs());

      expect(mockFindRepoOwnerInstallationForUser).not.toHaveBeenCalled();
      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        STORED,
        expect.anything(),
      );
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({
          feature: "cc-dispatcher",
          op: "self-heal-skip",
          extra: expect.objectContaining({
            membershipProbeOutcome: "org-type-stored-install",
            effectiveInstallationId: STORED,
          }),
        }),
      );
      // Fail-safe org-type path keeps the clone on the stored install too.
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: STORED }),
      );
    });

    it("probe failure (getInstallationAccount throws) → keeps stored install, mirrors to Sentry, dispatch proceeds", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      mockGetInstallationAccount.mockRejectedValueOnce(new Error("probe boom"));

      await realSdkQueryFactory(makeArgs());

      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          feature: "cc-dispatcher",
          op: "installation-self-heal-probe",
        }),
      );
      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        STORED,
        expect.anything(),
      );
      expect(mockQuery).toHaveBeenCalledOnce();
      // AC4: a self-heal probe failure now PRECEDES the clone (the hoist moved
      // the probe above ensureWorkspaceRepoCloned). The probe's try/catch keeps
      // effectiveInstallationId === STORED, so the clone STILL runs — the probe
      // is not a new clone-blocking dependency.
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: STORED }),
      );
    });

    it("AC6: self-heal deny path never serializes a GitHub token into Sentry or clone args", async () => {
      // The hoist relocates existing log.* / reportSilentFallback calls verbatim.
      // Guard that the move did not inline a minted token into a payload
      // (hr-github-app-auth-not-pat). Drive the deny path so the skip mirror fires.
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      mockGetInstallationAccount.mockResolvedValueOnce({ login: "outside-user", id: STORED, type: "User" });
      mockFindRepoOwnerInstallationForUser.mockResolvedValueOnce({ installationId: null, outcome: "not-member" });
      mockGenerateInstallationToken.mockResolvedValueOnce("ghs_secret_minted_token_value");

      await realSdkQueryFactory(makeArgs());

      // Positive control: the mint actually ran and produced a ghs_-shaped token
      // in this dispatch, so the negative scan below is meaningful — the payloads
      // are clean because the token was redacted/never-logged, NOT vacuously clean
      // because no token ever materialized.
      expect(mockGenerateInstallationToken).toHaveBeenCalled();

      const serialized = JSON.stringify([
        ...mockReportSilentFallback.mock.calls,
        ...mockEnsureWorkspaceRepoCloned.mock.calls,
      ]);
      expect(serialized).not.toMatch(/ghs_|gho_|ghp_/);
    });
  });

  // -------------------------------------------------------------------------
  // Sandbox GitHub egress lockstep (#5041 follow-up) — egress and the
  // entitled token move together. The sandbox-config mock delegates to the
  // REAL implementation in this block so the assertions reach the actual
// Expected signed-URL account fleet, generated locally (NOT imported from the
// source const) so a typo in the source list cannot self-verify: sa0..sa99
// minus sa22 (NXDOMAIN — see the docblock on GITHUB_ACTIONS_LOG_ACCOUNTS).
const EXPECTED_SA_ACCOUNTS = Array.from(
  { length: 100 },
  (_, i) => `productionresultssa${i}.blob.core.windows.net`,
).filter((h) => h !== "productionresultssa22.blob.core.windows.net");

  // allowedDomains the SDK receives (call-arg pinning alone cannot prove
  // the flag maps to the GitHub hosts).
  // -------------------------------------------------------------------------
  describe("sandbox GitHub egress lockstep (#5041 follow-up)", () => {
    const REPO = "https://github.com/jikig-ai/soleur";
    const STORED = 130018654; // personal install
    const OWNER = 122213433; // org install

    beforeEach(async () => {
      const actual = await vi.importActual<
        typeof import("@/server/agent-runner-sandbox-config")
      >("@/server/agent-runner-sandbox-config");
      mockBuildAgentSandboxConfig.mockImplementation(
        actual.buildAgentSandboxConfig,
      );
    });

    it("mismatch promotion → OWNER-install mint AND GitHub egress, in one test (lockstep)", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      mockGetInstallationAccount.mockResolvedValueOnce({
        login: "Elvalio",
        id: STORED,
        type: "User",
      });
      mockFindRepoOwnerInstallationForUser.mockResolvedValueOnce({
        installationId: OWNER,
        outcome: "member",
      });

      await realSdkQueryFactory(makeArgs());

      // (a) token minted for the entitled OWNER install (existing :727 style)
      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        OWNER,
        expect.anything(),
      );
      // (b) the SAME dispatch opens GitHub egress — the two move in lockstep.
      expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH, {
        allowGithubEgress: true, sandboxUnixDeny: false,
        readOnly: false,
        // #9534 — unentitled dispatch (webEgress grant off).
        allowWebEgress: false,
      });
      const opts = mockQuery.mock.calls[0][0].options;
      // Literal on purpose (canonical-literal style, do not import the
      // const) — an import would make a typo in the const self-verify.
      expect(opts.sandbox.network.allowedDomains).toEqual([
        "github.com",
        "api.github.com",
        "registry.npmjs.org",
        ...EXPECTED_SA_ACCOUNTS,
      ]);
    });

    it("fail-closed: no connected repo → no token AND sandbox fully closed", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(null);

      await realSdkQueryFactory(makeArgs());

      expect(mockGenerateInstallationToken).not.toHaveBeenCalled();
      expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH, {
        allowGithubEgress: false, sandboxUnixDeny: false,
        readOnly: false,
        // #9534 — entitlement-derived quarantine flag (unentitled → false).
        allowWebEgress: false,
      });
      const opts = mockQuery.mock.calls[0][0].options;
      expect(opts.sandbox.network.allowedDomains).toEqual([]);
    });

    it("fail-closed: mint failure → dispatch continues, egress collapses with the token", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(987654);
      mockGenerateInstallationToken.mockRejectedValueOnce(
        new Error("mint boom"),
      );

      await realSdkQueryFactory(makeArgs());

      expect(mockQuery).toHaveBeenCalledOnce();
      expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH, {
        allowGithubEgress: false, sandboxUnixDeny: false,
        readOnly: false,
        // #9534 — entitlement-derived quarantine flag (unentitled → false).
        allowWebEgress: false,
      });
      const opts = mockQuery.mock.calls[0][0].options;
      expect(opts.sandbox.network.allowedDomains).toEqual([]);
      // The token half of the lockstep: env got no ghToken either.
      expect(mockBuildAgentEnv).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        expect.objectContaining({ ghToken: undefined }),
      );
    });

    it("posture log emits boolean-only payload — never the token value", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(987654);
      // beforeEach default mint resolves "ghs_default_test_token".

      await realSdkQueryFactory(makeArgs());

      const postureCalls = mockLogInfo.mock.calls.filter(
        ([, msg]) => msg === "Concierge sandbox GitHub egress posture",
      );
      expect(postureCalls).toHaveLength(1);
      const payload = postureCalls[0][0];
      // #9558 — persona joined the posture payload (attribution axis).
      expect(payload).toEqual({
        userId: "user-1",
        githubEgress: true,
        persona: "command_center",
      });
      expect(typeof payload.githubEgress).toBe("boolean");
      expect(JSON.stringify(payload)).not.toContain("ghs_default_test_token");
    });

    it("no-token dispatch appends the GitHub-access-unavailable prompt addendum", async () => {
      // beforeEach default: no connected repo → no mint, no token.
      await realSdkQueryFactory(makeArgs());

      const opts = mockQuery.mock.calls[0][0].options;
      expect(opts.systemPrompt).toContain(
        "GitHub access unavailable in this session",
      );
      // Posture log mirrors the closed state.
      const postureCalls = mockLogInfo.mock.calls.filter(
        ([, msg]) => msg === "Concierge sandbox GitHub egress posture",
      );
      expect(postureCalls).toHaveLength(1);
      expect(postureCalls[0][0]).toEqual({
        userId: "user-1",
        githubEgress: false,
        persona: "command_center",
      });
    });

    it("token dispatch does NOT carry the GitHub-access-unavailable addendum", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(987654);

      await realSdkQueryFactory(makeArgs());

      const opts = mockQuery.mock.calls[0][0].options;
      expect(opts.systemPrompt).not.toContain(
        "GitHub access unavailable in this session",
      );
    });
  });

  // -------------------------------------------------------------------------
  // #5394 — repo-readiness gate (Layer A). The factory throws RepoNotReadyError
  // for a cloning/error workspace BEFORE ensureWorkspaceRepoCloned and before
  // the SDK query() spawn (AC1 no-spawn); a `ready` workspace flows UNCHANGED
  // into the self-heal (AC6 — proves the reclaim path is not short-circuited).
  // The gate keys on repo_status, never `.git` presence.
  // -------------------------------------------------------------------------
  describe("repo-readiness gate (#5394)", () => {
    it("AC1: cloning → throws RepoNotReadyError BEFORE ensureWorkspaceRepoCloned and BEFORE query() (no spawn)", async () => {
      const { RepoNotReadyError } = await import("@/server/repo-readiness");
      mockGetCurrentRepoStatus.mockResolvedValueOnce({
        repoStatus: "cloning",
        repoError: null,
      });

      await expect(realSdkQueryFactory(makeArgs())).rejects.toBeInstanceOf(
        RepoNotReadyError,
      );

      // The load-bearing AC1 assertion — the agent is never spawned and the
      // self-heal clone is never attempted against a not-ready workspace.
      expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
      expect(mockQuery).not.toHaveBeenCalled();
    });

    it("AC1: the thrown cloning error carries code=cloning and NO errorCode", async () => {
      const { RepoNotReadyError } = await import("@/server/repo-readiness");
      mockGetCurrentRepoStatus.mockResolvedValueOnce({
        repoStatus: "cloning",
        repoError: null,
      });

      let err: unknown;
      try {
        await realSdkQueryFactory(makeArgs());
      } catch (e) {
        err = e;
      }
      expect(err).toBeInstanceOf(RepoNotReadyError);
      const cloningErr = err as InstanceType<typeof RepoNotReadyError>;
      expect(cloningErr.code).toBe("cloning");
      expect(cloningErr.errorCode).toBeUndefined();
      expect(cloningErr.message).toContain("still being set up");
    });

    it("AC2: error → throws with code=error + errorCode=repo_setup_failed (reason from users.repo_error)", async () => {
      const { RepoNotReadyError } = await import("@/server/repo-readiness");
      mockGetCurrentRepoStatus.mockResolvedValueOnce({
        repoStatus: "error",
        repoError: JSON.stringify({
          code: "AUTH_FAILED",
          message: "Authentication failed",
        }),
      });

      let err: unknown;
      try {
        await realSdkQueryFactory(makeArgs());
      } catch (e) {
        err = e;
      }
      expect(err).toBeInstanceOf(RepoNotReadyError);
      const errorErr = err as InstanceType<typeof RepoNotReadyError>;
      expect(errorErr.code).toBe("error");
      expect(errorErr.errorCode).toBe("repo_setup_failed");
      expect(errorErr.message).toContain("Authentication failed");
      expect(errorErr.message).toContain("Reconnect in Settings → Repository");
      expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
      expect(mockQuery).not.toHaveBeenCalled();
    });

    it("AC6: ready → gate does NOT throw; ensureWorkspaceRepoCloned IS reached (reclaim/self-heal not short-circuited)", async () => {
      // beforeEach default is `ready`; assert it flows into the self-heal.
      await realSdkQueryFactory(makeArgs());
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledOnce();
      expect(mockQuery).toHaveBeenCalledOnce();
    });

    it("fail-open: a not_connected workspace is NOT blocked (flows to the existing repo-less path)", async () => {
      mockGetCurrentRepoStatus.mockResolvedValueOnce({
        repoStatus: "not_connected",
        repoError: null,
      });
      await realSdkQueryFactory(makeArgs());
      expect(mockQuery).toHaveBeenCalledOnce();
    });
  });

  // -------------------------------------------------------------------------
  // T10: patchWorkspacePermissions runs once per cold factory call
  // -------------------------------------------------------------------------
  it("T10: patchWorkspacePermissions fires once per factory invocation", async () => {
    await realSdkQueryFactory(makeArgs());
    expect(mockPatchWorkspacePermissions).toHaveBeenCalledOnce();
    expect(mockPatchWorkspacePermissions).toHaveBeenCalledWith(WORKSPACE_PATH);
  });

  // -------------------------------------------------------------------------
  // T2 (ADR-113): support persona bypasses the repo-lifecycle and runs read-only
  // at the plugin docs root. The mirror of T10 — patchWorkspacePermissions must
  // NOT run — plus cwd + read-only sandbox + kb-search-only skills.
  // -------------------------------------------------------------------------
  it("T2: support persona skips patchWorkspacePermissions and runs read-only at the plugin root", async () => {
    await realSdkQueryFactory(makeArgs({ persona: "support" }));

    // Repo-lifecycle write op is NOT invoked for support (contrast T10).
    expect(mockPatchWorkspacePermissions).not.toHaveBeenCalled();

    const opts = mockQuery.mock.calls[0][0].options;
    // cwd is the boot-validated plugin docs root, not the user's workspace.
    expect(opts.cwd).toBe("/app/shared/plugins/soleur");
    // SDK skills scoped to kb-search only (support surface).
    expect(opts.skills).toEqual(["kb-search"]);

    // Sandbox built read-only, at the plugin root — allowWrite:[] is enforced
    // inside buildAgentSandboxConfig (unit-tested T3 in agent-runner-query-options).
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(
      "/app/shared/plugins/soleur",
      expect.objectContaining({
        allowGithubEgress: false, sandboxUnixDeny: false,
        readOnly: true,
        // Internal KB obscured from the read-only support session (containment).
        denyReadExtra: ["/app/shared/knowledge-base"],
      }),
    );
  });

  // -------------------------------------------------------------------------
  // #9558 — support persona must mint NOTHING GitHub-side: a read-only docs
  // session has no repo lifecycle, so installation resolution, the GH_TOKEN
  // mint, the .soleur-askpass.sh write into the user's .git/, and the
  // ENTITLED_EGRESS_DOMAINS open are ALL out of contract. Drive the same
  // connected-repo shape that mints on command_center — the persona must be
  // the only delta.
  // -------------------------------------------------------------------------
  it("T2b: support persona skips installation resolve, GH_TOKEN mint, askpass write, and GitHub egress", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockResolvedValueOnce("ghs_minted_xyz");

    await realSdkQueryFactory(makeArgs({ persona: "support" }));

    // No GitHub machinery at all — not even the installation-id resolve or
    // the clone (it mints a token via gitWithInstallationAuth internally).
    expect(mockResolveInstallationId).not.toHaveBeenCalled();
    expect(mockGetInstallationAccount).not.toHaveBeenCalled();
    expect(mockFindRepoOwnerInstallationForUser).not.toHaveBeenCalled();
    expect(mockGenerateInstallationToken).not.toHaveBeenCalled();
    expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
    // No askpass helper is ever written under the user's .git/.
    expect(mockWriteAskpassScriptTo).not.toHaveBeenCalled();
    // The minted-token channel into the agent env stays empty.
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      {},
      { ghToken: undefined, pluginPath: "/app/shared/plugins/soleur", claudeTmpDir: expect.stringMatching(/^\/tmp\/\.cs\/[0-9a-f]{16}$/), sandboxUnixDeny: false },
    );
    // Egress closed (also pinned in T2 via the sandbox-config call).
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(
      "/app/shared/plugins/soleur",
      expect.objectContaining({ allowGithubEgress: false }),
    );
    // The egress posture log carries the persona so a support dispatch that
    // ever DID open egress is attributable (observability gate).
    const egressLog = mockLogInfo.mock.calls.find(
      ([, msg]) => msg === "Concierge sandbox GitHub egress posture",
    );
    expect(egressLog?.[0]).toMatchObject({
      githubEgress: false,
      persona: "support",
    });
  });

  it("T2c: support persona strips the user's stored GITHUB_TOKEN from serviceTokens (env must carry no GitHub credential)", async () => {
    // #9558 review: a write-closed sandbox still received the user's own
    // GITHUB_TOKEN via the Connected-Services map — readable in-env and
    // echoable into the transcript while every GitHub egress domain is
    // closed. The strip is provider-specific: other service tokens stay.
    mockGetUserServiceTokens.mockResolvedValueOnce({
      GITHUB_TOKEN: "ghp_stored_user_pat",
      STRIPE_SECRET_KEY: "sk_live_other",
    });

    await realSdkQueryFactory(makeArgs({ persona: "support" }));

    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      { STRIPE_SECRET_KEY: "sk_live_other" },
      { ghToken: undefined, pluginPath: "/app/shared/plugins/soleur", claudeTmpDir: expect.stringMatching(/^\/tmp\/\.cs\/[0-9a-f]{16}$/), sandboxUnixDeny: false },
    );
  });

  it("T2d: command_center keeps the stored GITHUB_TOKEN (strip is support-scoped)", async () => {
    mockGetUserServiceTokens.mockResolvedValueOnce({
      GITHUB_TOKEN: "ghp_stored_user_pat",
    });
    mockResolveInstallationId.mockResolvedValueOnce(987654);

    await realSdkQueryFactory(makeArgs({ persona: "command_center" }));

    const envArgs = mockBuildAgentEnv.mock.calls[0];
    expect(envArgs[1]).toMatchObject({ GITHUB_TOKEN: "ghp_stored_user_pat" });
  });

  // -------------------------------------------------------------------------
  // T16: sandbox-required-but-unavailable substring → feature: "agent-sandbox"
  // (filtered by feature tag per learning
  // 2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md)
  // -------------------------------------------------------------------------
  it("T16: sandbox-unavailable error tags Sentry with feature=agent-sandbox (filtered by tag)", async () => {
    const sandboxErr = new Error(
      "Error: sandbox required but unavailable: missing socat",
    );
    mockQuery.mockImplementationOnce(() => {
      throw sandboxErr;
    });

    await expect(realSdkQueryFactory(makeArgs())).rejects.toBe(sandboxErr);

    // Filter by feature tag per learning
    // 2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md
    // — module init can fire other features (e.g. kb-share baseUrl).
    const sandboxCalls = mockReportSilentFallback.mock.calls.filter(
      ([, opts]) => opts?.feature === "agent-sandbox",
    );
    expect(sandboxCalls).toHaveLength(1);
    expect(sandboxCalls[0][1].op).toBe("sdk-startup");
    expect(sandboxCalls[0][1].extra).toMatchObject({
      userId: "user-1",
      conversationId: "conv-1",
      leaderId: "cc_router",
    });
  });

  // -------------------------------------------------------------------------
  // T17 (negative): factory uses buildAgentSandboxConfig (no inline literal)
  // -------------------------------------------------------------------------
  it("T17: factory delegates sandbox shape to buildAgentSandboxConfig (no inline drift)", async () => {
    await realSdkQueryFactory(makeArgs());
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledOnce();
    // No-token dispatch → fail-closed egress (#5041 follow-up).
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH, {
      allowGithubEgress: false, sandboxUnixDeny: false,
      readOnly: false,
      // #9534 — entitlement-derived quarantine flag (unentitled → false).
      allowWebEgress: false,
    });
  });

  // -------------------------------------------------------------------------
  // Resume key: when resumeSessionId provided, options.resume is set.
  // -------------------------------------------------------------------------
  it("threads resumeSessionId into options.resume when present", async () => {
    // #9538 — the cc call site now passes `dropResumeOnEmptyHistory: true`,
    // so the default `[]` probe would drop the resume id. Give the guard a
    // live user-terminated session so `resume:` survives.
    mockGetSessionMessages.mockResolvedValueOnce([
      { type: "user", uuid: "u1", session_id: "sess-abc", message: {}, parent_tool_use_id: null },
    ]);
    await realSdkQueryFactory(makeArgs({ resumeSessionId: "sess-abc" }));
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBe("sess-abc");
  });

  it("omits options.resume when no resumeSessionId provided", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBeUndefined();
  });

  // -------------------------------------------------------------------------
  // T-AC4 (#2920): cc dispatcher writes real conversation status updates.
  // Replaces the prior no-op `ccDeps.updateConversationStatus`. Mirrors
  // `agent-runner.ts:303` shape (status + last_active) and includes the
  // R8 composite-key gate (`.eq("user_id", args.userId)`).
  // -------------------------------------------------------------------------
  describe("T-AC4: ccDeps.updateConversationStatus writes (#2920)", () => {
    function captureUpdateChain() {
      const updateCalls: Array<{
        payload: Record<string, unknown>;
        eqs: Array<[string, unknown]>;
      }> = [];

      mockSupabaseFrom.mockImplementation((table: string) => {
        if (table === "users") {
          return {
            select: () => ({
              eq: () => ({
                single: () => ({
                  data: { workspace_path: WORKSPACE_PATH },
                  error: null,
                }),
                maybeSingle: () => ({
                  data: { workspace_path: WORKSPACE_PATH },
                  error: null,
                }),
              }),
            }),
          };
        }
        if (table === "conversations") {
          return {
            update: (payload: Record<string, unknown>) => {
              const entry = { payload, eqs: [] as Array<[string, unknown]> };
              updateCalls.push(entry);
              const chain: Record<string, unknown> = {
                error: null,
                eq: (col: string, val: unknown) => {
                  entry.eqs.push([col, val]);
                  return chain;
                },
                select: () =>
                  Promise.resolve({ data: [{ id: "conv-1" }], error: null }),
                then: (resolve: (v: unknown) => void) =>
                  resolve({ error: null }),
              };
              return chain;
            },
          };
        }
        return {
          select: () => ({
            eq: () => ({ single: () => ({ data: null, error: null }) }),
          }),
          insert: () => ({ error: null }),
        };
      });
      return updateCalls;
    }

    async function getCcDepsFromFactory() {
      // The factory passes ccDeps via createCanUseTool(ctx). Capture the
      // ctx.deps so we can drive updateConversationStatus directly.
      await realSdkQueryFactory(makeArgs());
      const ctx = (
        createCanUseTool as unknown as { mock: { calls: unknown[][] } }
      ).mock.calls[0][0] as {
        deps: {
          updateConversationStatus: (
            convId: string,
            status: string,
          ) => Promise<void>;
        };
      };
      return ctx.deps;
    }

    it("T-AC4a: writes waiting_for_user with composite-key (.eq id + user_id)", async () => {
      const updateCalls = captureUpdateChain();
      const deps = await getCcDepsFromFactory();

      await deps.updateConversationStatus("conv-1", "waiting_for_user");

      expect(updateCalls).toHaveLength(1);
      expect(updateCalls[0].payload.status).toBe("waiting_for_user");
      // last_active is also written (parity with legacy agent-runner.ts:303)
      expect(typeof updateCalls[0].payload.last_active).toBe("string");
      // R8 composite-key invariant: BOTH id AND user_id must be present
      const cols = updateCalls[0].eqs.map(([c]) => c).sort();
      expect(cols).toEqual(["id", "user_id"]);
      const userIdEq = updateCalls[0].eqs.find(([c]) => c === "user_id");
      expect(userIdEq?.[1]).toBe("user-1");
      const idEq = updateCalls[0].eqs.find(([c]) => c === "id");
      expect(idEq?.[1]).toBe("conv-1");
    });

    it("T-AC4b: writes active on gate resolve (separate update)", async () => {
      const updateCalls = captureUpdateChain();
      const deps = await getCcDepsFromFactory();

      await deps.updateConversationStatus("conv-1", "active");

      expect(updateCalls).toHaveLength(1);
      expect(updateCalls[0].payload.status).toBe("active");
    });

    it("T-AC4c: every status update carries the user_id .eq gate (R8)", async () => {
      const updateCalls = captureUpdateChain();
      const deps = await getCcDepsFromFactory();

      await deps.updateConversationStatus("conv-1", "waiting_for_user");
      await deps.updateConversationStatus("conv-1", "active");

      expect(updateCalls).toHaveLength(2);
      for (const call of updateCalls) {
        const userIdEq = call.eqs.find(([c]) => c === "user_id");
        expect(userIdEq?.[1]).toBe("user-1");
      }
    });

    it("T-AC4d: error from supabase mirrors to reportSilentFallback", async () => {
      mockSupabaseFrom.mockImplementation((table: string) => {
        if (table === "users") {
          return {
            select: () => ({
              eq: () => ({
                single: () => ({
                  data: { workspace_path: WORKSPACE_PATH },
                  error: null,
                }),
                maybeSingle: () => ({
                  data: { workspace_path: WORKSPACE_PATH },
                  error: null,
                }),
              }),
            }),
          };
        }
        if (table === "conversations") {
          return {
            update: () => {
              const chain: Record<string, unknown> = {
                error: new Error("db unavailable"),
                eq: () => chain,
                select: () =>
                  Promise.resolve({
                    data: null,
                    error: new Error("db unavailable"),
                  }),
                then: (resolve: (v: unknown) => void) =>
                  resolve({ error: new Error("db unavailable") }),
              };
              return chain;
            },
          };
        }
        return {
          select: () => ({
            eq: () => ({ single: () => ({ data: null, error: null }) }),
          }),
          insert: () => ({ error: null }),
        };
      });
      const deps = await getCcDepsFromFactory();
      mockReportSilentFallback.mockClear();

      await deps.updateConversationStatus("conv-1", "waiting_for_user");

      const calls = mockReportSilentFallback.mock.calls.filter(
        ([, opts]) => opts?.feature === "cc-dispatcher",
      );
      expect(calls.length).toBeGreaterThanOrEqual(1);
      expect(calls[0][1].op).toBe("updateConversationStatus");
      expect(calls[0][1].extra).toMatchObject({
        userId: "user-1",
        conversationId: "conv-1",
        status: "waiting_for_user",
      });
    });
  });
  // -------------------------------------------------------------------------
  // feat-open-web-egress (#9534) — workspace "Agent web access" grant.
  // -------------------------------------------------------------------------
  describe("web egress entitlement (#9534)", () => {
    it("unentitled (default) → no forwarder spawn, no webEgress handle", async () => {
      await realSdkQueryFactory(makeArgs());
      expect(mockSpawnEgressForwarder).not.toHaveBeenCalled();
      const opts = mockQuery.mock.calls[0][0].options;
      // WebFetch stays disallowed; WebSearch too.
      expect(opts.disallowedTools).toContain("WebFetch");
      expect(opts.disallowedTools).toContain("WebSearch");
      expect(opts.allowedTools).not.toContain("WebFetch");
      expect(mockBuildAgentEnv).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        expect.objectContaining({ egressProxy: undefined }),
      );
      expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ allowWebEgress: false }),
      );
    });

    it("entitled + spawn OK → forwarder spawned for the workspace, handle threaded", async () => {
      mockResolveWebEgress.mockResolvedValue(true);
      mockSpawnEgressForwarder.mockResolvedValue({
        port: 28711,
        token: "tok-abc",
        pid: 4242,
      });
      await realSdkQueryFactory(makeArgs());
      expect(mockSpawnEgressForwarder).toHaveBeenCalledWith(
        "conv-1",
        expect.any(String),
      );
      const opts = mockQuery.mock.calls[0][0].options;
      // WebFetch re-enabled; WebSearch stays disallowed (Phase A).
      expect(opts.disallowedTools).not.toContain("WebFetch");
      expect(opts.disallowedTools).toContain("WebSearch");
      // WebFetch is ask-class: without the auto-approve it would still die at
      // canUseTool's deny-default (agent-native review critical finding).
      expect(opts.allowedTools).toContain("WebFetch");
      // The two security wires the tool-surface change depends on: the
      // credentialed proxy URL reaches the spawned CLI env, and the sandbox
      // credential census engages. Deleting either line in the factory is a
      // silent-bypass regression — pin both.
      expect(mockBuildAgentEnv).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        expect.objectContaining({
          egressProxy: { workspaceId: expect.any(String), token: "tok-abc", port: 28711 },
        }),
      );
      expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ allowWebEgress: true }),
      );
    });

    it("entitled + spawn failure → degrade to zero-egress, mirrored, Query still built", async () => {
      mockResolveWebEgress.mockResolvedValue(true);
      mockSpawnEgressForwarder.mockRejectedValue(new Error("bind boom"));
      await realSdkQueryFactory(makeArgs());
      expect(mockQuery).toHaveBeenCalledOnce();
      const opts = mockQuery.mock.calls[0][0].options;
      expect(opts.disallowedTools).toContain("WebFetch");
      const calls = mockReportSilentFallback.mock.calls.filter(
        ([, o]) => o?.op === "web-egress-forwarder-spawn",
      );
      expect(calls).toHaveLength(1);
    });

    it("entitled but support persona → no forwarder (repo lifecycle is off)", async () => {
      mockResolveWebEgress.mockResolvedValue(true);
      mockSpawnEgressForwarder.mockResolvedValue({
        port: 28711,
        token: "tok-abc",
        pid: 4242,
      });
      await realSdkQueryFactory(makeArgs({ persona: "support" }));
      expect(mockSpawnEgressForwarder).not.toHaveBeenCalled();
    });
  });

  // Agent auth-failure diagnostic (plan Phase 1 items 5 and 6): the cc factory taps the Query it returns and feeds the shared
  // probe. The probe, matcher, tap, context derivation and the real buildAgentQueryOptions are real; the emit is the
  // mocked observability seam; `sdkQuery` is the mock.
  describe("agent auth-failure diagnostic wiring", () => {
    const SEP = "\u00B7";
    const authEmits = () =>
      mockReportSilentFallback.mock.calls.filter((c) => (c[1] as { feature?: string })?.feature === "agent-auth");
    const failureStream = () => [
      { type: "system", subtype: "init", apiKeySource: "none", session_id: "sess-1" },
      {
        type: "assistant",
        message: { model: "<synthetic>", content: [{ type: "text", text: `Not logged in ${SEP} Please run /login` }] },
        error: "authentication_failed",
        is_api_error_message: true,
        session_id: "sess-1",
      },
      { type: "result", subtype: "success", is_error: true, result: `Not logged in ${SEP} Please run /login`, session_id: "sess-1" },
    ];
    const queryStreaming = (messages: unknown[]) => {
      const q = makeFakeQuery();
      q[Symbol.asyncIterator] = async function* () {
        for (const m of messages) yield m;
      };
      return q;
    };
    const drain = async (q: AsyncIterable<unknown>) => {
      const out: unknown[] = [];
      for await (const m of q) out.push(m);
      return out;
    };

    afterEach(() => {
      authDiag.scheme = "api_key";
    });

    beforeEach(() => {
      __resetAgentAuthDedupeForTests();
      authDiag.makeResolver.mockImplementation(() => async () => "managed");
      // The posture the REAL buildAgentSandboxConfig would record (this file mocks the builder).
      mockBuildAgentSandboxConfig.mockReturnValue(
        recordSandboxPosture(
          { enabled: true, filesystem: { allowWrite: [WORKSPACE_PATH], denyRead: ["/workspaces", "/proc"] } },
          { hasEgress: false, unixDenyFlag: false },
        ),
      );
    });

    it("an auth-failure stream emits exactly ONE reportSilentFallback(null, ...) with the cc runner and real context tags", async () => {
      const fake = queryStreaming(failureStream());
      mockQuery.mockReturnValue(fake);
      const q = await realSdkQueryFactory(makeArgs());
      expect(q).toBe(fake); // the tap preserves identity
      expect(await drain(q as unknown as AsyncIterable<unknown>)).toHaveLength(3);

      await vi.waitFor(() => expect(authEmits()).toHaveLength(1));
      const [first, opts] = authEmits()[0] as [unknown, { feature: string; op: string; tags: Record<string, string> }];
      expect(first).toBeNull();
      expect(opts).toMatchObject({ feature: "agent-auth", op: "cli-auth-failure" });
      expect(opts.tags).toMatchObject({
        runner: "cc-soleur-go",
        credential_scheme: "api_key",
        auth_env_present: "true",
        auth_mode: "managed",
        cli_key_source: "none",
        seccomp_artifact: "base",
        has_egress: "false",
        sandbox: "on",
        outer_wrap: "false",
        match_kind: "not_logged_in",
      });
      expect(authDiag.makeResolver).toHaveBeenCalledWith("user-1", "conv-1");
      await new Promise((r) => setTimeout(r, 20));
      expect(authEmits()).toHaveLength(1);
    });

    it("the leased scheme reaches the probe: an oauth_token lease reports credential_scheme=oauth_token and reads the OAuth variable", async () => {
      authDiag.scheme = "oauth_token";
      mockBuildAgentEnv.mockReturnValue({ CLAUDE_CODE_OAUTH_TOKEN: "sk-test-oauth" });
      mockQuery.mockReturnValue(queryStreaming(failureStream()));
      const q = await realSdkQueryFactory(makeArgs());
      await drain(q as unknown as AsyncIterable<unknown>);
      await vi.waitFor(() => expect(authEmits()).toHaveLength(1));
      const opts = authEmits()[0][1] as { tags: Record<string, string> };
      // A hard-coded api_key scheme would read ANTHROPIC_API_KEY (absent here) and report auth_env_present=false.
      expect(opts.tags).toMatchObject({ credential_scheme: "oauth_token", auth_env_present: "true" });
    });

    it("the debounce is per USER: two users with the same tuple each emit once", async () => {
      for (const userId of ["user-a", "user-b"]) {
        mockQuery.mockReturnValue(queryStreaming(failureStream()));
        const q = await realSdkQueryFactory(makeArgs({ userId, conversationId: `conv-${userId}` }));
        await drain(q as unknown as AsyncIterable<unknown>);
      }
      await vi.waitFor(() => expect(authEmits()).toHaveLength(2));
      await new Promise((r) => setTimeout(r, 20));
      expect(authEmits()).toHaveLength(2);
    });

    it("a clean stream emits nothing", async () => {
      mockQuery.mockReturnValue(queryStreaming([{ type: "system", subtype: "init", apiKeySource: "ANTHROPIC_API_KEY" }, { type: "result", subtype: "success", is_error: false, result: "ok" }]));
      const q = await realSdkQueryFactory(makeArgs());
      await drain(q as unknown as AsyncIterable<unknown>);
      await new Promise((r) => setTimeout(r, 20));
      expect(authEmits()).toHaveLength(0);
    });

    it("a throwing probe construction falls back to a working untapped Query and is NOT mirrored as a sandbox failure", async () => {
      authDiag.createProbe.mockImplementationOnce(() => {
        throw new Error("bwrap: Operation not permitted (the diagnostic must not be misreported as this)");
      });
      const fake = queryStreaming(failureStream());
      mockQuery.mockReturnValue(fake);
      const q = await realSdkQueryFactory(makeArgs());
      expect(q).toBe(fake);
      expect(await drain(q as unknown as AsyncIterable<unknown>)).toHaveLength(3);
      await new Promise((r) => setTimeout(r, 20));
      expect(authEmits()).toHaveLength(0);
      const sandboxMirrors = mockReportSilentFallback.mock.calls.filter(
        (c) => (c[1] as { feature?: string; op?: string })?.feature === "agent-sandbox" && (c[1] as { op?: string })?.op === "sdk-startup",
      );
      expect(sandboxMirrors).toHaveLength(0);
    });

    it("source pins: the factory imports the module, creates the probe, wraps the option expression, and returns the tapped Query", async () => {
      const { readFileSync } = await vi.importActual<typeof import("node:fs")>("node:fs");
      const src = readFileSync(new URL("../server/cc-dispatcher.ts", import.meta.url), "utf8");
      expect(src).toMatch(/from "\.\/agent-auth-failure"/);
      expect(src).toContain("createAgentAuthFailureProbe(");
      expect(src).toMatch(/options: authProbe\.bindOptions\(recordCcSeccompArtifact\(/);
      expect(src).toMatch(/return tapAgentAuthFailure\(\s*sdkQuery\(\{/);
      // The construction-failure fallback is visible, not silent.
      expect(src).toMatch(/\} catch \{[^}]*warnAgentAuthProbeUnavailable\(\);/);
    });
  });
});

// ---------------------------------------------------------------------------
// #9776 / ADR-284 — hosted must-ask lane: factory wiring (AC-14, AC-23).
//
// This does NOT claim runtime proof that the real SDK calls `canUseTool` for sandboxed
// Bash (the SDK is mocked here, as everywhere in this file). That proof is the real-SDK
// probe `scripts/dev-probe-destroy-ask.ts` (CLO C9): it FAILED at #9977 (#10054) because
// `autoAllowBashIfSandboxed: true` and the sandbox hook's `allow` pre-empted the callback.
// It pins the wiring: the REAL `createCanUseTool` is the callback
// in the options object (the sandbox value itself is pinned by agent-runner-sandbox-config.test.ts against the REAL
// builder; this file mocks the builder, so asserting it here would only read the mock back),
// `permissions.allow` stays empty, and the lane's inputs come from the dispatch
// scope, never from the empty-string `ctx.repoOwner` / `ctx.repoName`.
// ---------------------------------------------------------------------------
describe("realSdkQueryFactory — hosted must-ask lane wiring (#9776)", () => {
  async function realCanUseToolOptions() {
    const actual = await vi.importActual<typeof import("@/server/permission-callback")>(
      "@/server/permission-callback",
    );
    (createCanUseTool as unknown as { mockImplementationOnce(f: unknown): void }).mockImplementationOnce(
      actual.createCanUseTool,
    );
    await realSdkQueryFactory(makeArgs());
    return mockQuery.mock.calls[0][0].options;
  }

  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUserApiKey.mockResolvedValue("sk-test");
    mockGetUserServiceTokens.mockResolvedValue({});
    mockBuildAgentEnv.mockReturnValue({ ANTHROPIC_API_KEY: "sk-test" });
    mockBuildAgentSandboxConfig.mockReturnValue({
      enabled: true,
      failIfUnavailable: true,
      autoAllowBashIfSandboxed: false,
      allowUnsandboxedCommands: false,
      enableWeakerNestedSandbox: true,
      network: { allowedDomains: [], allowManagedDomainsOnly: true },
      filesystem: { allowWrite: [WORKSPACE_PATH], denyRead: ["/workspaces", "/proc"] },
    });
    mockQuery.mockReturnValue(makeFakeQuery());
    mockResolveInstallationId.mockResolvedValue(null);
    mockGenerateInstallationToken.mockResolvedValue("ghs_default_test_token");
    mockResolveBashAutonomous.mockResolvedValue(true);
    mockResolveAutonomousAck.mockResolvedValue("2026-10-10T00:00:00Z");
    mockResolveIsWorkspaceOwner.mockResolvedValue(true);
    mockResolveActiveWorkspace.mockImplementation(async (userId: string) => ({ ok: true, workspaceId: userId }));
    mockGetCurrentRepoUrl.mockResolvedValue(null);
    mockReadCurrentRepoUrlResult.mockImplementation(async (userId: string, workspaceId: string) => ({
      url: await mockGetCurrentRepoUrl(userId, workspaceId),
      degraded: false,
    }));
    mockGetCurrentRepoStatus.mockResolvedValue({ repoStatus: "ready", repoError: null });
    mockWriteAskpassScriptTo.mockReturnValue(`${WORKSPACE_PATH}/.git/.soleur-askpass.sh`);
  });

  it("AC-14: the real canUseTool is wired, permissions.allow is empty, and a destroy command still reaches the review gate in an acked autonomous workspace", async () => {
    mockSendToClient.mockReturnValue(true);
    // The lane flips the conversation status around the card: give the tenant client a recursive, awaitable chain
    // (`.update().eq().eq()` and `.in()` / `.select()` variants) so that write resolves instead of throwing.
    const chain: Record<string, unknown> = {};
    for (const m of ["update", "eq", "in", "select", "insert"]) chain[m] = () => chain;
    chain.then = (resolve: (v: unknown) => void) => resolve({ error: null, data: [{ id: "conv-1" }] });
    mockSupabaseFrom.mockImplementation((table: string) =>
      table === "conversations" ? chain : { select: () => chain, insert: () => chain, update: () => chain },
    );
    const opts = await realCanUseToolOptions();
    expect(typeof opts.canUseTool).toBe("function");
    expect(opts.settingSources).toEqual([]);
    expect(opts.permissions?.allow ?? []).toEqual([]);

    const ac = new AbortController();
    const pending = opts.canUseTool("Bash", { command: "terraform destroy" }, { signal: ac.signal, toolUseID: "t", requestId: "r" });
    await new Promise((r) => setTimeout(r, 25));
    const frame = mockSendToClient.mock.calls.map((c) => c[1]).find((m: { type: string }) => m.type === "review_gate");
    expect(frame, "the lane must send a review_gate frame, not auto-approve").toBeDefined();
    expect(frame.options).toEqual(["Approve", "Reject"]);
    ac.abort();
    const res = await pending;
    expect(res.behavior).toBe("deny");
  });

  it("AC-23: the lane's inputs come from the dispatch scope (connected repo slug and a resolver), not from ctx.repoOwner / ctx.repoName", async () => {
    mockGetCurrentRepoUrl.mockResolvedValue("https://github.com/alice/app");
    await realSdkQueryFactory(makeArgs());
    const ctx = (createCanUseTool as unknown as { mock: { calls: unknown[][] } }).mock.calls[0][0] as {
      repoOwner: string;
      repoName: string;
      deps: { connectedRepoSlug?: string; resolveProtectedBranches?: () => Promise<unknown> };
    };
    expect(ctx.repoOwner).toBe("");
    expect(ctx.repoName).toBe("");
    expect(ctx.deps.connectedRepoSlug).toBe("alice/app");
    expect(typeof ctx.deps.resolveProtectedBranches).toBe("function");
  });

  it("with no connected repo the slug is empty and the resolver still exists (it resolves unauthoritatively, so every force push asks)", async () => {
    await realSdkQueryFactory(makeArgs());
    const ctx = (createCanUseTool as unknown as { mock: { calls: unknown[][] } }).mock.calls[0][0] as {
      deps: { connectedRepoSlug?: string; resolveProtectedBranches?: () => Promise<{ authoritative: boolean }> };
    };
    expect(ctx.deps.connectedRepoSlug).toBe("");
    const r = await ctx.deps.resolveProtectedBranches!();
    expect(r.authoritative).toBe(false);
  });
});
