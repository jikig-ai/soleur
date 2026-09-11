import { describe, expect, it } from "vitest";
import {
  AgentEngineBindingStore,
  EngineBindingAuthorizationError,
} from "@/server/agent-engine-binding";

describe("AgentEngineBindingStore", () => {
  it("binds the current workspace default once and keeps retries on that engine", () => {
    const store = new AgentEngineBindingStore({ defaultEngineId: "claude-code" });
    const first = store.bind({
      execution: { kind: "conversation", conversationId: "conv-1" },
      actor: { userId: "member-1", isWorkspaceOwner: false },
    });

    store.setDefaultEngine("codex", { userId: "owner-1", isWorkspaceOwner: true });

    expect(first.engineId).toBe("claude-code");
    expect(store.get(first.runId)?.engineId).toBe("claude-code");
    expect(store.retry(first.runId)?.engineId).toBe("claude-code");
  });

  it("allows a workspace member to create a conversation binding", () => {
    const store = new AgentEngineBindingStore({ defaultEngineId: "claude-code" });
    expect(() => store.bind({
      execution: { kind: "conversation", conversationId: "conv-2" },
      actor: { userId: "member-1", isWorkspaceOwner: false },
    })).not.toThrow();
  });

  it("restricts workspace default mutation to an owner", () => {
    const store = new AgentEngineBindingStore({ defaultEngineId: "claude-code" });
    expect(() => store.setDefaultEngine("codex", { userId: "member-1", isWorkspaceOwner: false }))
      .toThrowError(new EngineBindingAuthorizationError("workspace_default_owner_required"));
  });

  it("rejects a second binding for the same execution", () => {
    const store = new AgentEngineBindingStore({ defaultEngineId: "claude-code" });
    const input = {
      execution: { kind: "routine", routineId: "routine-1", schedulerKey: "cron:daily" } as const,
      actor: { userId: "owner-1", isWorkspaceOwner: true },
    };
    store.bind(input);
    expect(() => store.bind(input)).toThrowError(/already bound/);
  });
});
