"use client";

import { useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { useConversations } from "@/hooks/use-conversations";
import { ConversationRow } from "@/components/inbox/conversation-row";
import { ErrorCard } from "@/components/ui/error-card";
import { STATUS_LABELS } from "@/lib/types";
import type { ConversationStatus } from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import { LEADER_BG_COLORS } from "@/components/chat/leader-colors";

const SUGGESTED_PROMPTS = [
  {
    icon: "📊",
    title: "Review my go-to-market strategy",
    leaders: ["cmo", "cro"] as DomainLeaderId[],
  },
  {
    icon: "📋",
    title: "Draft a privacy policy for my SaaS",
    leaders: ["clo", "cpo"] as DomainLeaderId[],
  },
  {
    icon: "💰",
    title: "Plan Q2 budget and runway",
    leaders: ["cfo", "coo"] as DomainLeaderId[],
  },
  {
    icon: "🗺️",
    title: "Prioritize my product roadmap",
    leaders: ["cpo", "cto"] as DomainLeaderId[],
  },
];

const STATUS_OPTIONS: { value: ConversationStatus | ""; label: string }[] = [
  { value: "", label: "All statuses" },
  { value: "waiting_for_user", label: STATUS_LABELS.waiting_for_user },
  { value: "active", label: STATUS_LABELS.active },
  { value: "completed", label: STATUS_LABELS.completed },
  { value: "failed", label: STATUS_LABELS.failed },
];

const DOMAIN_OPTIONS: { value: string; label: string }[] = [
  { value: "", label: "All domains" },
  { value: "general", label: "General" },
  ...DOMAIN_LEADERS.map((l) => ({ value: l.id, label: l.name })),
];

export default function DashboardPage() {
  const router = useRouter();
  const [statusFilter, setStatusFilter] = useState<ConversationStatus | null>(null);
  const [domainFilter, setDomainFilter] = useState<DomainLeaderId | "general" | null>(null);

  const { conversations, loading, error, refetch } = useConversations({
    statusFilter,
    domainFilter,
  });

  const handleStatusChange = useCallback((e: React.ChangeEvent<HTMLSelectElement>) => {
    setStatusFilter(e.target.value ? (e.target.value as ConversationStatus) : null);
  }, []);

  const handleDomainChange = useCallback((e: React.ChangeEvent<HTMLSelectElement>) => {
    const val = e.target.value;
    setDomainFilter(val ? (val as DomainLeaderId | "general") : null);
  }, []);

  const clearFilters = useCallback(() => {
    setStatusFilter(null);
    setDomainFilter(null);
  }, []);

  const handlePromptClick = useCallback(
    (promptText: string) => {
      const params = new URLSearchParams();
      params.set("msg", promptText);
      router.push(`/dashboard/chat/new?${params.toString()}`);
    },
    [router],
  );

  const hasActiveFilter = statusFilter !== null || domainFilter !== null;

  // Empty state: show suggested prompts + leader strip (preserves onboarding)
  if (!loading && !error && conversations.length === 0 && !hasActiveFilter) {
    return (
      <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10">
        <p className="mb-3 text-xs font-medium tracking-widest text-amber-500">
          COMMAND CENTER
        </p>
        <h1 className="mb-3 text-center text-3xl font-semibold text-white md:text-4xl">
          Your organization is ready.
        </h1>
        <p className="mb-8 text-center text-sm text-neutral-400">
          Start a conversation to put your agents to work.
        </p>

        <button
          type="button"
          onClick={() => router.push("/dashboard/chat/new")}
          className="mb-10 rounded-lg bg-gradient-to-r from-[#D4B36A] to-[#B8923E] px-6 py-3 text-sm font-semibold text-white transition-opacity hover:opacity-90"
        >
          New conversation
        </button>

        {/* Suggested prompts */}
        <div className="mb-10 grid w-full grid-cols-2 gap-3 md:grid-cols-4">
          {SUGGESTED_PROMPTS.map((prompt) => (
            <button
              key={prompt.title}
              type="button"
              onClick={() => handlePromptClick(prompt.title)}
              className="flex flex-col gap-2 rounded-xl border border-neutral-800 bg-neutral-900/50 p-4 text-left transition-colors hover:border-neutral-600"
            >
              <span className="text-lg">{prompt.icon}</span>
              <span className="text-sm font-medium text-white">
                {prompt.title}
              </span>
              <div className="flex gap-1">
                {prompt.leaders.map((id) => (
                  <span key={id} className="text-xs text-neutral-500">
                    {DOMAIN_LEADERS.find((l) => l.id === id)?.name}
                  </span>
                ))}
              </div>
            </button>
          ))}
        </div>

        {/* Leader strip */}
        <p className="mb-4 text-xs font-medium tracking-widest text-neutral-400">
          YOUR ORGANIZATION
        </p>
        <div className="flex flex-wrap justify-center gap-3">
          {DOMAIN_LEADERS.map((leader) => (
            <button
              key={leader.id}
              type="button"
              onClick={() => {
                const params = new URLSearchParams();
                params.set("msg", `@${leader.id} `);
                router.push(`/dashboard/chat/new?${params.toString()}`);
              }}
              className="group flex items-center gap-1.5 rounded-lg px-2 py-1 transition-colors hover:bg-neutral-800/50"
            >
              <span
                className={`flex h-5 w-5 items-center justify-center rounded text-[10px] font-semibold text-white ${LEADER_BG_COLORS[leader.id]}`}
              >
                {leader.id.toUpperCase()}
              </span>
              <span className="text-xs text-neutral-500 group-hover:text-neutral-300">
                {leader.name}
              </span>
            </button>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-4xl px-4 py-6 md:py-8">
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-white md:text-2xl">
          Command Center
        </h1>
        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-neutral-800 text-xs font-medium text-neutral-300">
          {conversations.length > 0 ? conversations[0].user_id?.slice(0, 2).toUpperCase() : ""}
        </div>
      </div>

      {/* Filter bar */}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <select
          value={statusFilter ?? ""}
          onChange={handleStatusChange}
          className={`min-h-[44px] rounded-lg border px-3 py-2 text-sm transition-colors ${
            statusFilter
              ? "border-amber-500/50 bg-neutral-900 text-amber-500"
              : "border-neutral-700 bg-neutral-900 text-neutral-300"
          }`}
        >
          {STATUS_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>

        <select
          value={domainFilter ?? ""}
          onChange={handleDomainChange}
          className={`min-h-[44px] rounded-lg border px-3 py-2 text-sm transition-colors ${
            domainFilter
              ? "border-amber-500/50 bg-neutral-900 text-amber-500"
              : "border-neutral-700 bg-neutral-900 text-neutral-300"
          }`}
        >
          {DOMAIN_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>

        <div className="flex-1" />

        <button
          type="button"
          onClick={() => router.push("/dashboard/chat/new")}
          className="min-h-[44px] rounded-lg bg-gradient-to-r from-[#D4B36A] to-[#B8923E] px-4 py-2 text-sm font-semibold text-white transition-opacity hover:opacity-90"
        >
          + New conversation
        </button>
      </div>

      {/* Loading state */}
      {loading && (
        <div className="space-y-3">
          {[1, 2, 3, 4].map((i) => (
            <div
              key={i}
              className="animate-pulse rounded-lg border border-neutral-800 bg-neutral-900/50 p-4"
            >
              <div className="flex items-center gap-4">
                <div className="h-5 w-28 rounded-full bg-neutral-800" />
                <div className="h-4 w-48 rounded bg-neutral-800" />
                <div className="flex-1" />
                <div className="h-7 w-7 rounded-md bg-neutral-800" />
                <div className="h-4 w-16 rounded bg-neutral-800" />
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Error state */}
      {error && (
        <ErrorCard
          title="Failed to load conversations"
          message={error}
          onRetry={refetch}
        />
      )}

      {/* Filtered empty state */}
      {!loading && !error && conversations.length === 0 && hasActiveFilter && (
        <div className="flex flex-col items-center justify-center py-20">
          <p className="mb-4 text-sm text-neutral-400">
            No conversations match your filters.
          </p>
          <button
            type="button"
            onClick={clearFilters}
            className="rounded-lg border border-neutral-700 px-4 py-2 text-sm text-neutral-300 transition-colors hover:bg-neutral-800"
          >
            Clear filters
          </button>
        </div>
      )}

      {/* Conversation list */}
      {!loading && !error && conversations.length > 0 && (
        <div className="space-y-2">
          {conversations.map((conv) => (
            <ConversationRow key={conv.id} conversation={conv} />
          ))}
        </div>
      )}
    </div>
  );
}
