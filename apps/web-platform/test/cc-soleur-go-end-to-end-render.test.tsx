/**
 * Stage 4 (#2886) — Component-level integration smoke for the cc-soleur-go
 * render pipeline.
 *
 * Replays a recorded WS event sequence through the reducer and asserts that
 * the resulting ChatMessage tree contains every Stage 4 variant in the right
 * place. Uses `applyStreamEvent` directly (not WebSocket), so the test is
 * deterministic and runs in jsdom.
 *
 * Per `cq-jsdom-no-layout-gated-assertions`: assertions key off message type
 * + `data-*` attributes on rendered components, never `clientWidth` / etc.
 */
import { describe, test, expect } from "vitest";
import { render } from "@testing-library/react";
import {
  applyStreamEvent,
  type ChatMessage,
  type WorkflowLifecycleState,
  type SpawnIndex,
} from "@/lib/chat-state-machine";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { SubagentGroup } from "@/components/chat/subagent-group";
import { InteractivePromptCard } from "@/components/chat/interactive-prompt-card";
import { ToolUseChip } from "@/components/chat/tool-use-chip";
import { WorkflowLifecycleBar } from "@/components/chat/workflow-lifecycle-bar";

interface ReducerState {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, number>;
  workflow: WorkflowLifecycleState;
  spawnIndex: SpawnIndex;
}

function emptyState(): ReducerState {
  return {
    messages: [],
    activeStreams: new Map(),
    workflow: { state: "idle" },
    spawnIndex: new Map(),
  };
}

// Review F22 (#2886): use the inferred event type from `applyStreamEvent`'s
// 3rd parameter once at the helper signature, so individual events declared
// in the test bodies don't need an `as Parameters<typeof ...>[2]` per-event.
type StreamEventArg = Parameters<typeof applyStreamEvent>[2];

// Replay a list of WS events through `applyStreamEvent` and return the
// final reducer state. Deliberately threads `workflow` and `spawnIndex`
// since the Stage 4 reducer needs them.
function replay(events: StreamEventArg[]): ReducerState {
  let state = emptyState();
  for (const ev of events) {
    const r = applyStreamEvent(
      state.messages,
      state.activeStreams,
      ev,
      state.spawnIndex,
      state.workflow,
    );
    state = {
      messages: r.messages,
      activeStreams: r.activeStreams,
      workflow: r.workflow,
      spawnIndex: r.spawnIndex,
    };
  }
  return state;
}

