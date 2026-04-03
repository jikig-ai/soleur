"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Cormorant_Garamond, Inter } from "next/font/google";
import { safeReturnTo } from "@/lib/safe-return-to";

// ---------------------------------------------------------------------------
// Fonts — scoped to this page only (layout.tsx is NOT modified)
// ---------------------------------------------------------------------------
const serif = Cormorant_Garamond({
  subsets: ["latin"],
  weight: ["400", "600", "700"],
  variable: "--font-serif",
  display: "swap",
});
const sans = Inter({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-sans",
  display: "swap",
});

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
type State =
  | "choose"
  | "create_project"
  | "github_redirect"
  | "select_project"
  | "no_projects"
  | "setting_up"
  | "ready"
  | "failed"
  | "interrupted";

type Repo = {
  name: string;
  fullName: string;
  private: boolean;
  description: string | null;
  language: string | null;
  updatedAt: string;
};

type SetupStep = {
  label: string;
  status: "pending" | "active" | "done";
};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const DEFAULT_GITHUB_APP_SLUG = process.env.NEXT_PUBLIC_GITHUB_APP_SLUG ?? "soleur-ai";
const GOLD_GRADIENT = "linear-gradient(135deg, #D4B36A, #B8923E)";

// ---------------------------------------------------------------------------
// Inline SVG Icons
// ---------------------------------------------------------------------------
function PlusIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <line x1="12" y1="5" x2="12" y2="19" />
      <line x1="5" y1="12" x2="19" y2="12" />
    </svg>
  );
}

function LinkIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
      <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
    </svg>
  );
}

function ShieldIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
    </svg>
  );
}

function CheckCircleIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
      <polyline points="22 4 12 14.01 9 11.01" />
    </svg>
  );
}

function XCircleIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="10" />
      <line x1="15" y1="9" x2="9" y2="15" />
      <line x1="9" y1="9" x2="15" y2="15" />
    </svg>
  );
}

function AlertTriangleIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
      <line x1="12" y1="9" x2="12" y2="13" />
      <line x1="12" y1="17" x2="12.01" y2="17" />
    </svg>
  );
}

function FolderIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" />
    </svg>
  );
}

function SearchIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="8" />
      <line x1="21" y1="21" x2="16.65" y2="16.65" />
    </svg>
  );
}

function ArrowLeftIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <line x1="19" y1="12" x2="5" y2="12" />
      <polyline points="12 19 5 12 12 5" />
    </svg>
  );
}

function SpinnerIcon({ className }: { className?: string }) {
  return (
    <svg className={`animate-spin ${className ?? ""}`} viewBox="0 0 24 24" fill="none">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth={3} />
      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
    </svg>
  );
}

function LockIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
      <path d="M7 11V7a5 5 0 0 1 10 0v4" />
    </svg>
  );
}

function GlobeIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="10" />
      <line x1="2" y1="12" x2="22" y2="12" />
      <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
    </svg>
  );
}

function ChevronDownIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <polyline points="6 9 12 15 18 9" />
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Shared UI Components
// ---------------------------------------------------------------------------
function Badge({ children }: { children: React.ReactNode }) {
  return (
    <span className="text-xs font-medium uppercase tracking-widest text-amber-500/70">
      {children}
    </span>
  );
}

function GoldButton({
  children,
  onClick,
  disabled,
  type = "button",
}: {
  children: React.ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  type?: "button" | "submit";
}) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className="rounded-lg px-6 py-3 text-sm font-medium text-black transition-opacity hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
      style={{ background: GOLD_GRADIENT }}
    >
      {children}
    </button>
  );
}

function OutlinedButton({
  children,
  onClick,
}: {
  children: React.ReactNode;
  onClick?: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-lg border border-neutral-700 bg-transparent px-6 py-3 text-sm font-medium text-neutral-200 transition-colors hover:bg-neutral-800"
    >
      {children}
    </button>
  );
}

function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={`rounded-xl border border-neutral-800 bg-neutral-900/50 p-6 ${className ?? ""}`}>
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function relativeTime(dateStr: string): string {
  const now = Date.now();
  const then = new Date(dateStr).getTime();
  const diffMs = now - then;
  const diffMins = Math.floor(diffMs / 60000);
  if (diffMins < 1) return "just now";
  if (diffMins < 60) return `${diffMins}m ago`;
  const diffHrs = Math.floor(diffMins / 60);
  if (diffHrs < 24) return `${diffHrs}h ago`;
  const diffDays = Math.floor(diffHrs / 24);
  if (diffDays < 30) return `${diffDays}d ago`;
  const diffMonths = Math.floor(diffDays / 30);
  return `${diffMonths}mo ago`;
}

