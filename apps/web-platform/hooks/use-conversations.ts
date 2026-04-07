"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Conversation, Message, ConversationStatus } from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";

export interface ConversationWithPreview extends Conversation {
  title: string;
  preview: string | null;
  lastMessageLeader: DomainLeaderId | null;
}

interface UseConversationsOptions {
  statusFilter?: ConversationStatus | null;
  domainFilter?: DomainLeaderId | "general" | null;
}

interface UseConversationsResult {
  conversations: ConversationWithPreview[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

function deriveTitle(messages: Message[], conversationId: string): string {
  const firstUserMsg = messages.find(
    (m) => m.conversation_id === conversationId && m.role === "user",
  );
  if (!firstUserMsg) return "Untitled conversation";
  const content = firstUserMsg.content.replace(/@\w+\s*/g, "").trim();
  return content.length > 60 ? `${content.slice(0, 57)}...` : content;
}

function derivePreview(messages: Message[], conversationId: string): { text: string | null; leader: DomainLeaderId | null } {
  const convMessages = messages.filter((m) => m.conversation_id === conversationId);
  const lastMsg = convMessages[convMessages.length - 1];
  if (!lastMsg) return { text: null, leader: null };
  const stripped = lastMsg.content.replace(/[#*`_~\[\]()]/g, "").trim();
  const text = stripped.length > 100 ? `${stripped.slice(0, 97)}...` : stripped;
  return { text, leader: lastMsg.leader_id };
}

export function useConversations(
  options: UseConversationsOptions = {},
): UseConversationsResult {
  const { statusFilter = null, domainFilter = null } = options;
  const [conversations, setConversations] = useState<ConversationWithPreview[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const userIdRef = useRef<string | null>(null);
  const channelRef = useRef<ReturnType<ReturnType<typeof createClient>["channel"]> | null>(null);

  const fetchConversations = useCallback(async () => {
    setLoading(true);
    setError(null);

    const supabase = createClient();

    // Get user ID for Realtime filter
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) {
      setError("Authentication required");
      setLoading(false);
      return;
    }
    userIdRef.current = authData.user.id;

    // Query 1: Fetch conversations
    let query = supabase
      .from("conversations")
      .select("*")
      .order("last_active", { ascending: false })
      .order("created_at", { ascending: false });

    if (statusFilter) {
      query = query.eq("status", statusFilter);
    }
    if (domainFilter === "general") {
      query = query.is("domain_leader", null);
    } else if (domainFilter) {
      query = query.eq("domain_leader", domainFilter);
    }

    const { data: convData, error: convError } = await query.limit(50);
    if (convError) {
      setError(convError.message);
      setLoading(false);
      return;
    }
    if (!convData || convData.length === 0) {
      setConversations([]);
      setLoading(false);
      return;
    }

    // Query 2: Fetch messages for displayed conversations
    const ids = convData.map((c: Conversation) => c.id);
    const { data: msgData, error: msgError } = await supabase
      .from("messages")
      .select("conversation_id, role, content, leader_id, created_at")
      .in("conversation_id", ids)
      .order("created_at", { ascending: true });

    if (msgError) {
      setError(msgError.message);
      setLoading(false);
      return;
    }

    const messages = (msgData ?? []) as Message[];

    // Derive titles and previews
    const enriched: ConversationWithPreview[] = convData.map((conv: Conversation) => {
      const { text, leader } = derivePreview(messages, conv.id);
      return {
        ...conv,
        title: deriveTitle(messages, conv.id),
        preview: text,
        lastMessageLeader: leader,
      };
    });

    setConversations(enriched);
    setLoading(false);
  }, [statusFilter, domainFilter]);

  // Initial fetch
  useEffect(() => {
    fetchConversations();
  }, [fetchConversations]);

  // Supabase Realtime subscription for status updates
  useEffect(() => {
    if (!userIdRef.current) return;

    const supabase = createClient();
    const channel = supabase
      .channel("command-center")
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "conversations",
          filter: `user_id=eq.${userIdRef.current}`,
        },
        (payload) => {
          const updated = payload.new as Conversation;
          setConversations((prev) =>
            prev.map((c) =>
              c.id === updated.id
                ? { ...c, status: updated.status, last_active: updated.last_active, domain_leader: updated.domain_leader }
                : c,
            ),
          );
        },
      )
      .subscribe();

    channelRef.current = channel;

    return () => {
      supabase.removeChannel(channel);
    };
  }, [conversations.length > 0 ? userIdRef.current : null]);

  return { conversations, loading, error, refetch: fetchConversations };
}
