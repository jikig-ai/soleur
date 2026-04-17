const DEFAULT_WIDTHS = ["85%", "70%", "90%", "65%", "80%"];

export function KbContentSkeleton({ widths = DEFAULT_WIDTHS }: { widths?: string[] }) {
  return (
    <div className="space-y-4">
      <div className="h-8 w-64 animate-pulse rounded bg-neutral-800" />
      <div className="space-y-2">
        {widths.map((w, i) => (
          <div
            key={i}
            data-testid="kb-content-skeleton-row"
            className="h-4 animate-pulse rounded bg-neutral-800"
            style={{ width: w }}
          />
        ))}
      </div>
    </div>
  );
}