// ---------------------------------------------------------------------------
// State: choose
// ---------------------------------------------------------------------------
function ChooseState({
  onCreateNew,
  onConnectExisting,
  onSkip,
}: {
  onCreateNew: () => void;
  onConnectExisting: () => void;
  onSkip: () => void;
}) {
  return (
    <div className="space-y-8">
      <div className="space-y-4 text-center">
        <Badge>GETTING STARTED</Badge>
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Give Your AI Team the Full Picture
        </h1>
        <p className="mx-auto max-w-lg text-base text-neutral-400">
          Your AI team works best when it understands your actual business — your
          decisions, your patterns, what you have built so far. Connect a project
          so your team starts with real context, not a blank slate.
        </p>
        <p className="text-sm text-neutral-500">
          You stay in control — your AI team proposes changes, you decide what ships.
        </p>
      </div>

      <div className="mx-auto grid max-w-2xl grid-cols-1 gap-4 sm:grid-cols-2">
        {/* Card A: Start Fresh */}
        <Card className="flex flex-col justify-between">
          <div className="space-y-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg border border-neutral-700 bg-neutral-800">
              <PlusIcon className="h-5 w-5 text-neutral-300" />
            </div>
            <h2 className={`${serif.className} text-xl font-semibold`}>Start Fresh</h2>
            <p className="text-sm text-neutral-400">
              Starting from scratch? We create a project workspace on GitHub
              (owned by Microsoft) under your own account — you keep full
              ownership of your code and data. Your AI team gets a home base
              from day one.
            </p>
          </div>
          <div className="mt-6">
            <GoldButton onClick={onCreateNew}>Create Project</GoldButton>
          </div>
        </Card>

        {/* Card B: Connect Existing Project */}
        <Card className="flex flex-col justify-between">
          <div className="space-y-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg border border-neutral-700 bg-neutral-800">
              <LinkIcon className="h-5 w-5 text-neutral-300" />
            </div>
            <h2 className={`${serif.className} text-xl font-semibold`}>
              Connect Existing Project
            </h2>
            <p className="text-sm text-neutral-400">
              Already have code on GitHub? Connect it and your AI team starts
              with full context — your architecture, your patterns, your
              decisions.
            </p>
          </div>
          <div className="mt-6">
            <OutlinedButton onClick={onConnectExisting}>Connect Project</OutlinedButton>
          </div>
        </Card>
      </div>

      <p className="text-center text-sm text-neutral-500">
        <button
          type="button"
          onClick={onSkip}
          className="underline decoration-neutral-600 underline-offset-2 transition-colors hover:text-neutral-300"
        >
          Skip this step
        </button>{" "}
        — you can connect a project later from Settings.
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// State: create_project
// ---------------------------------------------------------------------------
function CreateProjectState({
  onBack,
  onSubmit,
}: {
  onBack: () => void;
  onSubmit: (name: string, isPrivate: boolean) => void;
}) {
  const [projectName, setProjectName] = useState("");
  const [isPrivate, setIsPrivate] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const slug = projectName
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!slug) return;
    setSubmitting(true);
    setError("");
    try {
      onSubmit(slug, isPrivate);
    } catch {
      setError("Something went wrong. Please try again.");
      setSubmitting(false);
    }
  }

  return (
    <div className="mx-auto max-w-md space-y-8">
      <div className="space-y-4 text-center">
        <Badge>NEW PROJECT</Badge>
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Name Your Project
        </h1>
        <p className="text-base text-neutral-400">
          Give your project a name. This will be used to create your workspace on GitHub.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="space-y-2">
          <label htmlFor="project-name" className="block text-sm font-medium text-neutral-200">
            Project Name
          </label>
          <input
            id="project-name"
            type="text"
            required
            value={projectName}
            onChange={(e) => setProjectName(e.target.value)}
            placeholder="my-startup"
            className="w-full rounded-lg border border-neutral-700 bg-neutral-900 px-4 py-3 text-sm placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none"
          />
          {slug && (
            <p className="text-xs text-neutral-500">
              This becomes your project address on GitHub (e.g. github.com/you/{slug}).
            </p>
          )}
          {!slug && (
            <p className="text-xs text-neutral-500">
              This becomes your project address on GitHub (e.g. github.com/you/my-startup).
            </p>
          )}
        </div>

        <div className="space-y-2">
          <label className="block text-sm font-medium text-neutral-200">
            Visibility
          </label>
          <div className="flex overflow-hidden rounded-lg border border-neutral-700">
            <button
              type="button"
              onClick={() => setIsPrivate(true)}
              className={`flex flex-1 items-center justify-center gap-2 px-4 py-2.5 text-sm transition-colors ${
                isPrivate
                  ? "bg-neutral-800 text-neutral-100"
                  : "bg-transparent text-neutral-400 hover:text-neutral-200"
              }`}
            >
              <LockIcon className="h-4 w-4" />
              Private (recommended)
            </button>
            <button
              type="button"
              onClick={() => setIsPrivate(false)}
              className={`flex flex-1 items-center justify-center gap-2 border-l border-neutral-700 px-4 py-2.5 text-sm transition-colors ${
                !isPrivate
                  ? "bg-neutral-800 text-neutral-100"
                  : "bg-transparent text-neutral-400 hover:text-neutral-200"
              }`}
            >
              <GlobeIcon className="h-4 w-4" />
              Public
            </button>
          </div>
        </div>

        {error && <p role="alert" className="text-sm text-red-400">{error}</p>}

        <div className="flex items-center gap-3">
          <GoldButton type="submit" disabled={!slug || submitting}>
            {submitting ? "Creating..." : "Create Project"}
          </GoldButton>
          <OutlinedButton onClick={onBack}>Back</OutlinedButton>
        </div>
      </form>
    </div>
  );
}

