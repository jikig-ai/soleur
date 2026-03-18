"use client";

import { useState, useRef, useEffect } from "react";
import { useParams, useSearchParams } from "next/navigation";
import { useWebSocket } from "@/lib/ws-client";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { DomainLeaderId } from "@/server/domain-leaders";

export default function ChatPage() {
  const params = useParams<{ conversationId: string }>();
  const searchParams = useSearchParams();
  const conversationId = params.conversationId;
  const leaderId = searchParams.get("leader") as DomainLeaderId | null;

  const { messages, startSession, sendMessage, sendReviewGateResponse, status } =
    useWebSocket(conversationId);

  const [input, setInput] = useState("");
  const [sessionStarted, setSessionStarted] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const leader = DOMAIN_LEADERS.find((l) => l.id === leaderId);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  // Start session when connection is established for a new conversation
  useEffect(() => {
    if (
      status === "connected" &&
      conversationId === "new" &&
      leaderId &&
      !sessionStarted
    ) {
      startSession(leaderId);
      setSessionStarted(true);
    }
  }, [status, conversationId, leaderId, sessionStarted, startSession]);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = input.trim();
    if (!trimmed || status !== "connected") return;
    sendMessage(trimmed);
    setInput("");
  }

  return (
    <div className="flex h-full flex-col">
      {/* Top bar */}
      <header className="flex shrink-0 items-center justify-between border-b border-neutral-800 px-6 py-3">
        <div className="flex items-center gap-3">
          {leader && (
            <>
              <span className="text-sm font-semibold text-white">
                {leader.name}
              </span>
              <span className="text-sm text-neutral-500">{leader.title}</span>
            </>
          )}
          {!leader && (
            <span className="text-sm text-neutral-500">Chat</span>
          )}
        </div>
        <StatusIndicator status={status} />
      </header>

      {/* Message list */}
      <div className="flex-1 overflow-y-auto px-6 py-4">
        {messages.length === 0 && (
          <div className="flex h-full items-center justify-center">
            <p className="text-sm text-neutral-600">
              {leader
                ? `Start a conversation with ${leader.name}`
                : "Send a message to get started"}
            </p>
          </div>
        )}

        <div className="mx-auto max-w-3xl space-y-4">
          {messages.map((msg) => (
            <div key={msg.id}>
              {msg.type === "review_gate" ? (
                <ReviewGateCard
                  gateId={msg.gateId!}
                  question={msg.question!}
                  options={msg.options!}
                  onSelect={sendReviewGateResponse}
                />
              ) : (
                <MessageBubble role={msg.role} content={msg.content} />
              )}
            </div>
          ))}
          <div ref={messagesEndRef} />
        </div>
      </div>

      {/* Input bar */}
      <div className="shrink-0 border-t border-neutral-800 bg-neutral-950 px-6 py-4">
        <form
          onSubmit={handleSubmit}
          className="mx-auto flex max-w-3xl items-center gap-3"
        >
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder={
              status === "connected"
                ? "Type a message..."
                : "Reconnecting..."
            }
            disabled={status !== "connected"}
            className="flex-1 rounded-lg border border-neutral-700 bg-neutral-900 px-4 py-3 text-sm text-white placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none disabled:opacity-50"
          />
          <button
            type="submit"
            disabled={!input.trim() || status !== "connected"}
            className="rounded-lg bg-white px-5 py-3 text-sm font-medium text-black transition-colors hover:bg-neutral-200 disabled:opacity-50 disabled:hover:bg-white"
          >
            Send
          </button>
        </form>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Sub-components                                                     */
/* ------------------------------------------------------------------ */

function MessageBubble({
  role,
  content,
}: {
  role: "user" | "assistant";
  content: string;
}) {
  const isUser = role === "user";

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[80%] rounded-xl px-4 py-3 text-sm leading-relaxed ${
          isUser
            ? "bg-white text-black"
            : "bg-neutral-900 text-neutral-200 border border-neutral-800"
        }`}
      >
        <p className="whitespace-pre-wrap">{content}</p>
      </div>
    </div>
  );
}

function ReviewGateCard({
  gateId,
  question,
  options,
  onSelect,
}: {
  gateId: string;
  question: string;
  options: string[];
  onSelect: (gateId: string, selection: string) => void;
}) {
  const [selected, setSelected] = useState<string | null>(null);

  function handleSelect(option: string) {
    if (selected) return; // Already answered
    setSelected(option);
    onSelect(gateId, option);
  }

  return (
    <div className="rounded-xl border border-amber-800/50 bg-amber-950/30 p-5">
      <p className="mb-3 text-sm font-medium text-amber-200">{question}</p>
      <div className="flex flex-wrap gap-2">
        {options.map((option) => (
          <button
            key={option}
            onClick={() => handleSelect(option)}
            disabled={selected !== null}
            className={`rounded-lg border px-4 py-2 text-sm transition-colors ${
              selected === option
                ? "border-amber-500 bg-amber-900/50 text-amber-100"
                : selected !== null
                  ? "border-neutral-700 text-neutral-500 opacity-50"
                  : "border-neutral-700 text-neutral-300 hover:border-amber-600 hover:text-amber-200"
            }`}
          >
            {option}
          </button>
        ))}
      </div>
    </div>
  );
}

function StatusIndicator({
  status,
}: {
  status: "connecting" | "connected" | "reconnecting" | "disconnected";
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
      <span className="text-xs text-neutral-500">{label}</span>
    </div>
  );
}
