"use client";

import React, { useState, useRef, useEffect, useCallback } from "react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { useWebSocket } from "@/lib/ws-client";
import type { ConversationContext, AttachmentRef } from "@/lib/types";
import { ErrorCard } from "@/components/ui/error-card";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { ChatInput } from "@/components/chat/chat-input";
import { AtMentionDropdown } from "@/components/chat/at-mention-dropdown";
import { useTeamNames } from "@/hooks/use-team-names";
import { NotificationPrompt } from "@/components/chat/notification-prompt";
import { getPendingFiles, clearPendingFiles } from "@/lib/pending-attachments";
import { uploadPendingFiles } from "@/lib/upload-attachments";
import * as Sentry from "@sentry/nextjs";
import { MessageBubble } from "@/components/chat/message-bubble";
import { ReviewGateCard } from "@/components/chat/review-gate-card";
import { StatusIndicator } from "@/components/chat/status-indicator";
import { SubagentGroup } from "@/components/chat/subagent-group";
import { InteractivePromptCard } from "@/components/chat/interactive-prompt-card";
import { WorkflowLifecycleBar } from "@/components/chat/workflow-lifecycle-bar";
import { ToolUseChip } from "@/components/chat/tool-use-chip";
import type {
  InteractivePromptResponsePayload,
  InteractivePromptPayload,
} from "@/lib/types";
import type { ChatInteractivePromptMessage } from "@/lib/chat-state-machine";

export type ChatSurfaceVariant = "full" | "sidebar";

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
  /** Sidebar-only props. Ignored (shallow) when variant === "full". */
  sidebarProps?: ChatSurfaceSidebarProps;
}