// ---------------------------------------------------------------------------
// State: github_redirect
// ---------------------------------------------------------------------------
function GitHubRedirectState({
  onContinue,
  onBack,
}: {
  onContinue: () => void;
  onBack: () => void;
}) {
  return (
    <div className="mx-auto max-w-lg space-y-8">
      <div className="space-y-4 text-center">
        <Badge>SECURE CONNECTION</Badge>
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Connecting to GitHub
        </h1>
        <p className="text-base text-neutral-400">
          GitHub is a trusted platform used by millions of developers and
          businesses to manage their projects securely.
        </p>
      </div>

      <Card>
        <h3 className="mb-4 text-sm font-medium text-neutral-200">What happens next</h3>
        <ol className="space-y-4">
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              1
            </span>
            <span className="text-sm text-neutral-300">Sign in to GitHub</span>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              2
            </span>
            <div>
              <span className="text-sm text-neutral-300">Grant project access</span>
              <p className="mt-0.5 text-xs text-neutral-500">
                We only request permission to read and manage your project files — nothing else.
              </p>
            </div>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              3
            </span>
            <span className="text-sm text-neutral-300">Return here automatically</span>
          </li>
        </ol>
      </Card>

      <Card className="flex items-start gap-3">
        <ShieldIcon className="mt-0.5 h-5 w-5 shrink-0 text-amber-500/70" />
        <div>
          <h3 className="text-sm font-medium text-neutral-200">
            Why your own GitHub account?
          </h3>
          <p className="mt-1 text-xs text-neutral-500">
            Your project stays in your GitHub account, under your control. Your
            AI team accesses it through a secure GitHub App installation — you
            can revoke access at any time from your GitHub settings.
          </p>
        </div>
      </Card>

      <div className="flex items-center gap-3">
        <GoldButton onClick={onContinue}>Continue to GitHub</GoldButton>
        <OutlinedButton onClick={onBack}>Go Back</OutlinedButton>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// State: select_project
// ---------------------------------------------------------------------------
function SelectProjectState({
  repos,
  loading,
  onSelect,
  onBack,
}: {
  repos: Repo[];
  loading: boolean;
  onSelect: (repo: Repo) => void;
  onBack: () => void;
}) {
  const [selected, setSelected] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const [showAccess, setShowAccess] = useState(false);
  const perPage = 8;

  const filtered = repos.filter(
    (r) =>
      r.name.toLowerCase().includes(search.toLowerCase()) ||
      (r.description ?? "").toLowerCase().includes(search.toLowerCase()),
  );
  const totalPages = Math.max(1, Math.ceil(filtered.length / perPage));
  const paginated = filtered.slice((page - 1) * perPage, page * perPage);

  function handleConnect() {
    const repo = repos.find((r) => r.fullName === selected);
    if (repo) onSelect(repo);
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={onBack}
          className="flex h-8 w-8 items-center justify-center rounded-lg border border-neutral-700 text-neutral-400 transition-colors hover:bg-neutral-800 hover:text-neutral-200"
        >
          <ArrowLeftIcon className="h-4 w-4" />
        </button>
        <Badge>CONNECT PROJECT</Badge>
      </div>

      <div className="space-y-2">
        <h1 className={`${serif.className} text-3xl font-semibold`}>
          Select a Project
        </h1>
        <p className="text-sm text-neutral-400">
          Choose which project your AI team should work on. You can change this
          later from Settings.
        </p>
      </div>

      {/* Search */}
      <div className="relative">
        <SearchIcon className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-neutral-500" />
        <input
          type="text"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setPage(1);
          }}
          placeholder="Search projects..."
          className="w-full rounded-lg border border-neutral-700 bg-neutral-900 py-2.5 pl-10 pr-4 text-sm placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none"
        />
      </div>

      {/* Repo list */}
      {loading ? (
        <div className="flex items-center justify-center py-12">
          <SpinnerIcon className="h-6 w-6 text-amber-500/70" />
        </div>
      ) : (
        <div className="space-y-1">
          {paginated.map((repo) => (
            <button
              key={repo.fullName}
              type="button"
              onClick={() => setSelected(repo.fullName)}
              className={`flex w-full items-center justify-between rounded-lg border px-4 py-3 text-left transition-colors ${
                selected === repo.fullName
                  ? "border-amber-500/40 bg-amber-500/5"
                  : "border-neutral-800 bg-neutral-900/30 hover:bg-neutral-900/60"
              }`}
            >
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-neutral-100">
                    {repo.name}
                  </span>
                  <span
                    className={`rounded px-1.5 py-0.5 text-[10px] font-medium uppercase ${
                      repo.private
                        ? "bg-neutral-800 text-neutral-400"
                        : "bg-emerald-950 text-emerald-400"
                    }`}
                  >
                    {repo.private ? "Private" : "Public"}
                  </span>
                </div>
                {repo.description && (
                  <p className="mt-0.5 truncate text-xs text-neutral-500">
                    {repo.description}
                  </p>
                )}
              </div>
              <span className="shrink-0 text-xs text-neutral-400">
                Updated {relativeTime(repo.updatedAt)}
              </span>
            </button>
          ))}
        </div>
      )}

      {/* Pagination */}
      {!loading && totalPages > 1 && (
        <div className="flex items-center justify-between text-xs text-neutral-500">
          <button
            type="button"
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            disabled={page === 1}
            className="rounded px-2 py-1 hover:bg-neutral-800 disabled:opacity-30"
          >
            Previous
          </button>
          <span>
            Page {page} of {totalPages}
          </span>
          <button
            type="button"
            onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
            disabled={page === totalPages}
            className="rounded px-2 py-1 hover:bg-neutral-800 disabled:opacity-30"
          >
            Next
          </button>
        </div>
      )}

      {/* Connect CTA */}
      <div className="flex items-center gap-3">
        <GoldButton onClick={handleConnect} disabled={!selected}>
          Connect This Repository
        </GoldButton>
      </div>

      {/* Expandable: access info */}
      <div className="border-t border-neutral-800 pt-4">
        <button
          type="button"
          onClick={() => setShowAccess((v) => !v)}
          className="flex items-center gap-2 text-sm text-neutral-400 transition-colors hover:text-neutral-200"
        >
          <ChevronDownIcon
            className={`h-4 w-4 transition-transform ${showAccess ? "rotate-180" : ""}`}
          />
          What can the GitHub App access?
        </button>
        {showAccess && (
          <div className="mt-3 rounded-lg border border-neutral-800 bg-neutral-900/50 p-4 text-xs text-neutral-500">
            <p>
              The Soleur GitHub App can read and write code in repositories you
              explicitly grant access to. It cannot access other repositories,
              your personal settings, billing information, or any other GitHub
              data. You can modify or revoke access at any time from your GitHub
              settings.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// State: no_projects
// ---------------------------------------------------------------------------
function NoProjectsState({
  onUpdateAccess,
  onBack,
}: {
  onUpdateAccess: () => void;
  onBack: () => void;
}) {
  return (
    <div className="mx-auto max-w-lg space-y-6">
      <div className="flex items-center gap-3">
        <Badge>CONNECT PROJECT</Badge>
      </div>

      <div className="space-y-2">
        <h1 className={`${serif.className} text-3xl font-semibold`}>
          Select a Project
        </h1>
      </div>

      <Card className="flex flex-col items-center py-12 text-center">
        <FolderIcon className="mb-4 h-12 w-12 text-neutral-600" />
        <h3 className="text-lg font-medium text-neutral-200">No projects found</h3>
        <p className="mt-2 max-w-sm text-sm text-neutral-500">
          We could not find any repositories you have granted access to. You may
          need to update the GitHub App permissions to include the repositories
          you want to connect.
        </p>
      </Card>

      <div className="flex items-center gap-3">
        <GoldButton onClick={onUpdateAccess}>Update Access on GitHub</GoldButton>
        <OutlinedButton onClick={onBack}>Go Back</OutlinedButton>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// State: setting_up
// ---------------------------------------------------------------------------
function SettingUpState({ steps }: { steps: SetupStep[] }) {
  return (
    <div className="mx-auto max-w-lg space-y-8">
      <div className="space-y-4 text-center">
        <Badge>SETTING UP</Badge>
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Setting up your AI team...
        </h1>
        <p className="text-base text-neutral-400">
          This usually takes less than a minute.
        </p>
      </div>

      {/* Progress bar */}
      <div className="h-1 overflow-hidden rounded-full bg-neutral-800">
        <div
          className="h-full rounded-full transition-all duration-700 ease-out"
          style={{
            background: GOLD_GRADIENT,
            width: `${
              ((steps.filter((s) => s.status === "done").length +
                (steps.some((s) => s.status === "active") ? 0.5 : 0)) /
                steps.length) *
              100
            }%`,
          }}
        />
      </div>

      {/* Step checklist */}
      <div className="space-y-3">
        {steps.map((step, i) => (
          <div key={i} className="flex items-center gap-3">
            {step.status === "done" && (
              <CheckCircleIcon className="h-5 w-5 shrink-0 text-green-400" />
            )}
            {step.status === "active" && (
              <SpinnerIcon className="h-5 w-5 shrink-0 text-amber-500/70" />
            )}
            {step.status === "pending" && (
              <div className="h-5 w-5 shrink-0 rounded-full border-2 border-neutral-600" />
            )}
            <span
              className={`text-sm ${
                step.status === "done"
                  ? "text-neutral-300"
                  : step.status === "active"
                    ? "text-neutral-100"
                    : "text-neutral-400"
              }`}
            >
              {step.label}
            </span>
          </div>
        ))}
      </div>

      {/* What happens next */}
      <Card>
        <h3 className="mb-2 text-sm font-medium text-neutral-200">What happens next</h3>
        <p className="text-xs text-neutral-500">
          Your AI team — marketing, engineering, legal, finance, and more —
          will have full context on your project from the first conversation.
        </p>
      </Card>

      <p className="text-center text-xs text-neutral-500">
        Your code stays in your GitHub account. Your AI team reads it —
        you decide what changes get made.
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// State: ready
// ---------------------------------------------------------------------------
function ReadyState({
  repoName,
  onContinue,
}: {
  repoName: string;
  onContinue: () => void;
}) {
  return (
    <div className="mx-auto max-w-lg space-y-8 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-green-500/10">
        <CheckCircleIcon className="h-8 w-8 text-green-400" />
      </div>

      <div className="space-y-3">
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Your AI Team Is Ready.
        </h1>
        <p className="text-base text-neutral-400">
          Your AI team. Your project. Full context from the first conversation.
        </p>
      </div>

      <Card className="mx-auto inline-block text-left">
        <div className="space-y-3">
          <div className="flex items-center justify-between gap-8">
            <span className="text-sm text-neutral-500">Project</span>
            <span className="text-sm font-medium text-neutral-100">{repoName}</span>
          </div>
          <div className="flex items-center justify-between gap-8">
            <span className="text-sm text-neutral-500">Agents</span>
            <span className="text-sm font-medium text-green-400">61 ready</span>
          </div>
        </div>
      </Card>

      <p className="text-sm text-neutral-500">
        You are always the decision-maker. Your AI team proposes — you approve.
      </p>

      <GoldButton onClick={onContinue}>Open Dashboard</GoldButton>
    </div>
  );
}

// ---------------------------------------------------------------------------
// State: failed
// ---------------------------------------------------------------------------
function FailedState({
  onRetry,
  errorMessage,
}: {
  onRetry: () => void;
  errorMessage?: string | null;
}) {
  return (
    <div className="mx-auto max-w-lg space-y-8 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-red-500/10">
        <XCircleIcon className="h-8 w-8 text-red-400" />
      </div>

      <div className="space-y-3">
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Project Setup Failed
        </h1>
        <p className="text-base text-neutral-400">
          Something went wrong while setting up your project. This is usually a
          temporary issue.
        </p>
      </div>

      {errorMessage && (
        <Card className="text-left">
          <h3 className="mb-2 text-sm font-medium text-neutral-200">Error details</h3>
          <p className="text-sm text-neutral-400 font-mono break-all">{errorMessage}</p>
        </Card>
      )}

      <Card className="text-left">
        <h3 className="mb-3 text-sm font-medium text-neutral-200">What you can do</h3>
        <ol className="space-y-3">
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              1
            </span>
            <span className="text-sm text-neutral-400">
              Try again — most issues resolve on a second attempt.
            </span>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              2
            </span>
            <span className="text-sm text-neutral-400">
              Check GitHub&apos;s status page for ongoing incidents.
            </span>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              3
            </span>
            <span className="text-sm text-neutral-400">
              If the problem persists, contact support with the time of the error.
            </span>
          </li>
        </ol>
      </Card>

      <div className="flex items-center justify-center gap-3">
        <GoldButton onClick={onRetry}>Try Again</GoldButton>
        <OutlinedButton
          onClick={() => window.open("https://www.githubstatus.com", "_blank")}
        >
          GitHub Status Page
        </OutlinedButton>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// State: interrupted
// ---------------------------------------------------------------------------
function InterruptedState({
  onResume,
  onStartOver,
}: {
  onResume: () => void;
  onStartOver: () => void;
}) {
  return (
    <div className="mx-auto max-w-lg space-y-8 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-amber-500/10">
        <AlertTriangleIcon className="h-8 w-8 text-amber-400" />
      </div>

      <div className="space-y-3">
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Setup Was Interrupted
        </h1>
        <p className="text-base text-neutral-400">
          It looks like the GitHub authorization process was not completed. This
          can happen if the browser was closed or the connection was lost.
        </p>
      </div>

      <Card className="text-left">
        <p className="text-sm text-neutral-400">
          No changes were made to your GitHub account. You can resume the
          connection process right where you left off, or start over from the
          beginning.
        </p>
      </Card>

      <div className="flex items-center justify-center gap-3">
        <GoldButton onClick={onResume}>Resume on GitHub</GoldButton>
        <OutlinedButton onClick={onStartOver}>Start Over</OutlinedButton>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main Page Component
// ---------------------------------------------------------------------------
const SETUP_STEPS_TEMPLATE: SetupStep[] = [
  { label: "Copying your project files", status: "pending" },
  { label: "Scanning project structure", status: "pending" },
  { label: "Detecting knowledge base", status: "pending" },
  { label: "Analyzing conventions and patterns", status: "pending" },
  { label: "Preparing your AI team to work on your project", status: "pending" },
];

export default function ConnectRepoPage() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const [state, setState] = useState<State>(() => {
    // Avoid flashing the "choose" screen when returning from GitHub App install
    if (typeof window !== "undefined") {
      const params = new URLSearchParams(window.location.search);
      if (params.get("installation_id") && params.get("setup_action") === "install") {
        return "github_redirect";
      }
    }
    return "choose";
  });
  const [repos, setRepos] = useState<Repo[]>([]);
  const [reposLoading, setReposLoading] = useState(false);
  const [connectedRepoName, setConnectedRepoName] = useState("");
  const [setupSteps, setSetupSteps] = useState<SetupStep[]>(SETUP_STEPS_TEMPLATE);
  const [setupError, setSetupError] = useState<string | null>(null);
  const [pendingCreate, setPendingCreate] = useState<{
    name: string;
    isPrivate: boolean;
  } | null>(null);
  const [appSlug, setAppSlug] = useState(DEFAULT_GITHUB_APP_SLUG);

  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const stepTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // ---------------------------------------------------------------------------
  // On mount: fetch dynamic app slug and check for GitHub callback params
  // ---------------------------------------------------------------------------
  useEffect(() => {
    fetch("/api/repo/app-info")
      .then((res) => (res.ok ? res.json() : null))
      .then((data) => { if (data?.slug) setAppSlug(data.slug); })
      .catch(() => { /* retain env var fallback */ });
  }, []);

  useEffect(() => {
    const installationId = searchParams.get("installation_id");
    const setupAction = searchParams.get("setup_action");

    if (!installationId || setupAction !== "install") return;

    // Single atomic effect: register install, then handle pending create or
    // fetch repos. Merging these prevents concurrent useEffect race conditions
    // where stale sessionStorage could overwrite the install callback state.
    (async () => {
      try {
        // Step 1: Register the installation
        const installRes = await fetch("/api/repo/install", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ installationId: Number(installationId) }),
        });
        if (!installRes.ok) {
          setState("interrupted");
          return;
        }

        // Step 2: Check for pending create (from "Start Fresh" flow)
        let pendingCreateData: { name: string; isPrivate: boolean } | null =
          null;
        try {
          const raw = sessionStorage.getItem("soleur_create_project");
          if (raw) {
            pendingCreateData = JSON.parse(raw);
            sessionStorage.removeItem("soleur_create_project");
          }
        } catch {
          // sessionStorage unavailable
        }

        if (pendingCreateData) {
          const createRes = await fetch("/api/repo/create", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              name: pendingCreateData.name,
              private: pendingCreateData.isPrivate,
            }),
          });
          if (!createRes.ok) {
            setState("failed");
            return;
          }
          const data = await createRes.json();
          startSetup(data.repoUrl, data.fullName);
        } else {
          await fetchRepos();
        }
      } catch {
        setState("interrupted");
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---------------------------------------------------------------------------
  // Cleanup polling on unmount
  // ---------------------------------------------------------------------------
  useEffect(() => {
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
      if (stepTimerRef.current) clearInterval(stepTimerRef.current);
    };
  }, []);

  // ---------------------------------------------------------------------------
  // Fetch repos
  // ---------------------------------------------------------------------------
  const fetchRepos = useCallback(async () => {
    setReposLoading(true);
    try {
      const res = await fetch("/api/repo/repos");
      if (!res.ok) throw new Error("Failed to fetch repos");
      const data = await res.json();
      if (data.repos && data.repos.length > 0) {
        setRepos(data.repos);
        setState("select_project");
      } else {
        setState("no_projects");
      }
    } catch {
      setState("interrupted");
    } finally {
      setReposLoading(false);
    }
  }, []);

  // ---------------------------------------------------------------------------
  // Start setup + polling
  // ---------------------------------------------------------------------------
  const startSetup = useCallback(
    async (repoUrl: string, repoName: string) => {
      setConnectedRepoName(repoName);
      setState("setting_up");

      // Reset steps
      const steps = SETUP_STEPS_TEMPLATE.map((s) => ({ ...s }));
      steps[0].status = "active";
      setSetupSteps(steps);

      // Animate steps forward over time (visual polish)
      let currentStep = 0;
      stepTimerRef.current = setInterval(() => {
        currentStep++;
        if (currentStep >= steps.length) {
          if (stepTimerRef.current) clearInterval(stepTimerRef.current);
          return;
        }
        setSetupSteps((prev) =>
          prev.map((s, i) => ({
            ...s,
            status:
              i < currentStep ? "done" : i === currentStep ? "active" : "pending",
          })),
        );
      }, 3000);

      // Kick off setup
      try {
        const res = await fetch("/api/repo/setup", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ repoUrl }),
        });
        if (!res.ok) {
          if (stepTimerRef.current) clearInterval(stepTimerRef.current);
          setState("failed");
          return;
        }
      } catch {
        if (stepTimerRef.current) clearInterval(stepTimerRef.current);
        setState("failed");
        return;
      }

      // Poll status (max 60 attempts = 2 minutes before timeout)
      let pollAttempts = 0;
      const MAX_POLL_ATTEMPTS = 60;

      pollRef.current = setInterval(async () => {
        pollAttempts++;
        if (pollAttempts > MAX_POLL_ATTEMPTS) {
          if (pollRef.current) clearInterval(pollRef.current);
          if (stepTimerRef.current) clearInterval(stepTimerRef.current);
          setState("failed");
          return;
        }

        try {
          const res = await fetch("/api/repo/status");
          if (!res.ok) return;
          const data = await res.json();
          if (data.status === "ready") {
            if (pollRef.current) clearInterval(pollRef.current);
            if (stepTimerRef.current) clearInterval(stepTimerRef.current);
            // Mark all steps done
            setSetupSteps((prev) =>
              prev.map((s) => ({ ...s, status: "done" as const })),
            );
            setConnectedRepoName(data.repoName ?? repoName);
            // Brief delay so user sees the completed checklist
            setTimeout(() => setState("ready"), 800);
          } else if (data.status === "error") {
            if (pollRef.current) clearInterval(pollRef.current);
            if (stepTimerRef.current) clearInterval(stepTimerRef.current);
            setSetupError(data.errorMessage ?? null);
            setState("failed");
          }
        } catch {
          // Network blip — keep polling
        }
      }, 2000);
    },
    [],
  );

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------
  function handleCreateNew() {
    setState("create_project");
  }

  function handleConnectExisting() {
    setState("github_redirect");
  }

  /** Read and clear the stored return path from sessionStorage. */
  function consumeReturnTo(): string {
    try {
      const stored = sessionStorage.getItem("soleur_return_to");
      if (stored) {
        sessionStorage.removeItem("soleur_return_to");
        return safeReturnTo(stored);
      }
    } catch {
      // sessionStorage unavailable
    }
    return "/dashboard";
  }

  function handleSkip() {
    let returnPath = consumeReturnTo();
    if (returnPath === "/dashboard") {
      // Also check URL param directly (no GitHub redirect happened)
      returnPath = safeReturnTo(searchParams.get("return_to"));
    }
    router.push(returnPath);
  }

  function handleCreateSubmit(name: string, isPrivate: boolean) {
    setPendingCreate({ name, isPrivate });
    setState("github_redirect");
  }

  function handleGitHubRedirectContinue() {
    if (pendingCreate) {
      // Create flow: redirect to GitHub, then after callback create the repo
      // Store intent in sessionStorage so we know to create after callback
      try {
        sessionStorage.setItem(
          "soleur_create_project",
          JSON.stringify(pendingCreate),
        );
      } catch {
        // sessionStorage unavailable — proceed anyway
      }
    }
    // Persist return_to so it survives the GitHub redirect (validate before storing)
    try {
      const returnTo = searchParams.get("return_to");
      const validated = safeReturnTo(returnTo);
      if (validated !== "/dashboard") {
        sessionStorage.setItem("soleur_return_to", validated);
      }
    } catch {
      // sessionStorage unavailable
    }
    window.location.href = `https://github.com/apps/${appSlug}/installations/new`;
  }

  function handleGitHubRedirectBack() {
    if (pendingCreate) {
      setPendingCreate(null);
      setState("create_project");
    } else {
      setState("choose");
    }
  }

  function handleSelectProject(repo: Repo) {
    startSetup(`https://github.com/${repo.fullName}`, repo.fullName);
  }

  function handleUpdateAccess() {
    window.location.href = `https://github.com/apps/${appSlug}/installations/new`;
  }

  function handleRetry() {
    setSetupError(null);
    setState("choose");
  }

  function handleResume() {
    window.location.href = `https://github.com/apps/${appSlug}/installations/new`;
  }

  function handleStartOver() {
    setPendingCreate(null);
    setState("choose");
  }

  function handleOpenDashboard() {
    router.push(consumeReturnTo());
  }

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------
  return (
    <main
      className={`${serif.variable} ${sans.variable} flex min-h-screen items-center justify-center p-4`}
      style={{ fontFamily: "var(--font-sans), system-ui, sans-serif" }}
    >
      <div className="w-full max-w-3xl">
        {state === "choose" && (
          <ChooseState
            onCreateNew={handleCreateNew}
            onConnectExisting={handleConnectExisting}
            onSkip={handleSkip}
          />
        )}
        {state === "create_project" && (
          <CreateProjectState
            onBack={() => setState("choose")}
            onSubmit={handleCreateSubmit}
          />
        )}
        {state === "github_redirect" && (
          <GitHubRedirectState
            onContinue={handleGitHubRedirectContinue}
            onBack={handleGitHubRedirectBack}
          />
        )}
        {state === "select_project" && (
          <SelectProjectState
            repos={repos}
            loading={reposLoading}
            onSelect={handleSelectProject}
            onBack={() => setState("choose")}
          />
        )}
        {state === "no_projects" && (
          <NoProjectsState
            onUpdateAccess={handleUpdateAccess}
            onBack={() => setState("choose")}
          />
        )}
        {state === "setting_up" && <SettingUpState steps={setupSteps} />}
        {state === "ready" && (
          <ReadyState
            repoName={connectedRepoName}
            onContinue={handleOpenDashboard}
          />
        )}
        {state === "failed" && <FailedState onRetry={handleRetry} errorMessage={setupError} />}
        {state === "interrupted" && (
          <InterruptedState
            onResume={handleResume}
            onStartOver={handleStartOver}
          />
        )}
      </div>
    </main>
  );
}
