// #11086 wire test for the LEGACY runner (startAgentSession): a REAL createAgentAuthFailureProbe observes the RAW message at the
// loop top, then the friendly copy feeds the stream frame and the persisted row, and the key_invalid recovery frame follows
// stream_end. (The cc runner has its own wire test: agent-auth-friendly-error-wire.test.ts.)
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
  mockLogWarn,
  mockMessagesInsert,
  mockLogError,
  mockNotifyTaskCompleted,
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
  mockLogWarn: vi.fn(),
  mockMessagesInsert: vi.fn(() => ({ error: null })),
  mockLogError: vi.fn(),
  mockNotifyTaskCompleted: vi.fn(),
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
  createClient: vi.fn(() => ({ from: mockFrom, rpc: mockRpc })),
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
// The "finished" nudge must be skipped for a terminal sign-in failure and still fire for an ordinary turn (control).
vi.mock("../server/notifications", () => ({
  notifyOfflineUser: vi.fn(),
  notifyTaskCompleted: mockNotifyTaskCompleted,
}));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: mockLogWarn,
    error: mockLogError,
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
// #11591: these cases pin the subscription (oauth_token) copy and scheme, so the lease's mode resolver is
// pinned to the managed path here; the selection itself is driven through the REAL lease and the REAL binding
// resolver in byok-lease-auth-mode-binding.test.ts, not here.
const mockMakeConversationAuthModeResolver = vi.hoisted(() => vi.fn((..._args: unknown[]) => async () => "managed"));
vi.mock("../server/engine-binding-auth-mode", () => ({
  makeConversationAuthModeResolver: mockMakeConversationAuthModeResolver,
  readConversationBindingAuthMode: async () => null,
}));

import { startAgentSession } from "../server/agent-runner";
import { reportSilentFallback } from "../server/observability";
import * as Sentry from "@sentry/nextjs";
import { ByokLeaseError } from "../server/byok-lease";
import { authFailureCopy, authModeUnresolvedFrame } from "../server/agent-auth-user-message";
import {
  PROBE_UNAVAILABLE_WARNING,
  __resetAgentAuthDedupeForTests,
  __resetAgentAuthMatcherWarnForTests,
} from "../server/agent-auth-failure";
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

const SEP = "\u00B7";
const USER = "44444444-4444-4444-8444-444444444444";
const CLI_TEXT = `Not logged in ${SEP} Please run /login`;

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

const cliAssistant = (text: string) => ({
  type: "assistant",
  message: { model: "<synthetic>", content: [{ type: "text", text }] },
  error: "authentication_failed",
  is_api_error_message: true,
  session_id: "sess-1",
});

const stream = (text: string) => [
  { type: "system", subtype: "init", apiKeySource: "none", session_id: "sess-1" },
  cliAssistant(text),
  { type: "result", session_id: "sess-1" },
];

const sent = () => mockSendToClient.mock.calls.map((c) => c[1] as { type: string; [k: string]: unknown });

