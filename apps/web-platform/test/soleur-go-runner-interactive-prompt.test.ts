import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import {
  createSoleurGoRunner,
  type QueryFactory,
} from "@/server/soleur-go-runner";
import {
  createMockQueryLean as createMockQuery,
  flushMicrotasks,
  makeAssistant,
} from "./helpers/soleur-go-fixtures";
import {
  PendingPromptRegistry,
  makePendingPromptKey,
} from "@/server/pending-prompt-registry";
import type { WSMessage } from "@/lib/types";
import { mintPromptId, mintConversationId } from "@/lib/branded-ids";
type InteractivePromptEvent = Extract<WSMessage, { type: "interactive_prompt" }>;

// RED test for Stage 2.10 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md.
//
// The "interactive-tool bridge" in the runner classifies assistant-message
// `tool_use` blocks whose `name` matches one of the six interactive kinds,
// synthesizes a payload, registers the prompt in the PendingPromptRegistry
// (composite key `${userId}:${conversationId}:${promptId}`), and emits
// `interactive_prompt` events via `deps.emitInteractivePrompt`.
//
// Non-interactive tool_use blocks (Skill, Glob, Grep, Read, LS, etc.) must
// NOT produce registry entries or WS events. This negative-space case is
// gated behind a dedicated assertion so a classifier that accidentally
// widens never falls back to a no-op pass.
//
// Invariants under test:
//   (a) ExitPlanMode → kind="plan_preview"; plan markdown in payload.
//   (b) TodoWrite → kind="todo_write"; items forwarded.
//   (c) NotebookEdit → kind="notebook_edit"; cellIds extracted.
//   (d) Edit / Write → kind="diff"; file path + coarse add/del counts.
//   (e) Bash → kind="bash_approval"; command + cwd + gated flag.
//   (f) AskUserQuestion → kind="ask_user"; question + options.
//   (g) Non-interactive tool_use (Skill) → neither emit nor register.
//   (h) Every emission is paired 1:1 with a registry entry under the same
//       composite key, so the `interactive_prompt_response` handler can
//       resolve back to the tool_use.
//   (i) Ownership key composition matches `makePendingPromptKey(userId,
//       conversationId, promptId)`. The promptId in the emitted event
//       matches the registered record's promptId.

function makeEvents() {
  return {
    onText: vi.fn(),
    onToolUse: vi.fn(),
    onWorkflowDetected: vi.fn(),
    onWorkflowEnded: vi.fn(),
    onResult: vi.fn(),
  };
}

