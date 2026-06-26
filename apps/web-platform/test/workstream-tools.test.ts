import { describe, expect, it, vi } from "vitest";

// Read-parity assertion: the workstream_issues_list agent tool returns the SAME
// issues the dashboard route serves, over the shared getWorkstreamIssues()
// accessor (no duplicated query). The SDK `tool()` wrapper is mocked to a plain
// object so the handler is directly invokable (mirrors conversations-tools.test).

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

import { buildWorkstreamTools } from "@/server/workstream/workstream-tools";
import { getWorkstreamIssues } from "@/server/workstream/seed-issues";

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

describe("buildWorkstreamTools", () => {
  it("registers exactly the read tool name (auto-approve namespaced id)", () => {
    const built = buildWorkstreamTools({ userId: "u1" });
    expect(built.toolNames).toEqual([
      "mcp__soleur_platform__workstream_issues_list",
    ]);
    expect(built.tools).toHaveLength(1);
  });

  it("returns the same issues as the accessor (read parity, incl. `user`)", async () => {
    const res = await getListTool().handler();
    expect(res.isError).toBeUndefined();
    const parsed = JSON.parse(res.content[0].text) as {
      issues: unknown[];
    };
    expect(parsed.issues).toEqual(getWorkstreamIssues());
    // The `user` field (Addendum item 5) is carried through for read parity.
    const withUser = (parsed.issues as Array<{ user?: unknown }>).find(
      (i) => i.user,
    );
    expect(withUser).toBeTruthy();
  });
});
