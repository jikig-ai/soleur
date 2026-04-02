export default function KnowledgeBasePage() {
  return (
    <div className="flex h-full items-center justify-center">
      <div className="max-w-md text-center">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl border border-neutral-800 bg-neutral-900">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-neutral-500">
            <path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <h1 className="mb-2 text-lg font-semibold text-white">
          Knowledge Base
        </h1>
        <p className="mb-4 text-sm text-neutral-400">
          Your knowledge base builds automatically as you chat with your leadership team. Start a conversation to begin building context about your business.
        </p>
        <a
          href="/dashboard/chat/new"
          className="inline-flex items-center gap-2 rounded-lg border border-neutral-700 px-4 py-2 text-sm text-neutral-300 transition-colors hover:border-neutral-500 hover:text-white"
        >
          Start a conversation
        </a>
      </div>
    </div>
  );
}
