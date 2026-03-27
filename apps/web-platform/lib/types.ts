import type { DomainLeaderId } from "@/server/domain-leaders";

// Typed error codes for structured error handling over WebSocket
export type WSErrorCode = "key_invalid" | "session_expired" | "session_resumed";

export class KeyInvalidError extends Error {
  constructor() {
    super("No valid API key found. Please set up your key first.");
    this.name = "KeyInvalidError";
  }
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
  | { type: "chat"; content: string }
  | { type: "start_session"; leaderId?: DomainLeaderId; context?: ConversationContext }
  | { type: "resume_session"; conversationId: string }
  | { type: "close_conversation" }
  | { type: "review_gate_response"; gateId: string; selection: string }
  | { type: "stream"; content: string; partial: boolean; leaderId: DomainLeaderId }
  | { type: "stream_start"; leaderId: DomainLeaderId }
  | { type: "stream_end"; leaderId: DomainLeaderId }
  | { type: "review_gate"; gateId: string; question: string; options: string[] }
  | { type: "session_started"; conversationId: string }
  | { type: "session_ended"; reason: string }
  | { type: "error"; message: string; errorCode?: WSErrorCode };

// Database types (matches Supabase schema)
export interface User {
  id: string;
  email: string;
  workspace_path: string;
  workspace_status: "provisioning" | "ready";
  tc_accepted_at: string | null;
  created_at: string;
}

export interface ApiKey {
  id: string;
  user_id: string;
  encrypted_key: string;
  provider: "anthropic" | "bedrock" | "vertex";
  is_valid: boolean;
  validated_at: string | null;
  iv: string;
  auth_tag: string;
  updated_at: string;
  created_at: string;
}

export interface Conversation {
  id: string;
  user_id: string;
  domain_leader: DomainLeaderId | null;
  session_id: string | null;
  status: "active" | "waiting_for_user" | "completed" | "failed";
  last_active: string;
}

export interface Message {
  id: string;
  conversation_id: string;
  role: "user" | "assistant";
  content: string;
  tool_calls: unknown | null;
  leader_id: DomainLeaderId | null;
  created_at: string;
}
