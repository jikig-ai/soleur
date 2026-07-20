"use client";

import { useState, useCallback, useEffect, useMemo, useRef } from "react";
import { useRouter } from "next/navigation";
import useSWR from "swr";
import { createClient } from "@/lib/supabase/client";
import { swrKeys, jsonFetcher } from "@/lib/swr-config";
import { isRevocationBounce } from "@/lib/auth/revocation-bounce";
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
import { ROUTABLE_DOMAIN_LEADERS } from "@/server/domain-leaders";
import { LeaderAvatar } from "@/components/leader-avatar";
import { FoundationSection } from "@/components/dashboard/foundation-section";
import type { FoundationCard } from "@/components/dashboard/foundation-cards";
import { useTeamNames } from "@/hooks/use-team-names";
import { TodayBanner } from "@/components/dashboard/today-banner";
import { RuntimeExplainerBanner } from "@/components/dashboard/runtime-explainer-banner";
import { TodayCard } from "@/components/dashboard/today-card";

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

const FOUNDATION_PATHS = [
  { id: "vision", title: "Vision", leaderId: "cpo" as DomainLeaderId, kbPath: "overview/vision.md", promptText: "" },
  { id: "brand", title: "Brand Identity", leaderId: "cmo" as DomainLeaderId, kbPath: "marketing/brand-guide.md", promptText: "Define the brand identity for my company — positioning, voice, and visual direction." },
  { id: "validation", title: "Business Validation", leaderId: "cpo" as DomainLeaderId, kbPath: "product/business-validation.md", promptText: "Run a business validation — market research, competitive landscape, and business model." },
  { id: "legal", title: "Legal Foundations", leaderId: "clo" as DomainLeaderId, kbPath: "legal/privacy-policy.md", promptText: "Set up legal foundations — privacy policy, terms of service, and recommended legal structure." },
] as const;

// ---------------------------------------------------------------------------
// Foundation status (existence + size for the KNOWN foundation KB paths)
// ---------------------------------------------------------------------------

interface PathStat {
  exists: boolean;
  size: number;
}

// ADR-067: the dashboard derives foundation-card completion only from a KNOWN
// set of KB paths, so it fetches /api/dashboard/foundation-status (a targeted
// stat) instead of the whole-KB-tree walk (/api/kb/tree buildTree()) that used
// to gate first paint. It caches under its OWN key (NOT swrKeys.kbTree(), whose
// richer payload + distinct error mapping would cross-contaminate this
// consumer). Per-route instant warm render still holds.
const DASHBOARD_FOUNDATION_STATUS_KEY = [
  "/api/dashboard/foundation-status",
  "dashboard",
] as const;

// Carries the dashboard's foundation-status error states through SWR's single
// error channel (503 → "provisioning", everything else → "error"; 401 →
// "redirect" which holds the skeleton through the /login navigation rather than
// flashing an error/empty state; a 404 returns an empty map → no error).
class DashFoundationError extends Error {
  constructor(public kind: "provisioning" | "error" | "redirect") {
    super(kind);
    this.name = "DashFoundationError";
  }
}

// ---------------------------------------------------------------------------
// Operational tasks (shown progressively as foundations complete)
// ---------------------------------------------------------------------------

