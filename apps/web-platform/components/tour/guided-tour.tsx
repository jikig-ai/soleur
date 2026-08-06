"use client";

// feat-guided-tour (#5743): the overlay renderer. Pure presentational + positioning
// (driven by props from TourProvider — no context import, so no provider<->overlay
// cycle). Single box-shadow spotlight over the target's live rect; centered card
// when there's no target / it's off-screen / on mobile. Focus-trapped, Escape =
// skip, reduced-motion aware, body-scroll-locked with guaranteed teardown.

import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import { GoldButton } from "@/components/ui/gold-button";
import { TOUR_STEPS, TOUR_STEP_COUNT } from "./tour-steps";

const PAD = 8; // px of breathing room around the spotlit target

interface Rect {
  top: number;
  left: number;
  width: number;
  height: number;
}

const VIEWPORT_MARGIN = 12; // min px between the card and any viewport edge

/** Does this rect have area AND intersect the viewport? */
function isOnScreen(r: {
  width: number;
  height: number;
  top: number;
  left: number;
  right: number;
  bottom: number;
}): boolean {
  return (
    r.width > 0 &&
    r.height > 0 &&
    r.bottom > 0 &&
    r.right > 0 &&
    r.top < window.innerHeight &&
    r.left < window.innerWidth
  );
}

// Position the card next to the spotlit target, then clamp it fully inside the
// viewport so it can never spill off an edge (#tour-overflow).
//
// Placement order is right → left → below → above → clamp. The two horizontal
// slots come first because a desktop target (a rail tab, a toolbar button)
// leaves room beside it, and beside is where the card obscures least.
//
// #7326 added the two VERTICAL fallbacks. A phone target is usually full-bleed,
// so neither horizontal slot fits and the old code clamped — which parked the
// card directly on top of the very control the copy was pointing at. Desktop
// placement is unchanged: it still takes the `right` branch first.
function anchoredCardStyle(
  rect: Rect,
  card: { w: number; h: number },
): React.CSSProperties {
  const vw = typeof window !== "undefined" ? window.innerWidth : 1200;
  const vh = typeof window !== "undefined" ? window.innerHeight : 800;
  const M = VIEWPORT_MARGIN;
  const base = { maxHeight: vh - 2 * M, overflowY: "auto" as const };

  const clampTop = (t: number) => Math.max(M, Math.min(t, vh - card.h - M));
  const clampLeft = (l: number) => Math.max(M, Math.min(l, vw - card.w - M));

  const rightOfTarget = rect.left + rect.width + PAD + M;
  if (rightOfTarget + card.w + M <= vw) {
    return { ...base, top: clampTop(rect.top), left: rightOfTarget };
  }

  const leftOfTarget = rect.left - PAD - M - card.w;
  if (leftOfTarget >= M) {
    return { ...base, top: clampTop(rect.top), left: leftOfTarget };
  }

  const left = clampLeft(rect.left);

  const belowTarget = rect.top + rect.height + PAD + M;
  if (belowTarget + card.h + M <= vh) {
    return { ...base, top: belowTarget, left };
  }

  const aboveTarget = rect.top - PAD - M - card.h;
  if (aboveTarget >= M) {
    return { ...base, top: aboveTarget, left };
  }

  // Target taller than the viewport minus the card — nothing fits cleanly.
  return { ...base, top: clampTop(rect.top), left };
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
  // Live card dimensions, so the position can be clamped fully inside the
  // viewport (the card body grows with copy length). Seeded with a close
  // estimate so the very first paint clamps sensibly before measurement.
  const [cardSize, setCardSize] = useState({ w: 320, h: 240 });
  // The keyboard handler + cleanup live in a once-only ([]) effect, so they must
  // read the LIVE onSkip / current target through refs — not the first-render
  // closure (which would report step 0 on Escape and never restore focus to the
  // step's nav item). Synced every render.
  const onSkipRef = useRef(onSkip);
  onSkipRef.current = onSkip;
  const targetRef = useRef<string | null>(step?.target ?? null);
  targetRef.current = step?.target ?? null;

  // Measure the target rect (or null → centered card). Null when: no target,
  // target absent, or target has a zero / off-screen rect. Returns whether it
  // found an on-screen target, so the poll below knows when to stop.
  //
  // #7326 removed a blanket `innerWidth < 768 → null` here. It dated from when
  // every step targeted a nav-rail item, which on a phone lives in a closed
  // drawer; but ten of the steps now target in-page `action:*` anchors that are
  // fully on screen, and the blanket rule denied those a spotlight too. The
  // on-screen test below is the honest version of the same guard — it still
  // rejects the drawer's off-canvas nav links, by measuring rather than by
  // assuming.
  const measure = useCallback(() => {
    if (!step?.target || typeof window === "undefined") {
      setRect(null);
      return false;
    }
    const el = document.querySelector<HTMLElement>(
      `[data-tour-id="${step.target}"]`,
    );
    if (!el) {
      setRect(null);
      return false;
    }
    const r = el.getBoundingClientRect();
    const onScreen = isOnScreen(r);
    setRect(
      onScreen
        ? { top: r.top, left: r.left, width: r.width, height: r.height }
        : null,
    );
    return onScreen;
  }, [step?.target]);

  // Re-measure on step change + capture-phase window scroll + resize + a
  // ResizeObserver on the target. requestAnimationFrame lets the rail-expand /
  // route layout settle before the first measure. Action steps navigate to a new
  // route first, so the target may not exist on the initial measure — poll for it
  // (up to ~2.5s), then attach the ResizeObserver; if it never appears,
  // measure() has already left a centered fallback card.
  //
  // #7326: the poll now waits for the target to be ON SCREEN, not merely
  // PRESENT. The mobile nav drawer is translated off-canvas rather than
  // unmounted, so a nav-tab step's link is found instantly at an off-screen rect
  // — and settling for "present" froze the fallback card in place for the whole
  // ~200ms slide-in. A transform transition changes neither size nor scroll
  // offset, so neither the ResizeObserver nor the scroll listener would ever
  // have corrected it.
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
      const onScreen = measure();
      const targetId = step?.target;
      if (!targetId) return; // centered step (Welcome/closing) — nothing to await
      const el = document.querySelector<HTMLElement>(
        `[data-tour-id="${targetId}"]`,
      );
      if (el && onScreen) {
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

  // Measure the card so its anchored position can be clamped inside the viewport.
  // Runs before paint (useLayoutEffect) on each step change / re-measure, so a
  // taller card never renders off-screen for a frame.
  useLayoutEffect(() => {
    const el = cardRef.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    if (r.width && r.height) {
      setCardSize((prev) =>
        Math.abs(prev.w - r.width) > 1 || Math.abs(prev.h - r.height) > 1
          ? { w: r.width, h: r.height }
          : prev,
      );
    }
  }, [stepIndex, rect]);

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
        // dark box-shadow. rgba (not hex) satisfies no-raw-hex. A modest corner
        // radius keeps the cutout a rectangle that traces the target — never a
        // `rounded-full` pill/oval, which balloons on large targets (the KB tree).
        <div
          aria-hidden="true"
          className="pointer-events-none absolute rounded-lg ring-2 ring-soleur-accent-gold-fill transition-all duration-200 motion-reduce:transition-none"
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
        style={centered || !rect ? undefined : anchoredCardStyle(rect, cardSize)}
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
