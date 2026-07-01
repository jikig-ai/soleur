import type { DomainLeaderId } from "@/server/domain-leaders";
import type { WorkflowName } from "@/server/conversation-routing";
import type { InteractivePromptKind } from "@/server/pending-prompt-registry";
import type { SpawnId, PromptId, ConversationId } from "@/lib/branded-ids";

// Re-export so client code can import workflow-name and branded IDs from the
// canonical wire-protocol module without reaching into server/* directly.
export type { WorkflowName } from "@/server/conversation-routing";
export type { SpawnId, PromptId, ConversationId } from "@/lib/branded-ids";

/**
 * Terminal states a `/soleur:go` workflow run can end in. The runner's
 * `WorkflowEnd["status"]` union in `server/soleur-go-runner.ts` is the
 * canonical source; this tuple mirrors it (enforced by
 * `_AssertWorkflowEndStatusMatches` in `soleur-go-runner.ts` — adding to
 * either side without the other is a TS error there). Both the Zod
 * schema in `lib/ws-zod-schemas.ts` and the TS union below derive from
 * this tuple. #3827 + ADR-031 amendment 2026-05-15.
 */
export const WORKFLOW_END_STATUSES = [
  "completed",
  "user_aborted",
  "cost_ceiling",
  "idle_timeout",
  "plugin_load_failure",
  "runner_runaway",
  "internal_error",
  // #4440 follow-up to #4418 — cross-process JWT-deny propagation to
  // agent-driven workflows. Emitted when soleur-go-runner / cc-dispatcher
  // / agent-runner catch a `RuntimeAuthError` with `cause === "denied_jti"`
  // mid-run. Today only the human WS client receives the discriminated
  // `revocation_notice` frame (`ws-handler.tenantFor` catch path); agents
  // running long workflows received a generic `internal_error`, which
  // is indistinguishable from a transient SDK failure. Adding this
  // terminal status lets the runner surface the same operator-supplied
  // `reason` to API/agent consumers and gives them a deterministic
  // discriminator on which to invalidate cached JWT material before
  // any retry attempt. Recoverable from the agent's perspective only
  // in the sense that the underlying session is gone — pairing in
  // `cc-dispatcher.onWorkflowEnded` routes it to the terminal
  // `session_ended` family (see TERMINAL_WORKFLOW_END_STATUSES).
  "session_revoked",
  // #5313 (deferred #5240 FR-half) — the worktree-rebind loop. Emitted by
  // the runner's command-pattern detector when N=3 consecutive
  // near-identical `cd <path> && pwd` CWD-verification commands return a
  // `pwd` that does not equal the expected worktree path (the Bash bwrap
  // sandbox could not enter the worktree). A fast, honest terminal state
  // so the operator sees "couldn't enter the workspace" in seconds instead
  // of the agent looping the verify command until the 10-min runner_runaway
  // breaker fires with a generic status. `z.enum(WORKFLOW_END_STATUSES)` in
  // `ws-zod-schemas.ts` reuses this tuple — no duplicate enum to update.
  "worktree_enter_failed",
] as const;
export type WorkflowEndStatus = typeof WORKFLOW_END_STATUSES[number];

/**
 * `subagent_complete.status` allowed values. Tuple-as-source so the Zod
 * schema and TS union cannot drift.
 */
export const SUBAGENT_COMPLETE_STATUSES = ["success", "error", "timeout"] as const;
export type SubagentCompleteStatus = typeof SUBAGENT_COMPLETE_STATUSES[number];

/**
 * `context_reset.reason` allowed values (#3269). Tuple-as-source — the
 * Zod schema, the helper return shape (`agent-prefill-guard.ts`), the
 * `ChatContextResetMessage` reducer variant, and the `CONTEXT_RESET_COPY`
 * render-side const all derive from this union to prevent silent drift
 * when the family widens. ADR-025 documents the lifecycle-notice family.
 */
export const CONTEXT_RESET_REASONS = ["prefill-guard", "tool_use_orphan"] as const;
export type ContextResetReason = typeof CONTEXT_RESET_REASONS[number];

/**
 * `interactive_prompt.kind` allowed values. Tuple is shared with
 * `server/pending-prompt-registry.ts:InteractivePromptKind` via a compile-
 * time `_AssertKindsMatch` check below.
 */