describe("cc-soleur-go end-to-end reducer + render", () => {
  test("workflow_started → tool_use chip path → subagent_spawn × 2 → subagent_complete → interactive_prompt → workflow_ended", () => {
    const state = replay([
      // 1. cc_router emits a routing tool_use chip.
      {
        type: "tool_use",
        leaderId: "cc_router" as DomainLeaderId,
        label: "Routing via /soleur:go",
      } as StreamEventArg,
      // 2. Workflow starts — chip MUST be removed by reducer.
      {
        type: "workflow_started",
        workflow: "brainstorm",
        conversationId: "c-1",
      } as StreamEventArg,
      // 3. Two subagents spawn under the same parent.
      {
        type: "subagent_spawn",
        parentId: "p-1",
        leaderId: "cmo" as DomainLeaderId,
        spawnId: "s-1",
        task: "Audit copy",
      } as StreamEventArg,
      {
        type: "subagent_spawn",
        parentId: "p-1",
        leaderId: "cfo" as DomainLeaderId,
        spawnId: "s-2",
        task: "Audit budget",
      } as StreamEventArg,
      // 4. One of them completes successfully.
      {
        type: "subagent_complete",
        spawnId: "s-1",
        status: "success",
      } as StreamEventArg,
      // 5. An interactive prompt is raised.
      {
        type: "interactive_prompt",
        promptId: "pr-1",
        conversationId: "c-1",
        kind: "ask_user",
        payload: { question: "Continue?", options: ["yes", "no"], multiSelect: false },
      } as StreamEventArg,
      // 6. Workflow ends.
      {
        type: "workflow_ended",
        workflow: "brainstorm",
        status: "completed",
        summary: "Done",
      } as StreamEventArg,
    ]);

    // Reducer-level assertions.
    // No tool_use_chip survives workflow_started.
    expect(state.messages.filter((m) => m.type === "tool_use_chip").length).toBe(0);
    // One subagent_group with two children, child 0 completed.
    const group = state.messages.find((m) => m.type === "subagent_group");
    expect(group).toBeDefined();
    if (group?.type === "subagent_group") {
      expect(group.children.length).toBe(2);
      expect(group.children[0].status).toBe("success");
      expect(group.children[1].status).toBeUndefined();
    }
    // One interactive_prompt card.
    const prompt = state.messages.find((m) => m.type === "interactive_prompt");
    expect(prompt).toBeDefined();
    // One workflow_ended summary card.
    const ended = state.messages.find((m) => m.type === "workflow_ended");
    expect(ended).toBeDefined();
    // Lifecycle bar slice ended.
    expect(state.workflow.state).toBe("ended");

    // Render-level smoke: render each component standalone, asserting the
    // `data-*` hooks are present. Component composition in chat-surface is
    // exercised by the dedicated chat-surface-sidebar tests.
    if (group?.type === "subagent_group") {
      const { container } = render(
        <SubagentGroup
          parentSpawnId={group.parentSpawnId}
          parentLeaderId={group.parentLeaderId}
          parentTask={group.parentTask}
          subagents={group.children}
        />,
      );
      expect(container.querySelector(`[data-parent-spawn-id="${group.parentSpawnId}"]`)).not.toBeNull();
    }
    if (prompt?.type === "interactive_prompt" && prompt.promptKind === "ask_user") {
      const { container } = render(
        <InteractivePromptCard
          promptId={prompt.promptId}
          conversationId={prompt.conversationId}
          kind="ask_user"
          payload={prompt.promptPayload as { question: string; options: string[]; multiSelect: boolean }}
          onRespond={() => {}}
        />,
      );
      expect(container.querySelector('[data-prompt-kind="ask_user"]')).not.toBeNull();
    }
    if (state.workflow.state === "ended") {
      const { container } = render(<WorkflowLifecycleBar lifecycle={state.workflow} />);
      expect(container.querySelector('[data-lifecycle-state="ended"]')).not.toBeNull();
    }
  });

  test("tool_progress does NOT spawn a chip on the cc_router leader (regression)", () => {
    const state = replay([
      {
        type: "tool_progress",
        leaderId: "cc_router" as DomainLeaderId,
        toolUseId: "tu-1",
        toolName: "Skill",
        elapsedSeconds: 3,
      } as StreamEventArg,
    ]);
    expect(state.messages.length).toBe(0);
  });

  test("KB Concierge: stream → stream_end transitions cc_router bubble to 'done' so MarkdownRenderer engages", () => {
    // Drives the wire sequence the cc-dispatcher emits for a Concierge
    // turn that contains markdown. Without `stream_end`, the bubble would
    // stay in `state: "streaming"` (whitespace-pre-wrap raw text).
    const state = replay([
      {
        type: "stream_start",
        leaderId: "cc_router" as DomainLeaderId,
        source: "auto",
      } as StreamEventArg,
      {
        type: "stream",
        content: "**bold** text and a list:\n- one\n- two",
        partial: true,
        leaderId: "cc_router" as DomainLeaderId,
      } as StreamEventArg,
      {
        type: "stream_end",
        leaderId: "cc_router" as DomainLeaderId,
      } as StreamEventArg,
    ]);
    const bubble = state.messages.find(
      (m) => m.type === "text" && m.leaderId === "cc_router",
    );
    expect(bubble).toBeDefined();
    if (bubble && bubble.type === "text") {
      // Bubble must be in "done" so message-bubble.tsx:263 engages
      // MarkdownRenderer instead of the raw <p whitespace-pre-wrap> branch
      // at message-bubble.tsx:219-225.
      expect(bubble.state).toBe("done");
      expect(bubble.content).toContain("**bold**");
    }
    // activeStreams must no longer track cc_router after stream_end.
    expect(state.activeStreams.has("cc_router" as DomainLeaderId)).toBe(false);
  });

  test("ToolUseChip renders the Stage 4 chip variant from a real reducer message", () => {
    const state = replay([
      {
        type: "tool_use",
        leaderId: "cc_router" as DomainLeaderId,
        label: "Routing",
      } as StreamEventArg,
    ]);
    const chip = state.messages[0];
    expect(chip.type).toBe("tool_use_chip");
    if (chip.type === "tool_use_chip") {
      const { container } = render(
        <ToolUseChip
          toolName={chip.toolName}
          toolLabel={chip.toolLabel}
          leaderId={chip.leaderId}
        />,
      );
      expect(container.querySelector("[data-tool-chip-id]")).not.toBeNull();
    }
  });
});
