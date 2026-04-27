import type {
  WSMessage,
  MessageState,
  AttachmentRef,
  InteractivePromptPayload,
  InteractivePromptResponsePayload,
  WorkflowName,
  SubagentCompleteStatus,
  WorkflowEndStatus,
} from "./types";
import type { DomainLeaderId } from "@/server/domain-leaders";

/**
 * Pure streaming state machine for the chat message lifecycle.
 *
 * Extracted from ws-client.ts so tests exercise the real production code
 * instead of a shadow copy. The function is deliberately pure: takes the
 * current messages array and active-stream map, returns the new state.
 * The hook layer owns timers and other side effects — this module only
 * computes state transitions.
 *
 * Stage 4 (#2886) adds four new ChatMessage variants for the `/soleur:go`
 * router protocol: subagent_group, interactive_prompt, workflow_ended,
 * tool_use_chip. A `workflow` ambient slice tracks the WorkflowLifecycleBar
 * state, and a `spawnIndex` reverse-lookup map lets `subagent_complete`
 * (which carries `spawnId` only) mutate the right child without an O(N²)
 * scan.
 */

interface ChatMessageBase {
  id: string;
  role: "user" | "assistant";
  content: string;
  leaderId?: DomainLeaderId;
  attachments?: AttachmentRef[];
  state?: MessageState;
  toolLabel?: string;
  toolsUsed?: string[];
  /**
   * FR5 (#2861): set by `applyTimeout` on the first stuck-timeout and cleared
   * on a follow-up `tool_progress` or the second consecutive timeout. When
   * true, `message-bubble.tsx` shows the "Retrying…" chip with aria-live
   * polite. The bubble's `state` stays in its transitional form
   * (`thinking` / `tool_use`) — `retrying` is the orthogonal render flag.
   */
  retrying?: boolean;
}

interface ChatTextMessage extends ChatMessageBase {
  type: "text";
}

interface ChatGateMessage extends ChatMessageBase {
  type: "review_gate";
  gateId: string;
  question: string;
  options: string[];
  header?: string;
  descriptions?: Record<string, string | undefined>;
  stepProgress?: { current: number; total: number };
  resolved?: boolean;
  selectedOption?: string;
  gateError?: string;
}

/** Stage 4 (#2886): subagent group bubble — parent leader's assessment +
 *  nested child sub-bubbles, one per spawned subagent. */
export interface ChatSubagentGroupMessage extends ChatMessageBase {
  type: "subagent_group";
  parentSpawnId: string;
  parentLeaderId: DomainLeaderId;
  parentTask?: string;
  children: Array<{
    spawnId: string;
    leaderId: DomainLeaderId;
    task?: string;
    status?: SubagentCompleteStatus;
  }>;
}

/** Stage 4 (#2886): interactive_prompt card — six discriminated kinds carried
 *  in the original wire payload; resolved via local optimistic dispatch when
 *  the user clicks a response button. */
export interface ChatInteractivePromptMessage extends ChatMessageBase {
  type: "interactive_prompt";
  promptId: string;
  conversationId: string;
  promptKind: InteractivePromptPayload["kind"];
  promptPayload: InteractivePromptPayload["payload"];
  resolved?: boolean;
  selectedResponse?: InteractivePromptResponsePayload["response"];
}

/** Stage 4 (#2886): workflow_ended in-list summary card. The ambient
 *  `WorkflowLifecycleBar` renders simultaneously and is removed when a new
 *  conversation starts. */
export interface ChatWorkflowEndedMessage extends ChatMessageBase {
  type: "workflow_ended";
  workflow: WorkflowName;
  status: WorkflowEndStatus;
  summary?: string;
}

/** Stage 4 (#2886): inline tool-use chip for `cc_router`/`system` leaders
 *  before any real leader bubble exists. Removed when a stream event for the
 *  same leader arrives or `workflow_started` fires.
 *
 *  Review F13: `leaderId` narrowed to the chip-emitting leaders. The reducer
 *  only creates chips for cc_router/system; tightening here makes the
 *  invariant compile-checked and removes the runtime cast at the chat-surface
 *  call site. */
export interface ChatToolUseChipMessage extends Omit<ChatMessageBase, "leaderId"> {
  type: "tool_use_chip";
  toolName: string;
  toolLabel: string;
  leaderId: "cc_router" | "system";
}

export type ChatMessage =
  | ChatTextMessage
  | ChatGateMessage
  | ChatSubagentGroupMessage
  | ChatInteractivePromptMessage
  | ChatWorkflowEndedMessage
  | ChatToolUseChipMessage;

