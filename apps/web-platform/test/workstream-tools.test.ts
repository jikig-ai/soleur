import { afterEach, describe, expect, it, vi } from "vitest";
import type { WorkstreamIssue } from "@/lib/workstream";

// Read-parity assertion: the workstream_issues_list agent tool returns the SAME
// issues the dashboard route serves, over the shared (now async, user-scoped)
// getWorkstreamIssues() accessor (no duplicated query). The accessor is MOCKED
// here so there are NO live GitHub/network calls. The SDK `tool()` wrapper is
// mocked to a plain object so the handler is directly invokable.

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

const getWorkstreamIssues = vi.fn();
vi.mock("@/server/workstream/get-workstream-issues", () => ({
  getWorkstreamIssues: (userId: string) => getWorkstreamIssues(userId),
}));

import { buildWorkstreamTools } from "@/server/workstream/workstream-tools";

type ToolStub = {
  name: string;
  handler: () => Promise<{
    content: Array<{ type: "text"; text: string }>;
    isError?: true;
  }>;
};

function getListTool(userId = "u1"): ToolStub {
  const built = buildWorkstreamTools({ userId });
  const t = built.tools.find(
    (x) => (x as unknown as ToolStub).name === "workstream_issues_list",
  );
  if (!t) throw new Error("workstream_issues_list not found");
  return t as unknown as ToolStub;
}

const FIXTURE: WorkstreamIssue[] = [
  {
    id: "5652",
    title: "Tighten the gap",
    description: "body",
    status: "in_progress",
    priority: "high",
    assigneeRole: "cto",
    user: { name: "harry", initials: "HA" },
    live: true,
    createdAt: "2026-06-20T09:00:00.000Z",
    updatedAt: "2026-06-21T09:00:00.000Z",
  },
];

afterEach(() => {
  getWorkstreamIssues.mockReset();
});

describe("buildWorkstreamTools", () => {
  it("registers the read tool name (auto-approve) alongside the write tools", () => {
    const built = buildWorkstreamTools({ userId: "u1" });
    expect(built.toolNames).toContain(
      "mcp__soleur_platform__workstream_issues_list",
    );
    // Read tool is still present + invokable (write tools covered separately).
    expect(
      built.tools.some(
        (t) =>
          (t as unknown as { name: string }).name === "workstream_issues_list",
      ),
    ).toBe(true);
  });

  it("threads userId into the accessor and returns its mapped issues (read parity)", async () => {
    getWorkstreamIssues.mockResolvedValue(FIXTURE);
    const res = await getListTool("operator-7").handler();
    expect(res.isError).toBeUndefined();
    expect(getWorkstreamIssues).toHaveBeenCalledWith("operator-7");
    const parsed = JSON.parse(res.content[0].text) as { issues: unknown[] };
    expect(parsed.issues).toEqual(FIXTURE);
  });

  it("serializes an empty board honestly (no repo connected → [])", async () => {
    getWorkstreamIssues.mockResolvedValue([]);
    const res = await getListTool().handler();
    expect(res.isError).toBeUndefined();
    const parsed = JSON.parse(res.content[0].text) as { issues: unknown[] };
    expect(parsed.issues).toEqual([]);
  });

  it("returns isError when the accessor throws (GitHub failure, not empty)", async () => {
    getWorkstreamIssues.mockRejectedValue(new Error("GitHub API 502"));
    const res = await getListTool().handler();
    expect(res.isError).toBe(true);
    const parsed = JSON.parse(res.content[0].text) as { error: string };
    expect(parsed.error).toBe("workstream_query_error");
  });

  it("surfaces a degraded read as isError, NOT a misleading empty board (AC6)", async () => {
    const { WorkstreamDegradedError } = await import("@/lib/workstream");
    getWorkstreamIssues.mockRejectedValue(
      new WorkstreamDegradedError("workstream read degraded"),
    );
    const res = await getListTool().handler();
    expect(res.isError).toBe(true);
    const parsed = JSON.parse(res.content[0].text) as { error: string };
    expect(parsed.error).toBe("workstream_query_error");
  });
});
