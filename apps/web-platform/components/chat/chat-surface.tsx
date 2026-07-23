"use client";

import React, { useState, useRef, useEffect, useCallback, useMemo } from "react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { useWebSocket } from "@/lib/ws-client";
import type { ConversationContext, AttachmentRef } from "@/lib/types";
import { ErrorCard } from "@/components/ui/error-card";
import { DelegationErrorCard, isDelegationError } from "@/components/chat/delegation-error-card";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { ChatInput } from "@/components/chat/chat-input";
import { AtMentionDropdown } from "@/components/chat/at-mention-dropdown";
import { useTeamNames } from "@/hooks/use-team-names";
import { useActiveRepo } from "@/hooks/use-active-repo";
import { CONVERSATION_CREATED_EVENT } from "@/hooks/use-conversations";
import { NotificationPrompt } from "@/components/chat/notification-prompt";
import { getPendingFiles, clearPendingFiles } from "@/lib/pending-attachments";
import { uploadPendingFiles } from "@/lib/upload-attachments";
import * as Sentry from "@sentry/nextjs";
import { MessageBubble } from "@/components/chat/message-bubble";
import { ReviewGateCard } from "@/components/chat/review-gate-card";
import { StatusIndicator } from "@/components/chat/status-indicator";
import { AutoRunChip } from "@/components/chat/auto-run-chip";
import { AutonomousDisclosureBanner } from "@/components/chat/autonomous-disclosure-banner";
import { SubagentGroup } from "@/components/chat/subagent-group";
import { InteractivePromptCard } from "@/components/chat/interactive-prompt-card";
import { WorkflowLifecycleBar } from "@/components/chat/workflow-lifecycle-bar";
import { ToolUseChip } from "@/components/chat/tool-use-chip";
import { RoutedLeadersStrip } from "@/components/chat/routed-leaders-strip";
import { CohortMissingReplyMarker } from "@/components/chat/cohort-missing-reply-marker";
import { DebugStreamPanel } from "@/components/chat/debug-stream-panel";
import { TurnSummaryBubble } from "@/components/chat/turn-summary-bubble";
import { useOptionalFeatureFlag } from "@/components/feature-flags/provider";
import { CC_ROUTER_LEADER_ID } from "@/lib/cc-router-id";
import type {
  InteractivePromptResponsePayload,
  InteractivePromptPayload,
} from "@/lib/types";
import type {
  ChatInteractivePromptMessage,
  ChatDebugEventMessage,
} from "@/lib/chat-state-machine";
import { deriveReconnectView } from "@/lib/chat-state-machine";
import { CONTEXT_RESET_COPY } from "@/components/chat/chat-copy";

export type ChatSurfaceVariant = "full" | "sidebar";

/** #5282 — auto-dismiss window for the transient State-4 "workspace restored"
 *  notice. State 4 is a derived render affordance, not a reducer phase. */
const RESUMED_NOTICE_MS = 4000;

/**
 * Stage 4 review F6: typed render helper for `<InteractivePromptCard>`.
 * Replaces the prior `payload={msg.promptPayload as any}` /
 * `selectedResponse={msg.selectedResponse as any}` casts at the call site
 * with a per-kind switch that narrows the discriminated `{kind, payload}`
 * couple at the boundary. Each branch passes congruent shapes — TS now
 * tracks the union end-to-end.
 */
function renderInteractivePromptCard(
  msg: ChatInteractivePromptMessage,
  onRespond: (response: InteractivePromptResponsePayload) => void,
): React.ReactNode {
  switch (msg.promptKind) {
    case "ask_user":
      return (
        <InteractivePromptCard
          promptId={msg.promptId}
          conversationId={msg.conversationId}
          kind="ask_user"
          payload={msg.promptPayload as Extract<InteractivePromptPayload, { kind: "ask_user" }>["payload"]}
          resolved={msg.resolved}
          selectedResponse={msg.selectedResponse}
          onRespond={onRespond}
        />
      );
    case "plan_preview":
      return (
        <InteractivePromptCard
          promptId={msg.promptId}
          conversationId={msg.conversationId}
          kind="plan_preview"
          payload={msg.promptPayload as Extract<InteractivePromptPayload, { kind: "plan_preview" }>["payload"]}
          resolved={msg.resolved}
          selectedResponse={msg.selectedResponse}
          onRespond={onRespond}
        />
      );
    case "diff":
      return (
        <InteractivePromptCard
          promptId={msg.promptId}
          conversationId={msg.conversationId}
          kind="diff"
          payload={msg.promptPayload as Extract<InteractivePromptPayload, { kind: "diff" }>["payload"]}
          resolved={msg.resolved}
          selectedResponse={msg.selectedResponse}
          onRespond={onRespond}
        />
      );
    case "bash_approval":
      return (
        <InteractivePromptCard
          promptId={msg.promptId}
          conversationId={msg.conversationId}
          kind="bash_approval"
          payload={msg.promptPayload as Extract<InteractivePromptPayload, { kind: "bash_approval" }>["payload"]}
          resolved={msg.resolved}
          selectedResponse={msg.selectedResponse}
          onRespond={onRespond}
        />
      );
    case "todo_write":
      return (
        <InteractivePromptCard
          promptId={msg.promptId}
          conversationId={msg.conversationId}
          kind="todo_write"
          payload={msg.promptPayload as Extract<InteractivePromptPayload, { kind: "todo_write" }>["payload"]}
          resolved={msg.resolved}
          selectedResponse={msg.selectedResponse}
          onRespond={onRespond}
        />
      );
    case "notebook_edit":
      return (
        <InteractivePromptCard
          promptId={msg.promptId}
          conversationId={msg.conversationId}
          kind="notebook_edit"
          payload={msg.promptPayload as Extract<InteractivePromptPayload, { kind: "notebook_edit" }>["payload"]}
          resolved={msg.resolved}
          selectedResponse={msg.selectedResponse}
          onRespond={onRespond}
        />
      );
    default: {
      const _exhaustive: never = msg.promptKind;
      void _exhaustive;
      return null;
    }
  }
}

/**
 * Props only used by the sidebar variant. Grouping them behind
 * `sidebarProps?` keeps the full-variant call site (`<ChatSurface variant="full" />`)
 * from autocompleting 7 irrelevant options.
 */