/** Stage 4 (#2886): ambient lifecycle-bar slice. The bar is sticky context;
 *  `workflow_ended` sets state to "ended" AND pushes an in-list summary card.
 *
 *  Review F9: the prior `routing` variant was dead — the reducer never
 *  produced it and there's no clean WS signal for skill-name extraction
 *  pre-`workflow_started`. Dropped from the union to avoid implying
 *  capability that doesn't ship. The legacy "Routing to the right experts"
 *  chip in chat-surface covers the routing UX during this gap. */
export type WorkflowLifecycleState =
  | { state: "idle" }
  | {
      state: "active";
      workflow: WorkflowName;
      phase?: string;
      cumulativeCostUsd?: number;
    }
  | {
      state: "ended";
      workflow: WorkflowName;
      status: WorkflowEndStatus;
      summary?: string;
    };

/** Reverse-lookup index for `subagent_complete` is no longer needed —
 *  the reducer scans `prev` for the matching subagent_group + child by
 *  `spawnId`. Kept as an exported type alias for backward compat with any
 *  external snapshot consumers; the reducer treats it as a sentinel only.
 *  See review F2: absolute message indices were invalidated by
 *  `filter_prepend`. The id-based lookup is O(N) per `subagent_complete`,
 *  which is fine since spawn count per session is bounded. */
export type SpawnIndex = Map<
  string,
  { messageIdx: number; childIdx: number }
>;

/** Maximum number of `tool_use_chip` messages to retain per leader before
 *  the oldest is evicted. Plan §3 risk: "chip cap of 5 latest". */
export const TOOL_USE_CHIP_CAP_PER_LEADER = 5;

/** Snapshot of all reducer-tracked state. The hook layer holds
 *  `messages`, `activeStreams`, `workflow`, and `spawnIndex` together so
 *  `chat-surface.tsx` can read both the message list and the lifecycle bar
 *  from one source. */
export interface ChatStateSnapshot {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, number>;
  workflow: WorkflowLifecycleState;
  spawnIndex: SpawnIndex;
}

export interface StreamEventResult {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, number>;
  /** Stage 4 (#2886): ambient lifecycle slice. Always present; defaults to
   *  the prior value unless the event mutates it. */
  workflow: WorkflowLifecycleState;
  /** Stage 4 (#2886): updated spawnIndex. Defaults to the prior value. */
  spawnIndex: SpawnIndex;
  /**
   * Optional timer action the caller should apply. The state machine is
   * pure, so it doesn't call setTimeout — it only declares intent.
   *   - `reset`: (re)start the stuck-state timer for the given leaderId
   *   - `clear`: cancel any pending timer for the given leaderId
   * `undefined` means "no timer change" (e.g., auth_ok).
   */
  timerAction?:
    | { type: "reset"; leaderId: string }
    | { type: "clear"; leaderId: string }
    | { type: "clear_all" };
}

/**
 * Events that the state machine reacts to. Covers the subset of WSMessage
 * types that mutate the chat state machine (stream lifecycle + review gates),
 * plus the Stage 3 (#2885) `/soleur:go` event variants which are now
 * materialized as ChatMessage variants by Stage 4 (#2886).
 *
 * `interactive_prompt_response` is intentionally excluded — it's a
 * client→server event and never reaches the reducer.
 */
type StreamEvent = Extract<
  WSMessage,
  | { type: "stream_start" }
  | { type: "stream" }
  | { type: "stream_end" }
  | { type: "tool_use" }
  | { type: "tool_progress" }
  | { type: "review_gate" }
  | { type: "subagent_spawn" }
  | { type: "subagent_complete" }
  | { type: "workflow_started" }
  | { type: "workflow_ended" }
  | { type: "interactive_prompt" }
>;

const IDLE_WORKFLOW: WorkflowLifecycleState = { state: "idle" };

/** Build a new SpawnIndex from a prior one (copy-on-write). */
function cloneSpawnIndex(prev: SpawnIndex): SpawnIndex {
  return new Map(prev);
}

/** Stage 4 review F6: build a `ChatInteractivePromptMessage` from a wire
 *  `interactive_prompt` event with per-kind narrowing — replaces the prior
 *  `as InteractivePromptPayload["kind"]` / `as InteractivePromptPayload
 *  ["payload"]` casts. The event arrives as a discriminated union; the
 *  switch lets TS track the congruent `{kind, payload}` couple per branch.
 */
