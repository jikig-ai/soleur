/**
 * #12469 permission arm: with the registrar's six names in `platformToolNames` (the exact list the dispatcher builds),
 * `canUseTool` ALLOWS each read tool without opening a review gate, and DENIES a tool outside that list: the workflow-logs
 * tool (auto-approve in the tier map, but not registered for cc), a write tool and a made-up `github_create_issue`.
 */
import { vi, describe, test, expect, beforeEach } from "vitest";

const { log, mockLogDecision } = vi.hoisted(() => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  mockLogDecision: vi.fn(),
}));
vi.mock("../server/logger", () => ({ createChildLogger: () => log, default: log }));
vi.mock("../server/permission-log", () => ({ logPermissionDecision: mockLogDecision }));
vi.mock("../server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));

import { createCanUseTool, type CanUseToolContext } from "../server/permission-callback";
import { CC_GITHUB_READ_TOOL_FQNS } from "../server/cc-github-read";

const P = "mcp__soleur_platform__";

function make() {
  const controller = new AbortController();
  const deps = {
    abortableReviewGate: vi.fn(async () => "Approve"),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(true),
    updateConversationStatus: vi.fn(async () => {}),
  };
  const ctx = {
    userId: "u",
    conversationId: "c",
    leaderId: "cc-router",
    workspacePath: "/tmp/ws",
    platformToolNames: [...CC_GITHUB_READ_TOOL_FQNS],
    pluginMcpServerNames: [],
    repoOwner: "",
    repoName: "",
    session: { abort: controller, reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: controller.signal,
    deps,
  } as unknown as CanUseToolContext;
  return { ctx, deps };
}

const call = async (ctx: CanUseToolContext, fqn: string, input: Record<string, unknown> = {}) =>
  (await createCanUseTool(ctx)(fqn, input, { signal: new AbortController().signal, toolUseID: "t", requestId: "r" } as never)) as {
    behavior: string;
    message?: string;
  };

beforeEach(() => vi.clearAllMocks());

describe("canUseTool with the six read FQNs registered", () => {
  test.each([...CC_GITHUB_READ_TOOL_FQNS])("%s is allowed and opens no review gate", async (fqn) => {
    const { ctx, deps } = make();
    const res = await call(ctx, fqn, { issue_number: 1, pull_number: 1 });
    expect(res.behavior).toBe("allow");
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(deps.sendToClient).not.toHaveBeenCalled();
  });

  test.each([
    `${P}github_read_workflow_logs`,
    `${P}github_create_issue`,
    `${P}create_issue`,
    `${P}create_pull_request`,
    `${P}github_trigger_workflow`,
    `${P}github_list_issues`,
  ])("%s is NOT allowed (not in the registered list, and never auto-approved by accident)", async (fqn) => {
    const { ctx } = make();
    const res = await call(ctx, fqn, { run_id: 1, title: "t" });
    expect(res.behavior).not.toBe("allow");
  });

  test("the allow list is the registrar's list: removing one name denies exactly that tool (no re-resolve, no widening)", async () => {
    const { ctx } = make();
    const trimmed = { ...ctx, platformToolNames: ctx.platformToolNames.filter((n) => n !== `${P}github_read_pr`) } as CanUseToolContext;
    expect((await call(trimmed, `${P}github_read_pr`, { pull_number: 1 })).behavior).not.toBe("allow");
    expect((await call(trimmed, `${P}github_read_issue`, { issue_number: 1 })).behavior).toBe("allow");
  });
});
