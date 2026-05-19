"use client";

// PR-G (#3947) — First-run runtime onboarding banner. Three beats per
// FR10 / brainstorm K10+K18:
//   1) What runs while you sleep (per-action-class).
//   2) Per-action-class authorization link.
//   3) Cost disclosure (RUNTIME_COST_DISCLOSURE).
//
// Visual mirror of TodayBanner (today-banner.tsx) — same gold-accent +
// dismiss-X pattern per ux-design-lead wireframe at
// knowledge-base/product/design/scope-grants/screenshots/06-today-banner-
// runtime-onboarding-explainer.png.
//
// Gating: `runtime_explainer_dismissed_at IS NULL` in `users` (migration
// 049). Dismiss persists via useOnboarding.dismissRuntimeExplainer.

import Link from "next/link";
import { RUNTIME_COST_DISCLOSURE } from "@/lib/legal/disclosures";
import { ACTION_CLASSES } from "@/server/scope-grants/action-class-map";

interface Props {
  onDismiss: () => void;
}

export function RuntimeExplainerBanner({ onDismiss }: Props) {
  return (
    <div
      role="region"
      aria-labelledby="runtime-explainer-title"
      className="mb-4 rounded-lg border border-soleur-gold/40 bg-soleur-bg-surface-1 px-5 py-4 text-sm"
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 flex-1 space-y-2">
          <h2
            id="runtime-explainer-title"
            className="font-medium text-soleur-text-primary"
          >
            What runs while you sleep
          </h2>
          <p className="text-soleur-text-secondary">
            Soleur can act on your behalf for specific action classes. Today
            that is:{" "}
            {ACTION_CLASSES.map((ac, i) => (
              <span key={ac}>
                <code className="text-soleur-text-primary">{ac}</code>
                {i < ACTION_CLASSES.length - 1 ? ", " : ""}
              </span>
            ))}
            . You decide which ones, at what tier, in{" "}
            <Link
              href="/dashboard/settings/scope-grants"
              className="text-soleur-gold hover:underline"
            >
              Scope Grants
            </Link>
            . Nothing runs until you authorize.
          </p>
          <p className="text-soleur-text-muted">{RUNTIME_COST_DISCLOSURE}</p>
        </div>
        <button
          type="button"
          onClick={onDismiss}
          aria-label="Dismiss"
          className="shrink-0 rounded p-1 text-soleur-text-muted hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
        >
          <svg
            className="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={1.5}
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M6 18 18 6M6 6l12 12"
            />
          </svg>
        </button>
      </div>
    </div>
  );
}
