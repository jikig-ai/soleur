// Streaming skeleton for the KB segment: a sidebar tree skeleton beside a
// content-area skeleton. Inlines equivalent animate-pulse markup rather than
// importing the client `LoadingSkeleton` component, keeping this a pure server
// component with no client boundary. Hand-rolled animate-pulse idiom.
export default function KbLoading() {
  return (
    <div className="flex h-full min-h-0 flex-1">
      {/* Sidebar tree */}
      <div className="hidden w-64 shrink-0 space-y-2 border-r border-soleur-border-default px-3 py-4 md:block">
        {Array.from({ length: 10 }).map((_, i) => (
          <div
            key={i}
            className="h-5 animate-pulse rounded bg-soleur-bg-surface-2/50"
            style={{ width: `${60 + ((i * 7) % 35)}%` }}
          />
        ))}
      </div>
      {/* Content area */}
      <div className="min-w-0 flex-1 space-y-4 px-6 py-6">
        <div className="h-8 w-1/3 animate-pulse rounded bg-soleur-bg-surface-2/50" />
        {Array.from({ length: 8 }).map((_, i) => (
          <div key={i} className="h-4 w-full animate-pulse rounded bg-soleur-bg-surface-2/50" />
        ))}
      </div>
    </div>
  );
}
