"use client";

import { useState, useEffect, useCallback, useMemo, Component } from "react";
import type { ReactNode } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { KbContext } from "@/components/kb/kb-context";
import type { KbContextValue } from "@/components/kb/kb-context";
import { FileTree } from "@/components/kb/file-tree";
import { SearchOverlay } from "@/components/kb/search-overlay";
import { getAncestorPaths } from "@/components/kb/get-ancestor-paths";
import type { TreeNode } from "@/server/kb-reader";

export default function KbLayout({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [tree, setTree] = useState<TreeNode | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<KbContextValue["error"]>(null);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  useEffect(() => {
    let cancelled = false;
    async function fetchTree() {
      try {
        const res = await fetch("/api/kb/tree");
        if (!cancelled) {
          if (res.status === 401) {
            router.push("/login");
            return;
          }
          if (res.status === 503) {
            setError("workspace-not-ready");
            setLoading(false);
            return;
          }
          if (res.status === 404) {
            setError("not-found");
            setLoading(false);
            return;
          }
          if (!res.ok) {
            setError("unknown");
            setLoading(false);
            return;
          }
          const data = await res.json();
          setTree(data.tree);
          setLoading(false);
        }
      } catch {
        if (!cancelled) {
          setError("unknown");
          setLoading(false);
        }
      }
    }
    fetchTree();
    return () => { cancelled = true; };
  }, [router]);

  const toggleExpanded = useCallback((path: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(path)) {
        next.delete(path);
      } else {
        next.add(path);
      }
      return next;
    });
  }, []);

  // Auto-expand ancestor directories when navigating to a file
  useEffect(() => {
    if (!pathname.startsWith("/dashboard/kb/") || pathname === "/dashboard/kb") {
      return;
    }
    const relativePath = decodeURIComponent(pathname.slice("/dashboard/kb/".length));
    const ancestors = getAncestorPaths(relativePath);
    if (ancestors.length === 0) return;

    setExpanded((prev) => {
      const next = new Set(prev);
      let changed = false;
      for (const dir of ancestors) {
        if (!next.has(dir)) {
          next.add(dir);
          changed = true;
        }
      }
      return changed ? next : prev;
    });
  }, [pathname]);

  const isContentView = pathname !== "/dashboard/kb";
  const hasTreeContent = tree?.children && tree.children.length > 0;

  const ctxValue: KbContextValue = useMemo(() => ({
    tree,
    loading,
    error,
    expanded,
    toggleExpanded,
  }), [tree, loading, error, expanded, toggleExpanded]);

  // Full-width states: loading, errors, or empty KB (no sidebar needed)
  if (loading || error || (!loading && !hasTreeContent)) {
    return (
      <KbContext value={ctxValue}>
        {loading && <LoadingSkeleton />}
        {error === "workspace-not-ready" && <WorkspaceNotReady />}
        {error === "not-found" && <NoProjectState />}
        {error === "unknown" && <UnknownError />}
        {!loading && !error && !hasTreeContent && <EmptyState />}
      </KbContext>
    );
  }

  // Two-panel layout: tree sidebar + content area
  return (
    <KbContext value={ctxValue}>
      <div className="flex h-full">
        {/* Tree sidebar — visible on desktop always, on mobile only at root */}
        <aside
          className={`w-full shrink-0 overflow-y-auto border-r border-neutral-800 md:block md:w-64 ${
            isContentView ? "hidden" : "block"
          }`}
        >
          <div className="flex h-full flex-col">
            <header className="shrink-0 px-4 pb-3 pt-4">
              <h1 className="font-serif text-lg font-medium tracking-tight text-white">
                Knowledge Base
              </h1>
            </header>
            <div className="shrink-0 px-3 pb-3">
              <SearchOverlay />
            </div>
            <div className="flex-1 overflow-y-auto px-2 pb-4">
              <FileTree />
            </div>
          </div>
        </aside>

        {/* Content area — visible on desktop always, on mobile only when viewing content */}
        <div
          className={`min-w-0 flex-1 overflow-y-auto md:block ${
            isContentView ? "block" : "hidden"
          }`}
        >
          <KbErrorBoundary>
            {isContentView ? children : <DesktopPlaceholder />}
          </KbErrorBoundary>
        </div>
      </div>
    </KbContext>
  );
}