export const INTERACTIVE_PROMPT_KINDS = [
  "ask_user",
  "plan_preview",
  "diff",
  "bash_approval",
  "todo_write",
  "notebook_edit",
] as const;

/**
 * Single todo item carried by `interactive_prompt.kind === "todo_write"`.
 * Inlined here in Stage 3 — was previously in
 * the Stage 2 feature-local shim (deleted in Stage 3 / #2885).
 */
export interface TodoItem {
  id: string;
  content: string;
  status: "pending" | "in_progress" | "completed";
}

/** Discriminated payload for `interactive_prompt`, keyed by `kind`. Shapes
 *  mirror the runner-side contract used by `pending-prompt-registry`. */
export type InteractivePromptPayload =
  | { kind: "ask_user"; payload: { question: string; options: string[]; multiSelect: boolean } }
  | { kind: "plan_preview"; payload: { markdown: string } }
  | { kind: "diff"; payload: { path: string; additions: number; deletions: number } }
  | { kind: "bash_approval"; payload: { command: string; cwd: string; gated: boolean } }
  | { kind: "todo_write"; payload: { items: TodoItem[] } }
  | { kind: "notebook_edit"; payload: { notebookPath: string; cellIds: string[] } };

/** Discriminated user response for `interactive_prompt_response`. */
export type InteractivePromptResponsePayload =
  | { kind: "ask_user"; response: string | string[] }
  | { kind: "plan_preview"; response: "accept" | "iterate" }
  | { kind: "bash_approval"; response: "approve" | "deny" }
  | { kind: "diff" | "todo_write" | "notebook_edit"; response: "ack" };

/**
 * Bidirectional exhaustiveness assertions: the `kind` set on
 * `InteractivePromptPayload` AND `InteractivePromptResponsePayload` must
 * match the registry's `InteractivePromptKind` exactly. A new kind on any
 * side fails compilation here.
 */
type _AssertKindsMatch =
  InteractivePromptKind extends InteractivePromptPayload["kind"]
    ? InteractivePromptPayload["kind"] extends InteractivePromptKind
      ? true
      : never
    : never;
const _exhaustiveKindCheck: _AssertKindsMatch = true;
void _exhaustiveKindCheck;

type _AssertResponseKindsMatch =
  InteractivePromptKind extends InteractivePromptResponsePayload["kind"]
    ? InteractivePromptResponsePayload["kind"] extends InteractivePromptKind
      ? true
      : never
    : never;
const _exhaustiveResponseKindCheck: _AssertResponseKindsMatch = true;
void _exhaustiveResponseKindCheck;

// Typed error codes for structured error handling over WebSocket.
// SECOND CANONICAL COPY: the wire schema replicates this set as a `z.enum([...])`
// in `lib/ws-zod-schemas.ts` (errorSchema.errorCode). Widen BOTH in the same
// change — `tsc` fails the `_SchemaCovers` proof there if they drift (#5394).
export type WSErrorCode =
  | "key_invalid"
  // Phase 3.2 AC-D (feat-team-workspace-multi-user) — member-without-BYOK
  // fail-closed path. Client renders the configure-banner linking to
  // /dashboard/settings/byok rather than the `key_invalid` key-prompt.
  | "byok_key_missing"
  // feat-operator-cc-oauth FR5 — subscription credit/rate-limit exhaustion
  // on an oauth_token run. Distinct from `key_invalid` (re-pasting the token
  // is the wrong action) and `rate_limited` (per-account API throttle).
  // Client renders non-retryable copy; the credit window must reset.
  | "subscription_limit"
  | "session_expired"
  | "session_resumed"
  | "rate_limited"
  | "idle_timeout"
  | "upload_failed"
  | "file_too_large"
  | "unsupported_file_type"
  | "too_many_files"
  | "interactive_prompt_rejected"
  // Server stripped `[Image #N]` placeholders from inbound content. The
  // SDK CLI's text-editor markers leaked into `text/plain` paste data;
  // image bytes were never attached. Client renders a non-blocking
  // banner asking the user to re-attach the image directly.
  | "image_paste_lost"
  // #5394 — Concierge dispatch blocked because the active workspace's repo
  // setup `error`'d (repo_status === "error"). Client renders the reconnect
  // CTA to Settings → Repository. The `cloning` block carries NO errorCode
  // (a benign transient state, not a failure).
  | "repo_setup_failed"
  // ADR-044 PR-1 — Concierge dispatch blocked because the member was reset to
  // an empty solo workspace (their session pointed at a team they're not a
  // member of). Client renders a workspace-switcher affordance (carrying
  // `switchToWorkspaceId`), NOT a reconnect CTA — the member does not own the
  // connection. Distinct from `repo_setup_failed` (an owner's repo errored).
  | "workspace_switch_required"
  | "delegation_revoked_post_grace"
  | "delegation_expired"
  | "delegation_hourly_cap_exceeded"
  | "delegation_daily_cap_exceeded"
  | "delegation_cross_tenant";

