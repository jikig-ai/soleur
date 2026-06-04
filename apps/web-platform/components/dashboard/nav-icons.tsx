// Shared dashboard nav glyphs (#4915). Single-sourced so the workspace context
// band and the KB page-body header render the IDENTICAL "back to menu" arrow —
// a designer tweak lands in one place instead of drifting between copies.

/**
 * The "Back to menu" long left arrow. Deliberately distinct from the rail
 * collapse-toggle chevron (`M15.75 19.5 8.25 12l7.5-7.5`) so the two controls
 * never read as a duplicate (#4810). Color + size come from the caller's
 * `className`.
 */
export function BackArrowIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18"
      />
    </svg>
  );
}