const OPERATIONAL_TASKS = [
  { id: "pricing", title: "Set pricing strategy", leaderId: "cmo" as DomainLeaderId, kbPath: "product/pricing-strategy.md", promptText: "Design a pricing strategy for my product — tiers, value metrics, and competitive positioning." },
  { id: "competitive", title: "Create competitive analysis", leaderId: "cpo" as DomainLeaderId, kbPath: "product/competitive-analysis.md", promptText: "Run a competitive analysis — identify key competitors, positioning gaps, and differentiation opportunities." },
  { id: "launch", title: "Plan marketing launch", leaderId: "cmo" as DomainLeaderId, kbPath: "marketing/launch-plan.md", promptText: "Create a marketing launch plan — channels, timeline, and messaging strategy." },
  { id: "hiring", title: "Define hiring plan", leaderId: "coo" as DomainLeaderId, kbPath: "operations/hiring-plan.md", promptText: "Build a hiring plan — roles needed, timeline, and budget." },
  { id: "distribution", title: "Build distribution strategy", leaderId: "cmo" as DomainLeaderId, kbPath: "marketing/distribution-strategy.md", promptText: "Design a distribution strategy — channels, partnerships, and growth loops." },
  { id: "financial", title: "Set up financial projections", leaderId: "cfo" as DomainLeaderId, kbPath: "finance/financial-projections.md", promptText: "Create financial projections — revenue model, burn rate, and runway forecast." },
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
  const {
    completeOnboarding,
    runtimeExplainerDismissed,
    dismissRuntimeExplainer,
    onboardingLoaded,
  } = useOnboarding();
  const [statusFilter, setStatusFilter] = useState<ConversationStatus | null>(null);
  const [domainFilter, setDomainFilter] = useState<DomainLeaderId | "general" | null>(null);
  const [archiveFilter, setArchiveFilter] = useState<ArchiveFilter>("active");

  const { getIconPath } = useTeamNames();

  const { conversations, loading, error, refetch, archiveConversation, unarchiveConversation, updateStatus } = useConversations({
    statusFilter,
    domainFilter,
    archiveFilter,
  });

  // Per-error dismissal of the "Failed to load conversations" card.
  // Edge-triggered on `error` value change so an identical re-fail re-shows it.
  const [conversationsErrorDismissed, setConversationsErrorDismissed] = useState(false);
  const prevErrorRef = useRef<string | null>(null);
  useEffect(() => {
    if (error !== prevErrorRef.current) {
      setConversationsErrorDismissed(false);
      prevErrorRef.current = error ?? null;
    }
  }, [error]);

  // ---------------------------------------------------------------------------
  // KB state derivation (inline — extract if this grows)
  // ---------------------------------------------------------------------------

  // ADR-067: cache the foundation status so returning to the dashboard renders
  // instantly. The skeleton gates on `foundationData === undefined && !err`
  // (GAP F) — a warm remount keeps it defined, so the skeleton never re-shows.
  // This is a targeted stat of ~10 known paths, not a whole-tree walk, so it
  // resolves far faster than the old /api/kb/tree buildTree() consumer.
  const fetchFoundationStatus = useCallback(async (): Promise<{
    paths: Record<string, PathStat>;
  }> => {
    const res = await fetch("/api/dashboard/foundation-status");
    // GAP F (ADR-067 staleTimes): a session-revocation bounce is a
    // principal-LEAVING boundary — HARD-nav to /login so the App Router Router
    // Cache is wiped (a soft push would leave the ejected principal's warm RSC
    // shells reachable). isRevocationBounce detects BOTH a direct 401 AND the
    // #4307 middleware 302→/login (which fetch follows to 200 HTML).
    if (isRevocationBounce(res)) {
      window.location.assign("/login");
      throw new DashFoundationError("redirect"); // navigating away — hold skeleton
    }
    if (res.status === 503) throw new DashFoundationError("provisioning");
    // 404 = no workspace / not connected — fall through to Command Center.
    if (res.status === 404) return { paths: {} };
    if (!res.ok) throw new DashFoundationError("error");
    const data = await res.json();
    return { paths: (data?.paths as Record<string, PathStat>) ?? {} };
  }, [router]);

  const { data: foundationData, error: foundationErr } = useSWR(
    DASHBOARD_FOUNDATION_STATUS_KEY,
    fetchFoundationStatus,
  );
  // 401 (kind "redirect") holds the skeleton through the /login navigation.
  const isRedirecting401 =
    foundationErr instanceof DashFoundationError && foundationErr.kind === "redirect";
  const kbLoading =
    foundationData === undefined && (foundationErr === undefined || isRedirecting401);
  const kbError: "provisioning" | "error" | null =
    foundationErr instanceof DashFoundationError
      ? foundationErr.kind === "redirect"
        ? null
        : foundationErr.kind
      : foundationErr
        ? "error"
        : null;
  const foundationPaths = useMemo<Record<string, PathStat>>(
    () => foundationData?.paths ?? {},
    [foundationData],
  );

  // Disconnected-with-orphans hint: when a user has disconnected their repo
  // but has pre-existing conversations tied to another repo_url, surface a
  // one-line hint so the empty Command Center doesn't read as data loss.
  // See plan 2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md
  // Product/UX Gate findings.
  // PR-F (#3244, #3940) Phase 5 — Today section: drafts from
  // /api/dashboard/today. Fetched on mount; mounted ABOVE the foundation
  // + inbox sections per plan §Phase 5. Empty array means "no drafts yet".
  interface TodayItem {
    id: string;
    source: string;
    sourceRef?: string | null;
    owningDomain: string;
    draftPreview: string;
    urgency: string;
  }
  // ADR-067: cached so the Today section renders instantly on dashboard return.
  // Silent on error (the banner still mounts); defaults to [] until resolved.
  const { data: todayItems = [] } = useSWR(
    swrKeys.dashboardToday(),
    async (): Promise<TodayItem[]> => {
      const res = await fetch("/api/dashboard/today");
      if (!res.ok) return [];
      const body = (await res.json()) as { items: TodayItem[] };
      return body.items ?? [];
    },
  );

  // feat-inbox-attention-badge: the email-triage "Needs attention" list was
  // removed from the Dashboard — those items now live in the Inbox, surfaced as
  // a count badge on the Inbox left-nav item (components/dashboard/
  // inbox-nav-badge.tsx). The Dashboard no longer fetches /api/inbox/emails.

  // ADR-044 (#4543): the repo-disconnected hint reflects the ACTIVE workspace's
  // repo (never the caller's own users.repo_url), so an invited member viewing a
  // connected workspace doesn't see a spurious hint. ADR-067: cached under
  // swrKeys.workspaceActiveRepo so the nudge renders instantly on return.
  const { data: activeRepo } = useSWR(
    swrKeys.workspaceActiveRepo(),
    jsonFetcher<{ repoUrl?: string | null }>,
  );
  // The hint fires ONLY once the active-repo fetch has resolved with NO repo
  // connected (a network/transient failure leaves activeRepo undefined → no
  // false hint).
  const noActiveRepo = activeRepo !== undefined && !activeRepo?.repoUrl;

  // Orphan count: a coarse "you have conversations from a repo connected in
  // ANOTHER of your workspaces — reconnect" nudge. Gated on noActiveRepo (null
  // key skips the query otherwise). INTENTIONALLY cross-workspace (scoping
  // audit, 2026-06-02): scoping to the active workspace would make it ~0 and
  // useless; it is the user's OWN non-sensitive row count (no content, no
  // cross-tenant data). Do not add a workspace_id filter without re-deriving
  // the nudge's purpose.
  const { data: orphanCount } = useSWR(
    noActiveRepo ? swrKeys.dashboardOrphanCount() : null,
    async (): Promise<number> => {
      const supabase = createClient();
      const { data: auth } = await supabase.auth.getUser();
      if (!auth.user) return 0;
      const { count } = await supabase
        .from("conversations")
        .select("id", { count: "exact", head: true })
        .eq("user_id", auth.user.id)
        .not("repo_url", "is", null);
      return count ?? 0;
    },
  );
  const repoDisconnected = noActiveRepo;
  const orphanedCount = orphanCount ?? 0;

  const visionExists = foundationPaths["overview/vision.md"]?.exists ?? false;
  const foundationCards: FoundationCard[] = FOUNDATION_PATHS.map((f) => ({
    ...f,
    done:
      (foundationPaths[f.kbPath]?.exists ?? false) &&
      (foundationPaths[f.kbPath]?.size ?? 0) >= FOUNDATION_MIN_CONTENT_BYTES,
  }));
  const operationalCards: FoundationCard[] = OPERATIONAL_TASKS.map((t) => ({
    ...t,
    done:
      (foundationPaths[t.kbPath]?.exists ?? false) &&
      (foundationPaths[t.kbPath]?.size ?? 0) >= FOUNDATION_MIN_CONTENT_BYTES,
  }));
  const allCards = [...foundationCards, ...operationalCards];
  const allTasksComplete = allCards.every((c) => c.done);

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
  // Initial loading skeleton
  // ---------------------------------------------------------------------------

  // Cold-start perf (#5654): the dashboard is gated on the CONVERSATION-LIST
  // load (the primary content), NOT on /api/kb/tree. The KB tree only drives
  // foundation-card completion checkmarks, yet it is the slow path on a cold
  // start — uncached (the service worker skips /api/*) and behind the
  // per-request middleware auth waterfall + a disk tree-walk. It now resolves
  // ASYNC while the rest of the page renders. The skeleton shows only when:
  //   (a) the conversation list is still doing its FIRST load (no rows yet) —
  //       a later filter-triggered refetch keeps prior rows, so the inbox
  //       view's own row-level skeleton handles it (no full-page blank); or
  //   (b) a kb-tree 401 is navigating to /login (isRedirecting401) — hold the
  //       skeleton through the redirect rather than flash dashboard chrome
  //       (TR2); or
  //   (c) the user has NO content yet (no conversations, no active filter) AND
  //       the KB tree is still loading — only THIS case needs the tree, to
  //       choose first-run vs. empty without flashing the wrong state (FR2).
  //       Users WITH conversations never wait on the tree.
  // Merge note: this condition originally also required `emailItems.length === 0`.
  // feat-inbox-attention-badge removed the email-triage list from the Dashboard
  // (those items now surface as a count badge on the Inbox left-nav item, and
  // this page no longer fetches /api/inbox/emails), so the clause is dropped
  // rather than ported — there is no Dashboard-side email state left to gate on.
  const showInitialSkeleton =
    (loading && conversations.length === 0) ||
    isRedirecting401 ||
    (conversations.length === 0 && !hasActiveFilter && kbLoading);

  if (showInitialSkeleton) {
    return (
      <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10">
        <div className="mb-6 h-12 w-12 animate-pulse rounded-lg bg-amber-600/50" />
        <div className="mb-3 h-4 w-48 animate-pulse rounded bg-soleur-bg-surface-2" />
        <div className="mb-8 h-3 w-64 animate-pulse rounded bg-soleur-bg-surface-2" />
        <div className="h-[44px] w-full max-w-xl animate-pulse rounded-xl bg-soleur-bg-surface-2/50" />
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // Provisioning state (503 from foundation status)
  // ---------------------------------------------------------------------------

  if (kbError === "provisioning") {
    return (
      <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10">
        <div className="mb-6 h-12 w-12 animate-pulse rounded-lg bg-amber-600/50" />
        <p className="text-sm text-soleur-text-secondary">Setting up your workspace...</p>
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // First-run state (no vision.md, no conversations)
  // ---------------------------------------------------------------------------

  // feat-inbox-attention-badge: this empty state no longer special-cases
  // pending email-triage items. They are surfaced by the Inbox nav count badge —
  // persistent in the desktop rail in every dashboard state. On mobile the badge
  // rides the nav drawer, so with the drawer closed the count is one tap from
  // the top-bar hamburger (an accepted degradation vs. the removed inline block;
  // a mobile top-bar indicator is out of scope here — it needs its own
  // wireframe). A statutory clock is thus no longer hidden by the
  // conversation-less first-run screen on desktop, and is one tap away on mobile.
  if (!kbError && !visionExists && conversations.length === 0 && !hasActiveFilter) {
    return (
      <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10">
        <p className="mb-3 text-xs font-medium tracking-widest text-soleur-accent-gold-fg">
          DASHBOARD
        </p>
        <h1 className="mb-3 text-center text-3xl font-semibold text-soleur-text-primary md:text-4xl">
          Tell your organization what you&apos;re building.
        </h1>
        <p className="mb-10 max-w-md text-center text-sm text-soleur-text-secondary">
          Describe your startup idea and your AI organization will get to work.
        </p>
        {repoDisconnected && orphanedCount > 0 && (
          <p
            data-testid="disconnected-orphans-hint"
            className="mb-6 max-w-md text-center text-xs text-soleur-text-muted"
          >
            {orphanedCount === 1
              ? "Your previous conversation is tied to your disconnected repository. Reconnect that repository to view it."
              : `Your previous ${orphanedCount} conversations are tied to your disconnected repository. Reconnect that repository to view them.`}
          </p>
        )}

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
                  className="flex items-center gap-1.5 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 px-2 py-1.5"
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
                  <span className="max-w-[120px] truncate text-xs text-soleur-text-secondary">{att.file.name}</span>
                  <button
                    type="button"
                    onClick={() => removeFirstRunAttachment(att.id)}
                    className="ml-1 text-soleur-text-muted hover:text-soleur-text-primary"
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

          {/* Unified input box: the paperclip + send controls live *inside* one
              bordered container alongside the borderless input — mirrors the
              shared ChatInput (chat-input.tsx) ChatGPT-style box so the
              dashboard landing prompt matches the chat and KB surfaces. */}
          <div className="flex items-end gap-1.5 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 px-2 py-1.5 transition-shadow focus-within:border-soleur-text-secondary">
            {/* Paperclip / attach button */}
            <button
              type="button"
              onClick={() => fileInputRef.current?.click()}
              className="flex h-[36px] w-[36px] shrink-0 items-center justify-center rounded-lg text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
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

            <div className="flex-1">
              <input
                name="idea"
                type="text"
                placeholder="What are you building?"
                data-tour-id="action:new-conversation"
                autoFocus
                className="min-h-[36px] w-full border-none bg-transparent px-1 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted focus:outline-none focus-visible:shadow-none"
                onPaste={(e) => {
                  const files = Array.from(e.clipboardData.files);
                  if (files.length > 0) {
                    e.preventDefault();
                    validateAndAddFiles(files);
                  }
                }}
              />
            </div>
            <button
              type="submit"
              className="flex h-[36px] w-[36px] shrink-0 items-center justify-center rounded-lg bg-amber-600 text-soleur-text-on-accent transition-colors hover:bg-amber-500"
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
      <div className={`mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center px-4 py-10 ${visionExists && !allTasksComplete ? "pt-10" : "justify-center"}`}>
        {/* Foundation + operational cards (hidden when all complete) */}
        {visionExists && !allTasksComplete && (
          <FoundationSection
            cards={allCards}
            getIconPath={getIconPath}
            onIncompleteClick={handlePromptClick}
            className="mb-10 w-full"
          />
        )}

        <p className="mb-3 text-xs font-medium tracking-widest text-soleur-accent-gold-fg">
          DASHBOARD
        </p>
        <h1 className="mb-3 text-center text-3xl font-semibold text-soleur-text-primary md:text-4xl">
          {allTasksComplete
            ? "Your organization is ready."
            : "No conversations yet."}
        </h1>
        <p className="mb-8 text-center text-sm text-soleur-text-secondary">
          Start a conversation to put your agents to work.
        </p>

        <button
          type="button"
          onClick={() => router.push("/dashboard/chat/new")}
          data-tour-id="action:new-conversation"
          className="mb-10 rounded-lg bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end px-6 py-3 text-sm font-semibold text-soleur-text-on-accent transition-opacity hover:opacity-90"
        >
          New conversation
        </button>

        <LeaderStrip onLeaderClick={handleLeaderClick} getIconPath={getIconPath} />
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
        <h1 className="text-xl font-semibold text-soleur-text-primary md:text-2xl">
          Dashboard
        </h1>
      </div>

      {/* PR-F (#3244, #3940) Today section — page-level disclosure banner
          (RV14) + per-draft cards. Mounted ABOVE foundation/inbox per plan
          §Phase 5. The banner mounts unconditionally so the legal
          disclosure is present even when there are no drafts yet. */}
      <section aria-label="Today" className="mb-6">
        {onboardingLoaded && !runtimeExplainerDismissed ? (
          <RuntimeExplainerBanner onDismiss={dismissRuntimeExplainer} />
        ) : null}
        <TodayBanner />
        {todayItems.map((item) => (
          <TodayCard
            key={item.id}
            id={item.id}
            source={item.source}
            sourceRef={item.sourceRef ?? null}
            owningDomain={item.owningDomain}
            draftPreview={item.draftPreview}
            urgency={item.urgency}
          />
        ))}
      </section>

      {/* Foundation + operational cards (hidden when all complete) */}
      {visionExists && !allTasksComplete && (
        <FoundationSection
          cards={allCards}
          getIconPath={getIconPath}
          onIncompleteClick={handlePromptClick}
        />
      )}

      {/* Filter bar */}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        {/* Archive toggle */}
        <div className="flex rounded-lg border border-soleur-border-default overflow-hidden">
          <button
            type="button"
            onClick={() => setArchiveFilter("active")}
            className={`min-h-[44px] px-3 py-2 text-sm font-medium transition-colors ${
              archiveFilter === "active"
                ? "bg-soleur-bg-surface-2 text-soleur-text-primary"
                : "bg-soleur-bg-surface-1 text-soleur-text-secondary hover:text-soleur-text-secondary"
            }`}
          >
            Active
          </button>
          <button
            type="button"
            onClick={() => setArchiveFilter("archived")}
            className={`min-h-[44px] px-3 py-2 text-sm font-medium transition-colors ${
              archiveFilter === "archived"
                ? "bg-soleur-bg-surface-2 text-soleur-text-primary"
                : "bg-soleur-bg-surface-1 text-soleur-text-secondary hover:text-soleur-text-secondary"
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
              ? "border-soleur-border-emphasized bg-soleur-bg-surface-1 text-soleur-accent-gold-fg"
              : "border-soleur-border-default bg-soleur-bg-surface-1 text-soleur-text-secondary"
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
              ? "border-soleur-border-emphasized bg-soleur-bg-surface-1 text-soleur-accent-gold-fg"
              : "border-soleur-border-default bg-soleur-bg-surface-1 text-soleur-text-secondary"
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
          data-tour-id="action:new-conversation"
          className="min-h-[44px] rounded-lg bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end px-4 py-2 text-sm font-semibold text-soleur-text-on-accent transition-opacity hover:opacity-90"
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
              className="animate-pulse rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1/50 p-4"
            >
              <div className="flex items-center gap-4">
                <div className="h-5 w-28 rounded-full bg-soleur-bg-surface-2" />
                <div className="h-4 w-48 rounded bg-soleur-bg-surface-2" />
                <div className="flex-1" />
                <div className="h-7 w-7 rounded-md bg-soleur-bg-surface-2" />
                <div className="h-4 w-16 rounded bg-soleur-bg-surface-2" />
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Error state */}
      {error && !conversationsErrorDismissed && (
        <ErrorCard
          title="Failed to load conversations"
          message={error}
          onRetry={refetch}
          onDismiss={() => setConversationsErrorDismissed(true)}
        />
      )}

      {/* Filtered empty state */}
      {!loading && !error && conversations.length === 0 && hasActiveFilter && (
        <div className="flex flex-col items-center justify-center py-20">
          <p className="mb-4 text-sm text-soleur-text-secondary">
            No conversations match your filters.
          </p>
          <button
            type="button"
            onClick={clearFilters}
            className="rounded-lg border border-soleur-border-default px-4 py-2 text-sm text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2"
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

function LeaderStrip({ onLeaderClick, getIconPath }: { onLeaderClick: (leaderId: string) => void; getIconPath: (id: DomainLeaderId) => string | null }) {
  return (
    <div data-tour-id="action:org-panel" className="flex flex-col items-center">
      <p className="mb-4 text-xs font-medium tracking-widest text-soleur-text-secondary">
        YOUR ORGANIZATION
      </p>
      <div className="flex flex-wrap justify-center gap-3">
        {ROUTABLE_DOMAIN_LEADERS.map((leader) => (
          <button
            key={leader.id}
            type="button"
            onClick={() => onLeaderClick(leader.id)}
            className="group flex items-center gap-1.5 rounded-lg px-2 py-1 transition-colors hover:bg-soleur-bg-surface-2/50"
          >
            <LeaderAvatar leaderId={leader.id} size="sm" customIconPath={getIconPath(leader.id as DomainLeaderId)} />
            <span className="text-xs text-soleur-text-muted group-hover:text-soleur-text-secondary">
              {leader.name}
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}