// Shared WebSocket close codes — single source of truth for server, client, and tests.
// See: https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/code (4000-4999 = application-reserved)
export const WS_CLOSE_CODES = {
  AUTH_TIMEOUT: 4001,
  SUPERSEDED: 4002,
  AUTH_REQUIRED: 4003,
  TC_NOT_ACCEPTED: 4004,
  INTERNAL_ERROR: 4005,
  SUBSCRIPTION_SUSPENDED: 4006,
  RATE_LIMITED: 4008,
  IDLE_TIMEOUT: 4009,
  CONCURRENCY_CAP: 4010,
  TIER_CHANGED: 4011,
  /** AC-FLOW2 — workspace owner removed this user's membership. The server
   *  sends a `workspace_removed` preamble (with `organizationName`) before
   *  closing so the client can render the terminal screen. */
  MEMBERSHIP_REVOKED: 4012,
  /** #5274 Phase 3 (ADR-068 D0) — the owning host is draining/migrating this
   *  user's session to another host. NON-TERMINAL: the client reconnects via the
   *  CF ingress and is transparently re-proxied to the new owner (b2). The client
   *  resets its resume cursor first (the turn re-materialises on the new owner;
   *  ADR-059 replay buffer is Phase 4a — a brief re-render is acceptable, AC8). */
  ROUTING_MIGRATED: 4013,
  /** #5274 Phase 3 — a peer host owns this session's lease but its address is not
   *  resolvable (not in SOLEUR_HOST_ROSTER / owner unreachable). Non-terminal:
   *  the client retries; a transient roster/owner gap self-heals on reconnect. */
  ROUTING_UNAVAILABLE: 4014,
  SERVER_GOING_AWAY: 1001,
} as const;

/** Plan tier taxonomy. Ladder: free → solo → startup → scale → enterprise. */
export type PlanTier = "free" | "solo" | "startup" | "scale" | "enterprise";

/**
 * Preamble payload written by the server immediately before `ws.close(4010)`.
 * Client parses this in `onmessage` to drive the at-capacity upgrade modal.
 */
export interface ConcurrencyCapHitPreamble {
  type: "concurrency_cap_hit";
  currentTier?: PlanTier;
  nextTier?: PlanTier | null;
  activeCount: number;
  effectiveCap: number;
}

/**
 * Preamble payload written before `ws.close(4011)` on a tier-change
 * force-disconnect (Stripe webhook downgrade with new cap < prior cap).
 */
export interface TierChangedPreamble {
  type: "tier_changed";
  previousTier?: PlanTier;
  newTier?: PlanTier;
}

/**
 * Preamble written before `ws.close(4012)` when a workspace owner removes
 * this user's membership. The client renders a terminal screen using
 * `organizationName` so the user understands which workspace they were
 * removed from.
 */
export interface MembershipRevokedPreamble {
  type: "membership_revoked";
  organizationName: string | null;
  /** Optional workspace_id for client-side reconciliation / audit. */
  workspaceId?: string;
}

export type ClosePreamble =
  | ConcurrencyCapHitPreamble
  | TierChangedPreamble
  | MembershipRevokedPreamble;

export class KeyInvalidError extends Error {
  constructor() {
    super("No valid API key found. Please set up your key first.");
    this.name = "KeyInvalidError";
  }
}

// Attachment reference passed with chat messages
export interface AttachmentRef {
  storagePath: string;
  filename: string;
  contentType: string;
  sizeBytes: number;
}

