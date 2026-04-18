/**
 * canUseTool Permission-Callback Unit Tests (#2335)
 *
 * Unit-level coverage for the extracted `createCanUseTool` factory. Each
 * allow branch + deny-by-default asserts the SDK's `PermissionResult` shape:
 * - allow → behavior === "allow" AND updatedInput is present
 * - deny  → behavior === "deny"  AND message is non-empty
 *
 * SDK v0.2.80 Zod schema regression (`allow` without `updatedInput` →
 * `ZodError: invalid_union`) motivated this coverage. `updatedInput` is
 * declared optional in `sdk.d.ts` but was required by the runtime schema,
 * so the `allow` helper echoes it unconditionally and tests assert its
 * presence regardless of `.d.ts` optionality.
 */
import { readFileSync } from "fs";
import { resolve } from "path";
import { vi, describe, test, expect, beforeEach } from "vitest";
import type { PermissionResult } from "@anthropic-ai/claude-agent-sdk";

// Mock pure helpers imported directly by permission-callback so tests can
// steer file-tool / safe-tool / tier decisions without running the real
// implementations (which would require real workspaces, tool-tier map
// lookups, etc.).
const {
  mockIsFileTool,
  mockIsSafeTool,
  mockIsPathInWorkspace,
  mockExtractToolPath,
  mockGetToolTier,
  mockExtractReviewGateInput,
  mockBuildReviewGateResponse,
  mockBuildGateMessage,
} = vi.hoisted(() => ({
  mockIsFileTool: vi.fn(() => false),
  mockIsSafeTool: vi.fn(() => false),
  mockIsPathInWorkspace: vi.fn(() => true),
  mockExtractToolPath: vi.fn(() => null as string | null),
  mockGetToolTier: vi.fn(() => "auto-approve" as "auto-approve" | "gated" | "blocked"),
  mockExtractReviewGateInput: vi.fn(() => ({
    question: "",
    options: ["Approve", "Reject"],
    descriptions: {},
    header: undefined,
    isNewSchema: false,
  })),
  mockBuildReviewGateResponse: vi.fn(() => ({ answer: "Approve" })),
  mockBuildGateMessage: vi.fn(() => "Permission needed"),
}));

vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [] as readonly string[],
  extractToolPath: mockExtractToolPath,
  isFileTool: mockIsFileTool,
  isSafeTool: mockIsSafeTool,
}));
vi.mock("../server/sandbox", () => ({
  isPathInWorkspace: mockIsPathInWorkspace,
}));
vi.mock("../server/tool-tiers", () => ({
  getToolTier: mockGetToolTier,
  buildGateMessage: mockBuildGateMessage,
}));
vi.mock("../server/review-gate", () => ({
  extractReviewGateInput: mockExtractReviewGateInput,
  buildReviewGateResponse: mockBuildReviewGateResponse,
}));

import {
  createCanUseTool,
  type CanUseToolContext,
} from "../server/permission-callback";

// ---------------------------------------------------------------------------
// Isolated unit-test context. All hooks, side-effectful helpers, and paths
// are provided via the context object — no global mocks required.
// ---------------------------------------------------------------------------

function assertAllow(result: PermissionResult): Extract<PermissionResult, { behavior: "allow" }> {
  expect(result.behavior).toBe("allow");
  if (result.behavior !== "allow") throw new Error("unreachable");
  // SDK v0.2.80 required updatedInput on allow — keep the invariant pinned.
  expect(result.updatedInput).toBeDefined();
  return result;
}

function assertDeny(result: PermissionResult): Extract<PermissionResult, { behavior: "deny" }> {
  expect(result.behavior).toBe("deny");
  if (result.behavior !== "deny") throw new Error("unreachable");
  expect(typeof result.message).toBe("string");
  expect(result.message.length).toBeGreaterThan(0);
  return result;
}

function buildContext(overrides: Partial<CanUseToolContext> = {}): CanUseToolContext {
  return {
    userId: "user-1",
    conversationId: "conv-1",
    leaderId: "cpo",
    workspacePath: "/tmp/ws",
    platformToolNames: [],
    pluginMcpServerNames: [],
    repoOwner: "",
    repoName: "",
    session: {
      abort: new AbortController(),
      reviewGateResolvers: new Map(),
      sessionId: null,
    },
    controllerSignal: new AbortController().signal,
    deps: {
      abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
      sendToClient: vi.fn().mockReturnValue(true),
      notifyOfflineUser: vi.fn().mockResolvedValue(undefined),
      updateConversationStatus: vi.fn().mockResolvedValue(undefined),
    },
    ...overrides,
  };
}

