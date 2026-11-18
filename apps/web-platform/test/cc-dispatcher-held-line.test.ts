// #12714 (rulings W3, D29(3), D29(5)-(7), V6): the held-files agent line on the cc path, TW3 / TW1-b / TW3-b.
//
// The count comes from the member-checked RPC `get_workspace_kb_sync_held` (migration 187), called in the SAME Promise.all
// and keyed on the SAME activeWorkspaceId the push registration gets; the line is appended in the query factory's
// effectiveSystemPrompt next to c4PromptAddendum, with the variant from the registration result. The mock scaffold is the
// one cc-dispatcher-real-factory.test.ts uses (copied, not shared: vi.mock is hoisted per file), plus a tenant `rpc`.

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
  mockRefreshHeldCount,
  mockGithubApiGet,
  mockHeadSha,
  registrarOverride,
  readRegistrarOverride,
  conversationWriteOverride,
  mockTenantRpc,
} = vi.hoisted(() => ({
  // #12714: the tenant client's rpc, answering get_workspace_kb_sync_held per workspace (the migration-187 RPC).
  mockTenantRpc: vi.fn(),
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
  mockRefreshHeldCount: vi.fn(async () => undefined),
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
  getFreshTenantClient: vi.fn(async () => ({ from: mockSupabaseFrom, rpc: mockTenantRpc })),
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
// #12704 D40(1): the registrar reads the detailed shape; it wraps the same switch (a throw is the module's "error").
vi.mock("@/server/approval/flag", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/approval/flag")>()),
  isApprovalQueueEnabled: mockApprovalFlag,
  readApprovalQueueFlagDetailed: async (identity: unknown) => {
    try {
      return { value: (await mockApprovalFlag(identity)) === true, fellBack: false };
    } catch {
      return "error";
    }
  },
}));

// #12704 D39(a): the close-hook refresh is WP3's; here only the call is observed.
vi.mock("@/server/kb-sync-held-refresh", () => ({ refreshHeldCount: mockRefreshHeldCount }));

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

import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { __resetDispatcherForTests, dispatchSoleurGo, handleCcCloseQuery, realSdkQueryFactory } from "@/server/cc-dispatcher";
import { ccPushPromptAddendum } from "@/server/cc-github-push";
import { buildKbSyncHeldAgentLine, buildKbSyncMergeBlockedAgentLine } from "@/server/kb-sync-held-agent-line";
import { C4_PROMPT_ADDENDUM } from "@/server/c4-concierge-tools";

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


const HELD_HEADING = "## Code changes not on the main branch yet";
const MERGE_HEADING = "## Unfinished merge in this workspace";

describe("cc held-files agent line (#12714)", () => {
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
    // #11764: mirror the real contract — a threaded claudeTmpDir exports
    // CLAUDE_CODE_TMPDIR and routes TMPDIR at the same per-tenant `.cs` base,
    // so the T9/T18 env-shape arm can assert TMPDIR reaches the wire (the
    // factory hands the CLI exactly what buildAgentEnv built).
    mockBuildAgentEnv.mockImplementation((credential, _tokens, opts) => ({
      ANTHROPIC_API_KEY: "sk-test",
      ...(opts?.claudeTmpDir
        ? { CLAUDE_CODE_TMPDIR: opts.claudeTmpDir, TMPDIR: opts.claudeTmpDir }
        : {}),
    }));
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

  const REPO_URL = "https://github.com/acme/kb-repo";
  const CHECKED = "2026-11-17T09:05:41+00:00";
  const prompt = () => mockQuery.mock.calls.at(-1)![0].options.systemPrompt as string;
  const heldReads = () => mockTenantRpc.mock.calls.filter(([fn]) => fn === "get_workspace_kb_sync_held");
  // obs F7: a display-only read failure is a debounced WARNING (mirrorWarnWithDebounce), never an error-level report.
  const heldWarnings = () => mockMirrorWarnWithDebounce.mock.calls.filter(([, o]) => o?.op === "kb-sync-held-read");
  /** Every RPC answer by workspace id; an unknown workspace answers zero rows (the RPC's non-member shape). */
  let rpcByWorkspace: Record<string, unknown>;
  const tmpDirs: string[] = [];

  function held(workspaceId: string, files: unknown, checkedAt: unknown = CHECKED, pullBlocked?: unknown) {
    rpcByWorkspace[workspaceId] = {
      data: [{ kb_sync_held_files: files, kb_sync_held_checked_at: checkedAt, ...(pullBlocked === undefined ? {} : { kb_sync_pull_blocked: pullBlocked }) }],
      error: null,
    };
  }
  const expected = (over: Partial<Parameters<typeof buildKbSyncHeldAgentLine>[0]> = {}) =>
    buildKbSyncHeldAgentLine({ heldFiles: 2, checkedAt: CHECKED, route: "registered", runner: "cc", defaultBranch: "trunk", ...over }) as string;

  /** Push-registration preconditions (flag on, entitled, repo, installation); a test turns one off. */
  function eligible(over: { flag?: unknown; repo?: boolean } = {}) {
    mockApprovalFlag.mockResolvedValue(over.flag === undefined ? true : over.flag);
    mockResolveWebEgress.mockResolvedValue(true);
    if (over.repo !== false) {
      mockGetCurrentRepoUrl.mockResolvedValue(REPO_URL);
      mockResolveInstallationId.mockResolvedValue(987654);
    }
    mockSpawnEgressForwarder.mockResolvedValue({ port: 28711, token: "tok-abc", pid: 4242 });
  }

  beforeEach(() => {
    __resetDispatcherForTests();
    rpcByWorkspace = {};
    mockTenantRpc.mockReset().mockImplementation(async (fn: string, a: { p_workspace_id?: string }) =>
      fn === "get_workspace_kb_sync_held"
        ? (rpcByWorkspace[a.p_workspace_id as string] ?? { data: [], error: null })
        : { data: null, error: null },
    );
  });
  afterEach(() => {
    for (const d of tmpDirs.splice(0)) rmSync(d, { recursive: true, force: true });
  });

  describe("TW3: the line and its variant", () => {
    it("registered: the registered variant with n, the as-of time and origin/<default branch>, once, right after the push addendum", async () => {
      eligible();
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      const line = expected();
      expect(prompt().split(line)).toHaveLength(2);
      expect(line).toMatch(/As of 2026-11-17 09:05 UTC, 2 changed code files/);
      expect(line).toContain("`github_list_pull_requests`");
      expect(line).toContain("git diff --name-only origin/trunk...HEAD");
      expect(prompt()).toContain(`${ccPushPromptAddendum("trunk")}\n\n${line}`);
      expect(heldReads()).toEqual([["get_workspace_kb_sync_held", { p_workspace_id: "user-1" }]]);
      expect(heldWarnings()).toHaveLength(0);
    });

    it("next to c4PromptAddendum: c4, then the push addendum, then the held line, contiguous", async () => {
      eligible();
      mockResolveC4FlagEnabled.mockResolvedValue(true);
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(`${C4_PROMPT_ADDENDUM}\n\n${ccPushPromptAddendum("trunk")}\n\n${expected()}`);
    });

    it("next to c4PromptAddendum without the push tool: c4, then the held line", async () => {
      eligible({ flag: false });
      mockResolveC4FlagEnabled.mockResolvedValue(true);
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(`${C4_PROMPT_ADDENDUM}\n\n${expected({ route: "not-registered", defaultBranch: null })}`);
    });

    it("flag off (not registered): the not-registered variant, which never names github_push_branch", async () => {
      eligible({ flag: false });
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      const line = expected({ route: "not-registered", defaultBranch: null });
      expect(prompt()).toContain(line);
      expect(prompt()).not.toContain("github_push_branch");
    });

    it("D41(d): no repo connected (repoUrl null) -> no line, like the Settings card", async () => {
      eligible({ repo: false });
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).not.toContain(HELD_HEADING);
    });

    it.each([["cloning"], ["error"], ["not_connected"]])("D41(d): repo_status %s (not ready) -> no line", async (repoStatus) => {
      eligible();
      mockGetCurrentRepoStatus.mockResolvedValue({ repoStatus, repoError: null });
      held("user-1", 2);
      try {
        await realSdkQueryFactory(makeArgs());
      } catch {
        // cloning/error refuse the dispatch (RepoNotReadyError): no Query, so no line either way.
      }
      for (const c of mockQuery.mock.calls) expect(c[0].options.systemPrompt as string).not.toContain(HELD_HEADING);
    });

    it("a repo but no installation (no registration attempted, installation read held): not-registered", async () => {
      eligible();
      mockResolveInstallationId.mockResolvedValue(null);
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(expected({ route: "not-registered", defaultBranch: null }));
    });

    it("D40(2): no installation because the read failed (the strict re-read errors) -> transient, never 'not available for this workspace'", async () => {
      eligible();
      mockResolveInstallationId.mockResolvedValue(null);
      const base = mockTenantRpc.getMockImplementation()!;
      mockTenantRpc.mockImplementation(async (fn: string, a: { p_workspace_id?: string }) =>
        fn === "resolve_workspace_installation_id" ? { data: null, error: { message: "boom" } } : base(fn, a),
      );
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(expected({ route: "transient", defaultBranch: null }));
      expect(prompt()).not.toContain("not available for this workspace");
    });

    it.each([
      ["the strict read says entitled (the fail-closed read hid a blip)", () => mockResolveWebEgressStrict.mockResolvedValue(true), "transient"],
      ["the strict read throws", () => mockResolveWebEgressStrict.mockRejectedValue(new Error("rpc down")), "transient"],
      ["the strict read agrees: not entitled", () => mockResolveWebEgressStrict.mockResolvedValue(false), "not-registered"],
    ] as const)("D40(2): entitlement false and %s -> %s", async (_n, strict, route) => {
      eligible();
      mockResolveWebEgress.mockResolvedValue(false);
      strict();
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(expected({ route, defaultBranch: null }));
    });

    it("D40(2) lazy: with no renderable count, no strict re-read runs", async () => {
      eligible();
      mockResolveWebEgress.mockResolvedValue(false);
      await realSdkQueryFactory(makeArgs());
      expect(mockResolveWebEgressStrict).not.toHaveBeenCalled();
    });

    it("D40(3): the lookup answers 404 (installation lost access) -> the reconnect variant", async () => {
      eligible();
      mockGithubApiGet.mockRejectedValue(Object.assign(new Error("GitHub API GET failed"), { name: "GitHubApiError", statusCode: 404 }));
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(expected({ route: "reconnect", defaultBranch: null }));
      expect(prompt()).toContain("reconnect GitHub in Settings");
    });

    it("obs F12: one info line with the bucket, route, reason and runner, never the count", async () => {
      eligible();
      held("user-1", 12);
      await realSdkQueryFactory(makeArgs());
      const lines = mockLogInfo.mock.calls.filter(([o]) => (o as { op?: string })?.op === "kb-sync.held-agent-line");
      expect(lines).toHaveLength(1);
      expect(lines[0][0]).toMatchObject({ op: "kb-sync.held-agent-line", bucket: "10-99", route: "registered", mergeBlocked: "none", runner: "cc" });
      expect(JSON.stringify(lines[0][0])).not.toMatch(/\b12\b/);
    });

    it("a flag read that throws (registrar reason flag-error) -> the transient 'not available right now' variant", async () => {
      eligible();
      mockApprovalFlag.mockRejectedValue(new Error("flagsmith down"));
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      const line = expected({ route: "transient", defaultBranch: null });
      expect(prompt()).toContain(line);
      expect(line).toContain("not available right now");
      expect(prompt()).not.toContain("not available for this workspace");
    });

    it("a default-branch lookup that fails (default-branch-unresolved) -> the transient variant", async () => {
      eligible();
      mockGithubApiGet.mockRejectedValue(new Error("github down"));
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(expected({ route: "transient", defaultBranch: null }));
    });

    it("a registrar that throws -> the transient variant", async () => {
      eligible();
      registrarOverride.fn = async () => {
        throw new Error("registrar defect");
      };
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(expected({ route: "transient", defaultBranch: null }));
    });

    it.each([
      ["a null count", null, CHECKED],
      ["a count of 0", 0, CHECKED],
      ["a null checked_at", 2, null],
      ["a count above 10000", 10001, CHECKED],
      ["a string count", "2", CHECKED],
    ])("%s -> no line, no warning", async (_n, files, checkedAt) => {
      eligible();
      held("user-1", files, checkedAt);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).not.toContain(HELD_HEADING);
      expect(heldReads()).toHaveLength(1);
      expect(heldWarnings()).toHaveLength(0);
    });

    it("zero rows (the RPC's non-member answer) -> no line, no warning", async () => {
      eligible();
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).not.toContain(HELD_HEADING);
      expect(heldWarnings()).toHaveLength(0);
    });

    it.each([
      ["an RPC error", () => (rpcByWorkspace["user-1"] = { data: null, error: { message: "function does not exist", code: "42883" } })],
      ["a rejected RPC", () => mockTenantRpc.mockImplementation(async () => { throw new Error("socket hang up"); })],
    ])("%s -> no line, and ONE warning with a static message (null first argument)", async (_n, fail) => {
      eligible();
      fail();
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).not.toContain(HELD_HEADING);
      expect(heldWarnings()).toHaveLength(1);
      const [err, ctx] = heldWarnings()[0];
      expect(err).toBeNull();
      expect(ctx).toMatchObject({ feature: "cc-dispatcher", op: "kb-sync-held-read", message: "get_workspace_kb_sync_held read failed; no held-files line" });
      // obs F10: a closed cause tag, never the error text.
      expect(["rpc_error", "rejected"]).toContain(ctx.tags.cause);
      expect(JSON.stringify(ctx)).not.toContain("socket hang up");
      // The Query is still built: an optional line never breaks the dispatch.
      expect(mockQuery).toHaveBeenCalledTimes(1);
    });

    it("support persona: the count is never read and there is no line", async () => {
      eligible();
      held("user-1", 2);
      await realSdkQueryFactory(makeArgs({ persona: "support" }));
      expect(heldReads()).toHaveLength(0);
      expect(prompt()).not.toContain(HELD_HEADING);
    });
  });

  describe("TW1-b: keyed on the identity-bound workspace (D29(3))", () => {
    it("the RPC and the push registration get the SAME activeWorkspaceId; a count on another workspace adds no line", async () => {
      eligible();
      mockResolveActiveWorkspace.mockImplementation(async () => ({ ok: true, workspaceId: "ws-A" }));
      held("ws-B", 5);
      await realSdkQueryFactory(makeArgs());
      expect(heldReads()).toEqual([["get_workspace_kb_sync_held", { p_workspace_id: "ws-A" }]]);
      expect(mockApprovalFlag).toHaveBeenCalledWith({ userId: "user-1", workspaceId: "ws-A" });
      expect(prompt()).not.toContain(HELD_HEADING);
    });

    it("positive control: the same count on the active workspace adds the line", async () => {
      eligible();
      mockResolveActiveWorkspace.mockImplementation(async () => ({ ok: true, workspaceId: "ws-A" }));
      held("ws-A", 3);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(expected({ heldFiles: 3 }));
    });
  });

  describe("the merge-blocked line on the cc path (D29(4))", () => {
    function workspaceWith(files: string[]): string {
      const d = mkdtempSync(join(tmpdir(), "cc-held-merge-"));
      tmpDirs.push(d);
      mkdirSync(join(d, ".git"));
      for (const f of files) writeFileSync(join(d, ".git", f), "0".repeat(40) + "\n");
      mockResolveActiveWorkspacePath.mockResolvedValue(d);
      return d;
    }

    it.each([["MERGE_HEAD"], ["MERGE_AUTOSTASH"]])("a .git/%s present -> the unresolved_merge line", async (f) => {
      workspaceWith([f]);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(buildKbSyncMergeBlockedAgentLine("unresolved_merge") as string);
    });

    it.each([["untracked_collision"], ["merge_conflict_precheck"]])(
      "D42: the self-heal's persisted %s (kb_sync_pull_blocked) -> its line, with the registrar's default branch",
      async (blocked) => {
        workspaceWith(["HEAD"]);
        eligible();
        held("user-1", null, CHECKED, blocked);
        await realSdkQueryFactory(makeArgs());
        expect(prompt()).toContain(buildKbSyncMergeBlockedAgentLine(blocked as "untracked_collision", "trunk") as string);
      },
    );

    it("D42: an unfinished merge wins over a persisted refusal; an unknown value and a missing column add nothing", async () => {
      workspaceWith(["MERGE_HEAD"]);
      held("user-1", null, CHECKED, "untracked_collision");
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).toContain(buildKbSyncMergeBlockedAgentLine("unresolved_merge") as string);
      expect(prompt()).not.toContain("held by an untracked file");
      workspaceWith(["HEAD"]);
      held("user-1", null, CHECKED, "merge_conflict");
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).not.toContain(MERGE_HEADING);
      expect(prompt()).not.toContain("## Workspace");
    });

    it("no merge state -> no line", async () => {
      workspaceWith(["HEAD"]);
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).not.toContain(MERGE_HEADING);
    });

    it("a workspace with no .git -> no line", async () => {
      await realSdkQueryFactory(makeArgs());
      expect(prompt()).not.toContain(MERGE_HEADING);
    });

    it("support persona -> never checked, no line", async () => {
      workspaceWith(["MERGE_HEAD"]);
      await realSdkQueryFactory(makeArgs({ persona: "support" }));
      expect(prompt()).not.toContain(MERGE_HEADING);
    });
  });

  describe("D39(a): the close hook refreshes the held count (fire-and-forget)", () => {
    const flush = async () => {
      for (let i = 0; i < 10; i++) await new Promise((r) => setImmediate(r));
    };

    it("a ready, connected repo with an installation -> refreshHeldCount once at close, with the build's workspace", async () => {
      eligible();
      await realSdkQueryFactory(makeArgs());
      handleCcCloseQuery({ userId: "user-1", conversationId: makeArgs().conversationId });
      await flush();
      expect(mockRefreshHeldCount).toHaveBeenCalledTimes(1);
      expect(mockRefreshHeldCount.mock.calls[0][0]).toEqual({
        workspaceId: "user-1",
        workspacePath: WORKSPACE_PATH,
        installationId: 987654,
        userId: "user-1",
      });
      // Drained: a second close does not refresh again.
      handleCcCloseQuery({ userId: "user-1", conversationId: makeArgs().conversationId });
      await flush();
      expect(mockRefreshHeldCount).toHaveBeenCalledTimes(1);
    });

    it.each([
      ["no repo", () => eligible({ repo: false })],
      ["no installation", () => (eligible(), mockResolveInstallationId.mockResolvedValue(null))],
      ["the support persona", () => eligible()],
    ])("%s -> no refresh", async (name, setup) => {
      setup();
      await realSdkQueryFactory(makeArgs(name === "the support persona" ? { persona: "support" } : {}));
      handleCcCloseQuery({ userId: "user-1", conversationId: makeArgs().conversationId });
      await flush();
      expect(mockRefreshHeldCount).not.toHaveBeenCalled();
    });
  });

  describe("readers census (W2, D29(3)): no tenant select carries the held columns", () => {
    const root = join(__dirname, "..");
    const src = (p: string) => readFileSync(join(root, p), "utf8");

    it("getCurrentRepoStatus's select string is pinned (repo_status, repo_error), with no held column", () => {
      const s = src("server/current-repo-url.ts");
      const fn = s.slice(s.indexOf("export async function getCurrentRepoStatus"));
      const sel = /\.select\(\s*"([^"]*)"\s*\)/.exec(fn);
      expect(sel?.[1]).toBe("repo_status, repo_error");
      expect(s).not.toMatch(/kb_sync_held_/);
    });

    it("the dispatcher reads the held columns ONLY through the one stored reader: no select names them, one call", () => {
      const s = src("server/cc-dispatcher.ts");
      expect(s).not.toMatch(/\.select\(\s*[`"'][^`"']*kb_sync_held_/);
      expect(s).not.toMatch(/get_workspace_kb_sync_held/);
      expect(s.match(/\breadStoredKbSyncHeld\(/g)).toHaveLength(1);
      expect(src("server/kb-sync-held-agent-line.ts").match(/\.rpc\(\s*"get_workspace_kb_sync_held"/g)).toHaveLength(1);
    });
  });

  describe("TW3-b (D29(7)): through dispatchSoleurGo and the real runner, the SDK query spy records the line", () => {
    /** A permissive tenant chain for the dispatcher's own persistence: every builder call chains, every await yields no error. */
    function permissiveTenantChain(): unknown {
      const q: unknown = new Proxy(function () {}, {
        get: (_t, p) => {
          if (p === "then") return undefined;
          if (p === "error" || p === "data") return null;
          if (p === "single" || p === "maybeSingle") return async () => ({ data: { workspace_id: "user-1", workspace_path: WORKSPACE_PATH }, error: null });
          return () => q;
        },
      });
      return q;
    }

    async function dispatch() {
      mockSupabaseFrom.mockImplementation(() => permissiveTenantChain());
      conversationWriteOverride.fn = async () => ({ ok: true });
      await dispatchSoleurGo({
        persona: "command_center",
        userId: "user-1",
        conversationId: "conv-held",
        userMessage: "what is left to publish?",
        currentRouting: { kind: "soleur_go_pending" },
        sendToClient: vi.fn().mockReturnValue(true),
        persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
      } as never);
    }

    it("a held count of 2 -> the line with n = 2 reaches the SDK systemPrompt", async () => {
      eligible();
      held("user-1", 2);
      await dispatch();
      expect(mockQuery).toHaveBeenCalled();
      expect(prompt()).toContain(expected());
      expect(prompt()).toMatch(/2 changed code files in this workspace are not on the repository's main branch yet/);
    });

    it.each([["null", null], ["0", 0]])("a held count of %s -> no line in the SDK systemPrompt", async (_n, files) => {
      eligible();
      held("user-1", files);
      await dispatch();
      expect(mockQuery).toHaveBeenCalled();
      expect(prompt()).not.toContain(HELD_HEADING);
    });
  });
});
