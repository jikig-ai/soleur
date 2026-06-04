"use client";

import { useRouter } from "next/navigation";

/**
 * feat-bash-autonomous-default-on — persistent Concierge posture chip.
 *
 * Reflects the SERVER-resolved autonomous posture (never a client guess):
 *   - `autonomous: true`  → "Auto-run on"  (commands stream, no per-command cards)
 *   - `autonomous: false` → "Approve each" (the review-gate is the active surface)
 *
 * Clicking deep-links to the relocated toggle on the Scope-Grants page. Sharp
 * 0px corners per brand-guide.md:266 (the switch TRACK stays pill elsewhere; a
 * chip is not a switch).
 */
export function AutoRunChip({ autonomous }: { autonomous: boolean }) {
  const router = useRouter();
  const label = autonomous ? "Auto-run on" : "Approve each";

  return (
    <button
      type="button"
      aria-label={`Concierge command execution: ${label}. Open settings.`}
      onClick={() =>
        router.push(
          "/dashboard/settings/scope-grants#concierge-command-execution",
        )
      }
      className={`flex items-center gap-1.5 rounded-none border px-2 py-0.5 text-xs font-medium transition-colors ${
        autonomous
          ? "border-soleur-accent-gold-fg/40 bg-soleur-accent-gold-fill/10 text-soleur-accent-gold-fg hover:bg-soleur-accent-gold-fill/20"
          : "border-soleur-border-default bg-soleur-bg-surface-2 text-soleur-text-secondary hover:bg-soleur-bg-surface-1"
      }`}
    >
      <span
        className={`h-1.5 w-1.5 rounded-full ${
          autonomous ? "bg-soleur-accent-gold-fg" : "bg-soleur-text-muted"
        }`}
      />
      {label}
    </button>
  );
}