function DesktopPlaceholder() {
  return (
    <div className="hidden h-full items-center justify-center md:flex">
      <div className="text-center">
        <svg
          width="48"
          height="48"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1"
          className="mx-auto mb-3 text-neutral-600"
        >
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M14 2v6h6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <p className="text-sm text-neutral-500">Select a file to view</p>
        <p className="mt-1 text-xs text-neutral-600">
          Choose a file from the sidebar to preview its contents
        </p>
      </div>
    </div>
  );
}

function LoadingSkeleton() {
  const widths = [140, 120, 160, 100, 130];
  return (
    <div className="flex h-full flex-col p-4">
      <div className="mb-4 h-6 w-32 animate-pulse rounded bg-neutral-800" />
      <div className="space-y-2">
        {widths.map((w, i) => (
          <div key={i} className="flex items-center gap-2">
            <div className="h-4 w-4 animate-pulse rounded bg-neutral-800" />
            <div
              className="h-4 animate-pulse rounded bg-neutral-800"
              style={{ width: `${w}px` }}
            />
          </div>
        ))}
      </div>
    </div>
  );
}

function WorkspaceNotReady() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="text-center">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-neutral-800">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="animate-pulse text-amber-500">
            <path d="M12 6v6l4 2" strokeLinecap="round" strokeLinejoin="round" />
            <circle cx="12" cy="12" r="10" />
          </svg>
        </div>
        <h1 className="mb-2 font-serif text-lg font-medium text-white">
          Setting Up Your Workspace
        </h1>
        <p className="text-sm text-neutral-400">
          Your workspace is being prepared. This usually takes a moment.
        </p>
      </div>
    </div>
  );
}

function NoProjectState() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="max-w-sm text-center">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-neutral-800">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-amber-500">
            <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2Z" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <h1 className="mb-2 font-serif text-lg font-medium text-white">
          No Project Connected
        </h1>
        <p className="mb-6 text-sm leading-relaxed text-neutral-400">
          Connect a GitHub project so your AI team can build your knowledge
          base with plans, specs, and analyses.
        </p>
        <Link
          href="/connect-repo?return_to=/dashboard/kb"
          className="inline-flex items-center gap-2 rounded-lg bg-gradient-to-r from-amber-600 to-amber-500 px-5 py-2.5 text-sm font-medium text-neutral-950 transition-opacity hover:opacity-90"
        >
          Set Up Project
        </Link>
      </div>
    </div>
  );
}

function UnknownError() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="text-center">
        <p className="text-sm text-neutral-400">
          Unable to load your knowledge base. Please try again later.
        </p>
      </div>
    </div>
  );
}

function EmptyState() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="max-w-sm text-center">
        <p className="mb-4 text-xs font-semibold uppercase tracking-widest text-amber-500/80">
          Knowledge Base
        </p>
        <h1 className="mb-3 font-serif text-2xl font-medium text-white">
          Nothing Here Yet.{" "}
          <span className="text-neutral-400">One Message Changes That.</span>
        </h1>
        <p className="mb-6 text-sm leading-relaxed text-neutral-400">
          Start a conversation and your AI organization gets to work — producing
          plans, specs, brand guides, and competitive analyses that appear here
          automatically.
        </p>
        <Link
          href="/dashboard/chat/new"
          className="inline-flex items-center gap-2 rounded-lg bg-gradient-to-r from-amber-600 to-amber-500 px-5 py-2.5 text-sm font-medium text-neutral-950 transition-opacity hover:opacity-90"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="shrink-0">
            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          Open a Chat
        </Link>
      </div>
    </div>
  );
}

class KbErrorBoundary extends Component<
  { children: ReactNode },
  { hasError: boolean }
> {
  constructor(props: { children: ReactNode }) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex h-full items-center justify-center">
          <div className="text-center">
            <p className="text-sm text-neutral-400">
              Something went wrong loading this content.
            </p>
            <button
              onClick={() => this.setState({ hasError: false })}
              className="mt-2 text-sm text-amber-400 underline hover:text-amber-300"
            >
              Try again
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
