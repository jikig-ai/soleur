"use client";

import Link from "next/link";
import { useKb } from "@/components/kb/kb-context";
import { FileTree } from "@/components/kb/file-tree";

export default function KnowledgeBasePage() {
  const { tree, loading, error } = useKb();

  if (loading) {
    return <LoadingSkeleton />;
  }

  if (error === "workspace-not-ready") {
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

  if (error) {
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

  const hasContent = tree?.children && tree.children.length > 0;

  if (!hasContent) {
    return <EmptyState />;
  }

  // Tree view — rendered in sidebar on desktop (via layout), full-screen on mobile
  return (
    <div className="flex h-full flex-col">
      <header className="shrink-0 px-4 pb-3 pt-4">
        <h1 className="font-serif text-lg font-medium tracking-tight text-white">
          Knowledge Base
        </h1>
      </header>
      <div className="flex-1 overflow-y-auto px-2 pb-4">
        <FileTree />
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

function LoadingSkeleton() {
  return (
    <div className="flex h-full flex-col p-4">
      <div className="mb-4 h-6 w-32 animate-pulse rounded bg-neutral-800" />
      <div className="space-y-2">
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className="flex items-center gap-2">
            <div className="h-4 w-4 animate-pulse rounded bg-neutral-800" />
            <div
              className="h-4 animate-pulse rounded bg-neutral-800"
              style={{ width: `${100 + Math.random() * 80}px` }}
            />
          </div>
        ))}
      </div>
    </div>
  );
}
