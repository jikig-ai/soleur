import type { DomainLeaderId } from "@/server/domain-leaders";

// WebSocket message protocol
export type WSMessage =
  | { type: "chat"; content: string }
  | { type: "start_session"; leaderId: DomainLeaderId }
  | { type: "review_gate_response"; gateId: string; selection: string }
  | { type: "stream"; content: string; partial: boolean }
  | { type: "review_gate"; gateId: string; question: string; options: string[] }
  | { type: "session_started"; conversationId: string }
  | { type: "session_ended"; reason: string }
  | { type: "error"; message: string };

// Database types (matches Supabase schema)
export interface User {
  id: string;
  email: string;
  workspace_path: string;
  workspace_status: "provisioning" | "ready";
  created_at: string;
}

export interface ApiKey {
  id: string;
  user_id: string;
  encrypted_key: string;
  provider: "anthropic" | "bedrock" | "vertex";
  is_valid: boolean;
  validated_at: string | null;
}

export interface Conversation {
  id: string;
  user_id: string;
  domain_leader: DomainLeaderId;
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
  created_at: string;
}