// Context passed when starting a conversation from a specific page
export interface ConversationContext {
  // Optional: document-context types (e.g. "kb-viewer") carry a path; mode-flag
  // types (e.g. "routine-authoring", #5402) carry no document and omit it.
  path?: string;   // artifact path (e.g., "knowledge-base/product/roadmap.md")
  type: string;    // page type / mode flag (e.g., "kb-viewer", "routine-authoring")
  content?: string; // full artifact content for system prompt injection
}

// Message lifecycle states: each agent bubble progresses through these states
export type MessageState = "thinking" | "tool_use" | "streaming" | "done" | "error";

// WebSocket message protocol
export type WSMessage =
  | { type: "auth"; token: string }
  | { type: "auth_ok" }
  | { type: "chat"; content: string; attachments?: AttachmentRef[] }
  | { type: "start_session"; leaderId?: DomainLeaderId; context?: ConversationContext; resumeByContextPath?: string }
  | { type: "resume_session"; conversationId: string }
  | { type: "close_conversation" }
  | { type: "review_gate_response"; gateId: string; selection: string }
  // feat-bash-autonomous-default-on — first-run consent soft-gate response
  // (client→server). `selection` is "Got it" / "Keep autonomous on" /
  // "Ask me each time". `userId` is resolved from the authenticated socket —
  // NOT a wire field (TR4 cross-user invariant; strictObject rejects forgery).
  | { type: "autonomous_disclosure_response"; gateId: string; selection: string }
  // Client → server: user-initiated Stop. The server resolves `userId`
  // from the authenticated socket session — `userId` is intentionally
  // NOT part of the wire shape (TR4 cross-user invariant; see
  // `feat-abort-conversation-web` plan §"User-Brand Impact"). The
  // strictObject zod schema in `lib/ws-zod-schemas.ts` rejects extra
  // fields so a forged `userId` cannot land here from a network peer.
  | { type: "abort_turn"; conversationId: string }
  | {
      type: "stream";
      content: string;
      /**
       * Server-side diagnostic: `true` for streamed deltas, `false` for the
       * final consolidated text on completion. The client uses replace
       * semantics regardless — it treats every `stream` event as a cumulative
       * snapshot. Do not branch on this field on the client.
       */
      partial: boolean;
      leaderId: DomainLeaderId;
      /** seq (#5273): server-stamped monotonic replay cursor; optional on the wire for rolling-deploy back-compat. ADR-059. */
      seq?: number;
    }
  | { type: "stream_start"; leaderId: DomainLeaderId; source?: "auto" | "mention"; /** seq (#5273): server-stamped monotonic replay cursor; optional on the wire for rolling-deploy back-compat. ADR-059. */ seq?: number }
  | { type: "stream_end"; leaderId: DomainLeaderId; /** seq (#5273): server-stamped monotonic replay cursor; optional on the wire for rolling-deploy back-compat. ADR-059. */ seq?: number }
  | { type: "tool_use"; leaderId: DomainLeaderId; label: string; /** seq (#5273): server-stamped monotonic replay cursor; optional on the wire for rolling-deploy back-compat. ADR-059. */ seq?: number }
  // feat-concierge-stream-commands — Concierge Bash commands + their
  // (truncated, redacted) stdout/stderr stream INLINE into the cc_router
  // bubble, Claude-Code-terminal style, instead of spawning per-command
  // Approve/Deny cards. Gated to the autonomous posture at the emit site
  // (D1). `command` carries the REDACTED command on `phase:"start"`;
  // `output` carries a REDACTED, byte-capped chunk on `phase:"output"`;
  // `phase:"end"` closes the block. Both text fields are redacted at the
  // EMIT boundary (server) per TR4 — render-time redaction is the
  // belt-and-suspenders Art. 14 gate. `truncated:true` marks an output
  // chunk that hit the per-command cap (D4). Distinct from `tool_use`
  // (which deliberately withholds the raw tool name per #2138); the
  // redaction gate is the scoped exception that lets command text ride.
  | {
      type: "command_stream";
      leaderId: DomainLeaderId;
      command?: string;
      output?: string;
      phase: "start" | "output" | "end";
      truncated?: boolean;
      /**
       * FIX 2 — SDK `tool_use` block id correlating a `start`/`output`/`end`
       * sequence to its block. When one assistant turn emits two concurrent
       * Bash tool-uses, the reducer routes output by `toolUseId` instead of
       * appending to the last block (which mis-attributes A's output to B).
       * Optional for back-compat: absent → last-block append.
       */
      toolUseId?: string;
    }
  | {
      /**
       * FR4 (#2861): server forwards the SDK `SDKToolProgressMessage`
       * heartbeat (debounced to ≤1/5s per `toolUseId`) so the client watchdog
       * doesn't fire during long-running tool execution.
       */
      type: "tool_progress";
      leaderId: DomainLeaderId;
      toolUseId: string;
      toolName: string;
      elapsedSeconds: number;
      /** seq (#5273): server-stamped monotonic replay cursor; optional on the wire for rolling-deploy back-compat. ADR-059. */
      seq?: number;
    }
  // feat-debug-mode-stream — internal dev-cohort harness instruction stream
  // (server→client). A SEPARATE collapsed debug panel renders these; they are
  // NOT routed into the conversation bubble. Each frame is ONE delta event
  // (turn end is signalled by `stream_end`/`session_ended`). `body` is the
  // ALREADY-redacted-or-dropped display string built at the server emit
  // boundary (`server/debug-event.ts`): for `tool_use` it is the per-string-
  // leaf-redacted serialized tool_input, or the `[input withheld …]` drop
  // placeholder on a redaction-probe trip. `label` (when present) is the
  // human tool label from `buildToolLabel(name, undefined, …)` — NEVER the
  // raw SDK tool name (#2138/PR#2115). Flat (no leaderId): the panel is a
  // single ordered log, not a per-leader bubble. Render-only + ephemeral —
  // NEVER persisted to `messages`/logs/Sentry (standing CI grep gate).
  | {
      type: "debug_event";
      kind: "tool_use" | "reasoning" | "result";
      label?: string;
      body: string;
    }
  // feat-reasoning-chat-boxes (#5370) — agent-emitted, USER-FACING narration.
  // Distinct from `debug_event` (team-only, dev-cohort, raw SDK internals):
  // these carry deliberate plain-language text the agent authors via the
  // `narrate`/`summarize` MCP tools, redacted at the server emit boundary.
  //
  // `reasoning_narration` is the TRANSIENT live status line ("Looking into
  // the navigation issue…"). LIVE-ONLY: it carries NO `seq` and is EXCLUDED
  // from the stream-replay buffer (mirrors debug_event), so it never replays
  // on reconnect and is never persisted. The client stores it in a transient
  // `liveNarration` slot torn down on every turn-end path.
  | { type: "reasoning_narration"; message: string }
  // `turn_summary` is the DURABLE per-turn record ("✓ Fixed the side panel…").
  // Persisted as a `messages` row (message_kind='turn_summary', mig 105) AND
  // buffered (carries `seq`) so it survives reconnect + history refetch.
  | { type: "turn_summary"; summary: string; /** seq (#5273): server-stamped monotonic replay cursor; optional on the wire for rolling-deploy back-compat. ADR-059. */ seq?: number }
  | { type: "review_gate"; gateId: string; question: string; header?: string; options: string[]; descriptions?: Record<string, string | undefined>; stepProgress?: { current: number; total: number } }
  // feat-bash-autonomous-default-on — first-run consent soft-gate disclosure
  // (server→client). A held Bash command awaiting the owner's one-time ack.
  // `existingWorkspace` true => offer the opt-out ("Keep autonomous on" /
  // "Ask me each time"); false => default-ON workspace ("Got it" ack).
  | { type: "autonomous_disclosure"; gateId: string; existingWorkspace: boolean }
  // feat-bash-autonomous-default-on — SERVER-resolved autonomous posture for the
  // persistent chip (server→client). `autonomous` is the SERVER truth
  // `bashAutonomous && ackAt != null` — i.e. "Auto-run on" only when the toggle
  // is on AND the first-run disclosure has been acked. Emitted once per dispatch
  // after the server resolves the toggle + ack (and re-emitted on a successful
  // in-session ack-release). The chip reads THIS, never message presence — a
  // held (un-acked) disclosure is "Approve each", not "Auto-run on".
  | { type: "autonomous_posture"; autonomous: boolean }
  | { type: "session_started"; conversationId: string; capabilities?: { promptKinds: readonly string[]; incomingTypes?: readonly string[] } }
  | { type: "session_resumed"; conversationId: string; resumedFromTimestamp: string; messageCount: number }
  | {
      type: "session_ended";
      reason: string;
      /** Disambiguator for multi-tab clients: when a user has two open
       *  tabs on different conversations, a `session_ended` frame
       *  without `conversationId` would race the wrong tab's reducer
       *  into a `stopping`/`idle` transition. Optional so the existing
       *  emitters that don't yet pass it remain protocol-compatible.
       *  feat-abort-conversation-web PR1 emits it for `user_aborted`
       *  reasons. */
      conversationId?: string;
      /** seq (#5273): server-stamped monotonic replay cursor; optional on the wire for rolling-deploy back-compat. ADR-059. */
      seq?: number;
    }
  // #3269 — context-reset lifecycle notice. Emitted exactly once per
  // prefill-guard fire (assistant-terminated history → SDK 400 prevention
  // path drops `resume:` and the model loses prior-turn context). The
  // `reason` discriminator drives copywriter-approved render variants in
  // chat-surface.tsx; `prefill-guard` is the generic branch and
  // `tool_use_orphan` is the narrower branch where the trailing assistant
  // message contained a `tool_use` content block. ADR-025 establishes the
  // WS lifecycle-notice family invariants for forward-compat.
  | {
      type: "context_reset";
      reason: ContextResetReason;
      conversationId: string;
    }
  | {
      type: "usage_update";
      conversationId: string;
      /**
       * Phase 3 (feat-team-workspace-multi-user) — workspace_id for
       * workspace-grain cost attribution at the client. Optional for
       * one release cycle to absorb rolling prd deploys; tighten in a
       * follow-up after the old build ages out.
       */
      workspaceId?: string;
      totalCostUsd: number;
      inputTokens: number;
      outputTokens: number;
      // Cache tokens — `0` when prompt caching is not engaged. Widened
      // 2026-05-12 to close the dashboard cross-check gap vs the
      // Anthropic Console for cached prompts (plan §Risks R8).
      // Optional for one release cycle so rolling prd deploys don't
      // drop frames between mismatched server/client shapes; coerce
      // `?? 0` at every consumer. Tighten in a follow-up.
      cacheReadInputTokens?: number;
      cacheCreationInputTokens?: number;
      /** seq (#5273): server-stamped monotonic replay cursor; optional on the wire for rolling-deploy back-compat. ADR-059. */
      seq?: number;
    }
  | { type: "fanout_truncated"; dispatched: number; dropped: number }
  | { type: "upgrade_pending" }
  // Stage 3 (#2885) — Command Center soleur-go router protocol with
  // discriminated payloads + Zod-parsed boundary. The `interactive_prompt` /
  // `interactive_prompt_response` sub-unions were previously a feature-local
  // shim (Stage 2 of #2853); inlined here so
  // `WSMessage` is the single source of truth.
  //
  // ID fields are typed as plain `string` because WSMessage describes the
  // wire shape — JSON has no brand concept. The branded types `SpawnId` /
  // `PromptId` / `ConversationId` (re-exported above) provide compile-time
  // cross-confusion protection at internal API boundaries (registry
  // signatures, mint helpers); see `lib/branded-ids.ts`.
  | { type: "subagent_spawn"; parentId: string; leaderId: DomainLeaderId; spawnId: string; task?: string }
  | { type: "subagent_complete"; spawnId: string; status: "success" | "error" | "timeout" }
  | { type: "workflow_started"; workflow: WorkflowName; conversationId: string }
  | { type: "workflow_ended"; workflow: WorkflowName; status: WorkflowEndStatus; summary?: string }
  | ({ type: "interactive_prompt"; promptId: string; conversationId: string } & InteractivePromptPayload)
  | ({ type: "interactive_prompt_response"; promptId: string; conversationId: string } & InteractivePromptResponsePayload)
  | {
      type: "error";
      message: string;
      errorCode?: WSErrorCode;
      gateId?: string;
      // #3225: when this `error` event is mapped from a `runner_runaway`
      // WorkflowEnd, forward the diagnostic fields so an API client /
      // agent observing the conversation can distinguish idle-window
      // from max-turn-duration stalls and see which tool was last alive.
      // Optional and ignorable by existing consumers.
      runnerRunawayReason?: "idle_window" | "max_turn_duration";
      runnerRunawayLastBlockKind?: "text" | "tool_use" | null;
      runnerRunawayLastBlockToolName?: string | null;
      // ADR-044 PR-1 — set with `errorCode: "workspace_switch_required"`: the
      // workspace id (the discarded non-member claim) the client offers to
      // switch to. The client opens the workspace switcher (NOT a direct
      // membership-checked switch — a reset user is a non-member by
      // construction). Optional and ignorable by existing consumers.
      switchToWorkspaceId?: string;
    }
  // #3930 — cross-process JWT revocation discriminator. Emitted when
  // ws-handler's `tenantFor` catch site sees a RuntimeAuthError with
  // cause='denied_jti' AND the founder-side `my_revocation_status()`
  // confirms a deny-list row. Replaces the generic
  // "Authentication unavailable; retry shortly" toast with a discriminated
  // message so the founder understands WHY the session ended.
  // `reason` is the operator-supplied free-text from `denied_jti.reason`.
  | {
      type: "revocation_notice";
      reason: string | null;
      deniedAt: string | null;
    }
  // feat-stream-since-disconnect (#5273) — client→server reattach control
  // frame. Sent on a TRANSIENT reconnect (the `auth_ok` brief-drop path),
  // distinct from `resume_session` (which aborts the live agent at its first
  // line). The server replays buffered frames with `seq > ackSeq`, then live
  // streaming resumes from the still-running agent. `ackSeq` is the highest
  // `seq` the client has already rendered (a lower bound; the server clamps a
  // negative/huge value). Absent `ackSeq` ⇒ replay the whole buffered tail.
  // `userId` is NOT a wire field — resolved from the authenticated socket
  // (TR4 cross-user invariant; strictObject rejects forgery). See ADR-059.
  | { type: "resume_stream"; conversationId: string; ackSeq?: number }
  // feat-stream-since-disconnect (#5273) — server→client replay-status
  // boundary frame. Emitted ONLY on the fallback path: the requested cursor
  // is older than the oldest buffered frame, or the whole conversation buffer
  // was map-evicted. The client responds by triggering the v1 honest
  // persisted-history refetch (never a silent stale/duplicate render). The
  // happy path needs no bracket frames — per-`seq` dedup at the client makes
  // a replay window redundant. Per-status discriminated sub-union so a future
  // `complete`/`begin`/`end` status carries its own required fields without
  // widening this one. See ADR-059.
  | { type: "stream_replay"; conversationId: string; status: "incomplete" };

