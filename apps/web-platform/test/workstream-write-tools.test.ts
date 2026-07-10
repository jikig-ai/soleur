import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { WorkstreamIssue } from "@/lib/workstream";

// Agent-user WRITE parity (AC6): the workstream write tools delegate to the SAME
// shared mutateWorkstreamIssue accessor the HTTP routes call (no gh shell-out,
// no duplicated query). The accessor is mocked so there are no live GitHub calls.
// The SDK tool() wrapper is mocked to a plain object so handlers are invokable.

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn(
    (name: string, description: string, schema: unknown, handler: Function) => ({
      name,
      description,
      schema,
      handler,
    }),
  ),
}));

const createWorkstreamIssue = vi.fn();
const updateWorkstreamIssueTitle = vi.fn();
const setWorkstreamIssueStatus = vi.fn();
const reopenWorkstreamIssue = vi.fn();
const updateWorkstreamIssueFields = vi.fn();
vi.mock("@/server/workstream/mutate-workstream-issue", () => ({
  createWorkstreamIssue: (...a: unknown[]) => createWorkstreamIssue(...a),
  updateWorkstreamIssueTitle: (...a: unknown[]) =>
    updateWorkstreamIssueTitle(...a),
  setWorkstreamIssueStatus: (...a: unknown[]) => setWorkstreamIssueStatus(...a),
  reopenWorkstreamIssue: (...a: unknown[]) => reopenWorkstreamIssue(...a),
  updateWorkstreamIssueFields: (...a: unknown[]) =>
    updateWorkstreamIssueFields(...a),
}));

vi.mock("@/server/workstream/get-workstream-issues", () => ({
  getWorkstreamIssues: vi.fn(),
}));

const getWorkstreamIssueOptions = vi.fn();
vi.mock("@/server/workstream/get-workstream-issue-options", () => ({
  getWorkstreamIssueOptions: (...a: unknown[]) =>
    getWorkstreamIssueOptions(...a),
}));

import { buildWorkstreamTools } from "@/server/workstream/workstream-tools";

type ToolStub = {
  name: string;
  handler: (args: Record<string, unknown>) => Promise<{
    content: Array<{ type: "text"; text: string }>;
    isError?: true;
  }>;
};

function tool(name: string, userId = "op-1"): ToolStub {
  const built = buildWorkstreamTools({ userId });
  const t = built.tools.find((x) => (x as unknown as ToolStub).name === name);
  if (!t) throw new Error(`${name} not found`);
  return t as unknown as ToolStub;
}

const ISSUE: WorkstreamIssue = {
  id: "77",
  title: "made",
  description: "",
  status: "backlog",
  priority: "none",
  assigneeRole: null,
  createdAt: "2026-07-10T00:00:00Z",
  updatedAt: "2026-07-10T00:00:00Z",
};

beforeEach(() => {
  vi.clearAllMocks();
  createWorkstreamIssue.mockResolvedValue(ISSUE);
  updateWorkstreamIssueTitle.mockResolvedValue(ISSUE);
  setWorkstreamIssueStatus.mockResolvedValue(ISSUE);
  reopenWorkstreamIssue.mockResolvedValue(ISSUE);
  updateWorkstreamIssueFields.mockResolvedValue(ISSUE);
  getWorkstreamIssueOptions.mockResolvedValue({
    labels: [{ name: "bug", color: "d73a4a" }],
    assignees: [{ login: "harry" }],
    milestones: [{ number: 1, title: "v1" }],
  });
});
afterEach(() => vi.clearAllMocks());

describe("workstream write tools (AC6)", () => {
  it("registers the write + options tool names alongside the read tool", () => {
    const built = buildWorkstreamTools({ userId: "op-1" });
    expect(built.toolNames).toEqual(
      expect.arrayContaining([
        "mcp__soleur_platform__workstream_issues_list",
        "mcp__soleur_platform__workstream_issue_create",
        "mcp__soleur_platform__workstream_issue_set_status",
        "mcp__soleur_platform__workstream_issue_update_title",
        "mcp__soleur_platform__workstream_issue_close",
        "mcp__soleur_platform__workstream_issue_update_fields",
        "mcp__soleur_platform__workstream_issue_options",
      ]),
    );
  });

  it("update_fields delegates to updateWorkstreamIssueFields with the provided keys (agent-user parity)", async () => {
    await tool("workstream_issue_update_fields").handler({
      number: 42,
      body: "new body",
      labels: ["bug"],
      assignees: ["harry"],
      milestone: 3,
    });
    expect(updateWorkstreamIssueFields).toHaveBeenCalledWith("op-1", 42, {
      body: "new body",
      labels: ["bug"],
      assignees: ["harry"],
      milestone: 3,
    });
  });

  it("update_fields forwards milestone:null (clear) and omits absent keys", async () => {
    await tool("workstream_issue_update_fields").handler({
      number: 42,
      milestone: null,
    });
    expect(updateWorkstreamIssueFields).toHaveBeenCalledWith("op-1", 42, {
      milestone: null,
    });
  });

  it("options tool returns the discovery payload (auto-approve read)", async () => {
    const res = await tool("workstream_issue_options").handler({});
    expect(res.isError).toBeUndefined();
    expect(getWorkstreamIssueOptions).toHaveBeenCalledWith("op-1");
    const parsed = JSON.parse(res.content[0].text) as {
      labels: unknown[];
      assignees: unknown[];
      milestones: unknown[];
    };
    expect(parsed.labels).toEqual([{ name: "bug", color: "d73a4a" }]);
    expect(parsed.milestones).toEqual([{ number: 1, title: "v1" }]);
  });

  it("create delegates to the shared accessor with the operator userId", async () => {
    const res = await tool("workstream_issue_create").handler({
      title: "Do it",
      body: "desc",
      status: "in_progress",
    });
    expect(res.isError).toBeUndefined();
    expect(createWorkstreamIssue).toHaveBeenCalledWith("op-1", {
      title: "Do it",
      body: "desc",
      status: "in_progress",
    });
    const parsed = JSON.parse(res.content[0].text) as { issue: WorkstreamIssue };
    expect(parsed.issue.id).toBe("77");
  });

  it("set_status delegates with target column + optional state_reason", async () => {
    await tool("workstream_issue_set_status").handler({
      number: 42,
      status: "blocked",
    });
    expect(setWorkstreamIssueStatus).toHaveBeenCalledWith(
      "op-1",
      42,
      "blocked",
      undefined,
    );
  });

  it("update_title delegates to updateWorkstreamIssueTitle", async () => {
    await tool("workstream_issue_update_title").handler({
      number: 42,
      title: "New",
    });
    expect(updateWorkstreamIssueTitle).toHaveBeenCalledWith("op-1", 42, "New");
  });

  it("close delegates to set_status done with the reason; reopen path uses reopen", async () => {
    await tool("workstream_issue_close").handler({
      number: 42,
      reason: "not_planned",
    });
    expect(setWorkstreamIssueStatus).toHaveBeenCalledWith(
      "op-1",
      42,
      "done",
      "not_planned",
    );
    await tool("workstream_issue_close").handler({ number: 42, reopen: true });
    expect(reopenWorkstreamIssue).toHaveBeenCalledWith("op-1", 42);
  });

  it("returns isError when the accessor throws (fail-loud, not silent)", async () => {
    createWorkstreamIssue.mockRejectedValue(new Error("403 no write"));
    const res = await tool("workstream_issue_create").handler({ title: "x" });
    expect(res.isError).toBe(true);
    const parsed = JSON.parse(res.content[0].text) as { error: string };
    expect(parsed.error).toBe("workstream_write_error");
  });
});