function sdkOptions() {
  return { signal: new AbortController().signal, toolUseID: "tu-1" };
}

describe("createCanUseTool — allow branches (#2335)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset defaults: pure helpers return the permissive defaults between tests.
    mockIsFileTool.mockReturnValue(false);
    mockIsSafeTool.mockReturnValue(false);
    mockIsPathInWorkspace.mockReturnValue(true);
    mockExtractToolPath.mockReturnValue(null);
    mockGetToolTier.mockReturnValue("auto-approve");
    mockExtractReviewGateInput.mockReturnValue({
      question: "",
      options: ["Approve", "Reject"],
      descriptions: {},
      header: undefined,
      isNewSchema: false,
    });
    mockBuildReviewGateResponse.mockReturnValue({ answer: "Approve" });
    mockBuildGateMessage.mockReturnValue("Permission needed");
  });

  test("Write to workspace-internal path → allow w/ echoed updatedInput", async () => {
    mockIsFileTool.mockReturnValue(true);
    mockExtractToolPath.mockReturnValue("/tmp/ws/overview/vision.md");
    mockIsPathInWorkspace.mockReturnValue(true);
    const canUseTool = createCanUseTool(buildContext());
    const input = { file_path: "/tmp/ws/overview/vision.md", content: "x" };
    const result = await canUseTool("Write", input, sdkOptions());
    const allow = assertAllow(result);
    expect(allow.updatedInput).toEqual(input);
  });

  test("Agent tool → allow w/ echoed updatedInput", async () => {
    const canUseTool = createCanUseTool(buildContext());
    const input = { description: "spawn a subagent" };
    const result = await canUseTool("Agent", input, sdkOptions());
    assertAllow(result);
  });

  test("TodoWrite (safe tool) → allow", async () => {
    mockIsSafeTool.mockReturnValue(true);
    const canUseTool = createCanUseTool(buildContext());
    const result = await canUseTool("TodoWrite", { todos: [] }, sdkOptions());
    assertAllow(result);
  });

  test("AskUserQuestion (review gate) → allow after approval", async () => {
    mockExtractReviewGateInput.mockReturnValue({
      question: "Proceed?",
      options: ["Approve", "Reject"],
      descriptions: {},
      header: undefined,
      isNewSchema: true,
    });
    mockBuildReviewGateResponse.mockReturnValue({ answer: "Approve" });
    const abortableReviewGate = vi.fn().mockResolvedValue("Approve");
    const ctx = buildContext();
    ctx.deps.abortableReviewGate = abortableReviewGate;
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "AskUserQuestion",
      { questions: [{ question: "Proceed?", options: ["Approve", "Reject"] }] },
      sdkOptions(),
    );
    const allow = assertAllow(result);
    expect(allow.updatedInput).toEqual({ answer: "Approve" });
    expect(abortableReviewGate).toHaveBeenCalledOnce();
  });

  test("Platform tool (auto-approve tier) → allow", async () => {
    mockGetToolTier.mockReturnValue("auto-approve");
    const canUseTool = createCanUseTool(buildContext({
      platformToolNames: ["mcp__soleur_platform__github_read_ci_status"],
      repoOwner: "alice",
      repoName: "repo",
    }));
    const result = await canUseTool(
      "mcp__soleur_platform__github_read_ci_status",
      { branch: "main" },
      sdkOptions(),
    );
    assertAllow(result);
  });

  test("Platform tool (gated tier) + Approve → allow", async () => {
    mockGetToolTier.mockReturnValue("gated");
    const ctx = buildContext({
      platformToolNames: ["mcp__soleur_platform__github_push_branch"],
    });
    ctx.deps.abortableReviewGate = vi.fn().mockResolvedValue("Approve");
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "mcp__soleur_platform__github_push_branch",
      { branch: "feat" },
      sdkOptions(),
    );
    assertAllow(result);
  });

  test("Plugin MCP tool from registered server → allow", async () => {
    const canUseTool = createCanUseTool(buildContext({
      pluginMcpServerNames: ["cloudflare"],
    }));
    const result = await canUseTool(
      "mcp__plugin_soleur_cloudflare__zones_list",
      {},
      sdkOptions(),
    );
    assertAllow(result);
  });
});

