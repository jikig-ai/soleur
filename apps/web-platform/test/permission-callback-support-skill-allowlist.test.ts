/**
 * Support-persona Skill allowlist in `createCanUseTool` (Phase 3.3b, ADR-109).
 *
 * Deterministic unit test — exercises the canUseTool branch directly, NO SDK/LLM
 * invocation (learning 2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md).
 *
 * Non-vacuity: `isSafeTool` is mocked to return TRUE for "Skill" (mirrors the
 * real SAFE_TOOLS which includes "Skill"). So WITHOUT the support branch a
 * disallowed skill would fall through to the isSafeTool allow — the deny
 * assertions therefore prove the new branch fires, not the ambient default.
 */
import { vi, describe, test, expect, beforeEach } from "vitest";
import type { PermissionResult } from "@anthropic-ai/claude-agent-sdk";

const { mockIsFileTool, mockIsSafeTool } = vi.hoisted(() => ({
  mockIsFileTool: vi.fn(() => false),
  // Real SAFE_TOOLS includes "Skill" → without the support branch, any Skill call allows.
  mockIsSafeTool: vi.fn((t: string) => t === "Skill"),
}));

vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [] as readonly string[],
  extractToolPath: vi.fn(() => null),
  isFileTool: mockIsFileTool,
  isSafeTool: mockIsSafeTool,
}));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: vi.fn(() => true) }));
vi.mock("../server/tool-tiers", () => ({
  getToolTier: vi.fn(() => "auto-approve"),
  buildGateMessage: vi.fn(() => "Permission needed"),
}));
vi.mock("../server/review-gate", () => ({
  extractReviewGateInput: vi.fn(() => ({
    question: "",
    options: ["Approve", "Reject"],
    descriptions: {},
    header: undefined,
    isNewSchema: false,
  })),
  buildReviewGateResponse: vi.fn(() => ({ answer: "Approve" })),
}));

import {
  createCanUseTool,
  type CanUseToolContext,
} from "../server/permission-callback";

function buildContext(overrides: Partial<CanUseToolContext> = {}): CanUseToolContext {
  return {
    userId: "user-1",
    conversationId: "conv-1",
    leaderId: "cc-router",
    workspacePath: "/tmp/ws",
    platformToolNames: [],
    pluginMcpServerNames: [],
    repoOwner: "",
    repoName: "",
    session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
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

const opts = () => ({ signal: new AbortController().signal, toolUseID: "tu-1" });

function assertDeny(r: PermissionResult) {
  expect(r.behavior).toBe("deny");
  if (r.behavior !== "deny") throw new Error("unreachable");
  expect(r.message.length).toBeGreaterThan(0);
  return r;
}
function assertAllow(r: PermissionResult) {
  expect(r.behavior).toBe("allow");
  if (r.behavior !== "allow") throw new Error("unreachable");
  expect(r.updatedInput).toBeDefined();
  return r;
}

describe("support persona — Skill allowlist", () => {
  beforeEach(() => vi.clearAllMocks());

  test("allows kb-search (bare) under persona=support", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertAllow(await canUse("Skill", { skill: "kb-search" }, opts()));
  });

  test("allows kb-search (FQN soleur:kb-search) under persona=support", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertAllow(await canUse("Skill", { skill: "soleur:kb-search" }, opts()));
  });

  test("denies a non-allowlisted skill (one-shot) with a user-relayable message", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    const r = assertDeny(await canUse("Skill", { skill: "soleur:one-shot" }, opts()));
    expect(r.behavior === "deny" && r.message).toMatch(/support/i);
  });

  test("denies `help` (enumerates the engineering surface)", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertDeny(await canUse("Skill", { skill: "help" }, opts()));
  });

  test("denies a malformed/missing skill field under persona=support", async () => {
    const canUse = createCanUseTool(buildContext({ persona: "support" }));
    assertDeny(await canUse("Skill", {}, opts()));
  });

  test("NON-support persona is unaffected: any Skill still allowed (Command Center)", async () => {
    const canUse = createCanUseTool(buildContext()); // no persona
    assertAllow(await canUse("Skill", { skill: "one-shot" }, opts()));
  });
});