describe("legacy runner — friendly CLI auth-failure reply (#11086)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetAgentAuthDedupeForTests();
    __resetAgentAuthMatcherWarnForTests();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) return JSON.stringify({ mcpServers: {} });
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
    mockApplyPrefillGuard.mockImplementation(async ({ resumeSessionId }) => ({ safeResumeSessionId: resumeSessionId }));
    mockBuildAgentEnv.mockReturnValue({ ANTHROPIC_API_KEY: "sk-test-key" });
    mockResolveUnixDeny.mockResolvedValue(false);
    mockMakeAuthModeResolver.mockImplementation(() => async () => "api-key");
    createSupabaseMockImpl(mockFrom, { userData: BASE_USER_DATA, mockRpc, mockMessagesInsert });
  });

  test("streams and persists the friendly text, observes the RAW message, and sends key_invalid after stream_end", async () => {
    streamOf(stream(CLI_TEXT));
    await startAgentSession(USER, "conv-friendly", "cpo", "session-s");

    const friendly = authFailureCopy("not_logged_in", "api_key");
    const frames = sent();
    const textFrames = frames.filter((f) => f.type === "stream");
    expect(textFrames).toHaveLength(1);
    expect(textFrames[0].content).toBe(friendly);
    expect(JSON.stringify(frames)).not.toContain("Please run /login");

    // Order: stream_start, stream, stream_end, then the recovery frame.
    const kinds = frames.map((f) => f.type);
    const iEnd = kinds.indexOf("stream_end");
    const iErr = kinds.indexOf("error");
    expect(iEnd).toBeGreaterThan(kinds.indexOf("stream"));
    expect(iErr).toBeGreaterThan(iEnd);
    expect(frames[iErr]).toEqual({
      type: "error",
      message: friendly,
      errorCode: "key_invalid",
      credentialScheme: "api_key",
    });
    expect(kinds.filter((k) => k === "error")).toHaveLength(1);

    // The persisted assistant row carries the friendly text, never the raw line.
    const rows = (mockMessagesInsert.mock.calls as unknown as Array<[Record<string, unknown>]>).map((c) => c[0]);
    const assistantRows = rows.filter((r) => r?.role === "assistant");
    expect(assistantRows).toHaveLength(1);
    expect(assistantRows[0].content).toBe(friendly);

    // The REAL probe saw the original message: exactly one event, classified from the raw text.
    await vi.waitFor(() => expect(authEmits()).toHaveLength(1));
    expect((authEmits()[0][1] as unknown as { tags: { match_kind: string } }).tags.match_kind).toBe("not_logged_in");
  });

  test("an oauth_token lease gets the operator copy and scheme on the card, not the API-key copy", async () => {
    vi.stubEnv("CC_OAUTH_ENABLED", "1");
    try {
      mockBuildAgentEnv.mockReturnValue({ CLAUDE_CODE_OAUTH_TOKEN: "sk-test-oauth" });
      streamOf(stream(CLI_TEXT));
      await startAgentSession(USER, "conv-oauth-copy", "cpo", "session-s");
      // The lease is handed the resolver for THIS user and THIS conversation, in that order (both are strings).
      expect(mockMakeConversationAuthModeResolver).toHaveBeenCalledWith(USER, "conv-oauth-copy");
      const frames = sent();
      expect(frames.filter((f) => f.type === "stream")[0].content).toBe(authFailureCopy("not_logged_in", "oauth_token"));
      const err = frames.find((f) => f.type === "error");
      expect(err?.credentialScheme).toBe("oauth_token");
    } finally {
      vi.unstubAllEnvs();
    }
  });

  test("session_expired is bubble-only: friendly text, no recovery frame", async () => {
    streamOf(stream("Session expired. Please run /login to sign in again."));
    await startAgentSession(USER, "conv-expired", "cpo", "session-s");
    const frames = sent();
    expect(frames.filter((f) => f.type === "stream")[0].content).toBe(authFailureCopy("session_expired", "api_key"));
    expect(frames.some((f) => f.type === "error")).toBe(false);
  });

  test("a forged reply (non-synthetic model, no flag) is neither rewritten nor observed", async () => {
    streamOf([
      { type: "system", subtype: "init", apiKeySource: "ANTHROPIC_API_KEY", session_id: "sess-1" },
      { type: "assistant", message: { model: "claude-sonnet-4", content: [{ type: "text", text: CLI_TEXT }] }, session_id: "sess-1" },
      { type: "result", session_id: "sess-1" },
    ]);
    await startAgentSession(USER, "conv-forged", "cpo", "session-s");
    const frames = sent();
    expect(frames.filter((f) => f.type === "stream")[0].content).toBe(CLI_TEXT);
    expect(frames.some((f) => f.type === "error")).toBe(false);
    await vi.waitFor(() => expect(mockSendToClient.mock.calls.some((c) => (c[1] as { type: string }).type === "stream_end")).toBe(true));
    await new Promise((r) => setTimeout(r, 50));
    expect(authEmits()).toHaveLength(0);
  });

  test("a lease refusal for an unusable stored credential sends the oauth recovery frame, not the generic text", async () => {
    mockQuery.mockImplementation(() => {
      throw new ByokLeaseError("oauth_unusable", "refused");
    });
    await startAgentSession(USER, "conv-lease", "cpo", "session-s");
    const errors = sent().filter((f) => f.type === "error");
    expect(errors).toEqual([
      {
        type: "error",
        message: authFailureCopy("oauth_unusable", "oauth_token"),
        errorCode: "key_invalid",
        credentialScheme: "oauth_token",
      },
    ]);
    // One failed turn, one Sentry event: the lease already reported it, so the catch adds no raw capture.
    expect(vi.mocked(Sentry.captureException)).not.toHaveBeenCalled();
    // Layer 2 would capture a `log.error({ err })` independently of the Sentry call above, so pin that too.
    expect(mockLogError).not.toHaveBeenCalled();
  });

  // #11599 — an unresolvable authentication mode gets its own typed frame (not the key_invalid "Update key" card), and the
  // lease's own event is the only one: the call-site mirror and the ERROR log are skipped.
  test.each(["auth_mode_unresolved", "auth_mode_unavailable"] as const)(
    "a %s lease refusal sends the typed frame, adds no Sentry capture and no ERROR log",
    async (cause) => {
      mockQuery.mockImplementation(() => {
        throw new ByokLeaseError(cause, "Authentication unavailable; retry shortly", cause === "auth_mode_unresolved" ? "unbound" : "read_failed");
      });
      await startAgentSession(USER, `conv-${cause}`, "cpo", "session-s");
      expect(sent().filter((f) => f.type === "error")).toEqual([authModeUnresolvedFrame(cause)]);
      expect(vi.mocked(Sentry.captureException)).not.toHaveBeenCalled();
      expect(mockLogError).not.toHaveBeenCalled();
    },
  );

  test("positive control for the skip: a non-lease error in the same harness IS captured and logged", async () => {
    mockQuery.mockImplementation(() => {
      throw new Error("boom");
    });
    await startAgentSession(USER, "conv-liveness", "cpo", "session-s");
    expect(vi.mocked(Sentry.captureException)).toHaveBeenCalledTimes(1);
    expect(mockLogError).toHaveBeenCalledTimes(1);
  });

  test("any other error keeps the generic path (sanitized text, mapped code, no scheme)", async () => {
    mockQuery.mockImplementation(() => {
      throw new ByokLeaseError("fetch_failed", "boom");
    });
    await startAgentSession(USER, "conv-other", "cpo", "session-s");
    const errors = sent().filter((f) => f.type === "error");
    expect(errors).toHaveLength(1);
    expect(errors[0].message).toBe("error"); // the mocked sanitizer
    expect(errors[0].errorCode).toBe("key_invalid");
    expect("credentialScheme" in errors[0]).toBe(false);
    // Positive control for the skip above: any other lease cause IS captured.
    expect(vi.mocked(Sentry.captureException)).toHaveBeenCalledTimes(1);
    expect(mockLogError).toHaveBeenCalledTimes(1);
  });

  test("a terminal sign-in failure is not announced as a finished task; an ordinary turn still is", async () => {
    streamOf(stream(CLI_TEXT));
    await startAgentSession(USER, "conv-no-nudge", "cpo", "session-s");
    await vi.waitFor(() => expect(sent().some((f) => f.type === "stream_end")).toBe(true));
    expect(mockNotifyTaskCompleted).not.toHaveBeenCalled();

    // Positive control: the same harness DOES announce an ordinary completed turn, so the zero above is the guard, not a
    // harness that can never reach the call.
    mockSendToClient.mockClear();
    streamOf([
      { type: "system", subtype: "init", apiKeySource: "ANTHROPIC_API_KEY", session_id: "sess-2" },
      { type: "assistant", message: { model: "claude-sonnet-4", content: [{ type: "text", text: "all done" }] }, session_id: "sess-2" },
      { type: "result", session_id: "sess-2" },
    ]);
    await startAgentSession(USER, "conv-nudge-control", "cpo", "session-s");
    await vi.waitFor(() => expect(mockNotifyTaskCompleted).toHaveBeenCalledTimes(1));
  });

  test("a session_expired reply after a terminal one keeps the recovery frame (first terminal frame wins)", async () => {
    streamOf([
      { type: "system", subtype: "init", apiKeySource: "none", session_id: "sess-1" },
      cliAssistant(CLI_TEXT),
      cliAssistant("Session expired. Please run /login to sign in again."),
      { type: "result", session_id: "sess-1" },
    ]);
    await startAgentSession(USER, "conv-mixed", "cpo", "session-s");
    expect(sent().filter((f) => f.type === "error")).toHaveLength(1);
  });
});
