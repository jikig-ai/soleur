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
      className="flex items-center justify-between gap-4 border-b border-neutral-800 bg-neutral-900/60 px-4 py-2 text-sm text-neutral-300"
      data-variant={variant}
      role="status"
    >
      <p>{copy.message}</p>
      <div className="flex items-center gap-3">
        {copy.cta ? (
          <Link href={copy.cta.href} className="font-medium text-amber-400 hover:text-amber-300">
            {copy.cta.label}
          </Link>
        ) : null}
        {onDismiss ? (
          <button
            type="button"
            onClick={onDismiss}
            className="text-neutral-500 hover:text-neutral-300"
            aria-label="Dismiss"
          >
            ×
          </button>
        ) : null}
      </div>
    </div>
  );
}
