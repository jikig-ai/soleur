import type { PlanTier } from "@/lib/types";

/**
 * Copy artifact at knowledge-base/marketing/copy/2026-04-19-concurrency-
 * enforcement-conversation-slot.md §1b–§1e is the source of truth. Any
 * customer-visible change must update that file first, then this table.
 *
 * `cap` is the active-conversation count substituted into {N} at render.
 */
export interface DefaultStateCopy {
  title: string;
  subhead: string;
  primaryCtaLabel: string;
  /** Destination tier for the Stripe checkout. null = no upgrade surface. */
  targetTier: PlanTier | null;
  secondaryLink: { label: string; href: string } | null;
}

export function defaultStateCopyFor(tier: PlanTier, cap: number): DefaultStateCopy {
  switch (tier) {
    case "free":
    case "solo":
      return {
        title: cap === 1 ? "Your conversation is working." : "Both conversations are working.",
        subhead:
          "Solo gives you 2 conversations at once. Bump to Startup to run 5 in parallel — your CTO can review a PR while your CMO ships a post and three more specialists cover the rest.",
        primaryCtaLabel: "Upgrade to Startup — $149/mo",
        targetTier: "startup",
        secondaryLink: { label: "See all plans", href: "/pricing" },
      };
    case "startup":
      return {
        title: `All ${cap} of your conversations are working.`,
        subhead:
          "You've filled your Startup parallel. Step up to Scale to run up to 50 conversations at once — enough room for every department to move at the same time.",
        primaryCtaLabel: "Upgrade to Scale — $499/mo",
        targetTier: "scale",
        secondaryLink: { label: "See all plans", href: "/pricing" },
      };
    case "scale":
      return {
        title: `All ${cap} of your conversations are working.`,
        subhead:
          "That's the Scale plan's standing parallel — the platform ceiling today. If you need more headroom, we'll set up a custom quota.",
        primaryCtaLabel: "Contact us for a custom quota",
        targetTier: null,
        secondaryLink: { label: "See all plans", href: "/pricing" },
      };
    case "enterprise":
      return {
        title: `All ${cap} of your conversations are working.`,
        subhead:
          "50 in parallel is the platform ceiling today. Your Enterprise contract can carry more — let's size a custom quota against your usage.",
        primaryCtaLabel: "Contact your account team",
        targetTier: null,
        secondaryLink: { label: "Dismiss", href: "#dismiss" },
      };
    default: {
      // Exhaustive check: if PlanTier widens with a new variant, the
      // assignment to `never` fails at build time and forces this switch to
      // cover it explicitly — preventing silent `undefined` returns.
      const _exhaustive: never = tier;
      return _exhaustive;
    }
  }
}

export interface LoadingStateCopy {
  title: string;
  body: string;
}

export const LOADING_COPY: LoadingStateCopy = {
  title: "Opening checkout",
  body: "Spinning up a secure Stripe session. One moment.",
};

export interface ErrorStateCopy {
  title: string;
  body: string;
  primaryCtaLabel: string;
  secondaryLink: { label: string; href: string };
}

export const ERROR_COPY: ErrorStateCopy = {
  title: "Checkout didn't open.",
  body: "Something on our end got in the way. Try again, or reach out and we'll finish the upgrade with you.",
  primaryCtaLabel: "Try again",
  secondaryLink: { label: "Email support", href: "mailto:jean@soleur.ai" },
};

export interface AdminOverrideCopy {
  title: string;
  subhead: string;
  primaryCtaLabel: string;
  primaryCtaHref: string;
  secondaryLink: { label: string; href: string };
}

export function adminOverrideCopy(cap: number): AdminOverrideCopy {
  return {
    title: `All ${cap} of your conversations are working.`,
    subhead:
      "You're on a custom parallel set by our team. If you need more room, reply to your last support thread and we'll raise it.",
    primaryCtaLabel: "Email support",
    primaryCtaHref: "mailto:jean@soleur.ai",
    secondaryLink: { label: "Dismiss", href: "#dismiss" },
  };
}

export interface BannerCopy {
  message: string;
  cta: { label: string; href: string } | null;
}

export const AT_CAPACITY_BANNER: BannerCopy = {
  message: "Concurrent conversations now run per plan — see pricing.",
  cta: { label: "See pricing", href: "/pricing" },
};

export function downgradeBannerCopy(newTier: PlanTier): BannerCopy {
  const tierLabel = newTier.charAt(0).toUpperCase() + newTier.slice(1);
  return {
    message: `You're now on ${tierLabel}. Your running conversations will finish; new ones will start as soon as there's room.`,
    cta: { label: "See pricing", href: "/pricing" },
  };
}
