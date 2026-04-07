"use client";

import { useState, useEffect, useCallback, Component } from "react";
import type { ReactNode } from "react";
import { usePathname, useRouter } from "next/navigation";
import { KbContext } from "@/components/kb/kb-context";
import type { KbContextValue } from "@/components/kb/kb-context";
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

  const isContentView = pathname !== "/dashboard/kb";
  const hasTreeContent = tree?.children && tree.children.length > 0;

  const ctxValue: KbContextValue = {
    tree,
    loading,
    error,
    expanded,
    toggleExpanded,
  };

  // Full-width states: loading, errors, or empty KB (no sidebar needed)
  if (loading || error || (!loading && !hasTreeContent)) {
    return (
      <KbContext value={ctxValue}>
        {children}
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
          {/* page.tsx renders here when at /dashboard/kb */}
          {!isContentView && children}
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
