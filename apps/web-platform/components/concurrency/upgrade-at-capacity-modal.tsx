"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { NavLink } from "@/components/ui/nav-link";
import { Button } from "@/components/ui/button";
import * as Sentry from "@sentry/nextjs";
import { PENDING_WATCHDOG_MS } from "@/hooks/use-pending-action";
import type { PlanTier, ConcurrencyCapHitPreamble } from "@/lib/types";
import { OPEN_UPGRADE_MODAL_EVENT } from "@/lib/ws-client";
import { PLAN_LIMITS } from "@/lib/plan-limits";
import { ResponsiveModal } from "@/components/ui/responsive-modal";
import {
  LOADING_COPY,
  ERROR_COPY,
  defaultStateCopyFor,
  adminOverrideCopy,
} from "./upgrade-copy";

export type ModalState =
  | "idle"
  | "loading"
  | "default"
  | "error"
  | "admin-override"
  | "enterprise-cap";

interface ModalContext {
  currentTier: PlanTier;
  nextTier: PlanTier | null;
  activeCount: number;
  effectiveCap: number;
  /** True if activeCount corresponds to a concurrency_override rather than
   *  the tier default. Computed by the caller (ws preamble does not include
   *  this flag; approximate by (effectiveCap > tierDefault) when needed). */
  adminOverride?: boolean;
}

/**
 * Top-level layout component. Listens for `soleur:openUpgradeModal` events
 * dispatched by ws-client's 4010 onclose handler, mounts with the right
 * state for the incoming preamble, and drives Stripe Embedded Checkout
 * for the default variant.
 *
 * Stripe Embedded Checkout wiring via `@stripe/react-stripe-js`
 * <EmbeddedCheckoutProvider> is left to a follow-up — the dependency is
 * tracked by Phase 0 preflight. Today the CTA POSTs to /api/checkout and
 * navigates to the hosted-page fallback (response `url`).
 */