/**
 * Wire-protocol naming convention (Stage 3, #2885):
 *   - `type` discriminator values are snake_case ("subagent_spawn",
 *     "session_started", "interactive_prompt_response").
 *   - `kind` sub-discriminator values are also snake_case ("ask_user",
 *     "plan_preview", "bash_approval").
 *   - All other fields are camelCase ("promptId", "conversationId",
 *     "leaderId", "totalCostUsd").
 * New variants must follow this convention. The `_SchemaCovers` proof in
 * `lib/ws-zod-schemas.ts` is the runtime drift gate; this comment is the
 * style gate.
 */

/** Centralized aliases for the `interactive_prompt*` and `subagent_*`
 *  variant subsets. Use these in importers (`server/cc-dispatcher.ts`,
 *  `server/ws-handler.ts`, etc.) instead of redeclaring `Extract<...>`
 *  locally. */
export type InteractivePromptEvent = Extract<WSMessage, { type: "interactive_prompt" }>;
export type InteractivePromptResponse = Extract<WSMessage, { type: "interactive_prompt_response" }>;
export type SubagentSpawnEvent = Extract<WSMessage, { type: "subagent_spawn" }>;
export type SubagentCompleteEvent = Extract<WSMessage, { type: "subagent_complete" }>;
export type WorkflowStartedEvent = Extract<WSMessage, { type: "workflow_started" }>;
export type WorkflowEndedEvent = Extract<WSMessage, { type: "workflow_ended" }>;

