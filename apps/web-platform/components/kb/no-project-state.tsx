import Link from "next/link";

export function NoProjectState() {
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
