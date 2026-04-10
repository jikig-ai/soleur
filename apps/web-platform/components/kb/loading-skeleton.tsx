export function LoadingSkeleton() {
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
