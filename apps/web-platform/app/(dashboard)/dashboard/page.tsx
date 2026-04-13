"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useConversations } from "@/hooks/use-conversations";
import type { ArchiveFilter } from "@/hooks/use-conversations";
import { useOnboarding } from "@/hooks/use-onboarding";
import { ConversationRow } from "@/components/inbox/conversation-row";
import { ErrorCard } from "@/components/ui/error-card";
import { STATUS_LABELS } from "@/lib/types";
import { FOUNDATION_MIN_CONTENT_BYTES } from "@/lib/kb-constants";
import { validateFiles } from "@/lib/validate-files";
import { setPendingFiles } from "@/lib/pending-attachments";
import type { ConversationStatus } from "@/lib/types";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { DOMAIN_LEADERS, ROUTABLE_DOMAIN_LEADERS } from "@/server/domain-leaders";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface FirstRunAttachment {
  id: string;
  file: File;
  preview?: string;
}

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
  size?: number;
  children?: TreeNode[];
}

interface FileInfo {
  size?: number;
}

function flattenTree(
  node: TreeNode,
  files = new Map<string, FileInfo>(),
): Map<string, FileInfo> {
  if (node.type === "file" && node.path) {
    files.set(node.path, { size: node.size });
  }
  for (const child of node.children ?? []) flattenTree(child, files);
  return files;
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
  ...ROUTABLE_DOMAIN_LEADERS.map((l) => ({ value: l.id, label: l.domain })),
];