export interface ChatSurfaceSidebarProps {
  /**
   * When set AND conversationId === "new", the sidebar starts a session
   * that looks up an existing (user_id, context_path) row and resumes it
   * instead of creating a fresh pending conversation.
   */
  resumeByContextPath?: string;
  onThreadResumed?: (conversationId: string, timestamp: string, messageCount: number) => void;
  onRealConversationId?: (conversationId: string) => void;
  onMessageCountChange?: (count: number) => void;
  /** Callback ref that invokes insertQuote for the KB selection-toolbar flow. */
  quoteRef?: React.MutableRefObject<((text: string) => void) | null>;
  /** Callback ref that focuses the textarea imperatively. */
  focusRef?: React.MutableRefObject<(() => void) | null>;
  /** Fires before sendMessage so sidebar callers can emit analytics (e.g.
   *  kb.chat.selection_sent when the content starts with a blockquote). */
  onBeforeSend?: (message: string) => void;
  /** Override the default placeholder — used by KB sidebar to surface ⌘⇧L. */
  placeholder?: string;
  /** Per-session storage key for the ChatInput draft (see AC5). */
  draftKey?: string;
}

export interface ChatSurfaceProps {
  conversationId: string;
  variant: ChatSurfaceVariant;
  onClose?: () => void;
  initialContext?: ConversationContext;
  /**
   * When true, defer the WS session start until the caller's async
   * `initialContext` resolves (audit M1). Lets the full-route page render the
   * chat shell immediately instead of returning null, while still delivering
   * the resolved KB context to `startSession` in one bootstrap. Defaults false
   * (no deferral) for every other call site.
   */
  contextPending?: boolean;
  /** Sidebar-only props. Ignored (shallow) when variant === "full". */
  sidebarProps?: ChatSurfaceSidebarProps;
}

