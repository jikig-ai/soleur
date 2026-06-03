import { describe, it, expect, vi, beforeEach } from "vitest";

// Issue B part 2 (AC18) — agent-native parity tool pair. Verifies the handlers
// call the resolve/set helpers and shape success/error responses, and that the
// SET tool carries the prompt-injection risk text in its description.

const { mockResolve, mockSet } = vi.hoisted(() => ({
  mockResolve: vi.fn(),
  mockSet: vi.fn(),
}));

vi.mock("@/server/resolve-bash-autonomous", () => ({
  resolveBashAutonomous: mockResolve,
}));
vi.mock("@/server/set-bash-autonomous", () => ({
  setBashAutonomous: mockSet,
}));

// Minimal tool() stub: capture (name, description, schema, handler) so we can
// invoke the handler directly and assert on the description text.
const captured: Record<
  string,
  { description: string; handler: (input: unknown) => Promise<unknown> }
> = {};
vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: (
    name: string,
    description: string,
    _schema: unknown,
    handler: (input: unknown) => Promise<unknown>,
  ) => {
    captured[name] = { description, handler };
    return { name };
  },
}));

import { buildWorkspaceSettingsTools } from "@/server/workspace-settings-tools";

function textOf(res: unknown): unknown {
  const r = res as { content: Array<{ text: string }>; isError?: boolean };
  return { payload: JSON.parse(r.content[0].text), isError: !!r.isError };
}

describe("buildWorkspaceSettingsTools", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    for (const k of Object.keys(captured)) delete captured[k];
  });

  it("registers the get + set tool names", () => {
    const { toolNames } = buildWorkspaceSettingsTools({ userId: "user-1" });
    expect(toolNames).toEqual([
      "mcp__soleur_platform__workspace_get_autonomous",
      "mcp__soleur_platform__workspace_set_autonomous",
    ]);
  });

  it("get tool returns { autonomous } from resolveBashAutonomous", async () => {
    mockResolve.mockResolvedValue(true);
    buildWorkspaceSettingsTools({ userId: "user-1" });
    const res = await captured.workspace_get_autonomous.handler({});
    expect(mockResolve).toHaveBeenCalledWith("user-1");
    expect(textOf(res)).toEqual({ payload: { autonomous: true }, isError: false });
  });

  it("set tool calls setBashAutonomous(userId, value) and returns the value", async () => {
    mockSet.mockResolvedValue(true);
    buildWorkspaceSettingsTools({ userId: "user-1" });
    const res = await captured.workspace_set_autonomous.handler({ value: true });
    expect(mockSet).toHaveBeenCalledWith("user-1", true);
    expect(textOf(res)).toEqual({ payload: { autonomous: true }, isError: false });
  });

  it("set tool surfaces an error (owner-deny / fault) as an isError response", async () => {
    mockSet.mockRejectedValue(new Error("not authorized"));
    buildWorkspaceSettingsTools({ userId: "user-1" });
    const res = await captured.workspace_set_autonomous.handler({ value: true });
    const out = textOf(res) as { payload: { error: string }; isError: boolean };
    expect(out.isError).toBe(true);
    expect(out.payload.error).toBe("not_authorized_or_failed");
  });

  it("set tool description carries the prompt-injection risk text", () => {
    buildWorkspaceSettingsTools({ userId: "user-1" });
    expect(captured.workspace_set_autonomous.description).toMatch(
      /prompt-injected|approval-bypass/i,
    );
    expect(captured.workspace_set_autonomous.description).toMatch(/owner-only/i);
  });
});
