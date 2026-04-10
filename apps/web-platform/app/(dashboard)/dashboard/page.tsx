"use client";

import { useState, useCallback, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useConversations } from "@/hooks/use-conversations";
import { useOnboarding } from "@/hooks/use-onboarding";
import { ConversationRow } from "@/components/inbox/conversation-row";
import { ErrorCard } from "@/components/ui/error-card";
import { STATUS_LABELS } from "@/lib/types";
import type { ConversationStatus } from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { DOMAIN_LEADERS, ROUTABLE_DOMAIN_LEADERS } from "@/server/domain-leaders";
import { LEADER_BG_COLORS } from "@/components/chat/leader-colors";

// ---------------------------------------------------------------------------
// Foundation card definitions
// ---------------------------------------------------------------------------

interface FoundationCard {
  id: string;
  title: string;
  leaderId: DomainLeaderId;
  kbPath: string;
  promptText: string;
  done: boolean;
}

const FOUNDATION_PATHS = [
  { id: "vision", title: "Vision", leaderId: "cpo" as DomainLeaderId, kbPath: "overview/vision.md", promptText: "" },
  { id: "brand", title: "Brand Identity", leaderId: "cmo" as DomainLeaderId, kbPath: "marketing/brand-guide.md", promptText: "Define the brand identity for my company — positioning, voice, and visual direction." },
  { id: "validation", title: "Business Validation", leaderId: "cpo" as DomainLeaderId, kbPath: "product/business-validation.md", promptText: "Run a business validation — market research, competitive landscape, and business model." },
  { id: "legal", title: "Legal Foundations", leaderId: "clo" as DomainLeaderId, kbPath: "legal/privacy-policy.md", promptText: "Set up legal foundations — privacy policy, terms of service, and recommended legal structure." },
] as const;

// ---------------------------------------------------------------------------
// TreeNode flattening (matches server/kb-reader.ts TreeNode interface)
// ---------------------------------------------------------------------------

interface TreeNode {
  name: string;
  type: "file" | "directory";
  path?: string;
  children?: TreeNode[];
}

function flattenTree(node: TreeNode, paths = new Set<string>()): Set<string> {
  if (node.type === "file" && node.path) paths.add(node.path);
  for (const child of node.children ?? []) flattenTree(child, paths);
  return paths;
}

// ---------------------------------------------------------------------------
// Static suggested prompts (shown when all foundations are complete)
// ---------------------------------------------------------------------------

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
  ...ROUTABLE_DOMAIN_LEADERS.map((l) => ({ value: l.id, label: l.name })),
];

