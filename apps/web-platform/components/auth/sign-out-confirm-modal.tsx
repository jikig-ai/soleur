"use client";

import { useEffect, useRef } from "react";

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
  useEffect(() => {
    onCloseRef.current = onClose;
    isSigningOutRef.current = isSigningOut;
  });

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
        const focusable = dialogRef.current.querySelectorAll<HTMLElement>(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
        );
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
        <div className="flex justify-end gap-3">
          <button
            ref={cancelButtonRef}
            type="button"
            onClick={onClose}
            disabled={isSigningOut}
            className="rounded-lg border border-soleur-border-default px-4 py-2 text-sm text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary disabled:cursor-not-allowed disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={isSigningOut}
            className="rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent transition-colors hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isSigningOut ? "Signing out…" : "Sign out"}
          </button>
        </div>
      </div>
    </div>
  );
}
