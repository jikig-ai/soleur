"use client";

import { useEffect, useState, type ReactNode } from "react";
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
// backdrop-click-to-close, and (mobile) the visual drag handle. Consumers pass
// their heading/body/footer as children WITHOUT an outer panel wrapper — the
// shell provides the border/background/rounding/padding. No focus trap (matches
// the pre-existing centered-modal behavior it replaces).

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

  useEffect(() => {
    if (!open || !onClose) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" && !e.defaultPrevented) {
        e.preventDefault();
        onClose!();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open || !mounted) return null;

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
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel}
        aria-labelledby={ariaLabelledBy}
        aria-describedby={ariaDescribedBy}
        className={`${panelClasses} ${panelClassName}`.trim()}
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