export function UpgradeAtCapacityModal() {
  const [state, setState] = useState<ModalState>("idle");
  const [ctx, setCtx] = useState<ModalContext | null>(null);
  /** Server-supplied error copy for the "error" state — set when the route
   *  returns a human-readable body (e.g. the 409 in-progress signal). */
  const [errorBody, setErrorBody] = useState<string | null>(null);
  /** Abort in-flight /api/checkout on unmount or modal close so an orphaned
   *  fetch doesn't setState on a stale component. */
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    function onOpen(e: Event) {
      const detail = (e as CustomEvent<ConcurrencyCapHitPreamble | null>).detail;
      if (!detail) return;
      const tier: PlanTier = detail.currentTier ?? "free";
      const next: PlanTier | null = detail.nextTier ?? null;
      // Admin-override detection: if the effectiveCap was raised above the
      // tier default (via concurrency_override), route to the override-aware
      // copy instead of the tier-default upgrade ladder. The preamble does
      // not carry the override bit; compare effectiveCap vs tier-default.
      const tierDefault = PLAN_LIMITS[tier];
      const isAdminOverride =
        detail.effectiveCap > tierDefault && tier !== "enterprise";
      const baseCtx: ModalContext = {
        currentTier: tier,
        nextTier: next,
        activeCount: detail.activeCount,
        effectiveCap: detail.effectiveCap,
        adminOverride: isAdminOverride,
      };
      setCtx(baseCtx);
      if (tier === "enterprise") {
        // Enterprise-cap: platform hard cap hit regardless of next-tier value.
        setState("enterprise-cap");
      } else if (isAdminOverride) {
        setState("admin-override");
      } else {
        setState("default");
      }
    }
    window.addEventListener(OPEN_UPGRADE_MODAL_EVENT, onOpen);
    return () => {
      window.removeEventListener(OPEN_UPGRADE_MODAL_EVENT, onOpen);
      abortRef.current?.abort();
    };
  }, []);

  const close = useCallback(() => {
    abortRef.current?.abort();
    setState("idle");
  }, []);

  const startCheckout = useCallback(async (targetTier: PlanTier | null) => {
    if (!targetTier) return;
    abortRef.current?.abort();
    const ctrl = new AbortController();
    abortRef.current = ctrl;
    setErrorBody(null);
    setState("loading");
    try {
      const res = await fetch("/api/checkout", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ targetTier }),
        // Bound the flight so a hung POST cannot park the modal in the
        // loading state forever — the compositing clock races with the
        // caller's own close-abort, whichever fires first.
        signal: AbortSignal.any([
          ctrl.signal,
          AbortSignal.timeout(PENDING_WATCHDOG_MS),
        ]),
      });
      if (!res.ok) {
        const body = (await res.json().catch(() => null)) as {
          error?: string;
          code?: string;
        } | null;
        // 409 = a sibling request owns a checkout in flight (or one just
        // completed) — an expected race, not a failure. Show the server's
        // copy and let Retry re-join; don't fire the Sentry warn.
        if (res.status === 409 && body?.error) {
          setErrorBody(body.error);
          setState("error");
          return;
        }
        Sentry.captureMessage(
          `/api/checkout returned ${res.status} ${res.statusText}`,
          { level: "warning", tags: { feature: "concurrency", op: "upgrade-checkout" } },
        );
        setErrorBody(body?.error ?? null);
        setState("error");
        return;
      }
      const body = (await res.json()) as { url?: string | null; clientSecret?: string | null };
      if (body.url) {
        window.location.href = body.url;
        return;
      }
      // res.ok with no url: /api/checkout returns url:null on embedded
      // sessions — without this arm the modal sits in "loading" forever.
      // Embedded-mode wiring (clientSecret → EmbeddedCheckoutProvider) is a
      // follow-up; the server sets ui_mode='embedded' so when the React
      // provider is installed this branch mounts it inline.
      setState("error");
    } catch (err) {
      // Swallowing here used to be silent; mirror to Sentry so transient
      // network failures on the upgrade path are observable. Aborts from
      // unmount / close are expected and intentional — skip those.
      if ((err as { name?: string } | null)?.name !== "AbortError") {
        Sentry.captureException(err, {
          tags: { feature: "concurrency", op: "upgrade-checkout" },
        });
        setState("error");
      }
    }
  }, []);

  /** Memoize the target tier we route the error-retry button to so it does
   *  not recompute on every render of the error branch. */
  const errorRetryTarget = useMemo<PlanTier | null>(
    () => (ctx ? defaultStateCopyFor(ctx.currentTier, ctx.effectiveCap).targetTier : null),
    [ctx],
  );

  if (state === "idle" || !ctx) return null;

  const copy =
    state === "default"
      ? defaultStateCopyFor(ctx.currentTier, ctx.effectiveCap)
      : null;

  return (
    <ResponsiveModal
      open
      onClose={close}
      desktopMaxWidth="max-w-md"
      aria-labelledby="upgrade-at-capacity-title"
    >
      <div data-state={state} className="text-soleur-text-primary">
        <Button
          variant="ghost"
          type="button"
          onClick={close}
          aria-label="Close"
          className="float-right text-soleur-text-muted hover:text-soleur-text-secondary"
        >
          ×
        </Button>

        {state === "loading" && (
          <div data-state="loading">
            <h2 id="upgrade-at-capacity-title" className="text-lg font-semibold">{LOADING_COPY.title}</h2>
            <p className="mt-2 text-sm text-soleur-text-secondary">{LOADING_COPY.body}</p>
          </div>
        )}

        {state === "default" && copy && (
          <div data-state="default">
            <h2 id="upgrade-at-capacity-title" className="text-lg font-semibold">{copy.title}</h2>
            <p className="mt-2 text-sm text-soleur-text-secondary">{copy.subhead}</p>
            <div className="mt-6 flex items-center justify-between">
              {copy.targetTier ? (
                <Button
                  variant="gold"
                  type="button"
                  onClick={() => startCheckout(copy.targetTier)}
                >
                  {copy.primaryCtaLabel}
                </Button>
              ) : (
                <NavLink
                  href="mailto:jean@soleur.ai"
                  className="rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent hover:opacity-90"
                >
                  {copy.primaryCtaLabel}
                </NavLink>
              )}
              {copy.secondaryLink ? (
                <NavLink href={copy.secondaryLink.href} className="text-sm text-soleur-text-secondary hover:text-soleur-text-primary">
                  {copy.secondaryLink.label}
                </NavLink>
              ) : null}
            </div>
          </div>
        )}

        {state === "error" && (
          <div data-state="error">
            <h2 id="upgrade-at-capacity-title" className="text-lg font-semibold">{ERROR_COPY.title}</h2>
            <p className="mt-2 text-sm text-soleur-text-secondary">{errorBody ?? ERROR_COPY.body}</p>
            <div className="mt-6 flex items-center justify-between">
              <Button
                variant="gold"
                type="button"
                onClick={() => startCheckout(errorRetryTarget)}
              >
                {ERROR_COPY.primaryCtaLabel}
              </Button>
              <NavLink href={ERROR_COPY.secondaryLink.href} className="text-sm text-soleur-text-secondary hover:text-soleur-text-primary">
                {ERROR_COPY.secondaryLink.label}
              </NavLink>
            </div>
          </div>
        )}

        {state === "admin-override" && ctx && (
          <AdminOverrideBody cap={ctx.effectiveCap} onClose={close} />
        )}

        {state === "enterprise-cap" && ctx && (
          <EnterpriseCapBody cap={ctx.effectiveCap} onClose={close} />
        )}
      </div>
    </ResponsiveModal>
  );
}

function AdminOverrideBody({ cap, onClose }: { cap: number; onClose: () => void }) {
  const copy = adminOverrideCopy(cap);
  return (
    <div data-state="admin-override">
      <h2 id="upgrade-at-capacity-title" className="text-lg font-semibold">{copy.title}</h2>
      <p className="mt-2 text-sm text-soleur-text-secondary">{copy.subhead}</p>
      <div className="mt-6 flex items-center justify-between">
        <NavLink
          href={copy.primaryCtaHref}
          className="rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent hover:opacity-90"
        >
          {copy.primaryCtaLabel}
        </NavLink>
        <Button
          variant="ghost"
          type="button"
          onClick={onClose}
          className="hover:text-soleur-text-primary"
        >
          {copy.secondaryLink.label}
        </Button>
      </div>
    </div>
  );
}

function EnterpriseCapBody({ cap, onClose }: { cap: number; onClose: () => void }) {
  return (
    <div data-state="enterprise-cap">
      <h2 id="upgrade-at-capacity-title" className="text-lg font-semibold">
        All {cap} of your conversations are working.
      </h2>
      <p className="mt-2 text-sm text-soleur-text-secondary">
        50 in parallel is the platform ceiling today. Your Enterprise contract can carry more — let&apos;s size a custom quota against your usage.
      </p>
      <div className="mt-6 flex items-center justify-between">
        <NavLink
          href="mailto:jean@soleur.ai"
          className="rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent hover:opacity-90"
        >
          Contact your account team
        </NavLink>
        <Button
          variant="ghost"
          type="button"
          onClick={onClose}
          className="hover:text-soleur-text-primary"
        >
          Dismiss
        </Button>
      </div>
    </div>
  );
}
