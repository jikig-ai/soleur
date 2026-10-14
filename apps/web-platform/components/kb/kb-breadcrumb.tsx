"use client";

export function safeDecode(segment: string): string {
  try {
    return decodeURIComponent(segment);
  } catch {
    return segment;
  }
}

/**
 * #7326 — the ANCESTOR segments shrink and ellipsize; the CURRENT one does not.
 *
 * A plain `truncate` on the whole trail would cut the tail, which is the
 * filename — the one segment the user needs. Letting each ancestor be its own
 * shrinkable, truncating box means a narrow header degrades to
 * `… / diagrams / c4-model.md` instead of `engineering / archi…`, and every
 * segment stays in the DOM for screen readers and DOM-driving agents.
 */
export function KbBreadcrumb({ path }: { path: string }) {
  const segments = path.split("/");

  return (
    <nav
      aria-label="Breadcrumb"
      className="flex min-w-0 items-center gap-1 overflow-hidden whitespace-nowrap text-xs text-soleur-text-muted"
    >
      {segments.map((segment, i) => {
        const isCurrent = i === segments.length - 1;
        return (
          <span
            key={i}
            className={`flex items-center gap-1 ${isCurrent ? "shrink-0" : "min-w-0"}`}
          >
            {i > 0 && <span className="shrink-0">/</span>}
            <span
              {...(isCurrent && {
                "data-testid": "kb-breadcrumb-current",
                "aria-current": "page",
              })}
              title={safeDecode(segment)}
              className={isCurrent ? "text-soleur-text-secondary" : "truncate"}
            >
              {safeDecode(segment)}
            </span>
          </span>
        );
      })}
    </nav>
  );
}