export function ChatSurface({
  conversationId,
  variant,
  initialContext,
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
    realConversationId,
    resumedFrom,
    workflow,
    workflowEndedAt,
    historyLoading,
  } = useWebSocket(conversationId);

  const { names: customNames, getDisplayName, getIconPath, loading: teamNamesLoading } = useTeamNames();

  const [sessionStarted, setSessionStarted] = useState(false);
  const [initialMsgSent, setInitialMsgSent] = useState(false);
  const [sessionStartTimeout, setSessionStartTimeout] = useState(false);
  const [atQuery, setAtQuery] = useState("");
  const [atVisible, setAtVisible] = useState(false);
  const [atPosition, setAtPosition] = useState(0);
  const [showNotificationPrompt, setShowNotificationPrompt] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const insertRef = useRef<((text: string, replaceFrom: number) => void) | null>(null);

  const handleReviewGateResponse = useCallback(
    (gateId: string, selection: string) => {
      sendReviewGateResponse(gateId, selection);
      setShowNotificationPrompt(true);
    },
    [sendReviewGateResponse],
  );

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
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  useEffect(() => {
    if (status !== "connected" || sessionStarted) return;

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
  }, [status, conversationId, leaderId, sessionStarted, startSession, resumeSession, initialContext, resumeByContextPath]);

  useEffect(() => {
    if (resumedFrom && onThreadResumed) {
      onThreadResumed(resumedFrom.conversationId, resumedFrom.timestamp, resumedFrom.messageCount);
    }
  }, [resumedFrom, onThreadResumed]);

  useEffect(() => {
    if (realConversationId && onRealConversationId) {
      onRealConversationId(realConversationId);
    }
  }, [realConversationId, onRealConversationId]);

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
  // Review F10: gate the legacy `isClassifying` chip on the lifecycle bar
  // being idle — once the bar takes over routing/active/ended, the legacy
  // chip must not double-render with the bar.
  const isClassifying =
    hasUserMessage &&
    !hasAssistantMessage &&
    routeSource === null &&
    workflow.state === "idle";

  // Review F3: workflow has ended either in-memory (this session) or in the
  // persisted DB column (reload of an already-ended conversation).
  const workflowEnded = workflow.state === "ended" || workflowEndedAt !== null;

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
  const rootClass = isFull ? "flex h-[100dvh] flex-col md:h-full" : "flex h-full min-w-0 flex-col";
  const widthWrapper = isFull ? "mx-auto max-w-3xl" : "max-w-none";
  const inputPadX = isFull ? "px-4 md:px-6" : "px-4";

  return (
    <div className={rootClass}>
      {isFull && (
        <header className="flex shrink-0 items-center justify-between border-b border-neutral-800 px-4 py-3 md:px-6">
          <div className="flex items-center gap-3">
            <a
              href="/dashboard"
              aria-label="Back to dashboard"
              className="flex items-center text-neutral-400 hover:text-white md:hidden"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="15 18 9 12 15 6" />
              </svg>
            </a>

            {activeLeaderIds.length > 0 && (
              <span className="text-sm text-neutral-400 md:hidden">
                {activeLeaderIds.map((id) => getDisplayName(id)).join(", ")} responding
              </span>
            )}

            <span className="hidden text-sm font-semibold text-white md:inline">
              Command Center
            </span>
          </div>
          <StatusIndicator status={status} disconnectReason={disconnectReason} />
        </header>
      )}

      {routeSource && respondingLeaders.length > 0 && (
        <div className={`border-b border-neutral-800/50 px-4 py-2 ${isFull ? "md:px-6" : ""}`}>
          <span className="inline-flex items-center gap-1.5 rounded-full bg-neutral-800/50 px-3 py-1 text-xs text-neutral-400">
            {routeSource === "auto" ? (
              <>Auto-routed to {respondingLeaders.map((id) => getDisplayName(id)).join(", ")}</>
            ) : (
              <>Directed to @{respondingLeaders.map((id) => getDisplayName(id)).join(", @")}</>
            )}
          </span>
        </div>
      )}

      {status === "reconnecting" && (
        <div className={`border-b border-yellow-800/50 bg-yellow-950/20 px-4 py-2 ${isFull ? "md:px-6" : ""}`}>
          <div className="flex items-center justify-between">
            <span className="text-xs text-yellow-300">Connection lost. Reconnecting...</span>
            <button
              onClick={reconnect}
              className="text-xs text-yellow-400 underline hover:text-yellow-300"
            >
              Retry now
            </button>
          </div>
        </div>
      )}

      {/* Review F15: WorkflowLifecycleBar is sticky context above the
          scroll region — moving it OUTSIDE the `overflow-y-auto` container
          keeps it pinned regardless of message-list scroll position. */}
      <WorkflowLifecycleBar
        lifecycle={workflow}
        onStartNewConversation={() => router.push("/dashboard")}
      />

      <div className={`min-w-0 flex-1 overflow-y-auto px-4 py-4 ${isFull ? "md:px-6" : ""}`}>
        {lastError && (
          <div className={`mb-4 ${widthWrapper}`}>
            <ErrorCard
              title={lastError.code === "key_invalid" ? "Invalid API Key" : lastError.code === "rate_limited" ? "Rate Limited" : "Connection Error"}
              message={lastError.message}
              onRetry={lastError.code !== "key_invalid" ? reconnect : undefined}
              retryLabel="Reconnect"
              action={lastError.action}
            />
          </div>
        )}

        {sessionStartTimeout && !sessionConfirmed && (
          <div className={`mb-4 ${widthWrapper}`}>
            <ErrorCard
              title="Session Failed to Start"
              message="The server did not confirm the session within 10 seconds. Please try again."
              onRetry={reconnect}
              retryLabel="Reconnect"
            />
          </div>
        )}

        {messages.length === 0 && !isClassifying && !lastError && !historyLoading && (
          <div className="flex h-full items-center justify-center">
            <p className="text-sm text-neutral-400">
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
                      retrying={msg.retrying}
                      getDisplayName={getDisplayName}
                      getIconPath={getIconPath}
                      attachments={msg.attachments}
                      variant={variant}
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
                      className="rounded-xl border border-neutral-800 bg-neutral-900/40 px-4 py-3"
                    >
                      <p className="text-sm text-neutral-200">
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
                        <p className="mt-1 text-xs text-neutral-400">{msg.summary}</p>
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
            <div className="flex justify-start">
              <div className="flex items-center gap-2 rounded-xl border border-neutral-800 bg-neutral-900 px-4 py-3">
                <span className="h-2 w-2 animate-pulse rounded-full bg-amber-500" />
                <span className="text-sm text-neutral-400">
                  Routing to the right experts...
                </span>
              </div>
            </div>
          )}

          <NotificationPrompt visible={showNotificationPrompt} />
          <div ref={messagesEndRef} />
        </div>
      </div>

      {isFull && (activeLeaderIds.length > 0 || (usageData && usageData.totalCostUsd > 0)) && (
        <div className="hidden border-t border-neutral-800/50 px-4 py-1.5 md:block md:px-6">
          <p className="text-xs text-neutral-500">
            {activeLeaderIds.length > 0 && (
              <>{activeLeaderIds.length} leaders responding</>
            )}
            {usageData && usageData.totalCostUsd > 0 && (
              <span className="text-neutral-400">
                {activeLeaderIds.length > 0 && " · "}
                ~${usageData.totalCostUsd.toFixed(4)}
                <span className="text-neutral-500 ml-1">estimated</span>
              </span>
            )}
          </p>
        </div>
      )}

      <div className={`shrink-0 border-t border-neutral-800 bg-neutral-950 py-3 ${inputPadX} ${isFull ? "safe-bottom md:px-6" : ""}`}>
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
          />
        </div>
        {!isFull && usageData && usageData.totalCostUsd > 0 && (
          <div className="mt-1 px-1 text-xs text-neutral-500">
            ~${usageData.totalCostUsd.toFixed(4)} estimated
          </div>
        )}
        {isFull && (
          <div className="mx-auto mt-1 flex max-w-3xl items-center justify-between text-xs text-neutral-400">
            <span className="md:hidden">
              {activeLeaderIds.length > 0 && (
                <>{activeLeaderIds.length} leaders responding</>
              )}
              {usageData && usageData.totalCostUsd > 0 && (
                <span className="text-neutral-400">
                  {activeLeaderIds.length > 0 && " · "}
                  ~${usageData.totalCostUsd.toFixed(4)} est.
                </span>
              )}
            </span>
          </div>
        )}
      </div>
    </div>
  );
}
