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
import { GoldButton } from "@/components/ui/gold-button";
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
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  // Synchronous single-flight guard — state flips are async, so a second submit
  // in the same tick would still fire without this ref.
  const inFlight = useRef(false);

  useEffect(() => {
    if (open) {
      setTitle("");
      setDescription("");
      setSubmitting(false);
      setError(null);
      inFlight.current = false;
      requestAnimationFrame(() => inputRef.current?.focus());
    }
  }, [open]);

  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault();
        if (!inFlight.current) onClose();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  const canSubmit = title.trim().length > 0 && !submitting;

  async function handleSubmit(e?: React.FormEvent) {
    e?.preventDefault();
    if (inFlight.current) return; // single-flight: block the double-fire
    if (title.trim().length === 0) return;
    inFlight.current = true;
    setSubmitting(true);
    setError(null);
    try {
      await onSubmit({
        title: title.trim(),
        ...(description.trim() ? { body: description.trim() } : {}),
      });
      onClose();
    } catch {
      // Board already rolled back the optimistic card + toasted; keep the form
      // values so the user can retry without re-typing.
      setError("Couldn't create the issue. Please try again.");
    } finally {
      inFlight.current = false;
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="New issue"
        className="w-full max-w-md rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-6 shadow-xl"
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
            <button
              type="button"
              disabled={!CONCIERGE_ONLINE}
              className="rounded-md border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-secondary disabled:cursor-not-allowed disabled:opacity-60"
            >
              Create with Concierge
            </button>
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
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-4 py-2 text-sm font-medium text-soleur-text-primary disabled:opacity-60"
            >
              Cancel
            </button>
            <GoldButton type="submit" disabled={!canSubmit}>
              {submitting ? "Creating…" : "Create issue"}
            </GoldButton>
          </div>
        </form>
      </div>
    </div>
  );
}
