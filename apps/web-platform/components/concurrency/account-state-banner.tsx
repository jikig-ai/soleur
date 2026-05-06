"use client";

import Link from "next/link";
import type { PlanTier } from "@/lib/types";
import {
  AT_CAPACITY_BANNER,
  downgradeBannerCopy,
} from "./upgrade-copy";

export type AccountStateBannerVariant = "at-capacity" | "downgrade-grace";

export interface AccountStateBannerProps {
  variant: AccountStateBannerVariant;
  /** Required for variant='downgrade-grace'. */
  newTier?: PlanTier;
  onDismiss?: () => void;
}

export function AccountStateBanner({
  variant,
  newTier,
  onDismiss,
}: AccountStateBannerProps) {
  const copy =
    variant === "at-capacity"
      ? AT_CAPACITY_BANNER
      : downgradeBannerCopy(newTier ?? "free");

  return (
    <div
      className="flex items-center justify-between gap-4 border-b border-soleur-border-default bg-soleur-bg-surface-1/60 px-4 py-2 text-sm text-soleur-text-secondary"
      data-variant={variant}
      role="status"
    >
      <p>{copy.message}</p>
      <div className="flex items-center gap-3">
        {copy.cta ? (
          <Link href={copy.cta.href} className="font-medium text-soleur-accent-gold-fg hover:text-soleur-accent-gold-text">
            {copy.cta.label}
          </Link>
        ) : null}
        {onDismiss ? (
          <button
            type="button"
            onClick={onDismiss}
            className="text-soleur-text-muted hover:text-soleur-text-secondary"
            aria-label="Dismiss"
          >
            ×
          </button>
        ) : null}
      </div>
    </div>
  );
}