describe("soleur-go-runner interactive-prompt bridge (Stage 2.10)", () => {
  let emittedEvents: Array<{ userId: string; event: InteractivePromptEvent }>;
  let registry: PendingPromptRegistry;
  let emitInteractivePrompt: ReturnType<
    typeof vi.fn<(userId: string, event: InteractivePromptEvent) => void>
  >;

  beforeEach(() => {
    vi.useFakeTimers({ now: 0 });
    emittedEvents = [];
    registry = new PendingPromptRegistry({ nowFn: () => Date.now() });
    emitInteractivePrompt = vi.fn<(userId: string, event: InteractivePromptEvent) => void>(
      (userId: string, event: InteractivePromptEvent) => {
        emittedEvents.push({ userId, event });
      },
    );
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  async function runOneToolUse(
    toolUse: {
      id: string;
      name: string;
      input: Record<string, unknown>;
    },
  ): Promise<void> {
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-1",
      userId: "user-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events: makeEvents(),
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });
    mock.emit(makeAssistant({ content: [{ type: "tool_use", ...toolUse }] }));
    await flushMicrotasks();
    mock.finish();
    await flushMicrotasks();
  }

  it("ExitPlanMode tool_use → emit interactive_prompt with kind plan_preview", async () => {
    await runOneToolUse({
      id: "toolu_plan",
      name: "ExitPlanMode",
      input: { plan: "1. Do A\n2. Do B" },
    });

    expect(emittedEvents).toHaveLength(1);
    const { event, userId } = emittedEvents[0]!;
    expect(userId).toBe("user-1");
    expect(event.type).toBe("interactive_prompt");
    expect(event.kind).toBe("plan_preview");
    expect(event.conversationId).toBe("conv-1");
    if (event.kind === "plan_preview") {
      expect(event.payload.markdown).toBe("1. Do A\n2. Do B");
    }

    // Registry contains the matching record.
    const key = makePendingPromptKey("user-1", mintConversationId("conv-1"), mintPromptId(event.promptId));
    const record = registry.get(key, "user-1");
    expect(record).toBeDefined();
    expect(record!.kind).toBe("plan_preview");
    expect(record!.toolUseId).toBe("toolu_plan");
  });

  it("TodoWrite tool_use → emit interactive_prompt with kind todo_write", async () => {
    await runOneToolUse({
      id: "toolu_todo",
      name: "TodoWrite",
      input: {
        todos: [
          { content: "First", status: "pending", activeForm: "Doing first" },
        ],
      },
    });

    expect(emittedEvents).toHaveLength(1);
    const { event } = emittedEvents[0]!;
    expect(event.kind).toBe("todo_write");
    if (event.kind === "todo_write") {
      expect(event.payload.items.length).toBeGreaterThanOrEqual(1);
    }
  });

  it("NotebookEdit tool_use → emit interactive_prompt with kind notebook_edit", async () => {
    await runOneToolUse({
      id: "toolu_nb",
      name: "NotebookEdit",
      input: { notebook_path: "/w/book.ipynb", cell_id: "c-1", new_source: "print(1)" },
    });

    expect(emittedEvents).toHaveLength(1);
    const { event } = emittedEvents[0]!;
    expect(event.kind).toBe("notebook_edit");
    if (event.kind === "notebook_edit") {
      expect(event.payload.notebookPath).toBe("/w/book.ipynb");
      expect(event.payload.cellIds).toContain("c-1");
    }
  });

  it("Edit tool_use → emit interactive_prompt with kind diff", async () => {
    await runOneToolUse({
      id: "toolu_edit",
      name: "Edit",
      input: {
        file_path: "/w/src/foo.ts",
        old_string: "a\nb\nc",
        new_string: "a\nb\nc\nd",
      },
    });

    expect(emittedEvents).toHaveLength(1);
    const { event } = emittedEvents[0]!;
    expect(event.kind).toBe("diff");
    if (event.kind === "diff") {
      expect(event.payload.path).toBe("/w/src/foo.ts");
      // Input: old_string="a\nb\nc" (3 lines), new_string="a\nb\nc\nd" (4 lines).
      // classifier computes max(0, new-old)=1 / max(0, old-new)=0 — pin exactly
      // so a classifier drift (e.g., swapping add/del) surfaces as a diff, not
      // as a tautology per `cq-mutation-assertions-pin-exact-post-state`.
      expect(event.payload.additions).toBe(1);
      expect(event.payload.deletions).toBe(0);
    }
  });

  it("Bash tool_use (non-allowlisted) → emits NO interactive_prompt (AC1: bash_approval card suppressed; command streams inline instead)", async () => {
    // feat-concierge-stream-commands (AC1): Bash no longer produces a
    // `bash_approval` interactive-prompt card. Autonomous workspaces stream
    // the command + output inline (`command_stream`); non-autonomous ones
    // gate via the authoritative `review_gate` in permission-callback. The
    // informational card is redundant either way, so classifier returns null.
    await runOneToolUse({
      id: "toolu_bash",
      name: "Bash",
      input: { command: "npm test", cwd: "/w" },
    });
    expect(emittedEvents).toHaveLength(0);
  });

  it("Bash tool_use (safe-bash allowlist) → still emits NO interactive_prompt", async () => {
    await runOneToolUse({
      id: "toolu_pwd",
      name: "Bash",
      input: { command: "pwd", cwd: "/w" },
    });
    expect(emittedEvents).toHaveLength(0);

    await runOneToolUse({
      id: "toolu_ls",
      name: "Bash",
      input: { command: "ls -la", cwd: "/w" },
    });
    expect(emittedEvents).toHaveLength(0);

    await runOneToolUse({
      id: "toolu_git_status",
      name: "Bash",
      input: { command: "git status", cwd: "/w" },
    });
    expect(emittedEvents).toHaveLength(0);
  });

  it("AskUserQuestion tool_use → emits NO interactive_prompt (AC1: ask_user card suppressed; the amber review_gate is the single surface)", async () => {
    // De-dup fix (feat-one-shot-concierge-web-duplicate-question-box, AC1):
    // AskUserQuestion no longer produces an `ask_user` interactive-prompt card.
    // The authoritative `review_gate` (permission-callback.ts `canUseTool`,
    // fired unconditionally for every AskUserQuestion) is the single question
    // surface — the amber "Confirm scope" card with per-option descriptions.
    // classifyInteractiveTool returns null, mirroring the Bash suppression
    // above, so no `interactive_prompt` is emitted and no pending prompt is
    // registered. The `ask_user` variant is KEPT in the union +
    // InteractivePromptCard for replay of already-persisted prompts.
    await runOneToolUse({
      id: "toolu_ask",
      name: "AskUserQuestion",
      input: {
        questions: [
          { question: "A or B?", header: "h", multiSelect: false, options: [{ label: "A" }, { label: "B" }] },
        ],
      },
    });

    expect(emittedEvents).toHaveLength(0);
    expect(registry.size()).toBe(0);
  });

  it("non-interactive tool_use (Skill) does NOT emit or register", async () => {
    await runOneToolUse({
      id: "toolu_skill",
      name: "Skill",
      input: { skill: "brainstorm" },
    });

    expect(emittedEvents).toHaveLength(0);
    expect(registry.size()).toBe(0);
  });

  it("no emit / no register when both deps are absent (runner remains usable w/o bridge)", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
    });
    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-2",
      userId: "user-2",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events: makeEvents(),
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });
    mock.emit(
      makeAssistant({
        content: [
          {
            type: "tool_use",
            id: "toolu_plan_2",
            name: "ExitPlanMode",
            input: { plan: "stuff" },
          },
        ],
      }),
    );
    await flushMicrotasks();
    mock.finish();
    await flushMicrotasks();

    // With no registry and no emitter, the runner must still run cleanly.
    expect(emittedEvents).toHaveLength(0);
  });
});
