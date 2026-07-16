import type {
  WSMessage,
  MessageState,
  AttachmentRef,
  InteractivePromptPayload,
  InteractivePromptResponsePayload,
  WorkflowName,
  SubagentCompleteStatus,
  WorkflowEndStatus,
  ContextResetReason,
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
   * FR5 (#2861) / FR4 (#5240): set by `applyTimeout` on the first stuck-timeout
   * and cleared on a follow-up `tool_progress` or the second consecutive
   * timeout. When true, `message-bubble.tsx` shows the honest "No response yet"
   * chip (aria-live polite) — NOT a "Retrying…" claim, since nothing is
   * actually retried on a silent stream. The bubble's `state` stays in its
   * transitional form (`thinking` / `tool_use`) — `retrying` is the orthogonal
   * render flag. This per-message activity flag is the State-2 ("No response
   * yet") input; connection-lifecycle state (State 1/3/4) now lives in the
   * reducer's `connection` slice (`ConnectionPhase` below + `ChatState.connection`
   * in ws-client.ts), and `deriveReconnectView` gives connection state
   * precedence over this activity flag (#5282, AC12).
   */
  retrying?: boolean;
  /**
   * #5240 (leader-liveness sub-issue): counts how many times THIS bubble's
   * Stage-2 escalation has been *suppressed* because a sibling leader was still
   * active (see `applyTimeout`). Bounded by `MAX_LIVENESS_REARMS` so a
   * perpetually-busy sibling cannot mask a genuinely-hung leader forever — once
   * the budget is exhausted the next timeout escalates to `error` regardless.
   * Optional so existing fixtures type-check unchanged; reset to 0 on genuine
   * (leader-attributed) liveness like a single-leader debug heartbeat.
   */
  livenessRearms?: number;
}

/**
 * #5240 — the ceiling on cross-leader liveness suppression. A sibling leader
 * being active is a *bounded grace*, NOT proof THIS leader is alive (A and its
 * workspace can hang independently of B). After this many suppressed Stage-2
 * timeouts (~`(2 + MAX) × STUCK_TIMEOUT_MS ≈ 3.75min` at 45s/window) the hung
 * leader escalates to `error` even while the sibling stays busy. Per
 * `2026-05-05-defense-relaxation-must-name-new-ceiling.md`: we add liveness
 * inputs + a bounded grace, we never remove the genuine-hang exit.
 */
export const MAX_LIVENESS_REARMS = 3;

/**
 * feat-concierge-stream-commands — one inline terminal block per Concierge
 * Bash command. The reducer's `command_stream` case APPENDS these onto the
 * active cc_router text bubble (output APPENDS to the matching block, the
 * command does NOT replace bubble text). `command`/`output` arrive
 * already-redacted at the server emit boundary; `message-bubble.tsx`
 * re-redacts at render as the belt-and-suspenders gate. `truncated` marks
 * a block whose output hit the per-command cap (D4).
 */
export interface CommandBlock {
  /** Redacted command text (set on `phase:"start"`). */
  command: string;
  /** Redacted, byte-capped accumulated stdout/stderr. */
  output: string;
  /** True once any output chunk reported the per-command cap was hit. */
  truncated?: boolean;
  /**
   * FIX 2 — SDK tool_use id stored on the block at `phase:"start"`. Lets the
   * reducer route `output` to the originating block when one turn runs two
   * concurrent Bash tool-uses. Absent on legacy blocks (last-block append).
   */
  toolUseId?: string;
}

interface ChatTextMessage extends ChatMessageBase {
  type: "text";
  /**
   * feat-concierge-stream-commands — inline streamed-terminal blocks for
   * Concierge Bash tool-uses. Append-only; `undefined`/empty on bubbles
   * that ran no commands so existing fixtures + non-cc bubbles are
   * unaffected.
   */
  commandBlocks?: CommandBlock[];
  /** #3448 PR2: persistence-tier discriminator surfaced by the history
   *  fetch (`status` column added in migration 040). `"aborted"` rows
   *  trigger the abort-marker render path in `message-bubble.tsx`.
   *  Optional so live-stream bubbles (which have no DB row yet) and
   *  legacy fixtures both type-check. */
  status?: "complete" | "aborted";
  /** #3448 PR2: aborted-turn snapshot. Present only for rows whose
   *  `status === "aborted"`. Shape mirrors the `usage` jsonb column
   *  documented in migration 040.
   *
   *  #3640 F6 — `variant` discriminates the legacy `agent-runner`
   *  `UsageSnapshot` (full fields) from the cc-router `{ cost_usd }`
   *  narrow shape. `input_tokens` + `output_tokens` widened to optional
   *  so cc-narrowed rows don't fabricate zeros at hydration. Readers
   *  switch on `variant`; `undefined` defaults to `"legacy"` for the
   *  fixture-stable backward-compat path. */
  usage?: {
    variant?: "legacy" | "cc";
    input_tokens?: number;
    output_tokens?: number;
    cost_usd?: number | null;
    completed_actions?: Array<{
      tool_name: string;
      input_summary: string;
      result_summary: string;
    }>;
  } | null;
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

/** feat-bash-autonomous-default-on — first-run consent soft-gate card. A held
 *  Bash command awaiting the owner's one-time autonomous-mode acknowledgement.
 *  Rendered as the AutonomousDisclosureBanner; resolved via
 *  `autonomous_disclosure_response`. `existingWorkspace` selects the opt-out
 *  (Keep on / Ask each) vs. the default-ON "Got it" surface. */
interface ChatAutonomousDisclosureMessage extends ChatMessageBase {
  type: "autonomous_disclosure";
  gateId: string;
  existingWorkspace: boolean;
  resolved?: boolean;
  selectedOption?: string;
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

/** #3269: inline context-reset notice. Single-shot lifecycle card; renders
 *  via `chat-surface.tsx` using copy from `CONTEXT_RESET_COPY` keyed by
 *  `reason`. No state mutation beyond appending the message itself. */
export interface ChatContextResetMessage extends ChatMessageBase {
  type: "context_reset";
  reason: ContextResetReason;
}

/** feat-debug-mode-stream — one harness instruction-stream event materialized
 *  from a `debug_event` WS frame. Rendered ONLY in the SEPARATE collapsed
 *  debug panel (`debug-stream-panel.tsx`), never inline in the conversation:
 *  `chat-surface.tsx` filters these out of the main message map and feeds them
 *  to `<DebugStreamPanel>`. `body` arrives already redacted-or-dropped at the
 *  server emit boundary; the panel re-redacts at render (belt-and-suspenders,
 *  mirroring `message-bubble.tsx`). Flat (no leaderId) — the panel is a single
 *  ordered log, not a per-leader bubble. */
export interface ChatDebugEventMessage extends ChatMessageBase {
  type: "debug_event";
  debugKind: "tool_use" | "reasoning" | "result";
  label?: string;
  body: string;
}

/** feat-reasoning-chat-boxes (#5370) — the DURABLE per-turn summary box. Unlike
 *  `ChatDebugEventMessage` (team-only, filtered into the debug panel), this
 *  renders INLINE in the main conversation as a confirmed (emerald-checkmark)
 *  box and is PERSISTED (messages row, message_kind='turn_summary', mig 105) so
 *  it survives reload. The summary text rides in `content` (ChatMessageBase).
 *  Render MUST be plain-text (no MarkdownRenderer) — see chat-surface render
 *  case + turn-summary-bubble.tsx. Authored deliberately by the agent via the
 *  `summarize` MCP tool and redacted at the server emit boundary. */
export interface ChatTurnSummaryMessage extends ChatMessageBase {
  type: "turn_summary";
}

export type ChatMessage =
  | ChatTextMessage
  | ChatGateMessage
  | ChatAutonomousDisclosureMessage
  | ChatSubagentGroupMessage
  | ChatInteractivePromptMessage
  | ChatWorkflowEndedMessage
  | ChatToolUseChipMessage
  | ChatContextResetMessage
  | ChatDebugEventMessage
  | ChatTurnSummaryMessage;

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

/** FIX 3 — cap on `commandBlocks` retained per bubble. A long autonomous turn
 *  can emit hundreds of Bash tool-uses; unbounded accumulation balloons the
 *  bubble's render cost and memory. When exceeded, the oldest blocks are
 *  dropped and a single leading marker block records the truncation. */
export const MAX_COMMAND_BLOCKS = 100;

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
   *   - `clear_all`: cancel every pending timer (teardown / clear_streams)
   *   - `reset_all`: (re)start every currently-armed timer. #5240 — emitted by
   *     the single-leader debug heartbeat, which has no `leaderId` to name (a
   *     debug_event carries none), so it re-arms the one armed timer en masse.
   * `undefined` means "no timer change" (e.g., auth_ok).
   */
  timerAction?:
    | { type: "reset"; leaderId: string }
    | { type: "clear"; leaderId: string }
    | { type: "clear_all" }
    | { type: "reset_all" };
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
export type StreamEvent = Extract<
  WSMessage,
  | { type: "stream_start" }
  | { type: "stream" }
  | { type: "stream_end" }
  | { type: "tool_use" }
  | { type: "command_stream" }
  | { type: "tool_progress" }
  // feat-debug-mode-stream — harness instruction stream (separate panel).
  | { type: "debug_event" }
  // feat-reasoning-chat-boxes (#5370) — durable per-turn summary (main list).
  | { type: "turn_summary" }
  | { type: "review_gate" }
  | { type: "autonomous_disclosure" }
  | { type: "subagent_spawn" }
  | { type: "subagent_complete" }
  | { type: "workflow_started" }
  | { type: "workflow_ended" }
  | { type: "interactive_prompt" }
  | { type: "context_reset" }
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
 * After Stage-2 `applyTimeout` paints `error` and evicts the leader from
 * `activeStreams`, later liveness (tool_use / tool_progress / stream /
 * command_stream / stream_start) would otherwise leave an orphan red banner
 * while tools continue — especially for `cc_router`, which takes the chip-only
 * branch when the leader is not in `activeStreams`.
 *
 * Walk from the end: the latest text bubble for `leaderId` is recoverable only
 * if it is still `error`. A newer non-error text bubble means the turn already
 * continued elsewhere — do not resurrect an older error.
 *
 * Plan: 2026-07-16-fix-concierge-agent-stop-mid-run-plan.md (Path A rebind).
 */
export function findRecoverableErrorBubble(
  messages: ChatMessage[],
  leaderId: DomainLeaderId,
): number | undefined {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m.type !== "text" || m.leaderId !== leaderId) continue;
    if (m.state === "error") return i;
    // Newer live text bubble for this leader — leave older errors alone.
    return undefined;
  }
  return undefined;
}

/**
 * Re-insert a Stage-2 error bubble into `activeStreams` and clear hang flags
 * so the stuck-watchdog + UI leave the terminal "Agent stopped responding"
 * path. Caller supplies the post-recovery state patch (tool_use / streaming /
 * thinking). Does not append chips.
 *
 * Precondition: `prev[errIdx]` is a `type: "text"` bubble (enforced by
 * `findRecoverableErrorBubble`).
 */
function rebindRecoveredErrorBubble(
  prev: ChatMessage[],
  activeStreams: Map<DomainLeaderId, number>,
  leaderId: DomainLeaderId,
  errIdx: number,
  patch: Partial<ChatTextMessage> & { state: MessageState },
): {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, number>;
} {
  const updated = [...prev];
  const current = updated[errIdx];
  if (current.type !== "text") {
    // Defensive: helper is only called after findRecoverableErrorBubble.
    return { messages: prev, activeStreams };
  }
  const { retrying: _retrying, livenessRearms: _rearms, ...rest } = current;
  void _retrying;
  void _rearms;
  updated[errIdx] = {
    ...rest,
    ...patch,
    type: "text",
    livenessRearms: 0,
  };
  const nextStreams = new Map(activeStreams);
  nextStreams.set(leaderId, errIdx);
  return { messages: updated, activeStreams: nextStreams };
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
      // Prefer rebind of a tip Stage-2 error over stacking a second thinking
      // row above a permanent red banner (Path A recovery).
      const errIdx = findRecoverableErrorBubble(prev, event.leaderId);
      if (errIdx !== undefined) {
        const rebound = rebindRecoveredErrorBubble(
          prev,
          activeStreams,
          event.leaderId,
          errIdx,
          { state: "thinking", toolLabel: undefined },
        );
        return {
          ...rebound,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
          timerAction: { type: "reset", leaderId: event.leaderId },
        };
      }
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
      //
      // Path A recovery: if the tip text bubble for this leader is Stage-2
      // `error` (evicted from activeStreams), rebind it instead of chip-only /
      // no-op — otherwise the red banner stays while tools continue.
      if (
        (event.leaderId === "cc_router" || event.leaderId === "system") &&
        !activeStreams.has(event.leaderId)
      ) {
        const errIdx = findRecoverableErrorBubble(prev, event.leaderId);
        if (errIdx !== undefined) {
          const current = prev[errIdx];
          const rebound = rebindRecoveredErrorBubble(
            prev,
            activeStreams,
            event.leaderId,
            errIdx,
            {
              state: "tool_use",
              toolLabel: event.label,
              toolsUsed: [...(current.toolsUsed ?? []), event.label],
            },
          );
          return {
            ...rebound,
            workflow: priorWorkflow,
            spawnIndex: priorSpawnIndex,
            timerAction: { type: "reset", leaderId: event.leaderId },
          };
        }
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
        const errIdx = findRecoverableErrorBubble(prev, event.leaderId);
        if (errIdx !== undefined) {
          const current = prev[errIdx];
          const rebound = rebindRecoveredErrorBubble(
            prev,
            activeStreams,
            event.leaderId,
            errIdx,
            {
              state: "tool_use",
              toolLabel: event.label,
              toolsUsed: [...(current.toolsUsed ?? []), event.label],
            },
          );
          return {
            ...rebound,
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
      // Path A: if the leader was Stage-2-evicted but the tip is still error,
      // rebind so heartbeats heal the orphan red banner (no chip spawn).
      const idx = activeStreams.get(event.leaderId);
      if (idx === undefined || idx >= prev.length) {
        const errIdx = findRecoverableErrorBubble(prev, event.leaderId);
        if (errIdx !== undefined) {
          const rebound = rebindRecoveredErrorBubble(
            prev,
            activeStreams,
            event.leaderId,
            errIdx,
            { state: "tool_use" },
          );
          return {
            ...rebound,
            workflow: priorWorkflow,
            spawnIndex: priorSpawnIndex,
            timerAction: { type: "reset", leaderId: event.leaderId },
          };
        }
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
      // Path A: rebind tip error instead of stacking a second streaming bubble
      // below a permanent red banner.
      const errIdx = findRecoverableErrorBubble(working, event.leaderId);
      if (errIdx !== undefined) {
        const rebound = rebindRecoveredErrorBubble(
          working,
          activeStreams,
          event.leaderId,
          errIdx,
          {
            state: "streaming",
            content: event.content,
            toolLabel: undefined,
          },
        );
        return {
          ...rebound,
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

    case "autonomous_disclosure": {
      // feat-bash-autonomous-default-on — first-run consent soft-gate. Mirrors
      // the `review_gate` arm: transition any mid-turn bubble to "done" before
      // clearing activeStreams (avoid the stuck "Working" badge, #2843), then
      // append the disclosure card. The held Bash command does not proceed
      // until the owner acks via `autonomous_disclosure_response`.
      const updated = prev.slice();
      for (const idx of activeStreams.values()) {
        if (idx >= updated.length) continue;
        const m = updated[idx];
        if (
          m.state === "thinking" ||
          m.state === "tool_use" ||
          m.state === "streaming"
        ) {
          updated[idx] = { ...m, state: "done" };
        }
      }
      const disclosureMsg: ChatMessage = {
        id: `autonomous-disclosure-${event.gateId}`,
        role: "assistant",
        content: "",
        type: "autonomous_disclosure",
        gateId: event.gateId,
        existingWorkspace: event.existingWorkspace,
      };
      return {
        messages: [...updated, disclosureMsg],
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
      // #3775 — idempotent on `spawnId`. The wire protocol guarantees spawnId
      // uniqueness server-side, but a WS reconnect / supabase realtime retry
      // / regressed runner could re-emit. Duplicate-key state would corrupt
      // `spawnIndex` (the second insert overwrites the first, breaking the
      // subsequent `subagent_complete` lookup at line 668). Mirror the
      // `interactive_prompt` arm's dedup shape (line 751-770).
      if (priorSpawnIndex.has(event.spawnId)) {
        return {
          messages: prev,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
        };
      }
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

    case "command_stream": {
      // feat-concierge-stream-commands — APPEND a Concierge Bash command +
      // its (already-redacted, byte-capped) output into the active cc_router
      // bubble as an inline terminal block. Mirrors the `stream` cc_router
      // special-casing: locate the bubble via `activeStreams`, else create
      // one (the SDK can emit a Bash tool-use before any text streams). The
      // command text does NOT replace the bubble's prose `content` — the two
      // surfaces coexist (output APPENDS to its block; text uses REPLACE in
      // the `stream` case). `start` pushes a new block; `output` appends to
      // the latest block; `end` is a no-op terminal marker.
      //
      // Chip-removal parity with `stream`/`stream_end`: a command stream is
      // also "first activity reached the user", so drop any lingering chip.
      let working = prev;
      if (event.leaderId === "cc_router" || event.leaderId === "system") {
        const filtered = prev.filter(
          (m) => !(m.type === "tool_use_chip" && m.leaderId === event.leaderId),
        );
        if (filtered.length !== prev.length) working = filtered;
      }

      const applyToBlocks = (existing: CommandBlock[] | undefined): CommandBlock[] => {
        let blocks = existing ? [...existing] : [];
        if (event.phase === "start") {
          blocks.push({
            command: event.command ?? "",
            output: "",
            toolUseId: event.toolUseId,
          });
          // FIX 3 — cap accumulation. Drop the oldest blocks and keep a single
          // leading marker so the user sees that earlier commands were elided.
          if (blocks.length > MAX_COMMAND_BLOCKS) {
            const kept = blocks.slice(blocks.length - (MAX_COMMAND_BLOCKS - 1));
            blocks = [
              { command: "[… earlier commands truncated]", output: "" },
              ...kept,
            ];
          }
        } else if (event.phase === "output") {
          // FIX 2 — route to the originating block by toolUseId when present
          // (concurrent Bash). Mirrors the subagent_complete id-lookup
          // precedent. Fall back to the last block when absent (back-compat)
          // or when the id is unknown (out-of-order/missed start).
          let targetIdx = blocks.length - 1;
          if (event.toolUseId !== undefined) {
            const byId = blocks.findIndex(
              (b) => b.toolUseId === event.toolUseId,
            );
            if (byId >= 0) targetIdx = byId;
          }
          if (targetIdx < 0) {
            // Output before any start (missed `start`): synthesize a block so
            // the chunk is not dropped. command unknown → empty string.
            blocks.push({ command: "", output: "", toolUseId: event.toolUseId });
            targetIdx = blocks.length - 1;
          }
          const target = blocks[targetIdx];
          blocks[targetIdx] = {
            ...target,
            output: target.output + (event.output ?? ""),
            truncated:
              target.truncated || event.truncated ? true : target.truncated,
          };
        }
        // phase === "end": terminal marker, no block mutation.
        return blocks;
      };

      const idx = activeStreams.get(event.leaderId);
      if (idx !== undefined && idx < working.length && working[idx].type === "text") {
        const updated = [...working];
        const target = updated[idx] as ChatTextMessage;
        updated[idx] = { ...target, commandBlocks: applyToBlocks(target.commandBlocks) };
        return {
          messages: updated,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
          timerAction: { type: "reset", leaderId: event.leaderId },
        };
      }

      // Path A: rebind tip Stage-2 error rather than appending a second
      // streaming bubble below a permanent red banner.
      const errIdx = findRecoverableErrorBubble(working, event.leaderId);
      if (errIdx !== undefined && working[errIdx].type === "text") {
        const target = working[errIdx] as ChatTextMessage;
        const rebound = rebindRecoveredErrorBubble(
          working,
          activeStreams,
          event.leaderId,
          errIdx,
          {
            state: "streaming",
            commandBlocks: applyToBlocks(target.commandBlocks),
          },
        );
        return {
          ...rebound,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
          timerAction: { type: "reset", leaderId: event.leaderId },
        };
      }

      // No active text bubble for this leader — create one carrying the block.
      const newMsg: ChatTextMessage = {
        id: `stream-${event.leaderId}-${crypto.randomUUID()}`,
        role: "assistant",
        content: "",
        type: "text",
        leaderId: event.leaderId,
        state: "streaming",
        toolsUsed: [],
        commandBlocks: applyToBlocks(undefined),
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

    case "context_reset": {
      // #3269: lifecycle notice — append a single-shot context-reset card
      // to the message stream. Mirrors `workflow_ended` shape (no other
      // state mutation; render reads copy from `CONTEXT_RESET_COPY`).
      const notice: ChatContextResetMessage = {
        id: `context-reset-${event.conversationId}-${crypto.randomUUID()}`,
        role: "assistant",
        content: "",
        type: "context_reset",
        reason: event.reason,
      };
      return {
        messages: [...prev, notice],
        activeStreams,
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
      };
    }

    case "debug_event": {
      // feat-debug-mode-stream — APPEND the harness event to the message list
      // as a flat ChatDebugEventMessage. `chat-surface.tsx` filters these into
      // the separate collapsed debug panel; they NEVER render inline in the
      // conversation. The event carries NO `leaderId` (`types.ts:341-346`).
      //
      // #5240 leader-liveness: a debug `tool_use` is a HEARTBEAT proving the
      // agent is alive — the operator can SEE it streaming while the watchdog
      // would otherwise falsely escalate to "Agent stopped responding". We use
      // it to reset the watchdog, but ONLY when exactly ONE leader is active:
      //   - `size === 1` → the unattributed heartbeat is unambiguously that
      //     leader's, so `reset_all` re-arms its single timer (sound). We also
      //     clear `retrying` + reset `livenessRearms` on that bubble (mirror
      //     `tool_progress` at the equivalent arm) so the stale "No response
      //     yet" chip clears on a working turn.
      //   - `size !== 1` → unattributable (≥2 leaders) or no active stream;
      //     resetting all timers would let a fast leader mask a hung sibling
      //     (the masking the scope guard forbids). The BOUNDED cross-leader gate
      //     in `applyTimeout` handles the multi-leader case instead, so the
      //     debug case stays inert here.
      // Safety: `reset_all` re-arms timers but cannot resurrect a terminal
      // bubble — `applyTimeout`'s transitional-state guard no-ops on
      // non-thinking/tool_use bubbles, so a re-armed dangling timer is harmless.
      // Only `kind: "tool_use"` counts; `reasoning`/`result` are weaker / can
      // fire post-turn and are excluded to keep the ceiling tight.
      // INVARIANT (enforced, not just asserted): debug events are LIVE-ONLY, so
      // this heartbeat can never fire on a dead socket. #5290's stream-replay
      // buffer EXCLUDES `debug_event` from its `BufferedWSMessage` family
      // (server/stream-replay-buffer.ts) — and that exclusion is compiler-
      // enforced via `BUFFERED_FRAME_TYPE_MAP` (a `Record<BufferedWSMessage
      // ["type"], true>`), so a buffered/replayed gap frame can never be a
      // debug_event. If a future change adds debug_event to the buffered family
      // it becomes a tsc error there AND re-opens this hole — keep it excluded.
      const debugMsg: ChatDebugEventMessage = {
        id: `debug-${crypto.randomUUID()}`,
        role: "assistant",
        content: "",
        type: "debug_event",
        debugKind: event.kind,
        label: event.label,
        body: event.body,
      };
      // Path A extension: when no leader is active but exactly one recoverable
      // Stage-2 error text bubble exists, a debug tool_use is unambiguous
      // liveness for that orphan — rebind + reset that leader (not reset_all
      // against an empty timer map). Multi-orphan stays inert.
      if (event.kind === "tool_use" && activeStreams.size === 0) {
        const orphanLeaders = new Map<DomainLeaderId, number>();
        for (let i = prev.length - 1; i >= 0; i--) {
          const m = prev[i];
          if (m.type !== "text" || m.state !== "error" || m.leaderId === undefined) {
            continue;
          }
          if (!orphanLeaders.has(m.leaderId)) {
            orphanLeaders.set(m.leaderId, i);
          }
        }
        if (orphanLeaders.size === 1) {
          const [[orphanLeader, errIdx]] = orphanLeaders;
          const rebound = rebindRecoveredErrorBubble(
            prev,
            activeStreams,
            orphanLeader,
            errIdx,
            { state: "tool_use" },
          );
          return {
            messages: [...rebound.messages, debugMsg],
            activeStreams: rebound.activeStreams,
            workflow: priorWorkflow,
            spawnIndex: priorSpawnIndex,
            timerAction: { type: "reset", leaderId: orphanLeader },
          };
        }
      }

      const isHeartbeat = event.kind === "tool_use" && activeStreams.size === 1;
      if (!isHeartbeat) {
        return {
          messages: [...prev, debugMsg],
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
        };
      }
      // Sole active leader → its bubble index is the lone activeStreams value.
      // Mirror `tool_progress`: only clone+rewrite when there is something to
      // clear (a re-arm heartbeat fires every ~1-5s on a working turn; rewriting
      // an already-clean bubble would churn the message array for no effect).
      const soleIdx = activeStreams.values().next().value as number | undefined;
      const sole =
        soleIdx !== undefined && soleIdx < prev.length ? prev[soleIdx] : undefined;
      const needsClear =
        sole !== undefined &&
        (sole.state === "thinking" || sole.state === "tool_use") &&
        (sole.retrying === true || (sole.livenessRearms ?? 0) !== 0);
      let messages: ChatMessage[];
      if (needsClear) {
        const updated = [...prev];
        const { retrying: _retrying, livenessRearms: _rearms, ...rest } = updated[soleIdx!];
        void _retrying;
        void _rearms;
        updated[soleIdx!] = { ...rest, livenessRearms: 0 };
        messages = [...updated, debugMsg];
      } else {
        // Already-clean / terminal / non-transitional bubble (or stale index) —
        // append only, no mutation (do not resurrect). reset_all still re-arms
        // harmlessly.
        messages = [...prev, debugMsg];
      }
      return {
        messages,
        activeStreams,
        workflow: priorWorkflow,
        spawnIndex: priorSpawnIndex,
        timerAction: { type: "reset_all" },
      };
    }

    case "turn_summary": {
      // feat-reasoning-chat-boxes (#5370) — APPEND a durable per-turn summary
      // box to the main message list (NOT filtered into the debug panel). The
      // summary text rides in `content`; render is plain-text (no markdown).
      // Server only emits this on a successful turn (the `summarize` tool drop-
      // guards aborted/stopping conversations), so a turn_summary row IS the
      // success signal — there is no false "Done" box for an aborted turn.
      const summaryMsg: ChatTurnSummaryMessage = {
        id: `turn-summary-${crypto.randomUUID()}`,
        role: "assistant",
        content: event.summary,
        type: "turn_summary",
      };
      return {
        messages: [...prev, summaryMsg],
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
 *      the bubble active, reset the watchdog. Visible as the honest "No
 *      response yet" chip (FR4 #5240) — nothing is actually retried.
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

  // Second consecutive timeout — already in retrying.
  if (current.retrying) {
    // #5240 — BOUNDED cross-leader liveness suppression. If ANOTHER leader
    // (`!== leaderId`) is still actively streaming, the session as a whole is
    // demonstrably alive, so suppress THIS bubble's false escalation — but only
    // up to `MAX_LIVENESS_REARMS` times. A sibling being busy is NOT proof THIS
    // leader is alive, so the grace is bounded: once the budget is exhausted the
    // hung leader escalates regardless. The `!== leaderId` exclusion is
    // mandatory — the in-flight leader is still in `activeStreams` at scan time,
    // so without it the leader would always see "itself" and never escalate.
    const rearms = current.livenessRearms ?? 0;
    const siblingActive = [...activeStreams.entries()].some(([id, sIdx]) => {
      if (id === (leaderId as DomainLeaderId)) return false;
      const sib = prev[sIdx];
      return (
        sib !== undefined &&
        (sib.state === "thinking" || sib.state === "tool_use" || sib.state === "streaming")
      );
    });
    if (siblingActive && rearms < MAX_LIVENESS_REARMS) {
      const updated = [...prev];
      updated[idx] = { ...updated[idx], retrying: true, livenessRearms: rearms + 1 };
      // Re-arm THIS leader's own timer only — never `reset_all` (would reset the
      // sibling's timer too), never `undefined` (the per-leader timer
      // self-deletes on fire, so no reset = permanent suppression).
      return {
        messages: updated,
        activeStreams,
        timerAction: { type: "reset", leaderId },
      };
    }
    // No sibling active, OR the re-arm budget is exhausted → escalate (the
    // genuine-hang exit, preserved even under a perpetually-busy sibling).
    const updated = [...prev];
    const { retrying: _retrying, livenessRearms: _rearms, ...rest } = updated[idx];
    void _retrying;
    void _rearms;
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

// ─────────────────────────────────────────────────────────────────────────
// #5282 — Reconnect state machine (connection-state input + render derivation)
// ─────────────────────────────────────────────────────────────────────────

/**
 * The connection-lifecycle phase tracked in the reducer's `connection` slice
 * (`ChatState.connection.phase` in ws-client.ts). This is the MINIMUM the
 * socket-layer `ConnectionStatus` ("connecting"|"connected"|"reconnecting"|
 * "disconnected") lacks: a single STICKY-TERMINAL value (`unrecoverable`) that
 * survives the socket flipping back to `connected` on reattach.
 *
 *   - `live`           — default; socket healthy, no banner.            (no State)
 *   - `reconnecting`   — transient drop; banner "Connection lost…".     (State 1)
 *   - `unrecoverable`  — the in-flight session was reclaimed (grace      (State 3)
 *                        expired → `stream_replay{incomplete}`) or the
 *                        socket closed non-transiently without a
 *                        redirect. STICKY: a later `connection_change`
 *                        to live/reconnecting is a no-op (AC11); only a
 *                        `reset_connection` (new user turn) escapes it.
 *
 * State 4 (the brief "Continuing… · workspace restored" notice) is DERIVED at
 * render time (a transient `resumedAt` affordance), NOT a phase — it has no
 * invariant that must survive in reducer state. State 3 (`unrecoverable`) takes
 * render precedence over the State-4 notice, which is what enforces "no 3→4
 * flip" at the render layer (the sticky guard enforces it at the state layer).
 */
export type ConnectionPhase = "live" | "reconnecting" | "unrecoverable";

/**
 * The State-1-vs-State-2 precedence view. `connection_lost` (State 1) and
 * `no_activity` (State 2) are derived from the SAME selector so they can never
 * co-render (AC12). `unrecoverable` (State 3) and the derived State-4 notice are
 * SEPARATE render branches in chat-surface.tsx — they intentionally return
 * `none` here and do not participate in this union.
 */
export type ReconnectView =
  | { kind: "none" }
  | { kind: "connection_lost" }
  | { kind: "no_activity" };

/**
 * Pure precedence selector (#5282, AC6/AC12). Connection state takes precedence
 * over the per-message activity watchdog: when the connection is `reconnecting`,
 * State 1 ("Connection lost…") renders regardless of any stuck-watchdog bubble,
 * so State 1 and State 2 are mutually exclusive.
 */
export function deriveReconnectView(input: {
  phase: ConnectionPhase;
  hasRetryingBubble: boolean;
}): ReconnectView {
  switch (input.phase) {
    case "reconnecting":
      // Connection precedence (AC12): State 1 wins over the activity watchdog.
      return { kind: "connection_lost" };
    case "live":
      return input.hasRetryingBubble ? { kind: "no_activity" } : { kind: "none" };
    case "unrecoverable":
      // State 3 is a separate render branch; it does not compete with the chip.
      return { kind: "none" };
    default: {
      // Exhaustiveness rail: a new ConnectionPhase value without a case here
      // fails `tsc --noEmit` (#5282 AC8, cq-union-widening-grep-three-patterns).
      const _exhaustive: never = input.phase;
      void _exhaustive;
      return { kind: "none" };
    }
  }
}