export default function DashboardPage() {
  const router = useRouter();
  const { completeOnboarding } = useOnboarding();
  const [statusFilter, setStatusFilter] = useState<ConversationStatus | null>(null);
  const [domainFilter, setDomainFilter] = useState<DomainLeaderId | "general" | null>(null);
  const [archiveFilter, setArchiveFilter] = useState<ArchiveFilter>("active");

  const { conversations, loading, error, refetch, archiveConversation, unarchiveConversation, updateStatus } = useConversations({
    statusFilter,
    domainFilter,
    archiveFilter,
  });

  // ---------------------------------------------------------------------------
  // KB state derivation (inline — extract if this grows)
  // ---------------------------------------------------------------------------

  const [kbLoading, setKbLoading] = useState(true);
  const [kbFiles, setKbFiles] = useState<Map<string, FileInfo>>(new Map());
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
          setKbFiles(flattenTree(data.tree));
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

  const visionExists = kbFiles.has("overview/vision.md");
  const foundationCards: FoundationCard[] = FOUNDATION_PATHS.map((f) => ({
    ...f,
    done:
      kbFiles.has(f.kbPath) &&
      (kbFiles.get(f.kbPath)?.size ?? 0) >= FOUNDATION_MIN_CONTENT_BYTES,
  }));
  const allFoundationsComplete = foundationCards.every((c) => c.done);

  // ---------------------------------------------------------------------------
  // First-run attachment state
  // ---------------------------------------------------------------------------

  const [firstRunAttachments, setFirstRunAttachments] = useState<FirstRunAttachment[]>([]);
  const [attachError, setAttachError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isDragOver, setIsDragOver] = useState(false);

  const validateAndAddFiles = useCallback(
    (files: FileList | File[]) => {
      const { valid, error } = validateFiles(files, firstRunAttachments.length);

      if (error) setAttachError(error);
      if (valid.length > 0) {
        setFirstRunAttachments((prev) => [
          ...prev,
          ...valid.map((file) => ({
            id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
            file,
            preview: file.type.startsWith("image/") ? URL.createObjectURL(file) : undefined,
          })),
        ]);
        setAttachError(null);
      }
    },
    [firstRunAttachments.length],
  );

  const removeFirstRunAttachment = useCallback((id: string) => {
    setFirstRunAttachments((prev) => {
      const item = prev.find((a) => a.id === id);
      if (item?.preview) URL.revokeObjectURL(item.preview);
      return prev.filter((a) => a.id !== id);
    });
  }, []);

  // Revoke preview URLs on unmount
  useEffect(() => {
    return () => {
      firstRunAttachments.forEach((a) => {
        if (a.preview) URL.revokeObjectURL(a.preview);
      });
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- cleanup only on unmount
  }, []);

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
    setArchiveFilter("active");
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
      if (!message && firstRunAttachments.length === 0) return;
      completeOnboarding();

      // Store pending files for the chat page to upload after conversation creation
      if (firstRunAttachments.length > 0) {
        setPendingFiles(firstRunAttachments.map((a) => a.file));
        // Revoke preview URLs — the files are now in the singleton
        firstRunAttachments.forEach((a) => {
          if (a.preview) URL.revokeObjectURL(a.preview);
        });
      }

      // Create vision.md server-side from the typed idea (fire-and-forget)
      if (message) {
        fetch("/api/vision", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ content: message }),
        }).catch(() => { /* non-blocking — agent will create via tryCreateVision fallback */ });
      }

      const params = new URLSearchParams();
      if (message) params.set("msg", message);
      router.push(`/dashboard/chat/new?${params.toString()}`);
    },
    [router, completeOnboarding, firstRunAttachments],
  );

  const hasActiveFilter = statusFilter !== null || domainFilter !== null || archiveFilter !== "active";

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

        <form
          onSubmit={handleFirstRunSend}
          className={`w-full max-w-xl ${isDragOver ? "rounded-2xl border-2 border-dashed border-amber-500 bg-amber-500/10 p-2" : ""}`}
          onDragOver={(e) => { e.preventDefault(); setIsDragOver(true); }}
          onDragLeave={() => setIsDragOver(false)}
          onDrop={(e) => {
            e.preventDefault();
            setIsDragOver(false);
            if (e.dataTransfer.files.length > 0) validateAndAddFiles(e.dataTransfer.files);
          }}
        >
          {/* Attachment preview strip */}
          {firstRunAttachments.length > 0 && (
            <div className="mb-2 flex flex-wrap gap-2">
              {firstRunAttachments.map((att) => (
                <div
                  key={att.id}
                  className="flex items-center gap-1.5 rounded-lg border border-neutral-700 bg-neutral-800 px-2 py-1.5"
                >
                  {att.preview ? (
                    <img
                      src={att.preview}
                      alt=""
                      className="h-8 w-8 rounded object-cover"
                    />
                  ) : (
                    <svg className="h-4 w-4 text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
                    </svg>
                  )}
                  <span className="max-w-[120px] truncate text-xs text-neutral-300">{att.file.name}</span>
                  <button
                    type="button"
                    onClick={() => removeFirstRunAttachment(att.id)}
                    className="ml-1 text-neutral-500 hover:text-white"
                    aria-label={`Remove ${att.file.name}`}
                  >
                    <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M6 18 18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>
              ))}
            </div>
          )}

          {/* Error message */}
          {attachError && (
            <p className="mb-2 text-xs text-red-400">{attachError}</p>
          )}

          <div className="flex items-center gap-3">
            {/* Paperclip / attach button */}
            <button
              type="button"
              onClick={() => fileInputRef.current?.click()}
              className="flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-xl border border-neutral-700 text-neutral-400 transition-colors hover:border-neutral-500 hover:text-white"
              aria-label="Attach files"
            >
              <svg className="h-[18px] w-[18px]" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="m18.375 12.739-7.693 7.693a4.5 4.5 0 0 1-6.364-6.364l10.94-10.94A3 3 0 1 1 19.5 7.372L8.552 18.32m.009-.01-.01.01m5.699-9.941-7.81 7.81a1.5 1.5 0 0 0 2.112 2.13" />
              </svg>
            </button>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/png,image/jpeg,image/gif,image/webp,application/pdf"
              multiple
              className="hidden"
              onChange={(e) => {
                if (e.target.files) validateAndAddFiles(e.target.files);
                e.target.value = "";
              }}
            />

            <input
              name="idea"
              type="text"
              placeholder="What are you building?"
              autoFocus
              className="min-h-[44px] flex-1 rounded-xl border border-neutral-700 bg-neutral-900 px-4 py-3 text-sm text-white placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none"
              onPaste={(e) => {
                const files = Array.from(e.clipboardData.files);
                if (files.length > 0) {
                  e.preventDefault();
                  validateAndAddFiles(files);
                }
              }}
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
  // Command Center — empty state (no conversations, no active filters)
  // Shows foundation cards at top when incomplete, then empty conversation
  // placeholder or suggested prompts depending on foundation status.
  // ---------------------------------------------------------------------------

  if (conversations.length === 0 && !hasActiveFilter) {
    return (
      <div className={`mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center px-4 py-10 ${visionExists && !allFoundationsComplete ? "pt-10" : "justify-center"}`}>
        {/* Foundation cards (only when incomplete) */}
        {visionExists && !allFoundationsComplete && (
          <div className="mb-10 w-full">
            <p className="mb-2 text-xs font-medium tracking-widest text-amber-500">
              FOUNDATIONS
            </p>
            <p className="mb-4 text-sm text-neutral-400">
              Complete these to brief your department leaders.
            </p>
            <div className="grid w-full grid-cols-2 gap-3 md:grid-cols-4">
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
                      className="flex h-5 w-5 items-center justify-center overflow-hidden rounded"
                      aria-label={`Soleur ${card.leaderId.toUpperCase()}`}
                    >
                      <img
                        src="/icons/soleur-logo-mark.png"
                        alt=""
                        width={20}
                        height={20}
                        className="h-full w-full object-cover"
                      />
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
          </div>
        )}

        <p className="mb-3 text-xs font-medium tracking-widest text-amber-500">
          COMMAND CENTER
        </p>
        <h1 className="mb-3 text-center text-3xl font-semibold text-white md:text-4xl">
          {allFoundationsComplete
            ? "Your organization is ready."
            : "No conversations yet."}
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

        {/* Suggested prompts (only when all foundations complete) */}
        {allFoundationsComplete && (
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
        )}

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

      {/* Foundation cards (only when incomplete) */}
      {visionExists && !allFoundationsComplete && (
        <div className="mb-6">
          <p className="mb-2 text-xs font-medium tracking-widest text-amber-500">
            FOUNDATIONS
          </p>
          <p className="mb-4 text-sm text-neutral-400">
            Complete these to brief your department leaders.
          </p>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
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
                    className="flex h-5 w-5 items-center justify-center overflow-hidden rounded"
                    aria-label={`Soleur ${card.leaderId.toUpperCase()}`}
                  >
                    <img
                      src="/icons/soleur-logo-mark.png"
                      alt=""
                      width={20}
                      height={20}
                      className="h-full w-full object-cover"
                    />
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
        </div>
      )}

      {/* Filter bar */}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        {/* Archive toggle */}
        <div className="flex rounded-lg border border-neutral-700 overflow-hidden">
          <button
            type="button"
            onClick={() => setArchiveFilter("active")}
            className={`min-h-[44px] px-3 py-2 text-sm font-medium transition-colors ${
              archiveFilter === "active"
                ? "bg-neutral-700 text-white"
                : "bg-neutral-900 text-neutral-400 hover:text-neutral-300"
            }`}
          >
            Active
          </button>
          <button
            type="button"
            onClick={() => setArchiveFilter("archived")}
            className={`min-h-[44px] px-3 py-2 text-sm font-medium transition-colors ${
              archiveFilter === "archived"
                ? "bg-neutral-700 text-white"
                : "bg-neutral-900 text-neutral-400 hover:text-neutral-300"
            }`}
          >
            Archived
          </button>
        </div>

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
            <ConversationRow
              key={conv.id}
              conversation={conv}
              onArchive={archiveConversation}
              onUnarchive={unarchiveConversation}
              onStatusChange={updateStatus}
            />
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
              className="flex h-5 w-5 items-center justify-center overflow-hidden rounded"
              aria-label={`Soleur ${leader.id.toUpperCase()}`}
            >
              <img
                src="/icons/soleur-logo-mark.png"
                alt=""
                width={20}
                height={20}
                className="h-full w-full object-cover"
              />
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
