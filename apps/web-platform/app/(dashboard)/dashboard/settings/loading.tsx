// Streaming skeleton for the settings segment. The settings page is an async
// server component (awaits Supabase), so this fallback streams during the
// server data-fetch — the canonical "stream during server data-fetch" win.
// Hand-rolled animate-pulse idiom.
export default function SettingsLoading() {
  return (
    <div className="mx-auto max-w-3xl space-y-6 px-6 py-8">
      <div className="h-8 w-40 animate-pulse rounded bg-soleur-bg-surface-2/50" />
      {Array.from({ length: 3 }).map((_, i) => (
        <div
          key={i}
          className="space-y-3 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6"
        >
          <div className="h-5 w-1/4 animate-pulse rounded bg-soleur-bg-surface-2/50" />
          <div className="h-4 w-3/4 animate-pulse rounded bg-soleur-bg-surface-2/50" />
          <div className="h-10 w-full animate-pulse rounded-lg bg-soleur-bg-surface-2/50" />
        </div>
      ))}
    </div>
  );
}
