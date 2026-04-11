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
  | "too_many_files";

// Shared WebSocket close codes — single source of truth for server, client, and tests.
// See: https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/code (4000-4999 = application-reserved)
export const WS_CLOSE_CODES = {
  AUTH_TIMEOUT: 4001,
  SUPERSEDED: 4002,
  AUTH_REQUIRED: 4003,
  TC_NOT_ACCEPTED: 4004,
  INTERNAL_ERROR: 4005,
  RATE_LIMITED: 4008,
  IDLE_TIMEOUT: 4009,
  SERVER_GOING_AWAY: 1001,
} as const;

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

// WebSocket message protocol
export type WSMessage =
  | { type: "auth"; token: string }
  | { type: "auth_ok" }
  | { type: "chat"; content: string; attachments?: AttachmentRef[] }
  | { type: "start_session"; leaderId?: DomainLeaderId; context?: ConversationContext }
  | { type: "resume_session"; conversationId: string }
  | { type: "close_conversation" }
  | { type: "review_gate_response"; gateId: string; selection: string }
  | { type: "stream"; content: string; partial: boolean; leaderId: DomainLeaderId }
  | { type: "stream_start"; leaderId: DomainLeaderId; source?: "auto" | "mention" }
  | { type: "stream_end"; leaderId: DomainLeaderId }
  | { type: "review_gate"; gateId: string; question: string; header?: string; options: string[]; descriptions?: Record<string, string | undefined> }
  | { type: "session_started"; conversationId: string }
  | { type: "session_ended"; reason: string }
  | { type: "usage_update"; conversationId: string; totalCostUsd: number; inputTokens: number; outputTokens: number }
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
