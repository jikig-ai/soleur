"use client";

function safeDecode(segment: string): string {
  try {
    return decodeURIComponent(segment);
  } catch {
    return segment;
  }
}

export function KbBreadcrumb({ path }: { path: string }) {
  const segments = path.split("/");

  return (
    <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-neutral-500">
      {segments.map((segment, i) => (
        <span key={i} className="flex items-center gap-1">
          {i > 0 && <span>/</span>}
          <span className={i === segments.length - 1 ? "text-neutral-300" : ""}>
            {safeDecode(segment)}
          </span>
        </span>
      ))}
    </nav>
  );
}
