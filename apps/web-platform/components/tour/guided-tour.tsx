"use client";

// feat-guided-tour (#5743): the overlay renderer. Pure presentational + positioning
// (driven by props from TourProvider — no context import, so no provider<->overlay
// cycle). Single box-shadow spotlight over the target's live rect; centered card
// when there's no target / it's off-screen / on mobile. Focus-trapped, Escape =
// skip, reduced-motion aware, body-scroll-locked with guaranteed teardown.

import { useCallback, useEffect, useRef, useState } from "react";
import { GoldButton } from "@/components/ui/gold-button";
import { TOUR_STEPS, TOUR_STEP_COUNT } from "./tour-steps";

const PAD = 8; // px of breathing room around the spotlit target
const MOBILE_MAX = 768; // < md: rail is an off-screen drawer → centered card

interface Rect {
  top: number;
  left: number;
  width: number;
  height: number;
}

export function GuidedTour({
  stepIndex,
  onNext,
  onBack,
  onSkip,
  onFinish,
}: {
  stepIndex: number;
  onNext: () => void;
  onBack: () => void;
  onSkip: () => void;
  onFinish: () => void;
}) {
  const step = TOUR_STEPS[stepIndex];
  const isFirst = stepIndex === 0;
  const isLast = stepIndex === TOUR_STEP_COUNT - 1;

  const cardRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLElement | null>(null);
  const [rect, setRect] = useState<Rect | null>(null);
  // The keyboard handler + cleanup live in a once-only ([]) effect, so they must
  // read the LIVE onSkip / current target through refs — not the first-render
  // closure (which would report step 0 on Escape and never restore focus to the
  // step's nav item). Synced every render.
  const onSkipRef = useRef(onSkip);
  onSkipRef.current = onSkip;
  const targetRef = useRef<string | null>(step?.target ?? null);
  targetRef.current = step?.target ?? null;

  // Measure the target rect (or null → centered card). Null when: no target,
  // mobile, target absent, or target has a zero / off-screen rect.
  const measure = useCallback(() => {
    if (!step?.target || typeof window === "undefined") {
      setRect(null);
      return;
    }
    if (window.innerWidth < MOBILE_MAX) {
      setRect(null);
      return;
    }
    const el = document.querySelector<HTMLElement>(
      `[data-tour-id="${step.target}"]`,
    );
    if (!el) {
      setRect(null);
      return;
    }
    const r = el.getBoundingClientRect();
    const onScreen =
      r.width > 0 &&
      r.height > 0 &&
      r.bottom > 0 &&
      r.right > 0 &&
      r.top < window.innerHeight &&
      r.left < window.innerWidth;
    setRect(
      onScreen
        ? { top: r.top, left: r.left, width: r.width, height: r.height }
        : null,
    );
  }, [step?.target]);

  // Re-measure on step change + capture-phase window scroll + resize + a
  // ResizeObserver on the target. requestAnimationFrame lets the rail-expand /
  // route layout settle before the first measure. Action steps navigate to a new
  // route first, so the target may not exist on the initial measure — poll for it
  // (up to ~2.5s) until it mounts, then attach the ResizeObserver; if it never
  // appears, measure() has already left a centered fallback card.
  useEffect(() => {
    let cancelled = false;
    let raf = 0;
    let pollTimer: ReturnType<typeof setTimeout> | undefined;
    let ro: ResizeObserver | undefined;
    const onScroll = () => measure();
    window.addEventListener("scroll", onScroll, true);
    window.addEventListener("resize", onScroll);
    const deadline = Date.now() + 2500;

    const poll = () => {
      if (cancelled) return;
      measure();
      const targetId = step?.target;
      if (!targetId) return; // centered step (Welcome/closing) — nothing to await
      const el = document.querySelector<HTMLElement>(
        `[data-tour-id="${targetId}"]`,
      );
      if (el) {
        if (typeof ResizeObserver !== "undefined") {
          ro = new ResizeObserver(() => measure());
          ro.observe(el);
        }
        return;
      }
      if (Date.now() < deadline) {
        pollTimer = setTimeout(() => {
          raf = requestAnimationFrame(poll);
        }, 100);
      }
    };
    raf = requestAnimationFrame(poll);

    return () => {
      cancelled = true;
      cancelAnimationFrame(raf);
      if (pollTimer) clearTimeout(pollTimer);
      window.removeEventListener("scroll", onScroll, true);
      window.removeEventListener("resize", onScroll);
      ro?.disconnect();
    };
  }, [measure, step?.target]);

  // Body-scroll-lock + focus management for the tour's lifetime. Guaranteed
  // teardown (restores overflow + focus) on unmount / finish / skip / flag-off.
  useEffect(() => {
    triggerRef.current = document.activeElement as HTMLElement | null;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    cardRef.current?.focus();

    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault();
        onSkipRef.current();
        return;
      }
      if (e.key === "Tab" && cardRef.current) {
        const focusable = cardRef.current.querySelectorAll<HTMLElement>(
          'button:not(:disabled), [href], [tabindex]:not([tabindex="-1"])',
        );
        if (focusable.length === 0) return;
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        const activeEl = document.activeElement;
        if (
          !activeEl ||
          activeEl === document.body ||
          activeEl === cardRef.current ||
          !cardRef.current.contains(activeEl)
        ) {
          // Focus on the dialog container itself (or escaped to body/background):
          // pull it onto the first control so Tab AND Shift+Tab stay trapped.
          e.preventDefault();
          first.focus();
        } else if (e.shiftKey && activeEl === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && activeEl === last) {
          e.preventDefault();
          first.focus();
        }
      }
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = prevOverflow;
      // Restore focus to a sensible target (the spotlit nav item if present,
      // else the original trigger) — never leave it on a detached node. Reads the
      // LIVE target via ref (the closure's `step` is frozen to the mount step).
      const liveTarget = targetRef.current;
      const target = liveTarget
        ? document.querySelector<HTMLElement>(`[data-tour-id="${liveTarget}"]`)
        : null;
      (target ?? triggerRef.current)?.focus?.();
    };
    // Run once for the tour lifetime — step-specific re-measure is handled above.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Keep focus inside the card after each step change (card content swaps).
  useEffect(() => {
    cardRef.current?.focus();
  }, [stepIndex]);

  const centered = rect === null;

  return (
    <div className="fixed inset-0 z-[70]" aria-hidden={false}>
      {/* Pointer/scroll catcher: dims interaction with the app behind. */}
      <div
        className="absolute inset-0"
        role="presentation"
        onClick={(e) => e.stopPropagation()}
      />

      {centered ? (
        // No target → full dark overlay, card centered (Welcome / mobile / fallback).
        <div className="absolute inset-0 bg-black/60" aria-hidden="true" />
      ) : (
        // Single-element spotlight: a transparent hole with a viewport-filling
        // dark box-shadow. rgba (not hex) satisfies no-raw-hex.
        <div
          aria-hidden="true"
          className="pointer-events-none absolute rounded-full ring-2 ring-soleur-accent-gold-fill transition-all duration-200 motion-reduce:transition-none"
          style={{
            top: rect.top - PAD,
            left: rect.left - PAD,
            width: rect.width + PAD * 2,
            height: rect.height + PAD * 2,
            boxShadow: "0 0 0 9999px rgba(0,0,0,0.6)",
          }}
        />
      )}

      <div
        ref={cardRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="tour-card-title"
        tabIndex={-1}
        className={`absolute w-[min(20rem,calc(100vw-2rem))] rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 p-5 shadow-2xl focus:outline-none ${
          centered
            ? "left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2"
            : ""
        }`}
        style={
          centered
            ? undefined
            : {
                top: Math.min(
                  rect.top,
                  (typeof window !== "undefined" ? window.innerHeight : 800) -
                    220,
                ),
                left:
                  rect.left +
                  rect.width +
                  PAD +
                  12 +
                  (typeof window !== "undefined" &&
                  rect.left + rect.width + 360 > window.innerWidth
                    ? -(rect.width + 360)
                    : 0),
              }
        }
      >
        <div className="mb-3 flex items-center justify-between gap-2">
          <span className="text-[11px] font-medium uppercase tracking-wide text-soleur-text-muted">
            {stepIndex + 1} of {TOUR_STEP_COUNT}
          </span>
          {!isLast && (
            <button
              type="button"
              onClick={onSkip}
              className="text-xs text-soleur-text-muted transition-colors hover:text-soleur-text-secondary"
            >
              Skip
            </button>
          )}
        </div>

        {/* Progress bar */}
        <div className="mb-4 h-1 w-full overflow-hidden rounded-full bg-soleur-bg-surface-2">
          <div
            className="h-full rounded-full bg-soleur-accent-gold-fill transition-all motion-reduce:transition-none"
            style={{ width: `${((stepIndex + 1) / TOUR_STEP_COUNT) * 100}%` }}
          />
        </div>

        <h2
          id="tour-card-title"
          className="mb-1.5 text-base font-semibold text-soleur-text-primary"
        >
          {step?.title}
        </h2>
        <p className="mb-5 text-sm leading-relaxed text-soleur-text-secondary">
          {step?.body}
        </p>

        <div className="flex items-center justify-between gap-3">
          {!isFirst ? (
            <button
              type="button"
              onClick={onBack}
              className="rounded-lg border border-soleur-border-default px-4 py-2 text-sm text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
            >
              Back
            </button>
          ) : (
            <span />
          )}
          <GoldButton onClick={isLast ? onFinish : onNext}>
            {isLast ? "Finish" : "Next"}
          </GoldButton>
        </div>
      </div>
    </div>
  );
}
