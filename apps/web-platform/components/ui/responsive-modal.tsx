"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useMediaQuery } from "@/hooks/use-media-query";

// Responsive dialog shell (mobile Phase 3). Below `md` the dialog anchors to the
// bottom edge as a sheet (rounded top, drag-handle affordance, safe-area bottom
// padding, scrolls); at `md`+ it is a centered `max-w-*` dialog. Both branches
// are backdropped overlays portaled to <body> — UNLIKE `ui/sheet.tsx`, whose
// desktop branch is an inline push-column. Use THIS for centered form/confirm
// modals; use `Sheet` for side drawers.
//
// The shell owns: the backdrop, positioning, Escape-to-close, optional
// backdrop-click-to-close, (mobile) the visual drag handle, AND focus management
// — on open it moves focus into the panel, traps Tab within it (honoring the
// `aria-modal="true"` promise that the background is inert), and restores focus
// to the previously-focused element on close. Consumers pass their
// heading/body/footer as children WITHOUT an outer panel wrapper — the shell
// provides the border/background/rounding/padding.

const FOCUSABLE_SELECTOR =
  'a[href],button:not([disabled]),textarea:not([disabled]),input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';

export interface ResponsiveModalProps {
  open: boolean;
  /** Escape and (unless disabled) backdrop-click call this. */
  onClose?: () => void;
  /**
   * Close when the backdrop is clicked. Default true. Set false for
   * destructive / typed-confirm flows that must be dismissed explicitly so a
   * stray click can't drop progress.
   */
  closeOnBackdrop?: boolean;
  /** Desktop max-width utility (mobile is always full-width). Default max-w-md. */
  desktopMaxWidth?: string;
  /** Extra classes appended to the panel. */
  panelClassName?: string;
  "aria-label"?: string;
  "aria-labelledby"?: string;
  "aria-describedby"?: string;
  children: ReactNode;
}

export function ResponsiveModal({
  open,
  onClose,
  closeOnBackdrop = true,
  desktopMaxWidth = "max-w-md",
  panelClassName = "",
  children,
  "aria-label": ariaLabel,
  "aria-labelledby": ariaLabelledBy,
  "aria-describedby": ariaDescribedBy,
}: ResponsiveModalProps) {
  const isDesktop = useMediaQuery("(min-width: 768px)");
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const panelRef = useRef<HTMLDivElement | null>(null);
  const restoreFocusRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!open || !onClose) return;
    const close = onClose;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" && !e.defaultPrevented) {
        e.preventDefault();
        close();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  // Focus management: on open, remember the trigger and move focus into the
  // panel (unless a child's own autofocus already put focus inside); on close,
  // restore focus to the trigger. Makes `aria-modal="true"` honest.
  useEffect(() => {
    if (!open || !mounted) return;
    restoreFocusRef.current =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    const panel = panelRef.current;
    if (panel && !panel.contains(document.activeElement)) {
      const first = panel.querySelector<HTMLElement>(FOCUSABLE_SELECTOR);
      (first ?? panel).focus();
    }
    return () => {
      restoreFocusRef.current?.focus?.();
    };
  }, [open, mounted]);

  if (!open || !mounted) return null;

  // Trap Tab within the panel so focus can't escape to the inert background.
  function onPanelKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    if (e.key !== "Tab") return;
    const panel = panelRef.current;
    if (!panel) return;
    const focusables = Array.from(
      panel.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR),
    ).filter((el) => el.offsetParent !== null || el === document.activeElement);
    if (focusables.length === 0) {
      e.preventDefault();
      panel.focus();
      return;
    }
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    const active = document.activeElement;
    if (e.shiftKey && (active === first || active === panel)) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && active === last) {
      e.preventDefault();
      first.focus();
    }
  }

  const backdropClasses = isDesktop
    ? "fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
    : "fixed inset-0 z-50 flex items-end justify-center bg-black/50";

  const panelClasses = isDesktop
    ? `w-full ${desktopMaxWidth} rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-6 shadow-xl`
    : "max-h-[90vh] w-full overflow-y-auto rounded-t-2xl border-t border-soleur-border-default bg-soleur-bg-surface-1 px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-3 shadow-2xl";

  const node = (
    <div
      className={backdropClasses}
      role="presentation"
      onClick={
        closeOnBackdrop && onClose
          ? (e) => {
              if (e.target === e.currentTarget) onClose();
            }
          : undefined
      }
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel}
        aria-labelledby={ariaLabelledBy}
        aria-describedby={ariaDescribedBy}
        tabIndex={-1}
        onKeyDown={onPanelKeyDown}
        className={`${panelClasses} ${panelClassName} focus:outline-none`.trim()}
      >
        {!isDesktop && (
          <div
            aria-hidden="true"
            className="mx-auto mb-3 h-1.5 w-10 shrink-0 rounded-full bg-soleur-bg-surface-2"
          />
        )}
        {children}
      </div>
    </div>
  );

  return createPortal(node, document.body);
}