type InteractivePromptEvent = Extract<StreamEvent, { type: "interactive_prompt" }>;

function buildInteractivePromptCard(
  event: InteractivePromptEvent,
): ChatInteractivePromptMessage {
  const base = {
    id: `prompt-${event.promptId}-${event.conversationId}`,
    role: "assistant" as const,
    content: "",
    type: "interactive_prompt" as const,
    promptId: event.promptId,
    conversationId: event.conversationId,
  };
  switch (event.kind) {
    case "ask_user":
      return { ...base, promptKind: "ask_user", promptPayload: event.payload };
    case "plan_preview":
      return { ...base, promptKind: "plan_preview", promptPayload: event.payload };
    case "diff":
      return { ...base, promptKind: "diff", promptPayload: event.payload };
    case "bash_approval":
      return { ...base, promptKind: "bash_approval", promptPayload: event.payload };
    case "todo_write":
      return { ...base, promptKind: "todo_write", promptPayload: event.payload };
    case "notebook_edit":
      return { ...base, promptKind: "notebook_edit", promptPayload: event.payload };
    default: {
      const _exhaustive: never = event;
      void _exhaustive;
      throw new Error("unreachable: interactive_prompt kind exhaustiveness");
    }
  }
}

/**
 * Apply a single WS event to the chat state. Pure function — does not
 * mutate the passed `prev` or `activeStreams`, returns new instances.
 *
 * `priorWorkflow` and `priorSpawnIndex` are optional for backward-compat
 * with Stage 3 callers; they default to idle/empty. The hook layer holds
 * these in `ChatState` and threads them through.
 */
