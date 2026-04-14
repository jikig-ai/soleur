"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import { useParams, useSearchParams, useRouter, usePathname } from "next/navigation";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { useWebSocket } from "@/lib/ws-client";
import type { ConversationContext, AttachmentRef, MessageState } from "@/lib/types";
import { ErrorCard } from "@/components/ui/error-card";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { LEADER_COLORS } from "@/components/chat/leader-colors";
import { LeaderAvatar } from "@/components/leader-avatar";
import { ChatInput } from "@/components/chat/chat-input";
import { AtMentionDropdown } from "@/components/chat/at-mention-dropdown";
import { useTeamNames } from "@/hooks/use-team-names";
import { AttachmentDisplay } from "@/components/chat/attachment-display";
import { NotificationPrompt } from "@/components/chat/notification-prompt";
import { getPendingFiles, clearPendingFiles } from "@/lib/pending-attachments";
import { uploadWithProgress } from "@/lib/upload-with-progress";

export default function ChatPage() {
  const params = useParams<{ conversationId: string }>();
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const conversationId = params.conversationId;
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

  // Fetch KB content when ?context= param is present
  const [kbContext, setKbContext] = useState<ConversationContext | undefined>();
  const [contextLoading, setContextLoading] = useState(!!contextParam);

  useEffect(() => {
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
        // Graceful degradation: proceed without context
        console.error("KB context fetch failed:", err);
      } finally {
        if (!cancelled) setContextLoading(false);
      }
    })();

    return () => { cancelled = true; };
  }, [contextParam]);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  // Start or resume session when connected
  useEffect(() => {
    if (status !== "connected" || sessionStarted) return;

    if (conversationId === "new") {
      if (!contextLoading) {
        startSession(leaderId ?? undefined, kbContext);
        setSessionStarted(true);
      }
    } else {
      // Existing conversation — resume the server-side session
      resumeSession(conversationId);
      setSessionStarted(true);
    }
  }, [status, conversationId, leaderId, sessionStarted, startSession, resumeSession, contextLoading, kbContext]);

  // Reset sessionStarted on reconnection so session init re-fires
  useEffect(() => {
    if (status === "reconnecting") {
      setSessionStarted(false);
    }
  }, [status]);

  // Send initial message from ?msg= param after server confirms session
  useEffect(() => {
    if (sessionConfirmed && msgParam && !initialMsgSent) {
      sendMessage(msgParam);
      setInitialMsgSent(true);
      // Clean URL params to prevent duplicate sends on refresh
      router.replace(pathname, { scroll: false });
    }
  }, [sessionConfirmed, msgParam, initialMsgSent, sendMessage, router, pathname]);

  // Upload pending files from command center after initial message materializes the conversation
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
        // Graceful degradation — text message was already sent, attachments just don't arrive
      }
    })();
  }, [initialMsgSent, pendingFilesHandled, realConversationId, sendMessage]);

  // Session confirmation timeout: if server never confirms, show error
  useEffect(() => {
    if (!sessionStarted || sessionConfirmed) return;

    const timer = setTimeout(() => {
      setSessionStartTimeout(true);
    }, 10_000);

    return () => clearTimeout(timer);
  }, [sessionStarted, sessionConfirmed]);

  // Derive leader names for routing badge
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
    if (attachments && attachments.length > 0) {
      sendMessage(message, attachments);
    } else {
      sendMessage(message);
    }
  }

  return (
    <div className="flex h-[100dvh] flex-col md:h-full">
      {/* Top bar */}
      <header className="flex shrink-0 items-center justify-between border-b border-neutral-800 px-4 py-3 md:px-6">
        <div className="flex items-center gap-3">
          {/* Mobile back arrow */}
          <a
            href="/dashboard"
            aria-label="Back to dashboard"
            className="flex items-center text-neutral-400 hover:text-white md:hidden"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="15 18 9 12 15 6" />
            </svg>
          </a>

          {/* Mobile status bar: leader names */}
          {activeLeaderIds.length > 0 && (
            <span className="text-sm text-neutral-400 md:hidden">
              {activeLeaderIds
                .map((id) => getDisplayName(id))
                .join(", ")}{" "}
              responding
            </span>
          )}

          {/* Desktop header */}
          <span className="hidden text-sm font-semibold text-white md:inline">
            Command Center
          </span>
        </div>
        <StatusIndicator status={status} disconnectReason={disconnectReason} />
      </header>

      {/* Routing badge */}
      {routeSource && respondingLeaders.length > 0 && (
        <div className="border-b border-neutral-800/50 px-4 py-2 md:px-6">
          <span className="inline-flex items-center gap-1.5 rounded-full bg-neutral-800/50 px-3 py-1 text-xs text-neutral-400">
            {routeSource === "auto" ? (
              <>
                Auto-routed to{" "}
                {respondingLeaders
                  .map((id) => getDisplayName(id))
                  .join(", ")}
              </>
            ) : (
              <>
                Directed to @
                {respondingLeaders
                  .map((id) => getDisplayName(id))
                  .join(", @")}
              </>
            )}
          </span>
        </div>
      )}

      {/* Network loss banner */}
      {status === "reconnecting" && (
        <div className="border-b border-yellow-800/50 bg-yellow-950/20 px-4 py-2 md:px-6">
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

      {/* Message list */}
      <div className="flex-1 overflow-y-auto px-4 py-4 md:px-6">
        {/* Error states */}
        {lastError && (
          <div className="mx-auto mb-4 max-w-3xl">
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
          <div className="mx-auto mb-4 max-w-3xl">
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

        <div className="mx-auto max-w-3xl space-y-4">
          {(() => {
            const seenSoFar = new Set<string>();
            return messages.map((msg) => {
              const isFirst = msg.leaderId && !seenSoFar.has(msg.leaderId);
              if (msg.leaderId) seenSoFar.add(msg.leaderId);

              return (
                <div key={msg.id}>
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
                  />
                )}
              </div>
              );
            });
          })()}

          {/* Pulsing classification indicator */}
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

      {/* Status bar */}
      {(activeLeaderIds.length > 0 || (usageData && usageData.totalCostUsd > 0)) && (
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

      {/* Input bar */}
      <div className="shrink-0 border-t border-neutral-800 bg-neutral-950 px-4 py-3 safe-bottom md:px-6">
        <div className="relative mx-auto max-w-3xl">
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
                ? "Follow up or ask another question... Type @ to switch leader"
                : "Reconnecting..."
            }
            insertRef={insertRef}
          />
        </div>
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
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Sub-components                                                     */
/* ------------------------------------------------------------------ */

function ThinkingDots() {
  return (
    <div className="flex items-center gap-1.5 py-1" data-testid="thinking-dots">
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-neutral-400" style={{ animationDelay: "0ms" }} />
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-neutral-400" style={{ animationDelay: "150ms" }} />
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-neutral-400" style={{ animationDelay: "300ms" }} />
    </div>
  );
}


function MessageBubble({
  role,
  content,
  leaderId,
  showFullTitle = false,
  messageState,
  toolLabel,
  toolsUsed,
  getDisplayName,
  getIconPath,
  attachments,
}: {
  role: "user" | "assistant";
  content: string;
  leaderId?: DomainLeaderId;
  showFullTitle?: boolean;
  messageState?: MessageState;
  toolLabel?: string;
  toolsUsed?: string[];
  getDisplayName?: (id: DomainLeaderId) => string;
  getIconPath?: (id: DomainLeaderId) => string | null;
  attachments?: AttachmentRef[];
}) {
  const isUser = role === "user";
  const leader = leaderId ? DOMAIN_LEADERS.find((l) => l.id === leaderId) : null;
  const colorClass = leaderId ? (LEADER_COLORS[leaderId] ?? "border-l-neutral-500") : "";
  const displayName = leaderId && getDisplayName ? getDisplayName(leaderId) : leader?.name;
  const customIconPath = leaderId && getIconPath ? getIconPath(leaderId) : null;

  // Determine if this bubble is in an active state (pulsing border)
  const isActive = messageState === "thinking" || messageState === "tool_use" || messageState === "streaming";
  const isError = messageState === "error";
  const isDone = messageState === "done";

  // Border style based on state
  const borderStyle = isError
    ? "border-2 border-red-900/60"
    : isActive
      ? "message-bubble-active border-2 border-amber-600/70"
      : isDone
        ? "border border-neutral-800/60"
        : "border border-neutral-800";

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div className={`flex max-w-[90%] gap-3 md:max-w-[80%] ${isUser ? "flex-row-reverse" : ""}`}>
        {/* Leader avatar */}
        {leader && (
          <LeaderAvatar leaderId={leaderId!} size="md" className="mt-1" customIconPath={customIconPath} />
        )}

        <div
          className={`relative rounded-xl px-4 py-3 text-sm leading-relaxed ${
            isUser
              ? "bg-neutral-800 text-neutral-100"
              : `bg-neutral-900 text-neutral-200 ${borderStyle} ${leader && !isActive && !isError ? `border-l-2 ${colorClass}` : ""}`
          }`}
        >
          {/* State badge chip (visible in TOOL_USE and STREAMING states) */}
          {(messageState === "tool_use" || messageState === "streaming") && (
            <span className="absolute -top-2.5 right-3 rounded-full border border-amber-700/50 bg-neutral-900 px-2 py-0.5 text-[10px] font-medium text-amber-500">
              {messageState === "tool_use" ? "Working" : "Streaming"}
            </span>
          )}

          {/* Checkmark on DONE */}
          {isDone && role === "assistant" && (
            <span
              className="absolute -top-2.5 right-3 flex h-5 w-5 items-center justify-center rounded-full bg-neutral-900 text-amber-600"
              aria-label="Response complete"
            >
              <svg width="12" height="12" viewBox="0 0 12 12" fill="none" aria-hidden="true">
                <path d="M2 6.5L4.5 9L10 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          )}

          {leader && (
            <div className="mb-1 flex items-center gap-2">
              <span className="text-xs font-semibold text-neutral-300">
                {displayName}
              </span>
              {showFullTitle && (
                <span className="text-xs text-neutral-500">{leader.title}</span>
              )}
            </div>
          )}

          {/* State-driven content rendering */}
          {messageState === "thinking" || (!messageState && content === "" && role === "assistant") ? (
            <ThinkingDots />
          ) : messageState === "tool_use" && toolLabel ? (
            <ToolStatusChip label={toolLabel} />
          ) : messageState === "error" ? (
            <div className="flex items-center gap-2 text-red-400">
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
                <circle cx="7" cy="7" r="6" stroke="currentColor" strokeWidth="1.2" />
                <path d="M7 4v3.5M7 9.5v.01" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
              </svg>
              <span className="text-sm">Agent stopped responding</span>
            </div>
          ) : isDone && content === "" && toolsUsed && toolsUsed.length > 0 ? (
            <div className="flex items-center gap-1.5 text-xs text-neutral-500">
              <span>Used:</span>
              {toolsUsed.map((t, i) => (
                <span key={i} className="rounded bg-neutral-800 px-1.5 py-0.5">{t}</span>
              ))}
            </div>
          ) : messageState === "streaming" || (content === "" && role === "assistant" && !isDone) ? (
            <p className="whitespace-pre-wrap [overflow-wrap:anywhere]">
              {content}<span className="animate-pulse text-amber-500">&#x258C;</span>
            </p>
          ) : isUser ? (
            <p className="whitespace-pre-wrap [overflow-wrap:anywhere]">{content}</p>
          ) : (
            <MarkdownRenderer content={content} />
          )}

          {attachments && attachments.length > 0 && (
            <AttachmentDisplay attachments={attachments} />
          )}
        </div>
      </div>
    </div>
  );
}

function ToolStatusChip({ label }: { label: string }) {
  return (
    <div className="flex items-center gap-2 py-0.5">
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-500" />
      <span className="text-sm text-neutral-400">{label}</span>
    </div>
  );
}

function ReviewGateCard({
  gateId,
  question,
  options,
  header,
  descriptions,
  stepProgress,
  resolved,
  selectedOption,
  gateError,
  onSelect,
}: {
  gateId: string;
  question: string;
  options: string[];
  header?: string;
  descriptions?: Record<string, string | undefined>;
  stepProgress?: { current: number; total: number };
  resolved?: boolean;
  selectedOption?: string;
  gateError?: string;
  onSelect: (gateId: string, selection: string) => void;
}) {
  const [pending, setPending] = useState<string | null>(null);

  function handleSelect(option: string) {
    if (pending || resolved) return;
    setPending(option);
    onSelect(gateId, option);
  }

  // Reset pending state when error arrives (allow retry)
  useEffect(() => {
    if (gateError) setPending(null);
  }, [gateError]);

  // Collapsed summary after resolution
  if (resolved && selectedOption) {
    return (
      <div className="flex items-center gap-2 rounded-lg border border-neutral-800 bg-neutral-900/50 px-4 py-2 text-sm text-neutral-400 transition-all duration-300">
        <svg className="h-4 w-4 text-green-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="20 6 9 17 4 12" />
        </svg>
        <span>Selected: <strong className="text-neutral-200">{selectedOption}</strong></span>
      </div>
    );
  }

  return (
    <div role="group" aria-label={question} aria-busy={pending !== null} className="rounded-xl border border-amber-800/50 bg-amber-950/30 p-5">
      {stepProgress && stepProgress.total > 0 && (() => {
        const pct = Math.round((stepProgress.current / stepProgress.total) * 100);
        return (
          <div className="mb-3">
            <div className="mb-1 flex items-center justify-between text-xs text-amber-300">
              <span>Step {stepProgress.current} of {stepProgress.total}</span>
              <span className="text-amber-400/60">{pct}%</span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-amber-900/40">
              <div
                className="h-full rounded-full bg-amber-500 transition-all duration-500"
                style={{ width: `${pct}%` }}
              />
            </div>
          </div>
        );
      })()}
      {header && (
        <span className="mb-2 inline-block rounded-md bg-amber-900/50 px-2 py-0.5 text-xs font-medium text-amber-300">
          {header}
        </span>
      )}
      <div className="mb-1 flex items-start gap-2">
        <svg className="mt-0.5 h-4 w-4 shrink-0 text-amber-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="10" />
          <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" />
          <line x1="12" y1="17" x2="12.01" y2="17" />
        </svg>
        <p className="text-base font-medium text-amber-200">{question}</p>
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        {options.map((option) => (
          <button
            key={option}
            onClick={() => handleSelect(option)}
            disabled={pending !== null}
            className={`flex flex-col items-start rounded-lg border px-4 py-2 text-sm transition-colors ${
              pending === option
                ? "border-amber-500 bg-amber-900/50 text-amber-100"
                : pending !== null
                  ? "border-neutral-700 text-neutral-500 opacity-50"
                  : "border-neutral-700 text-neutral-300 hover:border-amber-600 hover:text-amber-200"
            }`}
          >
            <span>{option}</span>
            {descriptions?.[option] && (
              <span className="mt-0.5 text-xs text-neutral-400">{descriptions[option]}</span>
            )}
          </button>
        ))}
      </div>
      {gateError && (
        <p role="alert" className="mt-2 text-sm text-red-400">{gateError}</p>
      )}
    </div>
  );
}

function StatusIndicator({
  status,
  disconnectReason,
}: {
  status: "connecting" | "connected" | "reconnecting" | "disconnected";
  disconnectReason?: string;
}) {
  const config = {
    connecting: { color: "bg-yellow-500", label: "Connecting" },
    connected: { color: "bg-green-500", label: "Connected" },
    reconnecting: { color: "bg-yellow-500", label: "Reconnecting" },
    disconnected: { color: "bg-red-500", label: "Disconnected" },
  };

  const { color, label } = config[status];

  return (
    <div className="flex items-center gap-2">
      <span className={`h-2 w-2 rounded-full ${color}`} />
      <span className="text-xs text-neutral-500">
        {status === "disconnected" && disconnectReason ? disconnectReason : label}
      </span>
    </div>
  );
}
