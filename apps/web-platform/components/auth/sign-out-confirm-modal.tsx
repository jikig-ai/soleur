"use client";

import { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";

// ~8s escalation delay (feat-ui-action-feedback brief §5): sign-out is one of
// the named irreversible-path surfaces — a pending episode older than this
// appends "Still working…" to a polite live region so a slow sign-out never
// reads as hung.
const ESCALATION_DELAY_MS = 8_000;

interface SignOutConfirmModalProps {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  isSigningOut: boolean;
}

export function SignOutConfirmModal({
  open,
  onClose,
  onConfirm,
  isSigningOut,
}: SignOutConfirmModalProps) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const cancelButtonRef = useRef<HTMLButtonElement>(null);
  const triggerRef = useRef<HTMLElement | null>(null);
  const onCloseRef = useRef(onClose);
  const isSigningOutRef = useRef(isSigningOut);
  const [stillWorking, setStillWorking] = useState(false);
  useEffect(() => {
    onCloseRef.current = onClose;
    isSigningOutRef.current = isSigningOut;
  });

  // ~8s escalation (brief §5). The timer resets per pending episode — a fresh
  // sign-out attempt gets a fresh clock.
  useEffect(() => {
    setStillWorking(false);
    if (!isSigningOut) return;
    const timer = setTimeout(() => setStillWorking(true), ESCALATION_DELAY_MS);
    return () => clearTimeout(timer);
  }, [isSigningOut]);

  useEffect(() => {
    if (!open) return;

    triggerRef.current = document.activeElement as HTMLElement;
    cancelButtonRef.current?.focus();

    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") {
        if (isSigningOutRef.current) return;
        onCloseRef.current();
        return;
      }

      if (e.key === "Tab" && dialogRef.current) {
        // Filter `:disabled` so the manual wrap does not call `.focus()` on a
        // disabled button (no-op that breaks the cycle) while the modal is
        // in the `isSigningOut=true` state.
        const focusable = dialogRef.current.querySelectorAll<HTMLElement>(
          'button:not(:disabled), [href], input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex="-1"])',
        );
        if (focusable.length === 0) return;
        const first = focusable[0];
        const last = focusable[focusable.length - 1];

        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last?.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first?.focus();
        }
      }
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      triggerRef.current?.focus();
    };
  }, [open]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center">
      <div
        className="absolute inset-0 bg-black/60"
        onClick={isSigningOut ? undefined : onClose}
        role="presentation"
      />
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="signout-heading"
        tabIndex={-1}
        className="relative w-full max-w-sm rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 p-6"
      >
        <h3
          id="signout-heading"
          className="mb-2 text-lg font-semibold text-soleur-text-primary"
        >
          Sign out?
        </h3>
        <p className="mb-6 text-sm text-soleur-text-secondary">
          You&apos;ll be returned to the login page. Any unsaved input in the
          current view may be lost.
        </p>
        {/* Reserved-space escalation sublabel (brief §5): always mounted so
            "Still working…" populating causes zero layout shift. */}
        <p
          role="status"
          aria-live="polite"
          className="mb-4 min-h-5 text-xs text-soleur-text-muted"
        >
          {stillWorking ? "Still working…" : ""}
        </p>
        <div className="flex justify-end gap-3">
          <Button
            variant="outlined"
            ref={cancelButtonRef}
            type="button"
            onClick={onClose}
            disabled={isSigningOut}
            className="text-soleur-text-secondary hover:text-soleur-text-primary"
          >
            Cancel
          </Button>
          <Button
            variant="gold"
            type="button"
            onClick={onConfirm}
            disabled={isSigningOut}
            loading={isSigningOut}
            loadingLabel="Signing out"
            modal
            aria-label="Sign out"
          >
            Sign out
          </Button>
        </div>
      </div>
    </div>
  );
}
