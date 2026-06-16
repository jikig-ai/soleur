"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Conversation, Message, ConversationStatus } from "@/lib/types";
import { DOMAIN_LEADERS, type DomainLeaderId } from "@/server/domain-leaders";

export interface ConversationWithPreview extends Conversation {
  title: string;
  preview: string | null;
  lastMessageLeader: DomainLeaderId | null;
}

export type ArchiveFilter = "active" | "archived";

// Cross-instance signal: chat-surface dispatches this window event the moment a
// freshly-started conversation gets its real id; the rail's useConversations
// listens and refetches once. A shared constant (not a raw literal in two
// files) so a typo cannot silently break the wiring — mirrors the codebase's
// RAIL_EXPAND_EVENT / OPEN_UPGRADE_MODAL_EVENT convention.
export const CONVERSATION_CREATED_EVENT = "soleur:conversation-created";

interface UseConversationsOptions {
  statusFilter?: ConversationStatus | null;
  domainFilter?: DomainLeaderId | "general" | null;
  archiveFilter?: ArchiveFilter;
  limit?: number;
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

// The two realtime channels the rail subscribes to. The own channel filters
// server-side on `user_id`; the shared channel on `workspace_id` (realtime-js#97
// allows only one equality predicate per channel — the rest is enforced
// client-side here).
type RealtimeChannelKind = "own" | "shared";

// Single source of truth for "this conversation does NOT belong in the rail's
// current scope". Used by BOTH the INSERT and UPDATE handlers so the two cannot
// drift (architecture review P2). Covers all four drop conditions, and is
// scope-EQUIVALENT to the fetch query (which filters by repo_url AND
// workspace_id, lines below) so the realtime path cannot surface a row the
// refetch would not:
//   (a) repo_url mismatch (both channels)
//   (b) workspace_id mismatch (both channels). The own channel's WAL filter is
//       only user_id, so without this an owner with two workspaces on the SAME
//       repo would see workspace-B conversations INSERTed into the workspace-A
//       rail — repo_url alone cannot discriminate two same-repo workspaces
//       (see the fetch-query comment + server/conversations-tools.ts). When the
//       active workspaceId is not yet resolved (null), this drops INSERTs; the
//       SUBSCRIBED backfill recovers them once the binding resolves.
//   (c) visibility !== "workspace" on the shared channel
//   (d) archive-state mismatch vs the active archiveFilter
export function shouldDropForScope(
  conv: Conversation,
  opts: {
    repoUrl: string | null;
    workspaceId: string | null;
    channel: RealtimeChannelKind;
    archiveFilter: ArchiveFilter;
  },
): boolean {
  if ((conv.repo_url ?? null) !== opts.repoUrl) return true;
  if ((conv.workspace_id ?? null) !== opts.workspaceId) return true;
  if (opts.channel === "shared" && conv.visibility !== "workspace") return true;
  const isArchived = conv.archived_at !== null;
  const showingArchived = opts.archiveFilter === "archived";
  if (isArchived !== showingArchived) return true;
  return false;
}

// Single title-derivation path shared by the fetch enrichment AND the INSERT
// placeholder. The `system` domain leader maps to the literal "Project
// Analysis" (architecture review P2) — without this branch a live-created system
// conversation reads "Untitled conversation" until the next refetch.
export function deriveRailTitle(conv: Conversation, messages: Message[]): string {
  return conv.domain_leader === "system"
    ? "Project Analysis"
    : deriveTitle(messages, conv.id, conv.domain_leader);
}

export function useConversations(
  options: UseConversationsOptions = {},
): UseConversationsResult {
  const { statusFilter = null, domainFilter = null, archiveFilter = "active", limit = 50 } = options;
  const [conversations, setConversations] = useState<ConversationWithPreview[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [userId, setUserId] = useState<string | null>(null);
  const [repoUrl, setRepoUrl] = useState<string | null>(null);
  const [workspaceId, setWorkspaceId] = useState<string | null>(null);
  // Ref mirror of repoUrl so Realtime callbacks read the latest value
  // without forcing the subscription effect to re-subscribe on every
  // repo change (see review F1). The conversation realtime channels
  // (own + workspace-shared) read from this ref.
  const repoUrlRef = useRef<string | null>(null);
  useEffect(() => {
    repoUrlRef.current = repoUrl;
  }, [repoUrl]);

  // `background: true` runs a QUIET refetch — it skips the loading/error toggle
  // so a reconcile that already has last-known rows present cannot re-enter the
  // rail's `!loading`-gated empty/error branches and blank/flash the list. Used
  // by the unconditional scope-resolve backfill below. A genuine refetch FAILURE
  // still surfaces via setError on the error paths within.
  const fetchConversations = useCallback(async (opts: { background?: boolean } = {}) => {
    if (!opts.background) {
      setLoading(true);
      setError(null);
    }

    try {
      const supabase = createClient();

      // Get user ID for query filter and Realtime subscription
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError || !authData.user) {
        setError("Authentication required");
        setLoading(false);
        return null;
      }
      const currentUserId = authData.user.id;
      setUserId(currentUserId);

      // Scope the list to the user's CURRENT repo. The source of truth is
      // `workspaces.repo_url` resolved via the ACTIVE workspace, read through
      // GET /api/workspace/active-repo (ADR-044, #4543). NEVER read
      // `users.repo_url` here: that deprecated per-user column is empty for a
      // joined workspace member, so reading it filters out the member's active
      // conversations and shows the empty rail forever — the #4543
      // dual-ownership trap restated at the UI layer. The route also returns
      // the resolved (self-healed) `workspaceId`, so the realtime channel and
      // the list query agree on the same workspace. See plan
      // 2026-06-15-fix-conversations-rail-empty-repo-url-source-divergence and
      // hooks/use-active-repo.ts (the established consumer of this route).
      // Disconnected users (repoUrl null) see an empty list — old-repo
      // conversations stay attached to their repo_url and are hidden until the
      // user reconnects that exact URL (2026-04-22 repo-swap isolation plan).
      const res = await fetch("/api/workspace/active-repo");
      if (!res.ok) {
        // Transient route failure — surface an error rather than silently
        // flashing the empty state (which reads as "you have no conversations").
        setError("Failed to resolve the active repository");
        setLoading(false);
        return null;
      }
      const activeRepo = (await res.json()) as {
        workspaceId: string;
        repoUrl: string | null;
      };
      // repoUrl is already normalized server-side by the active-repo route.
      const currentRepoUrl = activeRepo.repoUrl ?? null;
      setWorkspaceId(activeRepo.workspaceId ?? null);
      setRepoUrl(currentRepoUrl);

      if (!currentRepoUrl) {
        setConversations([]);
        setLoading(false);
        return [];
      }

      // visibility-sweep: RLS policies conversations_owner_select +
      // conversations_shared_select (migration 075) return own +
      // workspace-shared conversations; no app-level user_id filter needed.
      //
      // Scope by BOTH repo_url AND the active workspace_id, matching the
      // server-side list tool (server/conversations-tools.ts). repo_url alone
      // cannot separate two of the OWNER'S OWN workspaces connected to the
      // SAME repo — both rows share repo_url, and RLS (075) returns the
      // owner's rows across all their workspaces. conversations.workspace_id
      // (NOT NULL, mig 059) is the precise discriminator, and it matches the
      // route's resolved workspaceId so the list query and the workspace-
      // shared realtime channel agree on the same workspace.
      let query = supabase
        .from("conversations")
        .select("*")
        .eq("repo_url", currentRepoUrl)
        .eq("workspace_id", activeRepo.workspaceId)
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

      const { data: convData, error: convError } = await query.limit(limit);
      if (convError) {
        setError(convError.message);
        setLoading(false);
        return null;
      }
      if (!convData || convData.length === 0) {
        setConversations([]);
        setLoading(false);
        return [];
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
        return null;
      }

      const messages = (msgData ?? []) as Message[];

      // Derive titles and previews
      const enriched: ConversationWithPreview[] = convData.map((conv: Conversation) => {
        const { text, leader } = derivePreview(messages, conv.id);
        const title = deriveRailTitle(conv, messages);
        return {
          ...conv,
          title,
          preview: text,
          lastMessageLeader: leader,
        };
      });

      setConversations(enriched);
      setLoading(false);
      return enriched;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load conversations");
      setLoading(false);
      return null;
    }
  }, [statusFilter, domainFilter, archiveFilter, limit]);

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

    const handleConversationUpdate = (
      payload: { new: unknown },
      channel: RealtimeChannelKind,
    ) => {
      const updated = payload.new as Conversation;
      // Out-of-scope (wrong repo / non-shared / archive-flip): remove the row
      // if it is currently shown, then stop. Same single guard the INSERT path
      // uses, so the two cannot drift (architecture review P2). Returning the
      // same array reference when the row is absent lets React bail the render.
      if (shouldDropForScope(updated, { repoUrl: repoUrlRef.current, workspaceId, channel, archiveFilter })) {
        setConversations((prev) =>
          prev.some((c) => c.id === updated.id) ? prev.filter((c) => c.id !== updated.id) : prev,
        );
        return;
      }

      setConversations((prev) =>
        prev.map((c) =>
          c.id === updated.id
            ? { ...c, status: updated.status, last_active: updated.last_active, domain_leader: updated.domain_leader, archived_at: updated.archived_at, visibility: updated.visibility }
            : c,
        ),
      );
    };

    // Realtime INSERT delivers only the `conversations` row (no messages), so we
    // synthesize a placeholder enriched row. The reducer is FILL-ONLY: if the id
    // is already present (at-least-once delivery, or the SUBSCRIBED backfill
    // landed an enriched row first) we keep the existing row rather than
    // downgrading its title/preview to the placeholder (architecture review P2).
    // No per-INSERT messages fetch — the backfill + subsequent UPDATEs refine it.
    const handleConversationInsert = (
      payload: { new: unknown },
      channel: RealtimeChannelKind,
    ) => {
      const created = payload.new as Conversation;
      if (shouldDropForScope(created, { repoUrl: repoUrlRef.current, workspaceId, channel, archiveFilter })) {
        // Out of the rail's current scope. An own-channel INSERT dropped ONLY
        // because workspaceId has not resolved yet (the fresh-mount connect
        // window, since the rail portals per-drill — ADR-047 — and workspaceId
        // is set inside the async fetchConversations) is recovered by the
        // UNCONDITIONAL scope-resolve backfill below, which refetches once on
        // the null→id transition regardless of whether a drop was recorded. So
        // there is nothing to arm and nothing to mirror here: "the row isn't in
        // scope yet" is normal connect-window latency, not a silent fallback. A
        // drop while scope is already resolved is a genuine cross-(repo|
        // workspace) row — correctly silent (the F3 isolation invariant).
        return;
      }

      setConversations((prev) => {
        if (prev.some((c) => c.id === created.id)) return prev; // fill-only de-dup
        const placeholder: ConversationWithPreview = {
          ...created,
          title: deriveRailTitle(created, []),
          preview: null,
          lastMessageLeader: null,
        };
        // New row is stamped last_active = now() → belongs at the head; truncate
        // to the hook's limit so a long session cannot grow the list unbounded.
        return [placeholder, ...prev].slice(0, limit);
      });
    };

    // Channel 1 (user_id): own conversations — always subscribed when
    // userId is available, regardless of workspace membership. Branch on event
    // (UPDATE + INSERT) on the SAME channel (fewer WS connections). The
    // SUBSCRIBED backfill below closes the reconnection/initial-load gap:
    // Realtime delivers INSERTs at-least-once and does NOT replay events
    // buffered during a disconnect, so we refetch once when the channel goes
    // live (bounded to the subscribe transition — fires once, not per render).
    const ownChannel = supabase
      .channel("command-center-own")
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "conversations", filter: `user_id=eq.${userId}` },
        (payload) => handleConversationUpdate(payload, "own"),
      )
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "conversations", filter: `user_id=eq.${userId}` },
        (payload) => handleConversationInsert(payload, "own"),
      )
      .subscribe((status) => {
        if (status === "SUBSCRIBED") fetchConversations();
      });

    // Channel 2 (workspace_id): workspace-shared updates + inserts — additive,
    // only when workspaceId is available. Private conversation metadata transits
    // the WebSocket (WAL filter is workspace_id, not visibility) but
    // shouldDropForScope({ channel: "shared" }) drops non-shared payloads. The
    // backfill lives only on the own channel (always present); fetchConversations
    // refetches own + shared rows together, so one backfill covers both.
    let sharedChannel: ReturnType<typeof supabase.channel> | null = null;
    if (workspaceId) {
      sharedChannel = supabase
        .channel("command-center-shared")
        .on(
          "postgres_changes",
          { event: "UPDATE", schema: "public", table: "conversations", filter: `workspace_id=eq.${workspaceId}` },
          (payload) => handleConversationUpdate(payload, "shared"),
        )
        .on(
          "postgres_changes",
          { event: "INSERT", schema: "public", table: "conversations", filter: `workspace_id=eq.${workspaceId}` },
          (payload) => handleConversationInsert(payload, "shared"),
        )
        .subscribe();
    }

    return () => {
      supabase.removeChannel(ownChannel);
      if (sharedChannel) supabase.removeChannel(sharedChannel);
    };
  }, [userId, workspaceId, archiveFilter, limit, fetchConversations]);

  // Unconditional scope-resolve backfill. The conversations rail portals
  // per-drill (ADR-047) and mounts fresh on entry to /dashboard/chat/*, so its
  // realtime own-channel can subscribe while `workspaceId` is still null (it is
  // set inside the async fetchConversations). An own-channel INSERT arriving in
  // that window is dropped by shouldDropForScope (workspace_id !== null), and a
  // pre-SUBSCRIBED-buffered INSERT is never delivered at all (supabase-js does
  // not replay them) — and the completion UPDATE is map-only and cannot add the
  // missing row, so the freshly-started conversation would surface only "after
  // it completes" (the reported bug). Refetch ONCE — UNCONDITIONALLY — when
  // workspaceId transitions null → id, regardless of whether a drop was
  // recorded: the freshly-created row is created lazily server-side on the first
  // WS message (ws-handler.ts), which can land before OR after this transition,
  // so keying recovery on "a drop was observed" missed the no-drop orderings
  // (the residual flakiness #5421 left). This is strictly simpler and MORE
  // deterministic than a timed retry — it does not race the user-paced first
  // message. The refetch is QUIET (background: true) so a reconcile with rows
  // present cannot blank/flash the rail. Transition-gated via a ref — fires once
  // per resolve, not per render — same shape as the canonical
  // use-kb-layout-state.tsx:232-240 idiom. (That idiom seeds the ref with the
  // CURRENT value; here we seed null because `workspaceId` always starts null —
  // its useState init above is null and it is only set inside the async
  // fetchConversations — so the null→id transition still fires exactly once and
  // no spurious mount transition is manufactured.)
  const prevWorkspaceIdRef = useRef<string | null>(null);
  useEffect(() => {
    if (prevWorkspaceIdRef.current === workspaceId) return; // no transition
    const prev = prevWorkspaceIdRef.current;
    prevWorkspaceIdRef.current = workspaceId;
    if (prev === null && workspaceId !== null) {
      fetchConversations({ background: true });
    }
  }, [workspaceId, fetchConversations]);

  // Deterministic new-conversation refresh (the realtime-miss recovery).
  // chat-surface.tsx emits `soleur:conversation-created` the moment the server
  // assigns a freshly-started conversation its real id. The rail's realtime
  // own-channel INSERT can MISS that create: when the user starts a new
  // conversation the rail re-subscribes during navigation, and the INSERT lands
  // in the pre-SUBSCRIBED window supabase-js never replays — while the rail's
  // mount-time backfills already ran before the row existed. So the row would
  // surface only after a reload (the reported bug; client-timing fixes
  // #5391/#5421/#5436 could not close a race they cannot observe).
  //
  // COMMIT-TIMING RACE (#5449 follow-up, found via a live headless-browser
  // repro): the event fires at `session_started` — but the conversation ROW is
  // created LAZILY on the first persisted message (ws-handler.ts), which lands
  // slightly AFTER `session_started`. A single refetch on the event therefore
  // runs before the row is committed and misses it. So we refetch with a SMALL
  // BOUNDED RETRY keyed on the event's concrete `conversationId`: refetch, and
  // if that id is not visible yet, retry on a short backoff until it appears or
  // the bound is hit. This is deterministic (gated on the actual id, never a
  // blind clock) and self-cancelling — if no row ever commits (e.g. the message
  // was never sent) the retries exhaust harmlessly (nothing to show is correct).
  // F3 isolation preserved (every refetch is the scoped list query). See
  // knowledge-base learning 2026-06-17 rail-realtime-race.
  useEffect(() => {
    if (typeof window === "undefined") return;
    const MAX_ATTEMPTS = 6;
    const BACKOFF_MS = [0, 600, 1000, 1500, 2500, 4000]; // ≈ cumulative 9.6s bound
    let cancelled = false;
    const onCreated = (ev: Event) => {
      const targetId =
        (ev as CustomEvent<{ conversationId?: string }>).detail?.conversationId ?? null;
      let attempt = 0;
      const run = async () => {
        if (cancelled) return;
        const rows = await fetchConversations({ background: true });
        attempt += 1;
        // Stop once the new conversation is visible (or there is no id to wait
        // for, or the bound is hit). `rows === null` is a transient fetch error
        // — keep retrying within the bound.
        const present = !targetId || (rows?.some((c) => c.id === targetId) ?? false);
        if (cancelled || present || attempt >= MAX_ATTEMPTS) return;
        setTimeout(run, BACKOFF_MS[attempt] ?? 4000);
      };
      void run();
    };
    window.addEventListener(CONVERSATION_CREATED_EVENT, onCreated);
    return () => {
      cancelled = true;
      window.removeEventListener(CONVERSATION_CREATED_EVENT, onCreated);
    };
  }, [fetchConversations]);

  // Note: there is no cross-tab `users` UPDATE channel. Repo scope now comes
  // from /api/workspace/active-repo (workspaces.repo_url), not users.repo_url,
  // so watching `users` rows would be dead. A workspace switch is a hard
  // navigation to /dashboard (the org-switcher remounts the page →
  // fetchConversations re-runs), which covers the dominant re-scope path.
  // Caveat: a same-session repo connect/disconnect that uses router.refresh()
  // (settings/project-setup-card, repo/reconnect-notice) re-renders server
  // components without remounting this client hook, so the rail can show stale
  // scope until the next mount/refetch. Acceptable: scope staleness is a
  // read-freshness gap, never a correctness/isolation break (RLS + the
  // repo_url/workspace_id filter still bound what is shown). Revisit if
  // operators report stale rails after in-session reconnect.

  const archiveConversation = useCallback(async (id: string) => {
    // Slot release on archive: handled by AFTER UPDATE OF archived_at
    // trigger in supabase/migrations/036_release_slot_on_archive.sql.
    // Do NOT add an explicit release_conversation_slot RPC call here —
    // it would double-release.
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