describe("createCanUseTool — deny branches (#2335)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsFileTool.mockReturnValue(false);
    mockIsSafeTool.mockReturnValue(false);
    mockIsPathInWorkspace.mockReturnValue(true);
    mockExtractToolPath.mockReturnValue(null);
    mockGetToolTier.mockReturnValue("auto-approve");
    mockExtractReviewGateInput.mockReturnValue({
      question: "",
      options: ["Approve", "Reject"],
      descriptions: {},
      header: undefined,
      isNewSchema: false,
    });
    mockBuildReviewGateResponse.mockReturnValue({ answer: "Approve" });
    mockBuildGateMessage.mockReturnValue("Permission needed");
  });

  test("Write outside workspace → deny", async () => {
    mockIsFileTool.mockReturnValue(true);
    mockExtractToolPath.mockReturnValue("/etc/passwd");
    mockIsPathInWorkspace.mockReturnValue(false);
    const canUseTool = createCanUseTool(buildContext());
    const result = await canUseTool(
      "Write",
      { file_path: "/etc/passwd", content: "x" },
      sdkOptions(),
    );
    const deny = assertDeny(result);
    expect(deny.message).toMatch(/outside workspace/);
  });

  test("Platform tool (gated tier) + Reject → deny", async () => {
    mockGetToolTier.mockReturnValue("gated");
    const ctx = buildContext({
      platformToolNames: ["mcp__soleur_platform__github_push_branch"],
    });
    ctx.deps.abortableReviewGate = vi.fn().mockResolvedValue("Reject");
    const canUseTool = createCanUseTool(ctx);
    const result = await canUseTool(
      "mcp__soleur_platform__github_push_branch",
      { branch: "feat" },
      sdkOptions(),
    );
    assertDeny(result);
  });

  test("Platform tool (blocked tier) → deny", async () => {
    mockGetToolTier.mockReturnValue("blocked");
    const canUseTool = createCanUseTool(buildContext({
      platformToolNames: ["mcp__soleur_platform__dangerous_thing"],
    }));
    const result = await canUseTool(
      "mcp__soleur_platform__dangerous_thing",
      {},
      sdkOptions(),
    );
    assertDeny(result);
  });

  test("Plugin MCP tool from UNREGISTERED server → deny-by-default", async () => {
    const canUseTool = createCanUseTool(buildContext({
      pluginMcpServerNames: ["cloudflare"],
    }));
    const result = await canUseTool(
      "mcp__plugin_soleur_unknown__hack",
      {},
      sdkOptions(),
    );
    assertDeny(result);
  });

  test("Unregistered mcp__ prefix (not in platformToolNames or plugin list) → deny-by-default", async () => {
    // Protects the 2026-04-06-mcp-tool-canusertool-scope-allowlist regression class.
    const canUseTool = createCanUseTool(buildContext({
      platformToolNames: ["mcp__soleur_platform__create_pull_request"],
      pluginMcpServerNames: ["cloudflare"],
    }));
    const result = await canUseTool(
      "mcp__some_future_server__anything",
      {},
      sdkOptions(),
    );
    assertDeny(result);
  });

  test("Unknown non-mcp tool → deny-by-default", async () => {
    const canUseTool = createCanUseTool(buildContext());
    const result = await canUseTool("DangerousUnknown", {}, sdkOptions());
    assertDeny(result);
  });
});

describe("agent-runner delegation proof (#2335)", () => {
  // Negative-space only: assert that no inline canUseTool closure survives.
  // Behavioral tests above already prove that `createCanUseTool` is invoked
  // and its result is respected; asserting a positive regex for the invocation
  // would over-constrain on source text (barrel re-exports, aliases, currying)
  // per learning 2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space.md.
  test("agent-runner.ts has no inline canUseTool closure after extraction", () => {
    const src = readFileSync(
      resolve(__dirname, "../server/agent-runner.ts"),
      "utf-8",
    );
    const hasInlineClosure = /canUseTool:\s*async\s*\(/.test(src);
    expect(hasInlineClosure).toBe(false);
  });
});
