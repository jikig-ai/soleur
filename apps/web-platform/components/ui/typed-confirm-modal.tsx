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
//   - Pending (feat-ui-action-feedback brief §4): while `pending` is true
//     ALL dismiss vectors are inert (Cancel, Esc, backdrop, sheet close —
//     ResponsiveModal keys every one off `onClose` presence), the input is
//     locked, focus moves to the polite status element, and a failure is
//     announced + focused via role="alert" with the typed SEND preserved.
//
// NOTE: Tab focus trap is intentionally NOT implemented here. The dialog
// is mounted via React render-tree (not portal) and the page behind it
// is visually obscured by the backdrop; Tab can escape to the page
// below. A full focus trap (cycle on Tab/Shift+Tab against first/last
// focusable, aria-hidden on the rest of the DOM) lands with PR-I's
// dialog harmonization.

import { useEffect, useId, useRef, useState } from "react";

import { LockIcon } from "@/components/icons";
import { Button } from "@/components/ui/button";
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
  /**
   * Confirm POST in flight — wired from useActionSend's `confirmPending`.
   * Modal stays open; input locks; Cancel/Esc/close go inert; submit
   * shows "Sending…" at modal-surface opacity 0.65 (brief §4).
   */
  pending?: boolean;
  /**
   * Failure string from the send route rendered in-modal via role="alert"
   * (wired from useActionSend's `error`). The typed SEND value persists —
   * no re-typing on retry.
   */
  error?: string | null;
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
  pending = false,
  error = null,
}: TypedConfirmModalProps) {
  const [value, setValue] = useState("");
  const inputRef = useRef<HTMLInputElement | null>(null);
  const statusRef = useRef<HTMLParagraphElement | null>(null);
  const alertRef = useRef<HTMLParagraphElement | null>(null);
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

  // Focus contract (brief §4): while pending, focus moves to the polite
  // status element (the submit button is disabled, which would otherwise
  // drop focus to <body>); on failure, focus moves to the role="alert".
  useEffect(() => {
    if (pending) {
      statusRef.current?.focus();
    } else if (error) {
      alertRef.current?.focus();
    }
  }, [pending, error]);

  function handleSubmit(e?: React.FormEvent) {
    e?.preventDefault();
    // `canSubmit` stays true while the input is disabled — the pending
    // guard is what makes Enter during the flight a no-op (ux #10).
    if (!canSubmit || pending) return;
    onConfirm(true, value);
  }

  return (
    // Click-to-cancel is intentionally NOT wired (closeOnBackdrop={false}) —
    // typed-confirm should be exited explicitly via Esc or the Cancel button
    // so a stray mousedown doesn't drop progress. Escape → onClose={onCancel}.
    // While `pending`, `onClose` is undefined so every ResponsiveModal
    // dismiss vector — Esc listener, backdrop click, and the mobile-sheet
    // Close control — is inert until the POST resolves (brief §4 C3).
    <ResponsiveModal
      open={open}
      onClose={pending ? undefined : onCancel}
      closeOnBackdrop={false}
      desktopMaxWidth="max-w-md"
      aria-labelledby={titleId}
      aria-describedby={descId}
    >
      <div aria-busy={pending || undefined}>
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

        {/* Polite live region — the focus target while pending; announces
            the in-flight state (aria-busy alone does not announce
            resolution). role="status" implies aria-live="polite". */}
        <p
          ref={statusRef}
          role="status"
          tabIndex={-1}
          className="sr-only"
          data-testid="typed-confirm-status"
        >
          {pending ? "Sending…" : ""}
        </p>
        {error ? (
          <p
            ref={alertRef}
            role="alert"
            tabIndex={-1}
            className="mb-3 text-sm text-red-400"
            data-testid="typed-confirm-error"
          >
            {error}
          </p>
        ) : null}

        <form onSubmit={handleSubmit}>
          <label
            htmlFor={`${titleId}-input`}
            className="mb-1 block text-sm text-soleur-text-secondary"
          >
            Type <span className="font-mono font-semibold">{REQUIRED_PHRASE}</span> to confirm
          </label>
          <div className={`relative ${pending ? "mb-1" : "mb-4"}`}>
            <input
              id={`${titleId}-input`}
              ref={inputRef}
              type="text"
              value={value}
              onChange={(e) => setValue(e.target.value)}
              disabled={pending}
              autoComplete="off"
              spellCheck={false}
              // No autoCapitalize / autoCorrect — they would alter what the
              // server sees. The case-sensitive gate is load-bearing.
              autoCapitalize="off"
              autoCorrect="off"
              className="min-h-[44px] w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 pr-9 font-mono text-sm text-soleur-text-primary disabled:opacity-50"
              aria-required="true"
              data-testid="typed-confirm-input"
            />
            {pending && (
              <span
                aria-hidden="true"
                className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-soleur-text-muted"
              >
                <LockIcon className="h-3.5 w-3.5" />
              </span>
            )}
          </div>
          {pending && (
            <p className="mb-4 text-[11px] text-soleur-text-muted">
              Input locked while request in flight
            </p>
          )}

          <div className="flex flex-wrap justify-end gap-2">
            {/* Cancel keeps its rounded-md (brief §9-R14); the 0.5 inert
                opacity while pending is Button's non-loading disabled
                floor — the loading opacity contract belongs to the submit. */}
            <Button
              variant="outlined"
              type="button"
              onClick={onCancel}
              disabled={pending}
              className="min-h-[44px] rounded-md"
              data-testid="typed-confirm-cancel"
            >
              Cancel
            </Button>
            {/* Submit renders through Button variant="gold" + `modal` (0.65
                pending opacity on the scrim surface). `loading` supplies
                disabled + aria-busy + the leading SpinnerIcon at the shared
                150ms entry delay; the label swap to "Sending…" is immediate
                via children (the modal contract shows it the whole flight,
                not just post-delay). `loading` already forces `disabled`,
                so `disabled` carries only the canSubmit gate. */}
            <Button
              variant="gold"
              modal
              type="submit"
              disabled={!canSubmit}
              loading={pending}
              aria-disabled={!canSubmit || pending}
              className="min-h-[44px] font-semibold"
              data-testid="typed-confirm-submit"
            >
              {pending ? "Sending…" : "Confirm send"}
            </Button>
          </div>
        </form>
      </div>
    </ResponsiveModal>
  );
}
