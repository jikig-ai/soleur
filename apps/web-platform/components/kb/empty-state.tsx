import Link from "next/link";

export function EmptyState() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="max-w-sm text-center">
        <p className="mb-4 text-xs font-semibold uppercase tracking-widest text-amber-500/80">
          Knowledge Base
        </p>
        <h1 className="mb-3 font-serif text-2xl font-medium text-soleur-text-primary">
          Nothing Here Yet.{" "}
          <span className="text-soleur-text-secondary">One Message Changes That.</span>
        </h1>
        <p className="mb-6 text-sm leading-relaxed text-soleur-text-secondary">
          Start a conversation and your AI organization gets to work — producing
          plans, specs, brand guides, and competitive analyses that appear here
          automatically.
        </p>
        <Link
          href="/dashboard/chat/new"
          className="inline-flex items-center gap-2 rounded-lg bg-soleur-accent-gold-fill px-5 py-2.5 text-sm font-medium text-soleur-text-on-accent transition-opacity hover:opacity-90"
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