export function ChatSurface({
  conversationId,
  variant,
  initialContext,
  contextPending = false,
  sidebarProps,
}: ChatSurfaceProps) {
  const {
    resumeByContextPath,
    onThreadResumed,
    onRealConversationId,
    onMessageCountChange,
    quoteRef,
    focusRef,
    onBeforeSend,
    placeholder,
    draftKey,
  } = sidebarProps ?? {};
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const leaderId = searchParams.get("leader") as DomainLeaderId | null;
  const msgParam = searchParams.get("msg");

  const {
    messages,
    startSession,
    resumeSession,
    sendMessage,
    sendReviewGateResponse,
    sendAutonomousDisclosureResponse,
    sendInteractivePromptResponse,
    resolveInteractivePrompt,
    status,
    sessionConfirmed,
    disconnectReason,
    lastError,
    reconnect,
    routeSource,
    activeLeaderIds,
    usageData,
    autonomousPosture: serverAutonomousPosture,
    realConversationId,
    resumedFrom,
    workflow,
    workflowEndedAt,
    conversationCreatedAt,
    historyLoading,
    streamState,
    liveNarration,
    abort,
    connection,
    resumeAfterUnrecoverable,
  } = useWebSocket(conversationId);

  const { names: customNames, getDisplayName, getIconPath, loading: teamNamesLoading } = useTeamNames();

  // #5282 — reconnect state machine. `hasRetryingBubble` drives State 2 (the
  // per-message "No response yet" watchdog chip); `deriveReconnectView` gives
  // connection state precedence over it so State 1 and State 2 never co-render
  // (AC12). State 3 (`unrecoverable`) and the State-4 notice are separate
  // branches keyed directly on `connection`.
  const hasRetryingBubble = useMemo(
    () => messages.some((m) => m.retrying === true),
    [messages],
  );
  const reconnectView = deriveReconnectView({
    phase: connection.phase,
    hasRetryingBubble,
  });

  // #5282 State 4 — the derived "Continuing… · workspace restored" notice is
  // transient: shown briefly after a successful reconnect-reattach, then
  // auto-dismissed. Never shown under sticky `unrecoverable` (State 3 takes
  // precedence — enforces "no 3→4 flip" at the render layer).
  const [showResumedNotice, setShowResumedNotice] = useState(false);
  useEffect(() => {
    if (connection.phase === "unrecoverable" || connection.resumedAt === undefined) {
      setShowResumedNotice(false);
      return;
    }
    setShowResumedNotice(true);
    const t = setTimeout(() => setShowResumedNotice(false), RESUMED_NOTICE_MS);
    return () => clearTimeout(t);
  }, [connection.resumedAt, connection.phase]);

  const [sessionStarted, setSessionStarted] = useState(false);
  const [initialMsgSent, setInitialMsgSent] = useState(false);
  const [sessionStartTimeout, setSessionStartTimeout] = useState(false);
  const [dismissedErrorKey, setDismissedErrorKey] = useState<string | null>(null);
  const [sessionTimeoutDismissed, setSessionTimeoutDismissed] = useState(false);
  const prevSessionTimeoutRef = useRef(false);

  const activeErrorKey = useMemo(
    () => (lastError ? `${lastError.code}::${lastError.message}` : null),
    [lastError],
  );

  // Edge-triggered: re-show the timeout card when sessionStartTimeout flips false -> true.
  useEffect(() => {
    if (!prevSessionTimeoutRef.current && sessionStartTimeout) {
      setSessionTimeoutDismissed(false);
    }
    prevSessionTimeoutRef.current = sessionStartTimeout;
  }, [sessionStartTimeout]);

  // Reset dismissedErrorKey whenever lastError clears so an identical re-fire
  // (same code+message after a reconnect that nulled lastError) is shown again.
  useEffect(() => {
    if (!lastError) {
      setDismissedErrorKey(null);
    }
  }, [lastError]);
  const [atQuery, setAtQuery] = useState("");
  const [atVisible, setAtVisible] = useState(false);
  const [atPosition, setAtPosition] = useState(0);
  const [showNotificationPrompt, setShowNotificationPrompt] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const insertRef = useRef<((text: string, replaceFrom: number) => void) | null>(null);

  // ── Near-bottom scroll guard + Jump-to-latest ──────────────────────────────
  // Auto-scroll only follows the stream when the user is already near the
  // bottom; scrolling up to read history must not be yanked back down. The gate
  // is a LIVE ref (not a state snapshot) so a fast token stream reads the
  // user's latest intent, not the value captured at effect-creation time.
  const messagesScrollRef = useRef<HTMLDivElement>(null);
  const nearBottomRef = useRef(true);
  const programmaticScrollRef = useRef(false);
  const [showJumpButton, setShowJumpButton] = useState(false);
  // iOS Safari overlays the on-screen keyboard without reflowing dvh
  // (interactiveWidget is Chromium-only), so lift the composer by the covered
  // height. Stays 0 on Android/desktop where the layout already reflows.
  const [keyboardInset, setKeyboardInset] = useState(0);

  const NEAR_BOTTOM_PX = 80;
  const recomputeNearBottom = useCallback(() => {
    // Skip while our own auto-scroll is in flight — its intermediate onScroll
    // events would otherwise flash the pill / flip the gate.
    if (programmaticScrollRef.current) return;
    const el = messagesScrollRef.current;
    if (!el) return;
    const distance = el.scrollHeight - el.scrollTop - el.clientHeight;
    // A non-scrollable container (empty state, short/resumed history) fires no
    // onScroll before first paint — treat it as near-bottom so auto-scroll runs
    // and the pill stays hidden.
    const scrollable = el.scrollHeight - el.clientHeight > NEAR_BOTTOM_PX;
    const near = !scrollable || distance <= NEAR_BOTTOM_PX;
    nearBottomRef.current = near;
    setShowJumpButton(!near);
  }, []);

  const scrollToLatest = useCallback((behavior: ScrollBehavior) => {
    programmaticScrollRef.current = true;
    messagesEndRef.current?.scrollIntoView({ behavior });
    requestAnimationFrame(() => {
      programmaticScrollRef.current = false;
    });
  }, []);

  const handleJumpToLatest = useCallback(() => {
    // Set the ref synchronously (not just setState) so a still-streaming turn
    // resumes following immediately, before the next render commits.
    nearBottomRef.current = true;
    setShowJumpButton(false);
    scrollToLatest("auto");
  }, [scrollToLatest]);

  const handleReviewGateResponse = useCallback(
    (gateId: string, selection: string) => {
      sendReviewGateResponse(gateId, selection);
      setShowNotificationPrompt(true);
    },
    [sendReviewGateResponse],
  );

  const handleAutonomousDisclosureResponse = useCallback(
    (gateId: string, selection: string) => {
      sendAutonomousDisclosureResponse(gateId, selection);
    },
    [sendAutonomousDisclosureResponse],
  );

  // feat-bash-autonomous-default-on — persistent posture chip. The autonomous
  // posture is the SERVER-resolved truth pushed over the `autonomous_posture`
  // frame (`bashAutonomous && acked`), NOT a message-presence heuristic. A held
  // (un-acked) `autonomous_disclosure` is "Approve each", not "Auto-run on", and
  // `command_stream` / commandBlocks can appear in non-autonomous safe-bash
  // flows — so message presence cannot decide posture. `null` (pre-push) is
  // treated as "Approve each" (the safe, non-autonomous default).
  const autonomousPosture = serverAutonomousPosture ?? false;

  const handleInteractivePromptResponse = useCallback(
    (
      promptId: string,
      conversationIdArg: string,
      response: InteractivePromptResponsePayload,
    ) => {
      // Send the wire frame.
      sendInteractivePromptResponse({
        type: "interactive_prompt_response",
        promptId,
        conversationId: conversationIdArg,
        ...response,
      });
      // Optimistically mark the local card as resolved.
      resolveInteractivePrompt(promptId, conversationIdArg, response.response);
    },
    [sendInteractivePromptResponse, resolveInteractivePrompt],
  );

  useEffect(() => {
    // Only follow the stream to the bottom when the user is already there.
    // Always "auto" (never "smooth"): per-token smooth-scroll is the jank
    // source, and its intermediate positions flash the Jump-to-latest pill.
    if (!nearBottomRef.current) return;
    scrollToLatest("auto");
  }, [messages, scrollToLatest]);

  // Recompute the near-bottom gate on viewport changes that emit no onScroll:
  // the iOS keyboard opening (visualViewport shrinks) and any container resize.
  // The same visualViewport subscription drives the composer keyboard-lift.
  useEffect(() => {
    const vv = typeof window !== "undefined" ? window.visualViewport : null;
    const isCoarse =
      typeof window !== "undefined" &&
      (window.matchMedia?.("(pointer: coarse)").matches ?? false);

    const onViewportChange = () => {
      if (vv && isCoarse) {
        // Height the keyboard covers = layout viewport − visual viewport − any
        // upward offset. 0 on platforms that already reflow (Android/desktop).
        // Rounded so React's Object.is bail collapses the redundant sub-pixel
        // renders the iOS keyboard show/hide animation would otherwise emit.
        const covered = Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop));
        setKeyboardInset(covered);
      }
      recomputeNearBottom();
    };

    vv?.addEventListener("resize", onViewportChange);
    vv?.addEventListener("scroll", onViewportChange);

    let ro: ResizeObserver | undefined;
    const el = messagesScrollRef.current;
    if (el && typeof ResizeObserver !== "undefined") {
      ro = new ResizeObserver(() => recomputeNearBottom());
      ro.observe(el);
    }

    return () => {
      vv?.removeEventListener("resize", onViewportChange);
      vv?.removeEventListener("scroll", onViewportChange);
      ro?.disconnect();
    };
  }, [recomputeNearBottom]);

  useEffect(() => {
    if (status !== "connected" || sessionStarted || contextPending) return;

    if (conversationId === "new") {
      if (resumeByContextPath) {
        startSession({
          leaderId: leaderId ?? undefined,
          context: initialContext,
          resumeByContextPath,
        });
      } else {
        startSession(leaderId ?? undefined, initialContext);
      }
      setSessionStarted(true);
    } else {
      resumeSession(conversationId);
      setSessionStarted(true);
    }
  }, [status, conversationId, leaderId, sessionStarted, startSession, resumeSession, initialContext, resumeByContextPath, contextPending]);

  useEffect(() => {
    if (resumedFrom && onThreadResumed) {
      onThreadResumed(resumedFrom.conversationId, resumedFrom.timestamp, resumedFrom.messageCount);
    }
  }, [resumedFrom, onThreadResumed]);

  useEffect(() => {
    if (realConversationId && onRealConversationId) {
      onRealConversationId(realConversationId);
    }
    // Deterministic rail-refresh signal for a FRESHLY-started conversation
    // (conversationId === "new"): the server has just created the row and
    // assigned this real id. The Recent Conversations rail is a SEPARATE
    // `useConversations` instance whose realtime own-channel INSERT can miss the
    // create — it lands in the rail's navigation/re-subscribe window, which
    // supabase-js does not replay, and the rail's mount-time backfills already
    // ran before the row existed. So the new conversation surfaces only after a
    // reload (the reported bug; #5391/#5421/#5436 tuned the realtime timing but
    // could not close a race they cannot observe). Emit a window event the rail
    // listens for and refetches once — deterministic, independent of realtime.
    // See knowledge-base learning 2026-06-17 rail-realtime-race.
    if (
      realConversationId &&
      conversationId === "new" &&
      typeof window !== "undefined"
    ) {
      window.dispatchEvent(
        new CustomEvent(CONVERSATION_CREATED_EVENT, {
          // `detail.conversationId` is LOAD-BEARING: the rail listener keys its
          // bounded retry's stop-condition on it (refetch until this id appears,
          // since the row commits lazily after this event). Do not remove it.
          detail: { conversationId: realConversationId },
        }),
      );
    }
  }, [realConversationId, onRealConversationId, conversationId]);

  useEffect(() => {
    // Skip the zero-write while a hydration is genuinely pending — either the
    // history fetch is still in flight, or the server has resolved a prior
    // thread (`resumedFrom`) but its history hasn't arrived yet. Both cases
    // would otherwise clobber the prefetched messageCount that `useKbLayoutState`
    // seeded for the trigger label. A fresh `session_started` (no resume) does
    // NOT need the guard — `messages.length === 0` for a brand-new conversation
    // is the correct count, not stale.
    if (messages.length === 0 && (historyLoading || resumedFrom)) return;
    onMessageCountChange?.(messages.length);
  }, [messages.length, onMessageCountChange, historyLoading, resumedFrom]);

  useEffect(() => {
    if (status === "reconnecting") {
      setSessionStarted(false);
    }
  }, [status]);

  // #3448 PR2 — Esc keyboard shortcut with focus guard.
  //
  // Mounts a `document`-level keydown listener only while a turn is in
  // flight (`streaming`) or already aborting (`stopping`, so a quick second
  // Esc is harmlessly ignored by `abort()`'s own no-op-while-stopping
  // guard rather than racing the Stop button into a stale state).
  //
  // Esc-while-typing guard (plan §"Plan-time additions from SpecFlow"):
  // when the user is mid-sentence in the chat textarea, Esc must NOT
  // abort — the textarea's native Esc handling (clear autocomplete, blur)
  // is the more frequent intent. We treat "focused on a textarea with
  // content" as the suppressing condition; an empty textarea, an unfocused
  // textarea, or focus on any other element falls through to abort.
  //
  // Per AGENTS.md `cq-ref-removal-sweep-cleanup-closures`, the effect's
  // cleanup MUST return removeEventListener — orphaned listeners survive
  // unmount and would re-fire abort on a freshly-mounted bubble's first
  // Esc. The test `task 5.7` is the regression gate for this.
  useEffect(() => {
    if (streamState !== "streaming" && streamState !== "stopping") return;
    const handler = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      const target = document.activeElement;
      // Review fix (security): the original guard only suppressed Esc on
      // a non-empty <textarea>. That left native UA Esc semantics (close
      // autocomplete, clear, blur, dismiss dialog) shadowed for:
      //   - <input type="text"> and friends (KB filename input, search box,
      //     dialog text inputs),
      //   - any [contenteditable] element (rich-text widgets),
      //   - elements inside an open Radix/Headless `[role="dialog"]`
      //     where Esc is the established close gesture.
      // For all three, Esc-mid-stream now defers to the local handler:
      // user closes the dialog / clears the input WITHOUT also burning
      // their billable turn. Stop via the on-screen button still works.
      if (target instanceof HTMLElement) {
        if (target.closest('[role="dialog"]')) return;
        if (target.isContentEditable) return;
        const hasContent =
          (target instanceof HTMLInputElement &&
            target.type !== "checkbox" &&
            target.type !== "radio" &&
            target.value.length > 0) ||
          (target instanceof HTMLTextAreaElement && target.value.length > 0);
        if (hasContent) return;
      }
      e.preventDefault();
      abort();
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [streamState, abort]);

  useEffect(() => {
    if (sessionConfirmed && msgParam && !initialMsgSent) {
      sendMessage(msgParam);
      setInitialMsgSent(true);
      router.replace(pathname, { scroll: false });
    }
  }, [sessionConfirmed, msgParam, initialMsgSent, sendMessage, router, pathname]);

  const [pendingFilesHandled, setPendingFilesHandled] = useState(false);
  useEffect(() => {
    if (!initialMsgSent || pendingFilesHandled || !realConversationId) return;

    const files = getPendingFiles();
    if (files.length === 0) {
      clearPendingFiles();
      setPendingFilesHandled(true);
      return;
    }

    setPendingFilesHandled(true);
    clearPendingFiles();

    (async () => {
      try {
        const uploaded = await uploadPendingFiles(files, realConversationId);
        if (uploaded.length > 0) {
          sendMessage("", uploaded);
        }
      } catch (err) {
        // Defense-in-depth: uploadPendingFiles already catches per-file
        // failures internally. This outer catch only fires on a batch-level
        // failure (e.g., sendMessage throws). Re-wrap so Sentry does not
        // ingest any signed-URL tokens embedded in XHR error messages.
        const original = err instanceof Error ? err.message : String(err);
        const sanitized = new Error(
          `[kb-chat] pending-files batch failed (original message length ${original.length})`,
        );
        console.warn("[kb-chat] pending upload failed (batch)", { err: sanitized });
        Sentry.captureException(sanitized);
      }
    })();
  }, [initialMsgSent, pendingFilesHandled, realConversationId, sendMessage]);

  useEffect(() => {
    if (!sessionStarted || sessionConfirmed) return;

    const timer = setTimeout(() => {
      setSessionStartTimeout(true);
    }, 10_000);

    return () => clearTimeout(timer);
  }, [sessionStarted, sessionConfirmed]);

  const respondingLeaders = messages
    .filter((m) => m.role === "assistant" && m.leaderId)
    .reduce<DomainLeaderId[]>((acc, m) => {
      if (m.leaderId && !acc.includes(m.leaderId)) acc.push(m.leaderId);
      return acc;
    }, []);

  const hasUserMessage = messages.some((m) => m.role === "user");
  const hasAssistantMessage = messages.some((m) => m.role === "assistant");

  // feat-one-shot-concierge-web-duplicate-question-box — the agent is PARKED
  // (awaiting the operator, NOT working) while an unresolved `review_gate` or
  // `autonomous_disclosure` is on screen. These are the exact two surfaces
  // whose `canUseTool` site (permission-callback.ts) sets the server
  // conversation status to `waiting_for_user`, which cc-dispatcher.ts then
  // observes to pause the runaway wall-clock (cc-dispatcher.ts:2530).
  // Both keep `streamState === "streaming"` (they are not turn-active events),
  // so the live-narration slot below would otherwise show a contradictory
  // "Still working…" spinner while the operator is being asked to decide. The
  // amber prompt card already conveys the waiting state, so suppressing the
  // spinner is sufficient.
  //
  // Deliberately NOT `interactive_prompt`: after the AskUserQuestion de-dup,
  // the still-emitted interactive_prompt kinds (diff / todo_write /
  // notebook_edit / plan_preview) are AUTO-ALLOWED in `canUseTool` — the agent
  // keeps streaming while they render as informational "ack" cards. Gating on
  // them would dark real narration for the rest of a genuinely-working turn.
  //
  // Turn-scoped (`i > lastUserIdx`): an unresolved gate is durable in
  // `messages` (nothing prunes it — `stream_end` prunes only `tool_use_chip`),
  // so a gate abandoned by a prior turn (timeout / abort / the operator
  // ignored it and sent a new message) would otherwise dark the narration on
  // every later streaming turn. Only a gate AFTER the last user message counts.
  const lastUserIdx = messages.map((m) => m.role).lastIndexOf("user");
  const awaitingUserInput = messages.some(
    (m, i) =>
      i > lastUserIdx &&
      (m.type === "review_gate" || m.type === "autonomous_disclosure") &&
      !m.resolved,
  );

  // feat-debug-mode-stream — the separate debug drawer. Visibility is the
  // dev-cohort `debug-mode` flag; the panel filters debug_event frames out of
  // the main message flow (they render null inline). `connected` drives the
  // disconnected affordance; `hadCompletedTurn` sharpens the empty-vs-
  // unavailable hint. Emission is server-gated independently — this only
  // renders frames that already arrived over the ephemeral WS.
  // Non-throwing: a provider-less render surface (older test harnesses, any
  // future provider-less mount) reads "no flag info" as OFF — fail-closed, the
  // panel hides. Mirrors how other provider-optional chat components degrade.
  const debugAvailable = useOptionalFeatureFlag("debug-mode");
  const debugEvents = useMemo(
    () =>
      messages.filter(
        (m): m is ChatDebugEventMessage => m.type === "debug_event",
      ),
    [messages],
  );
  // Review F10: gate the legacy `isClassifying` chip on the lifecycle bar
  // being idle — once the bar takes over routing/active/ended, the legacy
  // chip must not double-render with the bar.
  // Defense-in-depth: never render the routing chip while the history fetch
  // is in flight (`historyLoading`) or after a confirmed resume of a prior
  // thread (`resumedFrom`). Either signal proves the user-only message
  // snapshot does not represent an unanswered question — the assistant row is
  // still in transit, or it was never persisted (legacy cc-path conversations
  // pre-#3286). Without this gate, "Continue thread" would re-render the chip
  // on every resumed thread that already has an answer.
  const isClassifying =
    hasUserMessage &&
    !hasAssistantMessage &&
    routeSource === null &&
    workflow.state === "idle" &&
    !historyLoading &&
    resumedFrom === null;

  // Review F3: workflow has ended either in-memory (this session) or in the
  // persisted DB column (reload of an already-ended conversation).
  const workflowEnded = workflow.state === "ended" || workflowEndedAt !== null;

  // #5394 Layer B — drive the composer's repo-setup state from the active
  // workspace's repo_status (workspaces-backed, same source as the Layer A
  // gate). While `cloning` the hook polls every 2s so this auto-transitions to
  // ready (prop → null, composer re-enables) WITHOUT a manual refresh; `error`
  // surfaces the reconnect CTA. Any other status (ready / not_connected) → null.
  const { data: activeRepo } = useActiveRepo();
  const repoSetupState: "cloning" | "error" | null =
    activeRepo?.repoStatus === "cloning"
      ? "cloning"
      : activeRepo?.repoStatus === "error"
        ? "error"
        : null;

  function handleSend(message: string, attachments?: AttachmentRef[]) {
    if (status !== "connected") return;
    onBeforeSend?.(message);
    if (attachments && attachments.length > 0) {
      sendMessage(message, attachments);
    } else {
      sendMessage(message);
    }
  }

  const isFull = variant === "full";
  // h-full (NOT h-[100dvh] / calc): the <main> slot is already a bounded flex
  // item, so h-full fills it exactly. h-[100dvh] overflowed the slot by the top
  // bar's height and pushed the composer below the fold; a calc(100dvh-bar)
  // regresses on notched devices because this PR's viewportFit:cover makes the
  // bar's safe-top inset non-zero. `relative` anchors the Jump-to-latest pill.
  const rootClass = isFull
    ? "relative flex h-full flex-col md:h-full"
    : "relative flex h-full min-w-0 flex-col";
  const widthWrapper = isFull ? "mx-auto max-w-3xl" : "max-w-none";
  const inputPadX = isFull ? "px-4 md:px-6" : "px-4";

  return (
    <div className={rootClass}>
      {isFull && (
        <header className="flex shrink-0 items-center justify-between border-b border-soleur-border-default px-4 py-3 md:px-6">
          <div className="flex items-center gap-3">
            <a
              href="/dashboard"
              aria-label="Back to dashboard"
              className="flex items-center text-soleur-text-secondary hover:text-soleur-text-primary md:hidden"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="15 18 9 12 15 6" />
              </svg>
            </a>

            {activeLeaderIds.length > 0 && (
              <span className="text-sm text-soleur-text-secondary md:hidden">
                {activeLeaderIds.map((id) => getDisplayName(id)).join(", ")} responding
              </span>
            )}

            <span className="hidden text-sm font-semibold text-soleur-text-primary md:inline">
              Dashboard
            </span>
          </div>
          <div className="flex items-center gap-3">
            <AutoRunChip autonomous={autonomousPosture} />
            <StatusIndicator status={status} disconnectReason={disconnectReason} />
          </div>
        </header>
      )}

      {routeSource && respondingLeaders.some((id) => id !== CC_ROUTER_LEADER_ID) && (
        <RoutedLeadersStrip
          routeSource={routeSource}
          routedLeaders={respondingLeaders}
          getDisplayName={getDisplayName}
          isFull={isFull}
        />
      )}

      {/* #5282 State 1 — REWIRED through `deriveReconnectView` (was a bare
          `status === "reconnecting"` check). The selector gives connection
          state precedence over the State-2 watchdog chip (AC12), and the
          latest-wins reducer slice guarantees exactly ONE banner across a flap
          (AC4). aria-live polite so SRs announce the transient state. */}
      {reconnectView.kind === "connection_lost" && (
        <div
          data-testid="connection-banner"
          aria-live="polite"
          className={`border-b border-yellow-800/50 bg-yellow-950/20 px-4 py-2 ${isFull ? "md:px-6" : ""}`}
        >
          <div className="flex items-center justify-between">
            <span className="text-xs text-yellow-300">Connection lost. Reconnecting…</span>
            <button
              onClick={reconnect}
              className="text-xs text-yellow-400 underline hover:text-yellow-300"
            >
              Retry now
            </button>
          </div>
        </div>
      )}

      {/* #5282 State 3 — unrecoverable (in-flight session reclaimed after grace,
          or non-transient close). Sticky: a late reattach frame cannot flip
          this to State 4 (sticky guard in the reducer + this branch taking
          precedence over the State-4 notice below). The honest "your session is
          gone; resume with context" affordance, never a stale-resume lie. */}
      {connection.phase === "unrecoverable" && (
        <div
          data-testid="connection-unrecoverable"
          aria-live="polite"
          className={`border-b border-red-900/50 bg-red-950/20 px-4 py-2 ${isFull ? "md:px-6" : ""}`}
        >
          <div className="flex items-center justify-between gap-3">
            <span className="text-xs text-red-300">
              Your place is held — your full conversation is intact. Start a new message to resume with full context.
            </span>
            <button
              onClick={resumeAfterUnrecoverable}
              className="shrink-0 text-xs text-red-200 underline hover:text-red-100"
            >
              Resume with full context
            </button>
          </div>
        </div>
      )}

      {/* #5282 State 4 — DERIVED transient "successful resume" notice (not a
          reducer phase). Shown only when a reconnect-reattach set `resumedAt`
          AND we are not in the sticky `unrecoverable` state (which takes
          precedence above — enforces "no 3→4 flip" at the render layer). */}
      {showResumedNotice && (
        <div
          data-testid="connection-resumed"
          aria-live="polite"
          className={`border-b border-emerald-900/50 bg-emerald-950/20 px-4 py-2 ${isFull ? "md:px-6" : ""}`}
        >
          <span className="text-xs text-emerald-300">
            {connection.resumedAt
              ? `— Continuing from ${new Date(connection.resumedAt).toLocaleString()} · workspace restored —`
              : "— Continuing… · workspace restored —"}
          </span>
        </div>
      )}

      {/* Review F15: WorkflowLifecycleBar is sticky context above the
          scroll region — moving it OUTSIDE the `overflow-y-auto` container
          keeps it pinned regardless of message-list scroll position.

          #3774: thread the accumulated cost from `usageData` (driven by the
          legacy `usage_update` setState at `ws-client.ts:791-806`) into the
          active lifecycle slice so the bar can render the running total.
          The reducer's `cumulativeCostUsd` field exists on the type but is
          never written by any arm — this prop-time merge is the minimum
          fix to expose the existing data without introducing a second
          source of truth. */}
      <WorkflowLifecycleBar
        lifecycle={
          workflow.state === "active" && usageData
            ? { ...workflow, cumulativeCostUsd: usageData.totalCostUsd }
            : workflow
        }
        onStartNewConversation={() => router.push("/dashboard")}
      />

      <div
        ref={messagesScrollRef}
        onScroll={recomputeNearBottom}
        className={`min-w-0 flex-1 overflow-y-auto px-4 py-4 ${isFull ? "md:px-6" : ""}`}
      >
        {lastError && activeErrorKey !== dismissedErrorKey && (
          // `data-rate-limit-exceeded` is a load-bearing canary attribute —
          // see e2e/cc-soleur-go-security.e2e.ts FR3.4 (Stage 6 PR-C #2939).
          // Pattern mirrors `data-error-boundary` at error-boundary-view.tsx.
          <div
            className={`mb-4 ${widthWrapper}`}
            data-rate-limit-exceeded={lastError.code === "rate_limited" ? "" : undefined}
          >
            {isDelegationError(lastError.code) ? (
              <DelegationErrorCard errorCode={lastError.code} message={lastError.message} />
            ) : (
              <ErrorCard
                title={lastError.code === "key_invalid" ? "Invalid API Key" : lastError.code === "rate_limited" ? "Rate Limited" : lastError.code === "subscription_limit" ? "Subscription Limit Reached" : "Connection Error"}
                message={lastError.message}
                onRetry={lastError.code !== "key_invalid" && lastError.code !== "subscription_limit" ? reconnect : undefined}
                retryLabel="Reconnect"
                action={lastError.action}
                onDismiss={() => setDismissedErrorKey(activeErrorKey)}
              />
            )}
          </div>
        )}

        {sessionStartTimeout && !sessionConfirmed && !sessionTimeoutDismissed && (
          <div className={`mb-4 ${widthWrapper}`}>
            <ErrorCard
              title="Session Failed to Start"
              message="The server did not confirm the session within 10 seconds. Please try again."
              onRetry={reconnect}
              retryLabel="Reconnect"
              onDismiss={() => setSessionTimeoutDismissed(true)}
            />
          </div>
        )}

        {messages.length === 0 && !isClassifying && !lastError && !historyLoading && (
          <div className="flex h-full items-center justify-center">
            <p className="text-sm text-soleur-text-secondary">
              Send a message to get started
            </p>
          </div>
        )}

        <div className={`min-w-0 space-y-4 ${widthWrapper}`}>
          {(() => {
            const seenSoFar = new Set<string>();
            return messages.map((msg) => {
              const isFirst = msg.leaderId && !seenSoFar.has(msg.leaderId);
              if (msg.leaderId) seenSoFar.add(msg.leaderId);

              // Render dispatch with `: never` exhaustiveness rail per
              // `cq-union-widening-grep-three-patterns`. A new ChatMessage
              // variant without a case here fails `tsc --noEmit`.
              let body: React.ReactNode;
              switch (msg.type) {
                case "text":
                  body = (
                    <MessageBubble
                      role={msg.role}
                      content={msg.content}
                      leaderId={msg.leaderId}
                      showFullTitle={!!isFirst}
                      messageState={msg.state}
                      toolLabel={msg.toolLabel}
                      toolsUsed={msg.toolsUsed}
                      // #5282 AC12 — suppress the State-2 watchdog chip whenever
                      // State 1 (connection-lost banner) is showing, so the two
                      // can never render simultaneously.
                      retrying={msg.retrying && reconnectView.kind !== "connection_lost"}
                      getDisplayName={getDisplayName}
                      getIconPath={getIconPath}
                      attachments={msg.attachments}
                      variant={variant}
                      status={msg.status}
                      usage={msg.usage}
                      commandBlocks={msg.commandBlocks}
                    />
                  );
                  break;
                case "review_gate":
                  body = (
                    <ReviewGateCard
                      gateId={msg.gateId}
                      question={msg.question}
                      options={msg.options}
                      header={msg.header}
                      descriptions={msg.descriptions}
                      stepProgress={msg.stepProgress}
                      resolved={msg.resolved}
                      selectedOption={msg.selectedOption}
                      gateError={msg.gateError}
                      onSelect={handleReviewGateResponse}
                    />
                  );
                  break;
                case "autonomous_disclosure":
                  body = (
                    <AutonomousDisclosureBanner
                      gateId={msg.gateId}
                      existingWorkspace={msg.existingWorkspace}
                      resolved={msg.resolved}
                      onRespond={handleAutonomousDisclosureResponse}
                    />
                  );
                  break;
                case "subagent_group":
                  body = (
                    <SubagentGroup
                      parentSpawnId={msg.parentSpawnId}
                      parentLeaderId={msg.parentLeaderId}
                      parentTask={msg.parentTask}
                      subagents={msg.children}
                      getDisplayName={getDisplayName}
                      getIconPath={getIconPath}
                      variant={variant}
                    />
                  );
                  break;
                case "interactive_prompt": {
                  body = renderInteractivePromptCard(msg, (response) =>
                    handleInteractivePromptResponse(
                      msg.promptId,
                      msg.conversationId,
                      response,
                    ),
                  );
                  break;
                }
                case "workflow_ended":
                  body = (
                    <div
                      data-message-type="workflow_ended"
                      className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 px-4 py-3"
                    >
                      <p className="text-sm text-soleur-text-primary">
                        Workflow{" "}
                        <span className="font-semibold">{msg.workflow}</span>{" "}
                        ended:{" "}
                        <span
                          className={
                            msg.status === "completed"
                              ? "text-emerald-400"
                              : "text-red-400"
                          }
                        >
                          {msg.status}
                        </span>
                      </p>
                      {msg.summary ? (
                        <p className="mt-1 text-xs text-soleur-text-secondary">{msg.summary}</p>
                      ) : null}
                    </div>
                  );
                  break;
                case "tool_use_chip":
                  // F13: `msg.leaderId` is already narrowed to "cc_router" | "system"
                  // by the ChatToolUseChipMessage type — no cast needed.
                  body = (
                    <ToolUseChip
                      toolName={msg.toolName}
                      toolLabel={msg.toolLabel}
                      leaderId={msg.leaderId}
                    />
                  );
                  break;
                case "context_reset":
                  // #3269 — inline lifecycle notice mirroring `workflow_ended`
                  // shape. Copy is read from `CONTEXT_RESET_COPY[msg.reason]`
                  // (single source of truth shared with the RTL test).
                  body = (
                    <div
                      data-message-type="context_reset"
                      className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 px-4 py-3"
                    >
                      <p className="text-sm text-soleur-text-primary">
                        {CONTEXT_RESET_COPY[msg.reason]}
                      </p>
                    </div>
                  );
                  break;
                case "debug_event":
                  // feat-debug-mode-stream — harness instruction-stream events
                  // render in the SEPARATE collapsed <DebugStreamPanel> below,
                  // NOT inline in the conversation. The case exists to satisfy
                  // the `: never` exhaustiveness rail; inline body is null.
                  body = null;
                  break;
                case "turn_summary":
                  // feat-reasoning-chat-boxes (#5370) — durable per-turn summary
                  // box, rendered INLINE in the main conversation (plain-text;
                  // never MarkdownRenderer — see TurnSummaryBubble security note).
                  body = <TurnSummaryBubble content={msg.content} />;
                  break;
                default: {
                  const _exhaustive: never = msg;
                  void _exhaustive;
                  body = null;
                }
              }

              return (
                <div key={msg.id} className="min-w-0">
                  {body}
                </div>
              );
            });
          })()}

          {isClassifying && (
            // Reuses MessageBubble's tool_use treatment (active border + Working
            // badge + ToolStatusChip) so the routing chip matches every
            // subsequent in-flight assistant turn rather than rendering a
            // distinct flat row. Outer wrapper preserves the routing-chip
            // testid for existing presence/absence assertions.
            <div className="flex justify-start" data-testid="routing-chip">
              <MessageBubble
                role="assistant"
                content=""
                leaderId={CC_ROUTER_LEADER_ID}
                messageState="tool_use"
                toolLabel="Routing to the right experts..."
                getDisplayName={getDisplayName}
                getIconPath={getIconPath}
                variant={variant}
              />
            </div>
          )}

          {/* feat-reasoning-chat-boxes (#5370) — transient live narration line.
              Shows the agent's deliberate plain-language status near the Working
              badge while a turn is in flight. The slot is gated only on
              `streamState === "streaming"`; the CONTENT falls back to a
              "Still working…" placeholder when `liveNarration === null` — which
              is exactly the spec-flow Finding 4 reconnect case: the live frame is
              live-only (never buffered), so a mid-turn reconnect nulls
              `liveNarration` while the turn is still streaming. The placeholder
              keeps the user oriented instead of leaving a blank gap, and is
              immediately replaced when the next `narrate` frame arrives. It
              disappears on turn-end (the reducer nulls liveNarration AND
              streamState leaves "streaming" on every turn-end path), so it is
              still fully inert outside an in-flight turn.

              feat-one-shot-concierge-web-duplicate-question-box — additionally
              gated on `!awaitingUserInput`: while an unresolved review_gate /
              autonomous_disclosure parks the turn on the operator, the amber
              prompt card is the waiting-for-input surface, so this spinner is
              suppressed to avoid a contradictory "Still working…" signal. See
              the `awaitingUserInput` derivation above for the turn-scoping and
              why informational interactive_prompt cards are excluded. */}
          {streamState === "streaming" && !awaitingUserInput && (
            <div
              data-testid="live-narration"
              aria-live="polite"
              className="flex items-center gap-2 px-1 text-sm text-soleur-text-secondary"
            >
              <span
                aria-hidden="true"
                className="inline-block h-1.5 w-1.5 shrink-0 animate-pulse rounded-full bg-amber-500"
              />
              <span className="min-w-0 [overflow-wrap:anywhere]">
                {liveNarration ?? "Still working…"}
              </span>
            </div>
          )}

          <NotificationPrompt visible={showNotificationPrompt} />
          {/* PR-B (#3603) — per-thread transparency marker for the
              row-absence cohort. Component self-gates on the cohort window,
              sunset date, message shape, and streaming state; rendering an
              empty pass when any gate fails. Mounted before
              `messagesEndRef` so scroll-into-view still lands on the
              composer anchor, not the marker. */}
          <CohortMissingReplyMarker
            createdAt={conversationCreatedAt}
            messages={messages}
            isTurnInFlight={streamState !== "idle"}
          />
          <DebugStreamPanel
            available={debugAvailable}
            events={debugEvents}
            connected={status === "connected"}
            hadCompletedTurn={hasAssistantMessage && streamState === "idle"}
          />
          <div ref={messagesEndRef} />
        </div>
      </div>

      {isFull && (activeLeaderIds.length > 0 || (usageData && usageData.totalCostUsd > 0)) && (
        <div className="hidden border-t border-soleur-border-default/50 px-4 py-1.5 md:block md:px-6">
          <p className="text-xs text-soleur-text-muted">
            {activeLeaderIds.length > 0 && (
              <>{activeLeaderIds.length} leaders responding</>
            )}
            {usageData && usageData.totalCostUsd > 0 && (
              <span className="text-soleur-text-secondary">
                {activeLeaderIds.length > 0 && " · "}
                ~${usageData.totalCostUsd.toFixed(4)}
                <span className="text-soleur-text-muted ml-1">estimated</span>
              </span>
            )}
          </p>
        </div>
      )}

      {/* Composer + Jump-to-latest share a `relative` shell so the pill anchors
          to the composer's actual top edge (bottom-full), never overlapping a
          grown multi-line composer, and rides up with the keyboard via the
          composer's own marginBottom. The pill is NOT inside the messages scroll
          div (it would scroll away exactly when the user is scrolled up). */}
      <div className="relative shrink-0">
        {showJumpButton && (
          <button
            type="button"
            onClick={handleJumpToLatest}
            aria-label="Jump to latest"
            className="absolute bottom-full left-1/2 z-10 mb-2 flex min-h-11 -translate-x-1/2 items-center gap-1.5 rounded-full border border-soleur-border-default bg-soleur-bg-surface-2 px-4 text-sm text-soleur-text-primary shadow-lg hover:bg-soleur-bg-surface-3"
          >
            Jump to latest
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <polyline points="6 9 12 15 18 9" />
            </svg>
          </button>
        )}

      <div
        data-tour-id={isFull ? "action:conversation-composer" : undefined}
        style={keyboardInset > 0 ? { marginBottom: keyboardInset } : undefined}
        className={`shrink-0 border-t border-soleur-border-default bg-soleur-bg-base py-3 ${inputPadX} ${isFull ? "safe-bottom md:px-6" : ""}`}
      >
        <div className={`relative min-w-0 ${widthWrapper}`}>
          <AtMentionDropdown
            query={atQuery}
            visible={atVisible}
            customNames={customNames}
            loading={teamNamesLoading}
            onSelect={(id) => {
              setAtVisible(false);
              if (insertRef.current) {
                insertRef.current(`@${getDisplayName(id)}`, atPosition);
              }
            }}
            onDismiss={() => setAtVisible(false)}
          />
          <ChatInput
            onSend={handleSend}
            conversationId={conversationId}
            onAtTrigger={(query, pos) => {
              setAtQuery(query);
              setAtPosition(pos);
              setAtVisible(true);
            }}
            onAtDismiss={() => setAtVisible(false)}
            atMentionVisible={atVisible}
            disabled={status !== "connected"}
            workflowEnded={workflowEnded}
            placeholder={
              status === "connected"
                ? (placeholder ??
                    "Follow up or ask another question... Type @ to switch leader")
                : "Reconnecting..."
            }
            insertRef={insertRef}
            quoteRef={quoteRef}
            focusRef={focusRef}
            draftKey={draftKey}
            streamState={streamState}
            onStop={abort}
            repoSetupState={repoSetupState}
          />
        </div>
        {!isFull && usageData && usageData.totalCostUsd > 0 && (
          <div className="mt-1 px-1 text-xs text-soleur-text-muted">
            ~${usageData.totalCostUsd.toFixed(4)} estimated
          </div>
        )}
        {isFull && (
          <div className="mx-auto mt-1 flex max-w-3xl items-center justify-between text-xs text-soleur-text-secondary">
            <span className="md:hidden">
              {activeLeaderIds.length > 0 && (
                <>{activeLeaderIds.length} leaders responding</>
              )}
              {usageData && usageData.totalCostUsd > 0 && (
                <span className="text-soleur-text-secondary">
                  {activeLeaderIds.length > 0 && " · "}
                  ~${usageData.totalCostUsd.toFixed(4)} est.
                </span>
              )}
            </span>
          </div>
        )}
      </div>
      </div>
    </div>
  );
}