export function applyStreamEvent(
  prev: ChatMessage[],
  activeStreams: Map<DomainLeaderId, number>,
  event: StreamEvent,
  priorSpawnIndex: SpawnIndex = new Map(),
  priorWorkflow: WorkflowLifecycleState = IDLE_WORKFLOW,
): StreamEventResult {
  switch (event.type) {
    case "stream_start": {
      const newMsg: ChatMessage = {
        id: `stream-${event.leaderId}-${crypto.randomUUID()}`,
        role: "assistant",
        content: "",
        type: "text",
        leaderId: event.leaderId,
        state: "thinking",
        toolsUsed: [],
      };
      const nextStreams = new Map(activeStreams);
      nextStreams.set(event.leaderId, prev.length);
      return {
        messages: [...prev, newMsg],
        activeStreams: nextStreams,
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
        timerAction: { type: "reset", leaderId: event.leaderId },
      };
    }

    case "tool_use": {
      // Stage 4 (#2886): cc_router / system leaders have NO leader bubble —
      // emit a ChatToolUseChipMessage chip rendered above the message list.
      // Per-real-leader tool_use stays on MessageBubble.toolLabel.
      //
      // Review F8: once a stream bubble exists for cc_router/system (e.g.
      // first content has reached the user), don't append more chips —
      // chips live "between user message and first leader bubble" only.
      // Fall through to the normal per-leader path so the bubble's
      // toolLabel updates instead.
      if (
        (event.leaderId === "cc_router" || event.leaderId === "system") &&
        !activeStreams.has(event.leaderId)
      ) {
        const chip: ChatMessage = {
          id: `chip-${event.leaderId}-${crypto.randomUUID()}`,
          role: "assistant",
          content: "",
          type: "tool_use_chip",
          toolName: event.label,
          toolLabel: event.label,
          leaderId: event.leaderId,
        };
        // Review F4: cap at TOOL_USE_CHIP_CAP_PER_LEADER chips per leader.
        // Drop oldest chips for the same leader before appending the new one.
        const sameLeaderChips: number[] = [];
        for (let i = 0; i < prev.length; i++) {
          const m = prev[i];
          if (m.type === "tool_use_chip" && m.leaderId === event.leaderId) {
            sameLeaderChips.push(i);
          }
        }
        let working = prev;
        if (sameLeaderChips.length >= TOOL_USE_CHIP_CAP_PER_LEADER) {
          // Compute set of indices to drop (oldest first).
          const dropCount = sameLeaderChips.length - TOOL_USE_CHIP_CAP_PER_LEADER + 1;
          const dropSet = new Set(sameLeaderChips.slice(0, dropCount));
          working = prev.filter((_, i) => !dropSet.has(i));
        }
        return {
          messages: [...working, chip],
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
        };
      }
      const idx = activeStreams.get(event.leaderId);
      if (idx === undefined || idx >= prev.length) {
        return {
          messages: prev,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
        };
      }
      const updated = [...prev];
      updated[idx] = {
        ...updated[idx],
        state: "tool_use",
        toolLabel: event.label,
        toolsUsed: [...(updated[idx].toolsUsed ?? []), event.label],
      };
      return {
        messages: updated,
        activeStreams,
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
        // Reset the stuck-state timer on each tool_use — long-running tools
        // (Read on large files, Bash commands, web searches) can exceed the
        // 45s timeout. Each new tool_use proves the agent is still active.
        // See #2430.
        timerAction: { type: "reset", leaderId: event.leaderId },
      };
    }

    case "tool_progress": {
      // FR4 (#2861): SDK heartbeat for long-running tool execution. Do NOT
      // mutate messages on the hot path — a 1/5s heartbeat for every active
      // tool would churn the bubble re-render. The only effects are:
      //   (1) reset the watchdog so 45s timeouts don't fire mid-tool
      //   (2) if the bubble is showing `retrying`, clear the flag — a fresh
      //       heartbeat means the tool is alive and the first-timeout retry
      //       should transition back to tool_use.
      // Stage 4 (#2886) regression guard: `tool_progress` MUST NOT spawn a
      // chip — `tool_use` is the chip-start signal; `tool_progress` is
      // heartbeat-only.
      const idx = activeStreams.get(event.leaderId);
      if (idx === undefined || idx >= prev.length) {
        // Unknown leader (e.g., heartbeat races stream_end) — inert no-op.
        return {
          messages: prev,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
        };
      }
      const current = prev[idx];
      if (current.retrying) {
        const updated = [...prev];
        const { retrying: _retrying, ...rest } = updated[idx];
        void _retrying;
        updated[idx] = { ...rest };
        return {
          messages: updated,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
          timerAction: { type: "reset", leaderId: event.leaderId },
        };
      }
      return {
        messages: prev,
        activeStreams,
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
        timerAction: { type: "reset", leaderId: event.leaderId },
      };
    }

    case "stream": {
      // Stage 4 (#2886): when a stream event for `cc_router`/`system` arrives,
      // the chip's job is done — first content has reached the user. Remove
      // any chips for this leader before processing the stream content.
      let working = prev;
      if (event.leaderId === "cc_router" || event.leaderId === "system") {
        const filtered = prev.filter(
          (m) => !(m.type === "tool_use_chip" && m.leaderId === event.leaderId),
        );
        if (filtered.length !== prev.length) {
          working = filtered;
        }
      }
      const idx = activeStreams.get(event.leaderId);
      if (idx !== undefined && idx < working.length) {
        // REPLACE content (not append) — server sends cumulative snapshots
        const updated = [...working];
        const target = updated[idx];
        // activeStreams should never index a chip/group/gate/prompt/ended
        // bubble (those are appended outside the activeStreams machinery), but
        // guard at the boundary so a future regression surfaces here, not as
        // a corrupted bubble shape.
        if (target.type === "text") {
          updated[idx] = {
            ...target,
            content: event.content,
            state: "streaming",
            toolLabel: undefined,
          };
        }
        return {
          messages: updated,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
          timerAction: { type: "reset", leaderId: event.leaderId },
        };
      }
      // No active stream for this leader (stream_start may have been missed)
      const newMsg: ChatMessage = {
        id: `stream-${event.leaderId}-${crypto.randomUUID()}`,
        role: "assistant",
        content: event.content,
        type: "text",
        leaderId: event.leaderId,
        state: "streaming",
        toolsUsed: [],
      };
      const nextStreams = new Map(activeStreams);
      nextStreams.set(event.leaderId, working.length);
      return {
        messages: [...working, newMsg],
        activeStreams: nextStreams,
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
        timerAction: { type: "reset", leaderId: event.leaderId },
      };
    }

    case "stream_end": {
      // Review F11: stream_end is also a chip-removal trigger for cc_router /
      // system leaders (plan §124). The `tool_use → stream_end` path with
      // no streamed content otherwise leaks a permanent chip.
      let working = prev;
      if (event.leaderId === "cc_router" || event.leaderId === "system") {
        const filtered = prev.filter(
          (m) => !(m.type === "tool_use_chip" && m.leaderId === event.leaderId),
        );
        if (filtered.length !== prev.length) working = filtered;
      }
      const idx = activeStreams.get(event.leaderId);
      const nextStreams = new Map(activeStreams);
      nextStreams.delete(event.leaderId);
      if (idx === undefined || idx >= working.length) {
        return {
          messages: working,
          activeStreams: nextStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
          timerAction: { type: "clear", leaderId: event.leaderId },
        };
      }
      const updated = [...working];
      updated[idx] = { ...updated[idx], state: "done" };
      return {
        messages: updated,
        activeStreams: nextStreams,
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
        timerAction: { type: "clear", leaderId: event.leaderId },
      };
    }

    case "review_gate": {
      // Transition any bubble still mid-turn to "done" BEFORE clearing
      // activeStreams. Leaking "thinking" / "tool_use" / "streaming" into an
      // unclearable state is the root cause of the stuck orange "Working"
      // badge when a review_gate fires while peer leaders are still streaming
      // (see #2843). The gate message itself is appended after the transition.
      const updated = prev.slice();
      for (const idx of activeStreams.values()) {
        if (idx >= updated.length) continue;
        const m = updated[idx];
        if (m.state === "thinking" || m.state === "tool_use" || m.state === "streaming") {
          updated[idx] = { ...m, state: "done" };
        }
      }
      const gateMsg: ChatMessage = {
        id: `gate-${event.gateId}`,
        role: "assistant",
        content: event.question,
        type: "review_gate",
        gateId: event.gateId,
        question: event.question,
        options: event.options,
        header: event.header,
        descriptions: event.descriptions,
        stepProgress: event.stepProgress,
      };
      return {
        messages: [...updated, gateMsg],
        activeStreams: new Map(),
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
        timerAction: { type: "clear_all" },
      };
    }

    // -----------------------------------------------------------------
    // Stage 4 (#2886) — `/soleur:go` event variants now produce real
    // ChatMessage variants instead of the Stage 3 inert pass-throughs.
    // -----------------------------------------------------------------

    case "subagent_spawn": {
      // Find an existing subagent_group in `prev` matching `parentId`.
      let groupIdx = -1;
      for (let i = prev.length - 1; i >= 0; i--) {
        const m = prev[i];
        if (m.type === "subagent_group" && m.parentSpawnId === event.parentId) {
          groupIdx = i;
          break;
        }
      }
      const updated = [...prev];
      const nextSpawnIndex = cloneSpawnIndex(priorSpawnIndex);
      if (groupIdx === -1) {
        // No matching parent — start a new subagent_group.
        const newGroup: ChatSubagentGroupMessage = {
          id: `subagent-group-${event.parentId}`,
          role: "assistant",
          content: "",
          type: "subagent_group",
          parentSpawnId: event.parentId,
          parentLeaderId: event.leaderId,
          children: [
            {
              spawnId: event.spawnId,
              leaderId: event.leaderId,
              task: event.task,
            },
          ],
        };
        updated.push(newGroup);
        nextSpawnIndex.set(event.spawnId, {
          messageIdx: updated.length - 1,
          childIdx: 0,
        });
        return {
          messages: updated,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: nextSpawnIndex,
        };
      }
      // Append child to existing group.
      const existing = updated[groupIdx];
      if (existing.type !== "subagent_group") {
        return {
          messages: prev,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
        };
      }
      const newChildren = [
        ...existing.children,
        {
          spawnId: event.spawnId,
          leaderId: event.leaderId,
          task: event.task,
        },
      ];
      updated[groupIdx] = { ...existing, children: newChildren };
      nextSpawnIndex.set(event.spawnId, {
        messageIdx: groupIdx,
        childIdx: newChildren.length - 1,
      });
      return {
        messages: updated,
        activeStreams,
        workflow: priorWorkflow,
        spawnIndex: nextSpawnIndex,
      };
    }

    case "subagent_complete": {
      // Review F2: id-based lookup instead of absolute-index spawnIndex.
      // `filter_prepend` (history backfill) shifted all indices, leaving the
      // pre-stored `messageIdx` pointing at the wrong row. Scan `prev` for
      // the matching subagent_group + child by spawnId — O(N), bounded by
      // spawn count per session.
      let foundMessageIdx = -1;
      let foundChildIdx = -1;
      for (let i = prev.length - 1; i >= 0; i--) {
        const m = prev[i];
        if (m.type !== "subagent_group") continue;
        const childIdx = m.children.findIndex((c) => c.spawnId === event.spawnId);
        if (childIdx >= 0) {
          foundMessageIdx = i;
          foundChildIdx = childIdx;
          break;
        }
      }
      if (foundMessageIdx === -1) {
        // Unknown spawnId — likely an out-of-order event. Leave state intact.
        return {
          messages: prev,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
        };
      }
      const target = prev[foundMessageIdx];
      if (target.type !== "subagent_group") {
        return {
          messages: prev,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
        };
      }
      const updated = [...prev];
      const newChildren = [...target.children];
      newChildren[foundChildIdx] = { ...newChildren[foundChildIdx], status: event.status };
      updated[foundMessageIdx] = { ...target, children: newChildren };
      return {
        messages: updated,
        activeStreams,
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
      };
    }

    case "workflow_started": {
      // Sticky context bar update; remove any leftover tool_use chips.
      const filtered = prev.filter((m) => m.type !== "tool_use_chip");
      const messages = filtered.length !== prev.length ? filtered : prev;
      return {
        messages,
        activeStreams,
        workflow: { state: "active", workflow: event.workflow },
        spawnIndex: priorSpawnIndex,
      };
    }

    case "workflow_ended": {
      const endedMsg: ChatWorkflowEndedMessage = {
        id: `workflow-ended-${event.workflow}-${crypto.randomUUID()}`,
        role: "assistant",
        content: "",
        type: "workflow_ended",
        workflow: event.workflow,
        status: event.status,
        summary: event.summary,
      };
      return {
        messages: [...prev, endedMsg],
        activeStreams,
        workflow: {
          state: "ended",
          workflow: event.workflow,
          status: event.status,
          summary: event.summary,
        },
        spawnIndex: priorSpawnIndex,
      };
    }

    case "interactive_prompt": {
      // Review F7: idempotency. On server re-emit / network duplicate /
      // supabase realtime retry, dispatching this twice would push two
      // cards with the same React key — duplicate-key warning + split-brain
      // (first card optimistically resolved, second still unresolved).
      // De-dupe on (promptId, conversationId).
      const alreadyExists = prev.some(
        (m) =>
          m.type === "interactive_prompt" &&
          m.promptId === event.promptId &&
          m.conversationId === event.conversationId,
      );
      if (alreadyExists) {
        return {
          messages: prev,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
        };
      }
      // Review F6: replace `as InteractivePromptPayload[...]` casts with a
      // per-kind switch that constructs the discriminated `{kind, payload}`
      // narrowed locally — TS now tracks the congruence end-to-end.
      const card = buildInteractivePromptCard(event);
      return {
        messages: [...prev, card],
        activeStreams,
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
      };
    }

    default: {
      // Compile-time exhaustiveness rail: a future variant added to
      // `WSMessage` (and pulled into `StreamEvent`) without a corresponding
      // case here fails `tsc --noEmit`.
      const _exhaustive: never = event;
      void _exhaustive;
      return {
        messages: prev,
        activeStreams,
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
      };
    }
  }
}

