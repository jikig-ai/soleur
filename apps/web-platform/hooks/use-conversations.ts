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

export type ArchiveFilter = "active" | "archived";

interface UseConversationsOptions {
  statusFilter?: ConversationStatus | null;
  domainFilter?: DomainLeaderId | "general" | null;
  archiveFilter?: ArchiveFilter;
}

interface UseConversationsResult {
  conversations: ConversationWithPreview[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
  archiveConversation: (id: string) => Promise<void>;
  unarchiveConversation: (id: string) => Promise<void>;
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
  const { statusFilter = null, domainFilter = null, archiveFilter = "active" } = options;
  const [conversations, setConversations] = useState<ConversationWithPreview[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [userId, setUserId] = useState<string | null>(null);
  const [repoUrl, setRepoUrl] = useState<string | null>(null);

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

      // Scope the list to the user's CURRENT repo_url. Disconnected users
      // (repo_url IS NULL) see an empty list — the old repo's conversations
      // stay attached to their repo_url and are hidden until the user
      // reconnects that exact URL. See plan
      // 2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md.
      const { data: userRow } = await supabase
        .from("users")
        .select("repo_url")
        .eq("id", currentUserId)
        .maybeSingle();
      const currentRepoUrl =
        (userRow?.repo_url as string | null | undefined) ?? null;
      setRepoUrl(currentRepoUrl);

      if (!currentRepoUrl) {
        setConversations([]);
        setLoading(false);
        return;
      }

      // Query 1: Fetch conversations (explicit user_id + repo_url filter)
      let query = supabase
        .from("conversations")
        .select("*")
        .eq("user_id", currentUserId)
        .eq("repo_url", currentRepoUrl)
        .order("last_active", { ascending: false })
        .order("created_at", { ascending: false });

      // Archive filter: default "active" excludes archived conversations
      if (archiveFilter === "active") {
        query = query.is("archived_at", null);
      } else if (archiveFilter === "archived") {
        query = query.not("archived_at", "is", null);
      }

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
  }, [statusFilter, domainFilter, archiveFilter]);

  // Initial fetch
  useEffect(() => {
    fetchConversations();
  }, [fetchConversations]);

  // Supabase Realtime subscription for status updates.
  // Uses userId state (not ref) so effect re-runs when auth completes.
  // Realtime `filter` accepts only ONE equality predicate per realtime-js#97 —
  // the `user_id` filter stays server-side; cross-repo payloads are dropped
  // client-side in the callback below (same pattern as `archived_at`).
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
          // Client-side repo_url check: Realtime can't express the second
          // equality, so drop payloads whose repo_url doesn't match the
          // current scope.
          if (repoUrl && updated.repo_url !== repoUrl) return;

          setConversations((prev) => {
            // Check if the conversation's archive state matches the current filter
            const isArchivedNow = updated.archived_at !== null;
            const showingArchived = archiveFilter === "archived";

            // If archive state doesn't match current view, remove from list
            if (isArchivedNow !== showingArchived) {
              return prev.filter((c) => c.id !== updated.id);
            }

            // Otherwise, update the conversation in place
            return prev.map((c) =>
              c.id === updated.id
                ? { ...c, status: updated.status, last_active: updated.last_active, domain_leader: updated.domain_leader, archived_at: updated.archived_at }
                : c,
            );
          });
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId, archiveFilter, repoUrl]);

  // Cross-tab disconnect/reconnect awareness (race R-C): another tab may
  // swap the user's repo_url while this hook is mounted. Subscribe to
  // users UPDATE events and refetch when repo_url changes — without this
  // the Command Center keeps showing the pre-swap scope until a hard reload.
  useEffect(() => {
    if (!userId) return;
    const supabase = createClient();
    const channel = supabase
      .channel("command-center-user")
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "users",
          filter: `id=eq.${userId}`,
        },
        (payload) => {
          const updated = payload.new as { repo_url?: string | null };
          const nextRepoUrl = updated?.repo_url ?? null;
          if (nextRepoUrl !== repoUrl) {
            fetchConversations();
          }
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId, repoUrl, fetchConversations]);

  const archiveConversation = useCallback(async (id: string) => {
    const supabase = createClient();
    const { error: updateError } = await supabase
      .from("conversations")
      .update({ archived_at: new Date().toISOString() })
      .eq("id", id);
    if (updateError) {
      setError(updateError.message);
      return;
    }
    setConversations((prev) => prev.filter((c) => c.id !== id));
  }, []);

  const unarchiveConversation = useCallback(async (id: string) => {
    const supabase = createClient();
    const { error: updateError } = await supabase
      .from("conversations")
      .update({ archived_at: null })
      .eq("id", id);
    if (updateError) {
      setError(updateError.message);
      return;
    }
    setConversations((prev) => prev.filter((c) => c.id !== id));
  }, []);

  const updateStatus = useCallback(
    async (conversationId: string, newStatus: ConversationStatus) => {
      const previousStatus = conversations.find((c) => c.id === conversationId)?.status;
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

  return { conversations, loading, error, refetch: fetchConversations, archiveConversation, unarchiveConversation, updateStatus };
}