// Database types (matches Supabase schema)
export interface User {
  id: string;
  email: string;
  workspace_status: "provisioning" | "ready";
  tc_accepted_at: string | null;
  created_at: string;
}

export type Provider =
  | "anthropic" | "bedrock" | "vertex"
  | "cloudflare" | "stripe" | "plausible" | "hetzner"
  | "github" | "doppler" | "resend"
  | "x" | "linkedin" | "bluesky" | "buttondown";

export interface ApiKey {
  id: string;
  user_id: string;
  encrypted_key: string;
  provider: Provider;
  is_valid: boolean;
  validated_at: string | null;
  iv: string;
  auth_tag: string;
  key_version: number;
  updated_at: string;
  created_at: string;
}

export interface Conversation {
  id: string;
  user_id: string;
  domain_leader: DomainLeaderId | null;
  session_id: string | null;
  status: "active" | "waiting_for_user" | "completed" | "failed";
  total_cost_usd: number;
  input_tokens: number;
  output_tokens: number;
  last_active: string;
  created_at: string;
  archived_at: string | null;
  context_path?: string | null;
  repo_url?: string | null;
  // Added in migration 032 for the /soleur:go runner (plan 2026-04-23,
  // Stage 1). `active_workflow`'s allowed values are enforced by the
  // `conversations_active_workflow_chk` DB CHECK constraint; the richer
  // discriminated union parse/serialize lives in
  // server/conversation-routing.ts (Stage 2). NULL = legacy router.
  active_workflow?: string | null;
  workflow_ended_at?: string | null;
  workspace_id?: string;
  visibility?: "private" | "workspace";
}

