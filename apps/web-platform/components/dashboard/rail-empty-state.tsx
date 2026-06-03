"use client";

import Link from "next/link";

// RQ5 / AC6: a drilled section's rail must NEVER be blank. When a section has
// no items yet (no conversations, no KB docs), show a labeled empty state with
// a single forward CTA instead of an empty list. One generic component, reused
// across sections.
export function RailEmptyState({
  message,
  ctaLabel,
  ctaHref,
  testId,
}: {
  message: string;
  ctaLabel: string;
  ctaHref: string;
  testId?: string;
}) {
  return (
    <div
      data-testid={testId ?? "rail-empty-state"}
      className="flex flex-col gap-2 px-3 py-4 text-sm text-soleur-text-muted"
    >
      <span>{message}</span>
      <Link
        href={ctaHref}
        className="font-medium text-soleur-accent-gold-fg hover:underline"
      >
        {ctaLabel} →
      </Link>
    </div>
  );
}
