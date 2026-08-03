"use client";

import Link from "next/link";
import { BackArrowIcon } from "@/components/dashboard/nav-icons";

/**
 * The mobile KB page header — one implementation, two callers.
 *
 * #7186 extracted this because the `fullWidth` states (kb/layout.tsx) and the
 * populated browse view (kb-mobile-layout.tsx) had grown near-identical copies
 * that had already drifted three ways: only one carried a `data-testid`, only
 * one met the 44px touch minimum this app applies everywhere else, and the two
 * copies together made "how many backs render in this state?" unauditable —
 * which is exactly the question the #4915 one-back-per-state contract asks.
 *
 * `showBack` is the caller's decision, not this component's: the two callers
 * cover disjoint states (fullWidth vs populated-landing), so neither can see
 * enough to derive it. Note the drawer's own `drawer-back-to-menu` is a THIRD
 * renderer that co-exists with both — see the census in (dashboard)/layout.tsx.
 */
export function KbMobilePageHeader({
  showBack,
  /** `true` for the shared fullWidth block, which also renders at md+. */
  hideOnDesktop = false,
}: {
  showBack: boolean;
  hideOnDesktop?: boolean;
}) {
  return (
    <header
      data-testid="kb-page-mobile-header"
      className={`flex shrink-0 items-center gap-2 border-b border-soleur-border-default px-4 py-3${
        hideOnDesktop ? " md:hidden" : ""
      }`}
    >
      {showBack && (
        <Link
          href="/dashboard"
          aria-label="Back to menu"
          className="flex min-h-11 min-w-11 items-center text-soleur-text-secondary hover:text-soleur-text-primary"
        >
          <BackArrowIcon className="h-5 w-5" />
        </Link>
      )}
      {/* The band's mobile section title is suppressed for KB, so this is the
          single "Knowledge Base" title on mobile (#4915 P2-4). */}
      <h1 className="text-sm font-medium text-soleur-text-primary">
        Knowledge Base
      </h1>
    </header>
  );
}
