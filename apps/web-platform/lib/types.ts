import type { DomainLeaderId } from "@/server/domain-leaders";

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
  | "interactive_prompt_rejected";

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
  | { type: "review_gate"; gateId: string; question: string; header?: string; options: string[]; descriptions?: Record<string, string | undefined>; stepProgress?: { current: number; total: number } }
  | { type: "session_started"; conversationId: string }
  | { type: "session_resumed"; conversationId: string; resumedFromTimestamp: string; messageCount: number }
  | { type: "session_ended"; reason: string }
  | { type: "usage_update"; conversationId: string; totalCostUsd: number; inputTokens: number; outputTokens: number }
  | { type: "fanout_truncated"; dispatched: number; dropped: number }
  | { type: "upgrade_pending" }
  // Stage 2 (#2853) — feature-local shape for the Command Center
  // soleur-go router. Stage 3 replaces these with branded IDs
  // (PromptId, ConversationId) + Zod parsing at the WS boundary. Until
  // then, payload is intentionally unstructured on the client side so
  // the router can ship the interactive-prompt bridge without a
  // breaking-change waterfall through chat-state-machine + ws-client.
  | {
      type: "interactive_prompt";
      promptId: string;
      conversationId: string;
      kind: "ask_user" | "plan_preview" | "diff" | "bash_approval" | "todo_write" | "notebook_edit";
      payload: unknown;
    }
  | {
      type: "interactive_prompt_response";
      promptId: string;
      conversationId: string;
      kind: "ask_user" | "plan_preview" | "diff" | "bash_approval" | "todo_write" | "notebook_edit";
      response: unknown;
    }
  | { type: "error"; message: string; errorCode?: WSErrorCode; gateId?: string };

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
