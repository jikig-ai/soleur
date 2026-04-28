// Drift-guard tests for `buildAgentQueryOptions` (#2922). Two consumers
// (legacy `agent-runner.ts startAgentSession` and cc-soleur-go
// `realSdkQueryFactory` in `cc-dispatcher.ts`) MUST receive the same
// canonical options shape for shared fields. Per-call divergent fields
// (mcpServers, allowedTools, model, maxTurns, etc.) flow through args.
//
// T1 — minimum-args call returns the canonical shape (cwd, model,
//      permissionMode, settingSources, includePartialMessages, sandbox,
//      plugins, hooks.PreToolUse).
// T2 — args.allowedTools wired through verbatim.
// T3 — args.systemPrompt wired through verbatim.
// T4 — drift-guard: stable JSON snapshot of canonical fields fails
//      LOUDLY when the helper drifts.

import { describe, it, expect, vi } from "vitest";

vi.mock("@/server/agent-env", () => ({
  buildAgentEnv: vi.fn((apiKey: string, _tokens: Record<string, string>) => ({
    ANTHROPIC_API_KEY: apiKey,
  })),
}));

vi.mock("@/server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => async () => ({})),
}));

import { buildAgentQueryOptions } from "@/server/agent-runner-query-options";

const WORKSPACE = "/tmp/test-workspace";
const PLUGIN = "/tmp/test-workspace/plugins/soleur";

const minArgs = {
  workspacePath: WORKSPACE,
  pluginPath: PLUGIN,
  apiKey: "sk-test",
  serviceTokens: {} as Record<string, string>,
  systemPrompt: "you are a router",
  canUseTool: (async () => ({ behavior: "allow" as const, updatedInput: {} })) as never,
};

describe("buildAgentQueryOptions — canonical shape (T1)", () => {
  it("T1: returns the canonical shape for minimum args", () => {
    const opts = buildAgentQueryOptions(minArgs);

    expect(opts.cwd).toBe(WORKSPACE);
    expect(opts.model).toBe("claude-sonnet-4-6");
    expect(opts.permissionMode).toBe("default");
    expect(opts.settingSources).toEqual([]);
    expect(opts.includePartialMessages).toBe(true);
    expect(opts.disallowedTools).toEqual(["WebSearch", "WebFetch"]);
    expect(opts.sandbox).toBeDefined();
    // biome-ignore lint/style/noNonNullAssertion: shape verified by toBeDefined
    expect(opts.sandbox!.failIfUnavailable).toBe(true);
    expect(opts.plugins).toEqual([{ type: "local", path: PLUGIN }]);
    expect(opts.hooks?.PreToolUse).toBeDefined();
    // biome-ignore lint/style/noNonNullAssertion: shape verified above
    expect(Array.isArray(opts.hooks!.PreToolUse)).toBe(true);
    // biome-ignore lint/style/noNonNullAssertion: shape verified above
    expect(opts.hooks!.PreToolUse![0].matcher).toContain("Bash");
    expect(opts.systemPrompt).toBe("you are a router");
    expect(opts.canUseTool).toBe(minArgs.canUseTool);
  });
});

describe("buildAgentQueryOptions — per-call overrides (T2/T3)", () => {
  it("T2: allowedTools is wired through verbatim", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      allowedTools: ["mcp__soleur_platform__kb_share_create"],
    });
    expect(opts.allowedTools).toEqual([
      "mcp__soleur_platform__kb_share_create",
    ]);
  });

  it("T3: systemPrompt is wired through verbatim", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      systemPrompt: "alpha bravo charlie",
    });
    expect(opts.systemPrompt).toBe("alpha bravo charlie");
  });

  it("threads resumeSessionId into options.resume when present", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      resumeSessionId: "sess-abc",
    });
    expect(opts.resume).toBe("sess-abc");
  });

  it("omits options.resume when no resumeSessionId provided", () => {
    const opts = buildAgentQueryOptions(minArgs);
    expect(opts.resume).toBeUndefined();
  });

  it("threads model override (cc path uses claude-sonnet-4-6 too — same default)", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      model: "claude-opus-4-7",
    });
    expect(opts.model).toBe("claude-opus-4-7");
  });

  it("maxTurns/maxBudgetUsd flow through (legacy path)", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      maxTurns: 50,
      maxBudgetUsd: 5.0,
    });
    expect(opts.maxTurns).toBe(50);
    expect(opts.maxBudgetUsd).toBe(5.0);
  });

  it("mcpServers={} (cc path) is preserved", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      mcpServers: {},
    });
    expect(opts.mcpServers).toEqual({});
  });

  it("subagentStartPayloadOverride switches the SubagentStart hook payload (legacy vs cc)", () => {
    // Legacy path strips [\r\n]; cc strips control chars + Unicode line/paragraph
    // separators + adds ccPath: true. Helper must accept the override.
    const cc = buildAgentQueryOptions({
      ...minArgs,
      subagentStartPayloadOverride: {
        sanitizer: (v: unknown) =>
          String(v ?? "")
            .replace(/[\x00-\x1f\x7f\u2028\u2029]/g, " ")
            .slice(0, 200),
        extraLogFields: { ccPath: true },
        logMessage: "Subagent started (cc-soleur-go)",
      },
    });
    expect(cc.hooks?.SubagentStart).toBeDefined();
    // biome-ignore lint/style/noNonNullAssertion: shape verified above
    expect(Array.isArray(cc.hooks!.SubagentStart)).toBe(true);
  });
});

describe("buildAgentQueryOptions — drift-guard snapshot (T4)", () => {
  // Stable JSON serialization across Node versions per plan Enhancement #2:
  // sort keys explicitly and exclude function-valued fields (canUseTool,
  // hooks, sandbox is object-only).
  function stableShape(opts: Record<string, unknown>): string {
    const SHARED_KEYS = [
      "cwd",
      "model",
      "permissionMode",
      "settingSources",
      "includePartialMessages",
      "disallowedTools",
    ] as const;
    const subset: Record<string, unknown> = {};
    for (const k of SHARED_KEYS) subset[k] = opts[k];
    return JSON.stringify(subset, Object.keys(subset).sort());
  }

  it("T4a: shared shape stable for legacy minimum args", () => {
    const opts = buildAgentQueryOptions(minArgs);
    expect(stableShape(opts as unknown as Record<string, unknown>)).toBe(
      JSON.stringify(
        {
          cwd: WORKSPACE,
          model: "claude-sonnet-4-6",
          permissionMode: "default",
          settingSources: [],
          includePartialMessages: true,
          disallowedTools: ["WebSearch", "WebFetch"],
        },
        [
          "cwd",
          "disallowedTools",
          "includePartialMessages",
          "model",
          "permissionMode",
          "settingSources",
        ],
      ),
    );
  });

  it("T4b: shared shape identical between legacy + cc args (drift-guard)", () => {
    const legacy = buildAgentQueryOptions({
      ...minArgs,
      maxTurns: 50,
      maxBudgetUsd: 5.0,
      allowedTools: ["mcp__soleur_platform__kb_share_create"],
    });
    const cc = buildAgentQueryOptions({
      ...minArgs,
      mcpServers: {},
      subagentStartPayloadOverride: {
        sanitizer: (v: unknown) => String(v ?? ""),
        extraLogFields: { ccPath: true },
        logMessage: "Subagent started (cc)",
      },
    });
    expect(stableShape(legacy as unknown as Record<string, unknown>)).toBe(
      stableShape(cc as unknown as Record<string, unknown>),
    );
  });
});
