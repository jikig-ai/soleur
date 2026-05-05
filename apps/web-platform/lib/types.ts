import type { DomainLeaderId } from "@/server/domain-leaders";
import type { WorkflowName } from "@/server/conversation-routing";
import type { InteractivePromptKind } from "@/server/pending-prompt-registry";
import type { SpawnId, PromptId, ConversationId } from "@/lib/branded-ids";

// Re-export so client code can import workflow-name and branded IDs from the
// canonical wire-protocol module without reaching into server/* directly.
export type { WorkflowName } from "@/server/conversation-routing";
export type { SpawnId, PromptId, ConversationId } from "@/lib/branded-ids";

/**
 * Terminal states a `/soleur:go` workflow run can end in (#2885 Stage 3).
 * The tuple is the single source of truth — both the TS union below and the
 * Zod schema in `lib/ws-zod-schemas.ts` derive from it.
 */
export const WORKFLOW_END_STATUSES = [
  "completed",
  "user_aborted",
  "cost_ceiling",
  "idle_timeout",
  "plugin_load_failure",
  "sandbox_denial",
  "runner_crash",
  "runner_runaway",
  "internal_error",
] as const;
export type WorkflowEndStatus = typeof WORKFLOW_END_STATUSES[number];

/**
 * `subagent_complete.status` allowed values. Tuple-as-source so the Zod
 * schema and TS union cannot drift.
 */
export const SUBAGENT_COMPLETE_STATUSES = ["success", "error", "timeout"] as const;
export type SubagentCompleteStatus = typeof SUBAGENT_COMPLETE_STATUSES[number];

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

// Typed error codes for structured error handling over WebSocket
export type WSErrorCode =
  | "key_invalid"
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
  | "image_paste_lost";

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

export type ClosePreamble = ConcurrencyCapHitPreamble | TierChangedPreamble;

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
  path: string;    // artifact path (e.g., "knowledge-base/product/roadmap.md")
  type: string;    // page type (e.g., "kb-viewer", "dashboard", "roadmap")
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
    }
  | { type: "stream_start"; leaderId: DomainLeaderId; source?: "auto" | "mention" }
  | { type: "stream_end"; leaderId: DomainLeaderId }
  | { type: "tool_use"; leaderId: DomainLeaderId; label: string }
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
    }
  | { type: "review_gate"; gateId: string; question: string; header?: string; options: string[]; descriptions?: Record<string, string | undefined>; stepProgress?: { current: number; total: number } }
  | { type: "session_started"; conversationId: string; capabilities?: { promptKinds: readonly string[] } }
  | { type: "session_resumed"; conversationId: string; resumedFromTimestamp: string; messageCount: number }
  | { type: "session_ended"; reason: string }
  | { type: "usage_update"; conversationId: string; totalCostUsd: number; inputTokens: number; outputTokens: number }
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
    };

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
  workspace_path: string;
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
}