export type ConversationStatus = Conversation["status"];

export const STATUS_LABELS: Record<ConversationStatus, string> = {
  waiting_for_user: "Needs your decision",
  active: "Executing",
  completed: "Completed",
  failed: "Needs attention",
} as const;

export interface MessageAttachment {
  id: string;
  storagePath: string;
  filename: string;
  contentType: string;
  sizeBytes: number;
}

export interface Message {
  id: string;
  conversation_id: string;
  role: "user" | "assistant";
  content: string;
  tool_calls: unknown | null;
  leader_id: DomainLeaderId | null;
  attachments?: MessageAttachment[];
  created_at: string;
  /** Added in migration 040. `'aborted'` rows carry partial assistant
   *  text and a `usage` snapshot from a user-initiated Stop or a
   *  tab-close abort. PR2's chat reload renders the abort marker via
   *  this discriminator. Optional in the type so existing
   *  fixtures/snapshots don't churn; runtime persistence always sets
   *  it (DB default is `'complete'`). */
  status?: "complete" | "aborted";
  /** #3640 F6 — discriminates the `usage` shape. **The discriminator
   *  lives on the nested `usage` object, NOT at the Message top level**
   *  (review #3670 — the top-level field was declared but unread; readers
   *  uniformly consult `usage?.variant`). The reader-side types
   *  (`AbortMarkerUsage` in `message-bubble.tsx`, `ChatTextMessage.usage`
   *  in `chat-state-machine.ts`) each carry their own `variant?` field;
   *  the hydration site in `lib/ws-client.ts:1010-1024` derives it from
   *  `leader_id === CC_ROUTER_LEADER_ID`. There is no `variant` column on
   *  the `messages` table — this is a TypeScript-only widening.
   *
   *  - **Legacy `agent-runner` path** (default — nested `variant` absent
   *    or `"legacy"`, `leader_id` ∈ domain leaders): full `UsageSnapshot`
   *    on `status === 'aborted'` turns — `{ input_tokens, output_tokens,
   *    cost_usd?, completed_actions[] }`. Shape documented in
   *    `UsageSnapshot` in `agent-runner.ts` and migration 040.
   *
   *  - **cc-router path** (nested `variant === "cc"`, `leader_id ===
   *    'cc_router'`, PR #3603 W4): cc-narrowed `{ cost_usd: number }`
   *    only — Art. 5(1)(c) data minimization. Persisted on `'complete'`
   *    turns when `CC_PERSIST_USAGE === "true"` (default off until PR-C
   *    Privacy Policy refresh ships); also attached to `'aborted'` rows
   *    when captured by `onResult` before the abort fired.
   *
   *  Optional in the type so existing fixtures don't churn. Readers
   *  should branch on `usage?.variant` (post-#3640 F6) rather than on
   *  field presence — see `renderAbortedAssistant` in `message-bubble.tsx`.
   */
  usage?: {
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
