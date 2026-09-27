"use client";

// "New Issue" dialog. Title is required; the issue defaults to Backlog. On
// submit it POSTs a REAL GitHub issue (ADR-109) via the board's `onSubmit`, which
// optimistically inserts the card and reconciles it with the returned real
// number. Write-integrity here:
//   - submit-disable + a single-flight ref so a double-click / slow-network
//     double-fire cannot create two real issues (idempotency guard, spec P0-3).
//   - empty/whitespace title blocked client-side (server also 422s).
//   - on failure the form values are PRESERVED and an inline retry is shown (no
//     dead-end); on success the dialog closes.
//
// "Create with Concierge" remains gated behind CONCIERGE_ONLINE (offline in v1) —
// the draft backend is a tracked follow-up; the manual quick-add above is live.

import { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";
import { ResponsiveModal } from "@/components/ui/responsive-modal";
import { CONCIERGE_ONLINE } from "./concierge-flag";
import type { CreateIssueBody } from "./workstream-writes";

export function NewIssueDialog({
  open,
  onClose,
  onSubmit,
}: {
  open: boolean;
  onClose: () => void;
  onSubmit: (input: CreateIssueBody) => Promise<void>;
}) {
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [error, setError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);

  // feat-ui-action-feedback: the bespoke inFlight-ref + submitting pair is
  // exactly the contract usePendingAction owns (single-flight ref gate,
  // watchdog, focus restore) — two mechanisms for one guarantee.
  const { run: runSubmit, pending: submitting } = usePendingAction(
    async () => {
      if (title.trim().length === 0) return;
      setError(null);
      try {
        await onSubmit({
          title: title.trim(),
          ...(description.trim() ? { body: description.trim() } : {}),
        });
        onClose();
      } catch {
        // Board already rolled back the optimistic card + toasted; keep the
        // form values so the user can retry without re-typing.
        setError("Couldn't create the issue. Please try again.");
      }
    },
  );

  useEffect(() => {
    if (open) {
      setTitle("");
      setDescription("");
      setError(null);
      requestAnimationFrame(() => inputRef.current?.focus());
    }
  }, [open]);

  const canSubmit = title.trim().length > 0 && !submitting;

  function handleSubmit(e?: React.FormEvent) {
    e?.preventDefault();
    runSubmit();
  }

  return (
    <ResponsiveModal
      open={open}
      // Preserve the pre-refactor single-flight guard: don't let Escape dismiss
      // while a create is in flight (backdrop is already disabled below).
      onClose={() => {
        if (!submitting) onClose();
      }}
      closeOnBackdrop={true}
      desktopMaxWidth="max-w-md"
      aria-label="New issue"
    >
      <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">
        New issue
      </h2>
        <form onSubmit={handleSubmit}>
          <label
            htmlFor="new-issue-title"
            className="mb-1 block text-sm text-soleur-text-secondary"
          >
            Title <span className="text-red-400">*</span>
          </label>
          <input
            id="new-issue-title"
            ref={inputRef}
            data-tour-id="action:issue-create-manual"
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Issue title"
            aria-required="true"
            disabled={submitting}
            className="mb-4 w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-base text-soleur-text-primary placeholder:text-soleur-text-tertiary focus:outline-none disabled:opacity-60 md:text-sm"
          />

          <label
            htmlFor="new-issue-description"
            className="mb-1 block text-sm text-soleur-text-secondary"
          >
            Description
          </label>
          <textarea
            id="new-issue-description"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={3}
            placeholder="Optional"
            disabled={submitting}
            className="mb-3 w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-base text-soleur-text-primary placeholder:text-soleur-text-tertiary focus:outline-none disabled:opacity-60 md:text-sm"
          />

          <p className="mb-4 text-xs text-soleur-text-tertiary">
            Adds to Backlog on your connected GitHub repo.
          </p>

          {error ? (
            <p
              role="alert"
              className="mb-4 rounded-md border border-red-500/40 bg-red-500/10 px-3 py-2 text-xs text-red-400"
            >
              {error}
            </p>
          ) : null}

          {/* Disabled "Create with Concierge" — gated behind CONCIERGE_ONLINE
              (offline in v1). Real `disabled` so it can never silently no-op. */}
          <fieldset
            disabled={!CONCIERGE_ONLINE}
            data-tour-id="action:concierge-draft"
            aria-describedby="concierge-offline-note"
            className="mb-4 rounded-md border border-dashed border-soleur-border-default bg-soleur-bg-surface-2/40 p-3 disabled:opacity-60"
          >
            <legend className="px-1 text-xs font-medium text-soleur-text-secondary">
              Create with Concierge
            </legend>
            <p className="mb-2 text-xs text-soleur-text-tertiary">
              Describe the outcome and let the Concierge draft and route the
              issue for you.
            </p>
            <textarea
              disabled={!CONCIERGE_ONLINE}
              rows={2}
              placeholder="e.g. We need a way for users to export their data…"
              aria-label="Describe the issue for Concierge"
              className="mb-2 w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2 text-base text-soleur-text-primary placeholder:text-soleur-text-tertiary disabled:cursor-not-allowed disabled:opacity-60 focus:outline-none md:text-sm"
            />
            <Button
              variant="outlined"
              type="button"
              disabled={!CONCIERGE_ONLINE}
              className="rounded-md border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-secondary disabled:cursor-not-allowed disabled:opacity-60"
            >
              Create with Concierge
            </Button>
            <p
              id="concierge-offline-note"
              className="mt-2 flex items-center gap-1.5 text-xs text-soleur-text-tertiary"
            >
              <span
                aria-hidden="true"
                className="h-1.5 w-1.5 rounded-full bg-soleur-text-muted"
              />
              Concierge is offline — coming soon
            </p>
          </fieldset>

          <div className="flex flex-wrap justify-end gap-2">
            <Button
              variant="outlined"
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-4 py-2 text-sm font-medium text-soleur-text-primary disabled:opacity-60"
            >
              Cancel
            </Button>
            <Button
              variant="gold"
              type="submit"
              disabled={!canSubmit}
              loading={submitting}
              loadingLabel="Creating"
              modal
            >
              Create issue
            </Button>
          </div>
      </form>
    </ResponsiveModal>
  );
}