/**
 * Apply the stuck-state timeout for a leader. Two-stage lifecycle (FR5 #2861):
 *   1. First timeout on a transitional bubble → set `retrying: true`, keep
 *      the bubble active, reset the watchdog. Visible as "Retrying…" chip.
 *   2. Second consecutive timeout (bubble already has `retrying: true`) →
 *      transition to `error`, preserve `toolLabel` for the error chip, clear
 *      the watchdog.
 * Bubbles that have already progressed to streaming/done/error are left alone.
 */
export function applyTimeout(
  prev: ChatMessage[],
  activeStreams: Map<DomainLeaderId, number>,
  leaderId: string,
): {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, number>;
  timerAction?:
    | { type: "reset"; leaderId: string }
    | { type: "clear"; leaderId: string };
} {
  const idx = activeStreams.get(leaderId as DomainLeaderId);
  if (idx === undefined || idx >= prev.length) {
    return { messages: prev, activeStreams };
  }
  const current = prev[idx];
  if (current.state !== "thinking" && current.state !== "tool_use") {
    return { messages: prev, activeStreams };
  }

  // Second consecutive timeout — already in retrying, give up.
  if (current.retrying) {
    const updated = [...prev];
    const { retrying: _retrying, ...rest } = updated[idx];
    void _retrying;
    updated[idx] = { ...rest, state: "error" };
    const nextStreams = new Map(activeStreams);
    nextStreams.delete(leaderId as DomainLeaderId);
    return {
      messages: updated,
      activeStreams: nextStreams,
      timerAction: { type: "clear", leaderId },
    };
  }

  // First timeout — flag as retrying, keep bubble active, restart watchdog.
  const updated = [...prev];
  updated[idx] = { ...updated[idx], retrying: true };
  return {
    messages: updated,
    activeStreams,
    timerAction: { type: "reset", leaderId },
  };
}
