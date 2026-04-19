"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import type { PlanTier, ConcurrencyCapHitPreamble } from "@/lib/types";
import { OPEN_UPGRADE_MODAL_EVENT } from "@/lib/ws-client";
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

  useEffect(() => {
    function onOpen(e: Event) {
      const detail = (e as CustomEvent<ConcurrencyCapHitPreamble | null>).detail;
      if (!detail) return;
      const tier: PlanTier = detail.currentTier ?? "free";
      const next: PlanTier | null = detail.nextTier ?? null;
      // Enterprise-cap: platform hard cap hit regardless of next-tier value.
      if (tier === "enterprise") {
        setCtx({
          currentTier: tier,
          nextTier: next,
          activeCount: detail.activeCount,
          effectiveCap: detail.effectiveCap,
        });
        setState("enterprise-cap");
        return;
      }
      setCtx({
        currentTier: tier,
        nextTier: next,
        activeCount: detail.activeCount,
        effectiveCap: detail.effectiveCap,
      });
      setState("default");
    }
    window.addEventListener(OPEN_UPGRADE_MODAL_EVENT, onOpen);
    return () => window.removeEventListener(OPEN_UPGRADE_MODAL_EVENT, onOpen);
  }, []);

  const close = useCallback(() => setState("idle"), []);

  const startCheckout = useCallback(async (targetTier: PlanTier | null) => {
    if (!targetTier) return;
    setState("loading");
    try {
      const res = await fetch("/api/checkout", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ targetTier }),
      });
      if (!res.ok) {
        setState("error");
        return;
      }
      const body = (await res.json()) as { url?: string | null; clientSecret?: string | null };
      if (body.url) {
        window.location.href = body.url;
      }
      // Embedded-mode wiring (clientSecret → EmbeddedCheckoutProvider) is a
      // follow-up; the server sets ui_mode='embedded' so when the React
      // provider is installed this branch mounts it inline.
    } catch {
      setState("error");
    }
  }, []);

  if (state === "idle" || !ctx) return null;

  const copy =
    state === "default"
      ? defaultStateCopyFor(ctx.currentTier, ctx.effectiveCap)
      : null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="upgrade-at-capacity-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      data-state={state}
      onClick={(e) => {
        if (e.target === e.currentTarget) close();
      }}
    >
      <div className="w-full max-w-md rounded-2xl border border-neutral-800 bg-neutral-950 p-6 text-neutral-100 shadow-2xl">
        <button
          type="button"
          onClick={close}
          aria-label="Close"
          className="float-right text-neutral-500 hover:text-neutral-300"
        >
          ×
        </button>

        {state === "loading" && (
          <div data-state="loading">
            <h2 id="upgrade-at-capacity-title" className="text-lg font-semibold">{LOADING_COPY.title}</h2>
            <p className="mt-2 text-sm text-neutral-400">{LOADING_COPY.body}</p>
          </div>
        )}

        {state === "default" && copy && (
          <div data-state="default">
            <h2 id="upgrade-at-capacity-title" className="text-lg font-semibold">{copy.title}</h2>
            <p className="mt-2 text-sm text-neutral-300">{copy.subhead}</p>
            <div className="mt-6 flex items-center justify-between">
              {copy.targetTier ? (
                <button
                  type="button"
                  onClick={() => startCheckout(copy.targetTier)}
                  className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-black hover:bg-amber-400"
                >
                  {copy.primaryCtaLabel}
                </button>
              ) : (
                <Link
                  href="mailto:jean@soleur.ai"
                  className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-black hover:bg-amber-400"
                >
                  {copy.primaryCtaLabel}
                </Link>
              )}
              {copy.secondaryLink ? (
                <Link href={copy.secondaryLink.href} className="text-sm text-neutral-400 hover:text-neutral-200">
                  {copy.secondaryLink.label}
                </Link>
              ) : null}
            </div>
          </div>
        )}

        {state === "error" && (
          <div data-state="error">
            <h2 id="upgrade-at-capacity-title" className="text-lg font-semibold">{ERROR_COPY.title}</h2>
            <p className="mt-2 text-sm text-neutral-300">{ERROR_COPY.body}</p>
            <div className="mt-6 flex items-center justify-between">
              <button
                type="button"
                onClick={() => ctx && startCheckout(defaultStateCopyFor(ctx.currentTier, ctx.effectiveCap).targetTier)}
                className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-black hover:bg-amber-400"
              >
                {ERROR_COPY.primaryCtaLabel}
              </button>
              <Link href={ERROR_COPY.secondaryLink.href} className="text-sm text-neutral-400 hover:text-neutral-200">
                {ERROR_COPY.secondaryLink.label}
              </Link>
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
    </div>
  );
}

function AdminOverrideBody({ cap, onClose }: { cap: number; onClose: () => void }) {
  const copy = adminOverrideCopy(cap);
  return (
    <div data-state="admin-override">
      <h2 id="upgrade-at-capacity-title" className="text-lg font-semibold">{copy.title}</h2>
      <p className="mt-2 text-sm text-neutral-300">{copy.subhead}</p>
      <div className="mt-6 flex items-center justify-between">
        <Link
          href={copy.primaryCtaHref}
          className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-black hover:bg-amber-400"
        >
          {copy.primaryCtaLabel}
        </Link>
        <button
          type="button"
          onClick={onClose}
          className="text-sm text-neutral-400 hover:text-neutral-200"
        >
          {copy.secondaryLink.label}
        </button>
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
      <p className="mt-2 text-sm text-neutral-300">
        50 in parallel is the platform ceiling today. Your Enterprise contract can carry more — let&apos;s size a custom quota against your usage.
      </p>
      <div className="mt-6 flex items-center justify-between">
        <Link
          href="mailto:jean@soleur.ai"
          className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-black hover:bg-amber-400"
        >
          Contact your account team
        </Link>
        <button
          type="button"
          onClick={onClose}
          className="text-sm text-neutral-400 hover:text-neutral-200"
        >
          Dismiss
        </button>
      </div>
    </div>
  );
}
