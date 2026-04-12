"use client";

import { useState, useRef, useEffect } from "react";
import { useParams, useSearchParams, useRouter, usePathname } from "next/navigation";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { useWebSocket } from "@/lib/ws-client";
import type { ConversationContext, AttachmentRef } from "@/lib/types";
import { ErrorCard } from "@/components/ui/error-card";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { LEADER_COLORS } from "@/components/chat/leader-colors";
import { ChatInput } from "@/components/chat/chat-input";
import { AtMentionDropdown } from "@/components/chat/at-mention-dropdown";
import { useTeamNames } from "@/hooks/use-team-names";
import { AttachmentDisplay } from "@/components/chat/attachment-display";

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
  } = useWebSocket(conversationId);

  const { names: customNames, getDisplayName } = useTeamNames();

  const [sessionStarted, setSessionStarted] = useState(false);
  const [initialMsgSent, setInitialMsgSent] = useState(false);
  const [sessionStartTimeout, setSessionStartTimeout] = useState(false);
  const [atQuery, setAtQuery] = useState("");
  const [atVisible, setAtVisible] = useState(false);
  const [atPosition, setAtPosition] = useState(0);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const insertRef = useRef<((text: string, replaceFrom: number) => void) | null>(null);

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

  // Start session when connected AND context is resolved (or not needed)
  useEffect(() => {
    if (status === "connected" && conversationId === "new" && !sessionStarted && !contextLoading) {
      startSession(leaderId ?? undefined, kbContext);
      setSessionStarted(true);
    }
  }, [status, conversationId, leaderId, sessionStarted, startSession, contextLoading, kbContext]);

  // Send initial message from ?msg= param after server confirms session
  useEffect(() => {
    if (sessionConfirmed && msgParam && !initialMsgSent) {
      sendMessage(msgParam);
      setInitialMsgSent(true);
      // Clean URL params to prevent duplicate sends on refresh
      router.replace(pathname, { scroll: false });
    }
  }, [sessionConfirmed, msgParam, initialMsgSent, sendMessage, router, pathname]);

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
                      resolved={msg.resolved}
                      selectedOption={msg.selectedOption}
                      gateError={msg.gateError}
                      onSelect={sendReviewGateResponse}
                  />
                ) : (
                  <MessageBubble
                    role={msg.role}
                    content={msg.content}
                    leaderId={msg.leaderId}
                    showFullTitle={!!isFirst}
                    isStreaming={!!msg.leaderId && activeLeaderIds.includes(msg.leaderId)}
                    getDisplayName={getDisplayName}
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
            onSelect={(id) => {
              setAtVisible(false);
              if (insertRef.current) {
                insertRef.current(`@${id}`, atPosition);
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
  isStreaming = false,
  getDisplayName,
  attachments,
}: {
  role: "user" | "assistant";
  content: string;
  leaderId?: DomainLeaderId;
  showFullTitle?: boolean;
  isStreaming?: boolean;
  getDisplayName?: (id: DomainLeaderId) => string;
  attachments?: AttachmentRef[];
}) {
  const isUser = role === "user";
  const leader = leaderId ? DOMAIN_LEADERS.find((l) => l.id === leaderId) : null;
  const colorClass = leaderId ? (LEADER_COLORS[leaderId] ?? "border-l-neutral-500") : "";

  const displayName = leaderId && getDisplayName ? getDisplayName(leaderId) : leader?.name;

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div className={`flex max-w-[90%] gap-3 md:max-w-[80%] ${isUser ? "flex-row-reverse" : ""}`}>
        {/* Leader avatar */}
        {leader && (
          <span
            className="mt-1 flex h-7 w-7 shrink-0 items-center justify-center overflow-hidden rounded-md"
            aria-label={`Soleur ${leaderId!.toUpperCase()}`}
          >
            <img
              src="/icons/soleur-logo-mark.png"
              alt=""
              width={28}
              height={28}
              className="h-full w-full object-cover"
            />
          </span>
        )}

        <div
          className={`rounded-xl px-4 py-3 text-sm leading-relaxed ${
            isUser
              ? "bg-neutral-800 text-neutral-100"
              : `bg-neutral-900 text-neutral-200 border border-neutral-800 ${leader ? `border-l-2 ${colorClass}` : ""}`
          }`}
        >
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
          {content === "" && role === "assistant" ? (
            <ThinkingDots />
          ) : isUser || isStreaming ? (
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

function ReviewGateCard({
  gateId,
  question,
  options,
  header,
  descriptions,
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
