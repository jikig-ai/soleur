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
    // Helpers — default to no-ops; individual tests override as needed
    abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(undefined),
    updateConversationStatus: vi.fn().mockResolvedValue(undefined),
    extractReviewGateInput: vi.fn().mockReturnValue({
      question: "",
      options: ["Approve", "Reject"],
      descriptions: {},
      header: undefined,
      isNewSchema: false,
    }),
    buildReviewGateResponse: vi.fn().mockReturnValue({ answer: "Approve" }),
    buildGateMessage: vi.fn().mockReturnValue("Permission needed"),
    getToolTier: vi.fn().mockReturnValue("auto-approve"),
    isFileTool: vi.fn().mockReturnValue(false),
    extractToolPath: vi.fn().mockReturnValue(null),
    isPathInWorkspace: vi.fn().mockReturnValue(true),
    isSafeTool: vi.fn().mockReturnValue(false),
    unverifiedParamTools: [],
    ...overrides,
  };
}

function sdkOptions() {
  return { signal: new AbortController().signal, toolUseID: "tu-1" };
}

describe("createCanUseTool — allow branches (#2335)", () => {
  beforeEach(() => vi.clearAllMocks());

  test("Write to workspace-internal path → allow w/ echoed updatedInput", async () => {
    const canUseTool = createCanUseTool(buildContext({
      isFileTool: vi.fn().mockReturnValue(true),
      extractToolPath: vi.fn().mockReturnValue("/tmp/ws/overview/vision.md"),
      isPathInWorkspace: vi.fn().mockReturnValue(true),
    }));
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
    const canUseTool = createCanUseTool(buildContext({
      isSafeTool: vi.fn((name: string) => name === "TodoWrite"),
    }));
    const result = await canUseTool("TodoWrite", { todos: [] }, sdkOptions());
    assertAllow(result);
  });

  test("AskUserQuestion (review gate) → allow after approval", async () => {
    const abortableReviewGate = vi.fn().mockResolvedValue("Approve");
    const canUseTool = createCanUseTool(buildContext({
      abortableReviewGate,
      extractReviewGateInput: vi.fn().mockReturnValue({
        question: "Proceed?",
        options: ["Approve", "Reject"],
        descriptions: {},
        header: undefined,
        isNewSchema: true,
      }),
      buildReviewGateResponse: vi.fn().mockReturnValue({ answer: "Approve" }),
    }));
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
    const canUseTool = createCanUseTool(buildContext({
      platformToolNames: ["mcp__soleur_platform__github_read_ci_status"],
      getToolTier: vi.fn().mockReturnValue("auto-approve"),
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
    const canUseTool = createCanUseTool(buildContext({
      platformToolNames: ["mcp__soleur_platform__github_push_branch"],
      getToolTier: vi.fn().mockReturnValue("gated"),
      abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
    }));
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
  beforeEach(() => vi.clearAllMocks());

  test("Write outside workspace → deny", async () => {
    const canUseTool = createCanUseTool(buildContext({
      isFileTool: vi.fn().mockReturnValue(true),
      extractToolPath: vi.fn().mockReturnValue("/etc/passwd"),
      isPathInWorkspace: vi.fn().mockReturnValue(false),
    }));
    const result = await canUseTool(
      "Write",
      { file_path: "/etc/passwd", content: "x" },
      sdkOptions(),
    );
    const deny = assertDeny(result);
    expect(deny.message).toMatch(/outside workspace/);
  });

  test("Platform tool (gated tier) + Reject → deny", async () => {
    const canUseTool = createCanUseTool(buildContext({
      platformToolNames: ["mcp__soleur_platform__github_push_branch"],
      getToolTier: vi.fn().mockReturnValue("gated"),
      abortableReviewGate: vi.fn().mockResolvedValue("Reject"),
    }));
    const result = await canUseTool(
      "mcp__soleur_platform__github_push_branch",
      { branch: "feat" },
      sdkOptions(),
    );
    assertDeny(result);
  });

  test("Platform tool (blocked tier) → deny", async () => {
    const canUseTool = createCanUseTool(buildContext({
      platformToolNames: ["mcp__soleur_platform__dangerous_thing"],
      getToolTier: vi.fn().mockReturnValue("blocked"),
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
  // Negative-space: enforces that agent-runner DELEGATES to createCanUseTool,
  // not just that it imports the module. See learning
  // 2026-04-15-negative-space-tests-must-follow-extracted-logic.md.
  test("agent-runner.ts invokes createCanUseTool and has no inline canUseTool closure", () => {
    const src = readFileSync(
      resolve(__dirname, "../server/agent-runner.ts"),
      "utf-8",
    );
    const invokesFactory = /canUseTool:\s*createCanUseTool\s*\(/.test(src);
    const hasInlineClosure = /canUseTool:\s*async\s*\(/.test(src);
    expect(invokesFactory).toBe(true);
    expect(hasInlineClosure).toBe(false);
  });
});
