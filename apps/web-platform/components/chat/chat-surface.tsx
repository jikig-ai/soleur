"use client";

import React, { useState, useRef, useEffect, useCallback } from "react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { useWebSocket } from "@/lib/ws-client";
import type { ConversationContext, AttachmentRef } from "@/lib/types";
import { ErrorCard } from "@/components/ui/error-card";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { ChatInput, type ChatInputQuoteHandle } from "@/components/chat/chat-input";
import { AtMentionDropdown } from "@/components/chat/at-mention-dropdown";
import { useTeamNames } from "@/hooks/use-team-names";
import { NotificationPrompt } from "@/components/chat/notification-prompt";
import { getPendingFiles, clearPendingFiles } from "@/lib/pending-attachments";
import { uploadWithProgress } from "@/lib/upload-with-progress";
import { MessageBubble } from "@/components/chat/message-bubble";
import { ReviewGateCard } from "@/components/chat/review-gate-card";
import { StatusIndicator } from "@/components/chat/status-indicator";

export type ChatSurfaceVariant = "full" | "sidebar";

export interface ChatSurfaceProps {
  conversationId: string;
  variant: ChatSurfaceVariant;
  onClose?: () => void;
  initialContext?: ConversationContext;
  /**
   * When set AND conversationId === "new", the sidebar starts a session
   * that looks up an existing (user_id, context_path) row and resumes it
   * instead of creating a fresh pending conversation.
   */
  resumeByContextPath?: string;
  onThreadResumed?: (conversationId: string, timestamp: string, messageCount: number) => void;
  onRealConversationId?: (conversationId: string) => void;
  onMessageCountChange?: (count: number) => void;
  /** Imperative handle for KB selection-toolbar quote insertion (sidebar only). */
  quoteRef?: React.MutableRefObject<ChatInputQuoteHandle | null>;
  /** Fires before sendMessage so sidebar callers can emit analytics (e.g.
   *  kb.chat.selection_sent when the content starts with a blockquote). */
  onBeforeSend?: (message: string) => void;
  /** Override the default placeholder — used by KB sidebar to surface ⌘⇧L. */
  placeholder?: string;
}

export function ChatSurface({
  conversationId,
  variant,
  initialContext,
  resumeByContextPath,
  onThreadResumed,
  onRealConversationId,
  onMessageCountChange,
  quoteRef,
  onBeforeSend,
  placeholder,
}: ChatSurfaceProps) {
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const leaderId = searchParams.get("leader") as DomainLeaderId | null;
  const msgParam = searchParams.get("msg");
  const contextParam = searchParams.get("context");

  const {
    messages,
    startSession,
    resumeSession,
    sendMessage,
    sendReviewGateResponse,
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

  // Fetch KB content when ?context= param is present (full-route only).
  // Sidebar callers pass `initialContext` directly and do not use the URL.
  const [kbContext, setKbContext] = useState<ConversationContext | undefined>(initialContext);
  const [contextLoading, setContextLoading] = useState(!initialContext && !!contextParam);

  useEffect(() => {
    if (initialContext) return;
    if (!contextParam) return;
    let cancelled = false;

    (async () => {
      try {
        const res = await fetch(`/api/kb/content/${contextParam}`);
        if (res.ok && !cancelled) {
          const data = await res.json();
          setKbContext({
            path: contextParam,
            type: "kb-viewer",
            content: data.content,
          });
        }
      } catch (err) {
        console.error("KB context fetch failed:", err);
      } finally {
        if (!cancelled) setContextLoading(false);
      }
    })();

    return () => { cancelled = true; };
  }, [contextParam, initialContext]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  useEffect(() => {
    if (status !== "connected" || sessionStarted) return;

    if (conversationId === "new") {
      if (!contextLoading) {
        if (resumeByContextPath) {
          startSession({
            leaderId: leaderId ?? undefined,
            context: kbContext,
            resumeByContextPath,
          });
        } else {
          startSession(leaderId ?? undefined, kbContext);
        }
        setSessionStarted(true);
      }
    } else {
      resumeSession(conversationId);
      setSessionStarted(true);
    }
  }, [status, conversationId, leaderId, sessionStarted, startSession, resumeSession, contextLoading, kbContext, resumeByContextPath]);

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
    onMessageCountChange?.(messages.length);
  }, [messages.length, onMessageCountChange]);

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
        const uploaded: AttachmentRef[] = [];

        for (const file of files) {
          const presignRes = await fetch("/api/attachments/presign", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              filename: file.name,
              contentType: file.type,
              sizeBytes: file.size,
              conversationId: realConversationId,
            }),
          });

          if (!presignRes.ok) continue;

          const { uploadUrl, storagePath } = await presignRes.json();
          const { promise } = uploadWithProgress(uploadUrl, file, file.type, () => {});
          await promise;

          uploaded.push({
            storagePath,
            filename: file.name,
            contentType: file.type,
            sizeBytes: file.size,
          });
        }

        if (uploaded.length > 0) {
          sendMessage("", uploaded);
        }
      } catch {
        // Graceful degradation
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
  const isClassifying = hasUserMessage && !hasAssistantMessage && routeSource === null;

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

        {messages.length === 0 && !isClassifying && !lastError && (
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

              return (
                <div key={msg.id} className="min-w-0">
                  {msg.type === "review_gate" ? (
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
                  ) : (
                    <MessageBubble
                      role={msg.role}
                      content={msg.content}
                      leaderId={msg.leaderId}
                      showFullTitle={!!isFirst}
                      messageState={msg.state}
                      toolLabel={msg.toolLabel}
                      toolsUsed={msg.toolsUsed}
                      getDisplayName={getDisplayName}
                      getIconPath={getIconPath}
                      attachments={msg.attachments}
                      variant={variant}
                    />
                  )}
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
            placeholder={
              status === "connected"
                ? (placeholder ??
                    "Follow up or ask another question... Type @ to switch leader")
                : "Reconnecting..."
            }
            insertRef={insertRef}
            quoteRef={quoteRef}
          />
        </div>
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
