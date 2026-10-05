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
 * state, and a `spawnIndex` Set<string> dedups `subagent_spawn` events;
 * `subagent_complete` finds its child by an id scan of `prev`.
 */

interface ChatMessageBase {
  id: string;
  role: "user" | "assistant";
  content: string;
  leaderId?: DomainLeaderId;
  attachments?: AttachmentRef[];
  state?: MessageState;
  toolLabel?: string;
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
   * feat-concierge-activity-trail (#9515): session-only in-turn step history —
   * dimmed PRIOR steps (the current step is `toolLabel`/`liveNarration` for
   * narration). Entries are pushed when a step is superseded or at
   * terminalization; the trail RENDERS only while the bubble is live-ish
   * (transitional state or `interrupted`) so teardown is free — turn end
   * simply stops rendering it. Never persisted; hydrated rows never carry it.
   */
  activity?: ActivityEntry[];
  /** #9515 follow-up — when the current text block began (set on every
   *  non-prefix `stream` replace), so the folded prior's trail entry can
   *  carry its real start time instead of the fold instant. */
  contentStartedAt?: number;
  /** ms epoch the CURRENT displayed step began (`toolLabel` set or last
   *  narration) — elapsed time computes at render, no hot-path mutation. */
  currentActivityStartedAt?: number;
  /**
   * feat-concierge-activity-trail (#9515): honest mid-flap marker set by
   * `sweepTransitional` (clear_streams / enter_stopping) on bubbles still
   * transitional at socket reconnect/teardown. Renders a neutral
   * "Interrupted" chip (never "Working"); a resuming stream/tool_use REBINDS
   * via `findInterruptedBubble` so the turn continues in one box. Cleared on
   * rebind. Flag — not a `MessageState` member — mirroring `retrying`.
   */
  interrupted?: boolean;
  /**
   * feat-concierge-activity-trail (#9515): user-stop variant of `interrupted`
   * — set by `sweepTransitional` only from `enter_stopping`. Renders the same
   * "Interrupted" chip, but `findInterruptedBubble` SKIPS it: frames racing
   * in behind a user abort (the cc path's `abort_turn` is a documented no-op,
   * so they do) must not resurrect a Working box — they spawn fresh.
   */
  stopped?: boolean;
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
 * Bash command. NOTE (#9515 follow-up): command blocks no longer render
 * inside the bubble — the working box shows reasoning + plain-language steps;
 * raw command detail lives in the Debug stream. The state is retained because
 * the `command_stream` arm also drives chip-prune + liveness. The reducer's
 * `command_stream` case APPENDS these onto the
 * active cc_router text bubble (output APPENDS to the matching block, the
 * command does NOT replace bubble text). `command`/`output` arrive
 * already-redacted at the server emit boundary. `truncated` marks
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
   * feat-concierge-stream-commands — retained for the command_stream arm's
   * chip-prune + liveness; nothing renders these. Append-only; `undefined`/empty on bubbles
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
  /** ms epoch the chip was created — seeds the activity trail's `startedAt`
   *  when the chip's label folds into the bubble on first stream. */
  at?: number;
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

/** feat-session-completion-inline — the inline per-request completion card.
 *  Renders INLINE in the viewed conversation when the server emits the
 *  `task_completed` frame; the matching inbox_item row stays the durable
 *  record and is marked read at render (see ws-client `case "task_completed"`).
 *  Render MUST be plain-text — the title is server-generated (never agent
 *  output, ADR-085) but the InboxItemRow plain-text invariant still applies.
 *  `content` carries the title. */
export interface ChatTaskCompletedMessage extends ChatMessageBase {
  type: "task_completed";
  inboxItemId: string;
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
  | ChatTurnSummaryMessage
  | ChatTaskCompletedMessage;

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

/** feat-concierge-activity-trail (#9515): collapsed to `Set<spawnId>` —
 *  the `{messageIdx, childIdx}` payload was write-only (absolute indices are
 *  invalidated by `filter_prepend`/chip-prune; `subagent_complete` has
 *  scanned `prev` by id since review F2). The only live read is
 *  `subagent_spawn`'s `has(spawnId)` dedup. */
export type SpawnIndex = Set<string>;

/** Maximum number of `tool_use_chip` messages to retain per leader before
 *  the oldest is evicted. Plan §3 risk: "chip cap of 5 latest". */
export const TOOL_USE_CHIP_CAP_PER_LEADER = 5;

/** feat-concierge-activity-trail (#9515): one step in the in-turn activity
 *  trail. `kind` separates tool labels from deliberate narration lines so the
 *  render can style them distinctly if needed. `startedAt` is the step's
 *  start — elapsed time is computed at render (no messages[] mutation on the
 *  `tool_progress` heartbeat path). */
export interface ActivityEntry {
  label: string;
  kind: "tool" | "narration";
  startedAt: number;
}

/** Stored cap on `activity[]` per bubble — bounded accumulation, mirrors
 *  MAX_COMMAND_BLOCKS (oldest entries evicted; the visible render cap is
 *  ACTIVITY_VISIBLE_CAP). */
export const MAX_ACTIVITY_ENTRIES = 20;

/** Visible cap — the box shows the last N priors + "…and M more steps". */
export const ACTIVITY_VISIBLE_CAP = 5;

/**
 * feat-concierge-activity-trail (#9515): append `entry` to `existing` with
 * consecutive-duplicate suppression and the stored cap. A step that repeats
 * verbatim (same label twice in a row — e.g. consecutive identical tool
 * labels) collapses into one entry rather than spamming the trail.
 */
export function pushActivity(
  existing: ActivityEntry[] | undefined,
  entry: ActivityEntry,
): ActivityEntry[] {
  const list = existing ?? [];
  if (list.length > 0 && list[list.length - 1].label === entry.label) {
    return list;
  }
  const next = [...list, entry];
  return next.length > MAX_ACTIVITY_ENTRIES
    ? next.slice(next.length - MAX_ACTIVITY_ENTRIES)
    : next;
}

/**
 * #9515 follow-up — a `stream` event REPLACES the bubble's content per text
 * block (W8); intermediate "reasoning" paragraphs were silently overwritten
 * while the append-only debug stream kept them. When the incoming content is
 * NOT a continuation of the current content (a new block, not a growing
 * partial — cumulative partials share the prefix), the previous block's first
 * line folds into the trail so the box shows the reasoning SEQUENCE.
 * The text is the user-visible assistant content — already at the emit
 * boundary — so no new exposure; label is bounded to one line / 160 chars.
 * SNAPSHOT assumption: every live emitter sends cumulative-per-block content
 * (cc `onText` block.replace, agent-runner lastBlock.text). The dormant Codex
 * mapper emits per-delta FRAGMENTS — when it wires into ws-handler, gate this
 * fold off that path or accumulate deltas per itemId upstream.
 */
function foldReplacedText(
  prevContent: string,
  nextContent: string,
  activity: ActivityEntry[] | undefined,
  contentStartedAt: number | undefined,
): ActivityEntry[] | undefined {
  if (!prevContent || nextContent.startsWith(prevContent)) return activity;
  const firstLine = prevContent
    .split("\n")
    .map((l) => l.trim())
    .find((l) => l.length > 0);
  if (!firstLine) return activity;
  return pushActivity(activity, {
    // Code-point-safe truncate — a naive slice can split a surrogate pair.
    label:
      Array.from(firstLine).length > 160
        ? `${Array.from(firstLine).slice(0, 159).join("")}…`
        : firstLine,
    kind: "narration",
    // When the OUTGOING block began (contentStartedAt stamps each non-prefix
    // replace); a missing stamp falls back to now — a 0s duration beats a
    // wrong long one.
    startedAt: contentStartedAt ?? Date.now(),
  });
}

/**
 * feat-concierge-activity-trail (#9515): fold the superseded `liveNarration`
 * line into the tip text bubble's `activity[]` as a "narration" step.
 * Tip = the sole active stream's bubble when unambiguous, else the newest
 * live-ish-or-done text bubble — the turn-end fold lands on the JUST-
 * terminalized bubble so the final narration is never dropped (bounded by
 * the user barrier: it can never attach to a LATER turn's record).
 * Returns `{messages, folded}` — `folded:false` when nothing could hold it.
 */
export function foldNarrationIntoTrail(
  messages: ChatMessage[],
  activeStreams: Map<DomainLeaderId, string>,
  narration: string | null,
  startedAt: number | null | undefined,
): { messages: ChatMessage[]; folded: boolean } {
  const none = { messages, folded: false };
  if (!narration) return none;
  let idx: number | undefined;
  if (activeStreams.size === 1) {
    const soleId = activeStreams.values().next().value;
    const i = messages.findIndex((m) => m.id === soleId);
    if (i !== -1) idx = i;
  }
  if (idx === undefined) {
    for (let i = messages.length - 1; i >= 0; i--) {
      const m = messages[i];
      // Never fold across a turn boundary into a prior turn's dead box.
      if (m.role === "user") break;
      if (
        m.type === "text" &&
        (m.state === "thinking" ||
          m.state === "tool_use" ||
          m.state === "streaming" ||
          m.state === "done" ||
          m.interrupted === true)
      ) {
        idx = i;
        break;
      }
    }
  }
  if (idx === undefined) return none;
  const t = messages[idx];
  if (t.type !== "text") return none;
  const updated = [...messages];
  updated[idx] = {
    ...t,
    activity: pushActivity(t.activity, {
      label: narration,
      kind: "narration",
      startedAt: startedAt ?? Date.now(),
    }),
  };
  return { messages: updated, folded: true };
}

/**
 * feat-concierge-activity-trail (#9515): `activeStreams` is keyed by message
 * ID — `Map<leaderId, message.id>` — NOT absolute index. Indices are
 * invalidated by `filter_prepend`, chip-prune `filter`s, and any future
 * messages[] reorder (the cross-leader content-corruption class verified in
 * plan review: a chip for leader A pruned while leader B streams shifts B's
 * stored index onto the wrong row). An id that no longer resolves means the
 * bubble is gone — the arm falls through cleanly rather than corrupting a
 * hydrated row. `subagent_complete`'s id-scan is the precedent.
 */
export function resolveStreamIndex(
  messages: ChatMessage[],
  activeStreams: Map<DomainLeaderId, string>,
  leaderId: DomainLeaderId,
): number | undefined {
  const id = activeStreams.get(leaderId);
  if (id === undefined) return undefined;
  const i = messages.findIndex((m) => m.id === id);
  return i === -1 ? undefined : i;
}

/**
 * feat-concierge-activity-trail (#9515): the latest text bubble for
 * `leaderId` still carrying the `interrupted` flag — same tip-contract walk
 * as `findRecoverableErrorBubble` (scan from the end; a newer non-flagged
 * text bubble means the turn already continued elsewhere). Used by the
 * rebind check that precedes every transitional entry path, so a resuming
 * frame reattaches to the swept bubble instead of spawning a sibling box.
 */
/** feat-concierge-activity-trail (#9515): the "current step becomes a prior"
 *  patch — folds `toolLabel` into `activity` (chip labels seeded FIRST so the
 *  trail keeps chronological order) and clears the live-step slot. */
function foldCurrentStep(
  current: ChatMessage,
  chips?: ChatMessage[],
): Partial<ChatTextMessage> {
  const seeded = chips?.length
    ? seedActivityFromChips(current.activity, chips)
    : current.activity;
  return {
    activity: current.toolLabel
      ? pushActivity(seeded, {
          label: current.toolLabel,
          kind: "tool",
          startedAt: current.currentActivityStartedAt ?? Date.now(),
        })
      : seeded,
    toolLabel: undefined,
    currentActivityStartedAt: undefined,
  };
}

/** feat-concierge-activity-trail (#9515): one-pass chip partition — the
 *  prune filter and the seed-collector fuse so a token-rate frame scans
 *  `prev` once, not twice (perf seat). */
function partitionLeaderChips(
  prev: ChatMessage[],
  leaderId: DomainLeaderId,
): { working: ChatMessage[]; prunedChips: ChatMessage[] } {
  const prunedChips: ChatMessage[] = [];
  const working = prev.filter((m) => {
    if (m.type === "tool_use_chip" && m.leaderId === leaderId) {
      prunedChips.push(m);
      return false;
    }
    return true;
  });
  return { working, prunedChips };
}

export function findInterruptedBubble(
  messages: ChatMessage[],
  leaderId: DomainLeaderId,
): number | undefined {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    // A user message is a turn boundary: rebind must never cross it, or the
    // new turn resumes a dead bubble positioned ABOVE the question it
    // answers (ordering inversion, review-seat P1).
    if (m.role === "user") break;
    if (m.type !== "text" || m.leaderId !== leaderId) continue;
    if (m.interrupted === true && m.stopped !== true) return i;
    return undefined;
  }
  return undefined;
}

/**
 * feat-concierge-activity-trail (#9515): sweep every transitional bubble
 * (thinking / tool_use / streaming) to an honest `interrupted` marker —
 * `state: undefined`, `interrupted: true`, `retrying` stripped and
 * `livenessRearms` reset to 0 (an orphan that timed out once would otherwise pin the
 * "No response yet" chip forever). Invoked by `clear_streams` (every
 * `connect()` reconnect + session_ended/error/teardown) and `enter_stopping`
 * — the two arms that can leave bubbles mid-turn outside a StreamEvent.
 * The final `toolLabel` folds into `activity` so no step is dropped.
 * The `interrupted`-flag bubble keeps its trail visible; a resuming frame
 * rebinds via `findInterruptedBubble`.
 */
export function sweepTransitional(
  messages: ChatMessage[],
  opts: { stopped?: boolean } = {},
): ChatMessage[] {
  let changed = false;
  const next = messages.map((m): ChatMessage => {
    if (
      m.type === "text" &&
      (m.state === "thinking" ||
        m.state === "tool_use" ||
        m.state === "streaming")
    ) {
      changed = true;
      const { retrying: _r, state: _s, ...rest } = m;
      void _r;
      void _s;
      const folded = rest.toolLabel
        ? {
            ...rest,
            activity: pushActivity(rest.activity, {
              label: rest.toolLabel,
              kind: "tool" as const,
              startedAt: rest.currentActivityStartedAt ?? Date.now(),
            }),
            toolLabel: undefined,
            currentActivityStartedAt: undefined,
          }
        : rest;
      return {
        ...folded,
        interrupted: true,
        ...(opts.stopped ? { stopped: true } : {}),
        livenessRearms: 0,
      };
    }
    return m;
  });
  return changed ? next : messages;
}

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
  activeStreams: Map<DomainLeaderId, string>;
  workflow: WorkflowLifecycleState;
  spawnIndex: SpawnIndex;
}

export interface StreamEventResult {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, string>;
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
  // feat-session-completion-inline — inline completion card (main list).
  | { type: "task_completed" }
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
  return new Set(prev);
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
    // Same turn-boundary barrier as findInterruptedBubble.
    if (m.role === "user") break;
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
  activeStreams: Map<DomainLeaderId, string>,
  leaderId: DomainLeaderId,
  errIdx: number,
  patch: Partial<ChatTextMessage> & { state: MessageState },
): {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, string>;
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
  nextStreams.set(leaderId, updated[errIdx].id);
  return { messages: updated, activeStreams: nextStreams };
}

/** feat-concierge-activity-trail (#9515): fold pruned `tool_use_chip` labels
 *  into `activity` — the pre-bubble steps the user already saw must survive
 *  the chip→bubble hand-off (spec-flow: chips are deleted on first stream,
 *  so without seeding the trail "forgets" its own early steps). */
function seedActivityFromChips(
  activity: ActivityEntry[] | undefined,
  chips: ChatMessage[],
): ActivityEntry[] | undefined {
  let out = activity;
  for (const c of chips) {
    if (c.type !== "tool_use_chip") continue;
    out = pushActivity(out, {
      label: c.toolLabel,
      kind: "tool",
      startedAt: c.at ?? Date.now(),
    });
  }
  return out;
}

/**
 * feat-concierge-activity-trail (#9515): rebind a resuming frame onto the
 * swept `interrupted` bubble — clears the flag, applies the transitional
 * patch, re-registers the leader in `activeStreams` (by message id), and
 * seeds any pruned chip labels so the trail continues in the SAME box.
 * Operator-chosen seamless resume (over the panel's honest-gap lean).
 */
function rebindInterruptedBubble(
  prev: ChatMessage[],
  activeStreams: Map<DomainLeaderId, string>,
  leaderId: DomainLeaderId,
  idx: number,
  patch: Partial<ChatTextMessage>,
): {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, string>;
} {
  const updated = [...prev];
  const current = updated[idx];
  if (current.type !== "text") {
    return { messages: prev, activeStreams };
  }
  const {
    interrupted: _i,
    stopped: _st,
    retrying: _r,
    livenessRearms: _l,
    ...rest
  } = current;
  void _i;
  void _st;
  void _r;
  void _l;
  updated[idx] = {
    ...rest,
    ...patch,
    type: "text",
    livenessRearms: 0,
  };
  const nextStreams = new Map(activeStreams);
  nextStreams.set(leaderId, updated[idx].id);
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
  activeStreams: Map<DomainLeaderId, string>,
  event: StreamEvent,
  priorSpawnIndex: SpawnIndex = new Set(),
  priorWorkflow: WorkflowLifecycleState = IDLE_WORKFLOW,
): StreamEventResult {
  switch (event.type) {
    case "stream_start": {
      // #9515 — a new turn for a leader whose tip bubble was swept to
      // `interrupted` on the flap rebinds into ONE box (operator-chosen
      // seamless resume). Checked before the error-rebind and the append —
      // an interrupted bubble is fresher than any stale error.
      const intIdx = findInterruptedBubble(prev, event.leaderId);
      if (intIdx !== undefined) {
        const rebound = rebindInterruptedBubble(
          prev,
          activeStreams,
          event.leaderId,
          intIdx,
          { state: "thinking", toolLabel: undefined },
        );
        return {
          ...rebound,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
          timerAction: { type: "reset", leaderId: event.leaderId },
        };
      }
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
      };
      const nextStreams = new Map(activeStreams);
      nextStreams.set(event.leaderId, newMsg.id);
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
        // #9515 — rebind BEFORE the chip path: a resuming tool_use after a
        // flap must reattach to the swept bubble, never spawn a sibling chip
        // row next to it (the duplicate-Working-box class, new costume).
        const intIdx = findInterruptedBubble(prev, event.leaderId);
        if (intIdx !== undefined) {
          const current = prev[intIdx];
          const rebound = rebindInterruptedBubble(
            prev,
            activeStreams,
            event.leaderId,
            intIdx,
            {
              state: "tool_use",
              ...foldCurrentStep(current),
              toolLabel: event.label,
              currentActivityStartedAt: Date.now(),
            },
          );
          return {
            ...rebound,
            workflow: priorWorkflow,
            spawnIndex: priorSpawnIndex,
            timerAction: { type: "reset", leaderId: event.leaderId },
          };
        }
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
              ...foldCurrentStep(current),
              toolLabel: event.label,
              currentActivityStartedAt: Date.now(),
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
          at: Date.now(),
        };
        // Review F4: cap at TOOL_USE_CHIP_CAP_PER_LEADER chips per leader.
        // Drop oldest chips for the same leader before appending the new one.
        // #9515 known tradeoff: evicted chip labels are dropped (no bubble
        // exists yet to seed into) — a >5-tool pre-bubble burst loses the
        // earliest steps from the trail. Bounded, transient, accepted.
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
      const idx = resolveStreamIndex(prev, activeStreams, event.leaderId);
      if (idx === undefined) {
        const intIdx = findInterruptedBubble(prev, event.leaderId);
        if (intIdx !== undefined) {
          const current = prev[intIdx];
          const rebound = rebindInterruptedBubble(
            prev,
            activeStreams,
            event.leaderId,
            intIdx,
            {
              state: "tool_use",
              ...foldCurrentStep(current),
              toolLabel: event.label,
              currentActivityStartedAt: Date.now(),
            },
          );
          return {
            ...rebound,
            workflow: priorWorkflow,
            spawnIndex: priorSpawnIndex,
            timerAction: { type: "reset", leaderId: event.leaderId },
          };
        }
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
              ...foldCurrentStep(current),
              toolLabel: event.label,
              currentActivityStartedAt: Date.now(),
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
      const target = updated[idx];
      // Belt: id-keyed activeStreams should never resolve to a non-text
      // message, but a stale id must not stamp state onto a chip/gate row.
      if (target.type !== "text") {
        return {
          messages: prev,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
        };
      }
      updated[idx] = {
        ...target,
        ...foldCurrentStep(target),
        state: "tool_use",
        toolLabel: event.label,
        currentActivityStartedAt: Date.now(),
        interrupted: false,
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
      const idx = resolveStreamIndex(prev, activeStreams, event.leaderId);
      if (idx === undefined) {
        const intIdx = findInterruptedBubble(prev, event.leaderId);
        if (intIdx !== undefined) {
          const rebound = rebindInterruptedBubble(
            prev,
            activeStreams,
            event.leaderId,
            intIdx,
            { state: "tool_use" },
          );
          return {
            ...rebound,
            workflow: priorWorkflow,
            spawnIndex: priorSpawnIndex,
            timerAction: { type: "reset", leaderId: event.leaderId },
          };
        }
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
        updated[idx] = { ...rest, interrupted: false };
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
      // #9515 — chips pruned here are the pre-bubble steps the user already
      // saw; seed their labels into the bubble's activity trail so nothing
      // is forgotten at the chip→bubble hand-off.
      const { working, prunedChips } =
        event.leaderId === "cc_router" || event.leaderId === "system"
          ? partitionLeaderChips(prev, event.leaderId)
          : { working: prev, prunedChips: [] };
      const idx = resolveStreamIndex(working, activeStreams, event.leaderId);
      if (idx !== undefined) {
        // REPLACE content (not append) — server sends cumulative snapshots
        const updated = [...working];
        const target = updated[idx];
        // activeStreams should never index a chip/group/gate/prompt/ended
        // bubble (those are appended outside the activeStreams machinery), but
        // guard at the boundary so a future regression surfaces here, not as
        // a corrupted bubble shape.
        if (target.type === "text") {
          const withText = foldReplacedText(
            target.content,
            event.content,
            target.activity,
            target.contentStartedAt,
          );
          const folded = foldCurrentStep(
            { ...target, activity: withText },
            prunedChips,
          );
          updated[idx] = {
            ...target,
            ...folded,
            content: event.content,
            state: "streaming",
            interrupted: false,
            contentStartedAt:
              target.content !== event.content &&
              !event.content.startsWith(target.content)
                ? Date.now()
                : (target.contentStartedAt ?? Date.now()),
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
      // #9515 — rebind the swept interrupted bubble first (one box on resume).
      const intIdx = findInterruptedBubble(working, event.leaderId);
      if (intIdx !== undefined) {
        const current = working[intIdx];
        const withText = foldReplacedText(
          current.content,
          event.content,
          current.activity,
          current.contentStartedAt,
        );
        const folded = foldCurrentStep(
          { ...current, activity: withText },
          prunedChips,
        );
        const rebound = rebindInterruptedBubble(
          working,
          activeStreams,
          event.leaderId,
          intIdx,
          {
            state: "streaming",
            content: event.content,
            contentStartedAt: Date.now(),
            ...folded,
          },
        );
        return {
          ...rebound,
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
            contentStartedAt: Date.now(),
            activity: foldReplacedText(
              working[errIdx].content,
              event.content,
              seedActivityFromChips(
                working[errIdx].activity,
                prunedChips,
              ),
              working[errIdx].contentStartedAt,
            ),
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
        activity: seedActivityFromChips(undefined, prunedChips),
      };
      const nextStreams = new Map(activeStreams);
      nextStreams.set(event.leaderId, newMsg.id);
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
      const { working, prunedChips } =
        event.leaderId === "cc_router" || event.leaderId === "system"
          ? partitionLeaderChips(prev, event.leaderId)
          : { working: prev, prunedChips: [] };
      const idx = resolveStreamIndex(working, activeStreams, event.leaderId);
      const nextStreams = new Map(activeStreams);
      nextStreams.delete(event.leaderId);
      if (idx === undefined) {
        // #9515 — the turn ended while the bubble sat `interrupted` (flap
        // during the gap). Terminalize honestly: done, flag cleared, final
        // toolLabel folded into the trail.
        const intIdx = findInterruptedBubble(working, event.leaderId);
        if (intIdx !== undefined && working[intIdx].type === "text") {
          const t = working[intIdx] as ChatTextMessage;
          const updated = [...working];
          const { interrupted: _i, retrying: _r, ...rest } = t;
          void _i;
          void _r;
          updated[intIdx] = {
            ...rest,
            type: "text",
            state: "done",
            ...foldCurrentStep(rest, prunedChips),
            livenessRearms: 0,
          };
          return {
            messages: updated,
            activeStreams: nextStreams,
            workflow: priorWorkflow,
            spawnIndex: priorSpawnIndex,
            timerAction: { type: "clear", leaderId: event.leaderId },
          };
        }
        // Post-stop chip phase: chips pruned here have no live bubble to
        // seed — fall back to the leader's newest text bubble (the stopped
        // one) so the labels aren't dropped (fix-round residual).
        if (prunedChips.length > 0) {
          const seeded = [...working];
          for (let i = seeded.length - 1; i >= 0; i--) {
            const m = seeded[i];
            if (m.role === "user") break;
            if (m.type === "text" && m.leaderId === event.leaderId) {
              seeded[i] = {
                ...m,
                activity: seedActivityFromChips(m.activity, prunedChips),
              };
              break;
            }
          }
          return {
            messages: seeded,
            activeStreams: nextStreams,
            workflow: priorWorkflow,
            spawnIndex: priorSpawnIndex,
            timerAction: { type: "clear", leaderId: event.leaderId },
          };
        }
        return {
          messages: working,
          activeStreams: nextStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
          timerAction: { type: "clear", leaderId: event.leaderId },
        };
      }
      const updated = [...working];
      const target = updated[idx];
      if (target.type !== "text") {
        return {
          messages: updated,
          activeStreams: nextStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
          timerAction: { type: "clear", leaderId: event.leaderId },
        };
      }
      // #9515 — fold the final step into the trail at terminalization and
      // seed any chip labels still pending, so the live "Used:" list is
      // complete and nothing the user saw is dropped.
      updated[idx] = {
        ...target,
        state: "done",
        interrupted: false,
        ...foldCurrentStep(target, prunedChips),
      };
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
      for (const id of activeStreams.values()) {
        const idx = updated.findIndex((m) => m.id === id);
        if (idx === -1) continue;
        const m = updated[idx];
        if (
          m.type === "text" &&
          (m.state === "thinking" || m.state === "tool_use" || m.state === "streaming")
        ) {
          updated[idx] = {
            ...m,
            state: "done",
            interrupted: false,
            ...foldCurrentStep(m),
          };
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
      for (const id of activeStreams.values()) {
        const idx = updated.findIndex((m) => m.id === id);
        if (idx === -1) continue;
        const m = updated[idx];
        if (
          m.type === "text" &&
          (m.state === "thinking" ||
            m.state === "tool_use" ||
            m.state === "streaming")
        ) {
          updated[idx] = {
            ...m,
            state: "done",
            interrupted: false,
            ...foldCurrentStep(m),
          };
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
      // `spawnIndex` (a duplicate would append a second child to the same
      // group — the Set is existence-only; id-scans own the lookup). Mirror the
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
        nextSpawnIndex.add(event.spawnId);
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
      nextSpawnIndex.add(event.spawnId);
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
      // Sticky context bar update; remove any leftover tool_use chips —
      // seeding their labels into a live bubble for the same leader first
      // (#9515: pruned chip steps must not silently vanish).
      const pruned = prev.filter((m) => m.type === "tool_use_chip");
      let messages = pruned.length > 0
        ? prev.filter((m) => m.type !== "tool_use_chip")
        : prev;
      if (pruned.length > 0) {
        const updated = [...messages];
        for (const chip of pruned) {
          const leader = (chip as ChatToolUseChipMessage).leaderId;
          let idx = resolveStreamIndex(updated, activeStreams, leader);
          if (idx === undefined) {
            // Chips exist only while their leader has NO active stream — the
            // resolve above is dead code there (data seat F3). Fall back to
            // the leader's newest text bubble so the label isn't dropped.
            for (let i = updated.length - 1; i >= 0; i--) {
              const m = updated[i];
              if (m.role === "user") break;
              if (m.type === "text" && m.leaderId === leader) {
                idx = i;
                break;
              }
            }
          }
          if (idx !== undefined && updated[idx].type === "text") {
            updated[idx] = {
              ...updated[idx],
              activity: seedActivityFromChips(updated[idx].activity, [chip]),
            };
          }
        }
        messages = updated;
      }
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
      const { working, prunedChips } =
        event.leaderId === "cc_router" || event.leaderId === "system"
          ? partitionLeaderChips(prev, event.leaderId)
          : { working: prev, prunedChips: [] };

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

      const idx = resolveStreamIndex(working, activeStreams, event.leaderId);
      if (idx !== undefined && working[idx].type === "text") {
        const updated = [...working];
        const target = updated[idx] as ChatTextMessage;
        updated[idx] = {
          ...target,
          commandBlocks: applyToBlocks(target.commandBlocks),
          activity: seedActivityFromChips(target.activity, prunedChips),
          interrupted: false,
        };
        return {
          messages: updated,
          activeStreams,
          workflow: priorWorkflow,
          spawnIndex: priorSpawnIndex,
          timerAction: { type: "reset", leaderId: event.leaderId },
        };
      }

      // #9515 — rebind the swept interrupted bubble first (one box on resume).
      const intIdx = findInterruptedBubble(working, event.leaderId);
      if (intIdx !== undefined && working[intIdx].type === "text") {
        const target = working[intIdx] as ChatTextMessage;
        const rebound = rebindInterruptedBubble(
          working,
          activeStreams,
          event.leaderId,
          intIdx,
          {
            state: "streaming",
            commandBlocks: applyToBlocks(target.commandBlocks),
            activity: seedActivityFromChips(target.activity, prunedChips),
          },
        );
        return {
          ...rebound,
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
            activity: seedActivityFromChips(target.activity, prunedChips),
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
        commandBlocks: applyToBlocks(undefined),
        activity: seedActivityFromChips(undefined, prunedChips),
      };
      const nextStreams = new Map(activeStreams);
      nextStreams.set(event.leaderId, newMsg.id);
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
      // INVARIANT: a debug heartbeat must only fire on LIVE liveness evidence.
      // `debug_event` IS a member of the #5290 stream-replay buffer family
      // (server/stream-replay-buffer.ts), so buffered frames CAN reach this
      // reducer twice — on a transient-reconnect `resume_stream` replay and on
      // a leave-and-return session rebind. Every re-emitted frame carries
      // `replayed: true` (server/ws-handler.ts `replayBufferedDebugEvents` and
      // the resume_stream re-emit loop), so the heartbeat paths below gate on
      // `!event.replayed`: replayed frames still append to the panel log but
      // never re-arm the watchdog or rebind an orphan bubble on stale evidence.
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
      // `replayed` frames are stale evidence — never rebind on them.
      // Use findRecoverableErrorBubble (tip contract) — not any historical error.
      if (event.kind === "tool_use" && !event.replayed && activeStreams.size === 0) {
        const orphanLeaders = new Map<DomainLeaderId, number>();
        const orphanKinds = new Map<DomainLeaderId, "interrupted" | "error">();
        const seenLeaders = new Set<DomainLeaderId>();
        for (let i = prev.length - 1; i >= 0; i--) {
          const m = prev[i];
          if (m.type !== "text" || m.leaderId === undefined) continue;
          if (seenLeaders.has(m.leaderId)) continue;
          seenLeaders.add(m.leaderId);
          const intIdx = findInterruptedBubble(prev, m.leaderId);
          if (intIdx !== undefined) {
            orphanLeaders.set(m.leaderId, intIdx);
            orphanKinds.set(m.leaderId, "interrupted");
            continue;
          }
          const errIdx = findRecoverableErrorBubble(prev, m.leaderId);
          if (errIdx !== undefined) {
            orphanLeaders.set(m.leaderId, errIdx);
            orphanKinds.set(m.leaderId, "error");
          }
        }
        if (orphanLeaders.size === 1) {
          const [[orphanLeader, idx]] = orphanLeaders;
          const rebound =
            orphanKinds.get(orphanLeader) === "interrupted"
              ? rebindInterruptedBubble(
                  prev,
                  activeStreams,
                  orphanLeader,
                  idx,
                  { state: "tool_use" },
                )
              : rebindRecoveredErrorBubble(
                  prev,
                  activeStreams,
                  orphanLeader,
                  idx,
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

      const isHeartbeat =
        event.kind === "tool_use" && !event.replayed && activeStreams.size === 1;
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
      const soleId = activeStreams.values().next().value as string | undefined;
      const soleIdx =
        soleId !== undefined
          ? prev.findIndex((m) => m.id === soleId)
          : -1;
      const sole = soleIdx >= 0 ? prev[soleIdx] : undefined;
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

    case "task_completed": {
      // feat-session-completion-inline — APPEND the inline completion card to
      // the main message list. Emitted by the shared `notifyTaskCompleted`
      // seam at every turn boundary (both lineages), so unlike turn_summary
      // it arrives on EVERY completed request. Ephemeral — the inbox_item row
      // (id in `inboxItemId`) is the durable record; a reload rehydrates from
      // history without it, which is honest (the completion already showed).
      const completedMsg: ChatTaskCompletedMessage = {
        id: `task-completed-${crypto.randomUUID()}`,
        role: "assistant",
        content: event.title,
        type: "task_completed",
        inboxItemId: event.inboxItemId,
      };
      return {
        messages: [...prev, completedMsg],
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
  activeStreams: Map<DomainLeaderId, string>,
  leaderId: string,
): {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, string>;
  timerAction?:
    | { type: "reset"; leaderId: string }
    | { type: "clear"; leaderId: string };
} {
  const idx = resolveStreamIndex(prev, activeStreams, leaderId as DomainLeaderId);
  if (idx === undefined) {
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
    const siblingActive = [...activeStreams.entries()].some(([id, sId]) => {
      if (id === (leaderId as DomainLeaderId)) return false;
      const sIdx = prev.findIndex((m) => m.id === sId);
      if (sIdx === -1) return false;
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
    updated[idx] = { ...rest, state: "error", interrupted: false };
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
