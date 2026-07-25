"use client";

// PR-H (#4077) — Typed-confirm modal for approve_every_time tier.
//
// Per Arch F4: operation-bounded primitive. Lives under components/ui/
// so PR-I template-authorization confirmations can reuse the same
// component. External UX reference: GitHub repository-deletion modal.
//
// Load-bearing TOM: server-side re-validation of typed_value === "SEND"
// (TR6 at the route layer). This component is the FIRST line of defense
// (UX); the route is the SECOND (security). Both required.
//
// A11y contract (per Phase 5.1 / FR7):
//   - role="dialog" + aria-modal="true" + aria-labelledby
//   - Esc closes WITHOUT triggering discard
//   - Enter submits when input value === "SEND" exact (case-sensitive)
//   - Submit disabled until value === "SEND" exact
//   - 44×44px minimum tap targets
//   - No hover-only affordances
//
// NOTE: Tab focus trap is intentionally NOT implemented here. The dialog
// is mounted via React render-tree (not portal) and the page behind it
// is visually obscured by the backdrop; Tab can escape to the page
// below. A full focus trap (cycle on Tab/Shift+Tab against first/last
// focusable, aria-hidden on the rest of the DOM) lands with PR-I's
// dialog harmonization.

import { useEffect, useId, useRef, useState } from "react";

import { ResponsiveModal } from "@/components/ui/responsive-modal";

export interface TypedConfirmModalProps {
  open: boolean;
  // Payload fields rendered to the founder before they type SEND.
  recipientExcerpt: string;
  contentExcerpt: string;
  actionClassLabel: string;
  tierLabel: string;
  /**
   * PR-A (#4124) — Optional override for the "Recipient" cell label.
   * GitHubCard's `approve_every_time` flow (cve_alert, secret-scan-)
   * passes `actionTargetLabel="PR #<n>"` or `"issue #<n>"` so the modal
   * names the GitHub target rather than the placeholder
   * recipientIdentifier. Backwards-compatible default = `recipientExcerpt`.
   * StripeCard's pre-PR-A behavior is unchanged.
   */
  actionTargetLabel?: string;
  onCancel: () => void;
  // confirmedTyped + typedValue are passed back so the parent can POST
  // with the exact values the founder typed.
  onConfirm: (confirmedTyped: boolean, typedValue: string) => void;
}

const REQUIRED_PHRASE = "SEND";

export function TypedConfirmModal({
  open,
  recipientExcerpt,
  contentExcerpt,
  actionClassLabel,
  tierLabel,
  actionTargetLabel,
  onCancel,
  onConfirm,
}: TypedConfirmModalProps) {
  const [value, setValue] = useState("");
  const inputRef = useRef<HTMLInputElement | null>(null);
  const titleId = useId();
  const descId = useId();

  // Reset input each time the modal opens so an aborted confirmation
  // doesn't carry typed state to the next attempt.
  useEffect(() => {
    if (open) {
      setValue("");
      // Focus the input on open for keyboard-first founders.
      requestAnimationFrame(() => inputRef.current?.focus());
    }
  }, [open]);

  // No .trim() / .normalize() per Kieran P2-7 — case-sensitive exact
  // match. ZWS, lowercase, trailing-space all fail the gate.
  const canSubmit = value === REQUIRED_PHRASE;

  function handleSubmit(e?: React.FormEvent) {
    e?.preventDefault();
    if (!canSubmit) return;
    onConfirm(true, value);
  }

  return (
    // Click-to-cancel is intentionally NOT wired (closeOnBackdrop={false}) —
    // typed-confirm should be exited explicitly via Esc or the Cancel button
    // so a stray mousedown doesn't drop progress. Escape → onClose={onCancel}.
    <ResponsiveModal
      open={open}
      onClose={onCancel}
      closeOnBackdrop={false}
      desktopMaxWidth="max-w-md"
      aria-labelledby={titleId}
      aria-describedby={descId}
    >
        <h2
          id={titleId}
          className="mb-2 text-lg font-semibold text-soleur-text-primary"
        >
          Confirm send
        </h2>
        <p
          id={descId}
          className="mb-4 text-sm text-soleur-text-secondary"
        >
          {tierLabel} — {actionClassLabel}
        </p>

        <div className="mb-3 rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 p-3">
          <div className="mb-1 text-xs font-medium uppercase tracking-wide text-soleur-text-secondary">
            {actionTargetLabel ? "Target" : "Recipient"}
          </div>
          <div className="break-words text-sm text-soleur-text-primary">
            {actionTargetLabel ?? (recipientExcerpt || "(empty)")}
          </div>
        </div>

        <div className="mb-4 rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 p-3">
          <div className="mb-1 text-xs font-medium uppercase tracking-wide text-soleur-text-secondary">
            Content preview
          </div>
          <div className="whitespace-pre-line break-words text-sm text-soleur-text-primary">
            {contentExcerpt || "(empty)"}
          </div>
        </div>

        <form onSubmit={handleSubmit}>
          <label
            htmlFor={`${titleId}-input`}
            className="mb-1 block text-sm text-soleur-text-secondary"
          >
            Type <span className="font-mono font-semibold">{REQUIRED_PHRASE}</span> to confirm
          </label>
          <input
            id={`${titleId}-input`}
            ref={inputRef}
            type="text"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            autoComplete="off"
            spellCheck={false}
            // No autoCapitalize / autoCorrect — they would alter what the
            // server sees. The case-sensitive gate is load-bearing.
            autoCapitalize="off"
            autoCorrect="off"
            className="mb-4 min-h-[44px] w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 font-mono text-sm text-soleur-text-primary"
            aria-required="true"
            data-testid="typed-confirm-input"
          />

          <div className="flex flex-wrap justify-end gap-2">
            <button
              type="button"
              onClick={onCancel}
              className="min-h-[44px] rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-4 py-2 text-sm font-medium text-soleur-text-primary"
              data-testid="typed-confirm-cancel"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!canSubmit}
              aria-disabled={!canSubmit}
              className="min-h-[44px] rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50"
              data-testid="typed-confirm-submit"
            >
              Confirm send
            </button>
          </div>
        </form>
    </ResponsiveModal>
  );
}
