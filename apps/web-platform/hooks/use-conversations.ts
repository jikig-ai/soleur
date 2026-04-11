"use client";

import { useState, useEffect, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Conversation, Message, ConversationStatus } from "@/lib/types";
import { DOMAIN_LEADERS, type DomainLeaderId } from "@/server/domain-leaders";

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
  updateStatus: (conversationId: string, newStatus: ConversationStatus) => Promise<void>;
}

function truncate(s: string, max = 60): string {
  return s.length > max ? `${s.slice(0, max - 3)}...` : s;
}

export function deriveTitle(
  messages: Message[],
  conversationId: string,
  domainLeader?: DomainLeaderId | null,
): string {
  const convMessages = messages.filter((m) => m.conversation_id === conversationId);
  const firstUserMsg = convMessages.find((m) => m.role === "user");
  const firstAssistantMsg = convMessages.find((m) => m.role === "assistant");

  // 1. First user message content (strip @-mentions)
  if (firstUserMsg) {
    const stripped = firstUserMsg.content.replace(/@\w+\s*/g, "").trim();
    if (stripped) return truncate(stripped);
  }

  // 2. Assistant message (better title than raw @-mention)
  if (firstAssistantMsg) return truncate(firstAssistantMsg.content.trim());

  // 3. Raw @-mention text (user message exists but was only @-mentions)
  if (firstUserMsg) {
    const raw = firstUserMsg.content.trim();
    if (raw) return truncate(raw);
  }

  // 4. Domain leader label
  if (domainLeader) {
    const leader = DOMAIN_LEADERS.find((l) => l.id === domainLeader);
    if (leader) return `${leader.name} conversation`;
  }

  // 5. Fallback
  return "Untitled conversation";
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
  const [userId, setUserId] = useState<string | null>(null);

  const fetchConversations = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const supabase = createClient();

      // Get user ID for query filter and Realtime subscription
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError || !authData.user) {
        setError("Authentication required");
        setLoading(false);
        return;
      }
      const currentUserId = authData.user.id;
      setUserId(currentUserId);

      // Query 1: Fetch conversations (explicit user_id filter for defence-in-depth)
      let query = supabase
        .from("conversations")
        .select("*")
        .eq("user_id", currentUserId)
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
        const title = conv.domain_leader === "system"
          ? "Project Analysis"
          : deriveTitle(messages, conv.id, conv.domain_leader);
        return {
          ...conv,
          title,
          preview: text,
          lastMessageLeader: leader,
        };
      });

      setConversations(enriched);
      setLoading(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load conversations");
      setLoading(false);
    }
  }, [statusFilter, domainFilter]);

  // Initial fetch
  useEffect(() => {
    fetchConversations();
  }, [fetchConversations]);

  // Supabase Realtime subscription for status updates
  // Uses userId state (not ref) so effect re-runs when auth completes
  useEffect(() => {
    if (!userId) return;

    const supabase = createClient();
    const channel = supabase
      .channel("command-center")
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "conversations",
          filter: `user_id=eq.${userId}`,
        },
        (payload) => {
          const updated = payload.new as Conversation;
          // Client-side user_id check: Free tier ignores server-side filter
          if (updated.user_id !== userId) return;
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

    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId]);

  const updateStatus = useCallback(
    async (conversationId: string, newStatus: ConversationStatus) => {
      // Capture only the previous status for targeted rollback (avoids stale closure)
      const previousStatus = conversations.find((c) => c.id === conversationId)?.status;
      // Optimistic update
      setConversations((prev) =>
        prev.map((c) => (c.id === conversationId ? { ...c, status: newStatus } : c)),
      );

      const supabase = createClient();
      const { error: updateError } = await supabase
        .from("conversations")
        .update({ status: newStatus })
        .eq("id", conversationId)
        .eq("user_id", userId!);

      if (updateError) {
        setConversations((prev) =>
          prev.map((c) => (c.id === conversationId ? { ...c, status: previousStatus! } : c)),
        );
        setError("Failed to update conversation status");
      }
    },
    [conversations, userId],
  );

  return { conversations, loading, error, refetch: fetchConversations, updateStatus };
}