export default function DashboardPage() {
  const router = useRouter();
  const { completeOnboarding } = useOnboarding();
  const [statusFilter, setStatusFilter] = useState<ConversationStatus | null>(null);
  const [domainFilter, setDomainFilter] = useState<DomainLeaderId | "general" | null>(null);

  const { conversations, loading, error, refetch } = useConversations({
    statusFilter,
    domainFilter,
  });

  // ---------------------------------------------------------------------------
  // KB state derivation (inline — extract if this grows)
  // ---------------------------------------------------------------------------

  const [kbLoading, setKbLoading] = useState(true);
  const [kbPaths, setKbPaths] = useState<Set<string>>(new Set());
  const [kbError, setKbError] = useState<"provisioning" | "error" | null>(null);

  useEffect(() => {
    let cancelled = false;

    fetch("/api/kb/tree")
      .then((res) => {
        if (res.status === 401) {
          router.push("/login");
          return null;
        }
        if (res.status === 503) {
          if (!cancelled) setKbError("provisioning");
          return null;
        }
        if (res.status === 404) {
          // No workspace / not connected — fall through to Command Center
          return null;
        }
        if (!res.ok) throw new Error(`KB tree: ${res.status}`);
        return res.json();
      })
      .then((data) => {
        if (cancelled) return;
        if (data?.tree) {
          setKbPaths(flattenTree(data.tree));
        }
        setKbLoading(false);
      })
      .catch(() => {
        if (!cancelled) {
          setKbError("error");
          setKbLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [router]);

  const visionExists = kbPaths.has("overview/vision.md");
  const foundationCards: FoundationCard[] = FOUNDATION_PATHS.map((f) => ({
    ...f,
    done: kbPaths.has(f.kbPath),
  }));
  const allFoundationsComplete = foundationCards.every((c) => c.done);

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

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

  const handleLeaderClick = useCallback(
    (leaderId: string) => {
      const params = new URLSearchParams();
      params.set("msg", `@${leaderId} `);
      router.push(`/dashboard/chat/new?${params.toString()}`);
    },
    [router],
  );

  const handleFirstRunSend = useCallback(
    (e: React.FormEvent<HTMLFormElement>) => {
      e.preventDefault();
      const form = e.currentTarget;
      const input = form.elements.namedItem("idea") as HTMLInputElement;
      const message = input?.value?.trim();
      if (!message) return;
      completeOnboarding();

      // Create vision.md server-side from the typed idea (fire-and-forget)
      fetch("/api/vision", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: message }),
      }).catch(() => { /* non-blocking — agent will create via tryCreateVision fallback */ });

      const params = new URLSearchParams();
      params.set("msg", message);
      router.push(`/dashboard/chat/new?${params.toString()}`);
    },
    [router, completeOnboarding],
  );

  const hasActiveFilter = statusFilter !== null || domainFilter !== null;

  // ---------------------------------------------------------------------------
  // Loading skeleton (shown while KB tree loads)
  // ---------------------------------------------------------------------------

  if (kbLoading) {
    return (
      <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10">
        <div className="mb-6 h-12 w-12 animate-pulse rounded-lg bg-amber-600/50" />
        <div className="mb-3 h-4 w-48 animate-pulse rounded bg-neutral-800" />
        <div className="mb-8 h-3 w-64 animate-pulse rounded bg-neutral-800" />
        <div className="h-[44px] w-full max-w-xl animate-pulse rounded-xl bg-neutral-800/50" />
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // Provisioning state (503 from KB tree)
  // ---------------------------------------------------------------------------

  if (kbError === "provisioning") {
    return (
      <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10">
        <div className="mb-6 h-12 w-12 animate-pulse rounded-lg bg-amber-600/50" />
        <p className="text-sm text-neutral-400">Setting up your workspace...</p>
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // First-run state (no vision.md, no conversations)
  // ---------------------------------------------------------------------------

  if (!kbError && !visionExists && conversations.length === 0 && !hasActiveFilter) {
    return (
      <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10">
        <p className="mb-3 text-xs font-medium tracking-widest text-amber-500">
          COMMAND CENTER
        </p>
        <h1 className="mb-3 text-center text-3xl font-semibold text-white md:text-4xl">
          Tell your organization what you&apos;re building.
        </h1>
        <p className="mb-10 max-w-md text-center text-sm text-neutral-400">
          Describe your startup idea and your AI organization will get to work.
        </p>

        <form onSubmit={handleFirstRunSend} className="w-full max-w-xl">
          <div className="flex items-end gap-2">
            <input
              name="idea"
              type="text"
              placeholder="What are you building?"
              autoFocus
              className="flex-1 rounded-xl border border-neutral-700 bg-neutral-900 px-4 py-3 text-sm text-white placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none"
            />
            <button
              type="submit"
              className="flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-xl bg-amber-600 text-white transition-colors hover:bg-amber-500"
              aria-label="Send message"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="12" y1="19" x2="12" y2="5" />
                <polyline points="5 12 12 5 19 12" />
              </svg>
            </button>
          </div>
        </form>
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // Foundations state (vision exists, not all foundations complete)
  // ---------------------------------------------------------------------------

  if (!kbError && visionExists && !allFoundationsComplete) {
    return (
      <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10">
        <p className="mb-3 text-xs font-medium tracking-widest text-amber-500">
          FOUNDATIONS
        </p>
        <h1 className="mb-3 text-center text-3xl font-semibold text-white md:text-4xl">
          Build the foundations.
        </h1>
        <p className="mb-8 text-center text-sm text-neutral-400">
          Each card briefs a department leader. Complete them in any order.
        </p>

        {/* Foundation cards */}
        <div className="mb-10 grid w-full grid-cols-2 gap-3 md:grid-cols-4">
          {foundationCards.map((card) =>
            card.done ? (
              <a
                key={card.id}
                href={`/dashboard/kb/${card.kbPath}`}
                className="flex flex-col gap-2 rounded-xl border border-neutral-800/50 bg-neutral-900/30 p-4 text-left transition-colors hover:border-neutral-700"
              >
                <span className="text-lg text-green-500" aria-label="Complete">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M20 6 9 17l-5-5" />
                  </svg>
                </span>
                <span className="text-sm font-medium text-neutral-400">
                  {card.title}
                </span>
                <span className="text-xs text-neutral-600">
                  View in Knowledge Base
                </span>
              </a>
            ) : (
              <button
                key={card.id}
                type="button"
                onClick={() => handlePromptClick(card.promptText)}
                className="flex flex-col gap-2 rounded-xl border border-neutral-800 bg-neutral-900/50 p-4 text-left transition-colors hover:border-neutral-600"
              >
                <span
                  className={`flex h-5 w-5 items-center justify-center rounded text-[10px] font-semibold text-white ${LEADER_BG_COLORS[card.leaderId]}`}
                >
                  {card.leaderId.toUpperCase()}
                </span>
                <span className="text-sm font-medium text-white">
                  {card.title}
                </span>
                <span className="text-xs text-neutral-500">
                  {card.promptText}
                </span>
              </button>
            ),
          )}
        </div>

        {/* New conversation button */}
        <button
          type="button"
          onClick={() => router.push("/dashboard/chat/new")}
          className="mb-10 rounded-lg bg-gradient-to-r from-[#D4B36A] to-[#B8923E] px-6 py-3 text-sm font-semibold text-white transition-opacity hover:opacity-90"
        >
          New conversation
        </button>

        <LeaderStrip onLeaderClick={handleLeaderClick} />
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // Command Center — empty state (all foundations complete, no conversations)
  // Show immediately once KB state is known — don't block on conversation
  // loading. If conversations load later and are non-empty, React re-renders
  // into the inbox view below. This prevents the Supabase client initialisation
  // (navigator locks, Realtime WebSocket) from keeping users on a skeleton.
  // ---------------------------------------------------------------------------

  if (conversations.length === 0 && !hasActiveFilter) {
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
                    {ROUTABLE_DOMAIN_LEADERS.find((l) => l.id === id)?.name}
                  </span>
                ))}
              </div>
            </button>
          ))}
        </div>

        <LeaderStrip onLeaderClick={handleLeaderClick} />
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // Command Center — inbox (conversations exist)
  // ---------------------------------------------------------------------------

  return (
    <div className="mx-auto max-w-4xl px-4 py-6 md:py-8">
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-white md:text-2xl">
          Command Center
        </h1>
        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-neutral-800 text-xs font-medium text-neutral-300">
          <UserIcon className="h-4 w-4" />
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

function LeaderStrip({ onLeaderClick }: { onLeaderClick: (leaderId: string) => void }) {
  return (
    <>
      <p className="mb-4 text-xs font-medium tracking-widest text-neutral-400">
        YOUR ORGANIZATION
      </p>
      <div className="flex flex-wrap justify-center gap-3">
        {ROUTABLE_DOMAIN_LEADERS.map((leader) => (
          <button
            key={leader.id}
            type="button"
            onClick={() => onLeaderClick(leader.id)}
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
    </>
  );
}

function UserIcon({ className }: { className?: string }) {
  return (
    <svg className={className} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
    </svg>
  );
}
