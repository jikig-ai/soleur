"use client";

import { useCallback, useState } from "react";

// AC5: owner-only inline rename for the organization display name (the org
// switcher label). Non-owners see the name read-only — the edit affordance is
// gated on isOwner. Posts to POST /api/workspace/rename and updates the
// displayed name in place on success (no full reload).
export function RenameWorkspaceAction({
  organizationId,
  organizationName,
  isOwner,
}: {
  organizationId: string;
  organizationName: string | null;
  isOwner: boolean;
}) {
  const [name, setName] = useState(organizationName ?? "");
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(name);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = useCallback(async () => {
    const trimmed = draft.trim();
    if (trimmed.length === 0 || trimmed.length > 60) {
      setError("Workspace name must be 1–60 characters.");
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch("/api/workspace/rename", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ organizationId, name: trimmed }),
      });
      if (!res.ok) {
        setError("Couldn't rename workspace. Please try again.");
        setSubmitting(false);
        return;
      }
      setName(trimmed);
      setEditing(false);
      setSubmitting(false);
    } catch {
      setError("Couldn't rename workspace. Please try again.");
      setSubmitting(false);
    }
  }, [draft, organizationId]);

  return (
    <div className="mb-6 flex flex-col gap-2">
      <div className="flex flex-wrap items-center gap-3">
        <span className="text-xs uppercase tracking-wider text-soleur-text-muted">
          Workspace
        </span>
        <span
          data-testid="workspace-name"
          className="text-sm font-medium text-soleur-text-primary"
        >
          {name || "Untitled"}
        </span>
        {isOwner && !editing && (
          <button
            type="button"
            onClick={() => {
              setDraft(name);
              setError(null);
              setEditing(true);
            }}
            className="text-xs text-soleur-accent-gold-fg underline decoration-dotted underline-offset-2 hover:opacity-90"
          >
            Rename
          </button>
        )}
      </div>
      {editing && (
        <div className="flex flex-col gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <input
              aria-label="Workspace name"
              value={draft}
              maxLength={60}
              onChange={(e) => setDraft(e.target.value)}
              className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2/50 px-3 py-1.5 text-sm text-soleur-text-primary outline-none focus:border-soleur-border-emphasized"
            />
            <button
              type="button"
              onClick={save}
              disabled={submitting}
              className="rounded-md bg-soleur-accent-gold-fg px-3 py-1.5 text-sm font-medium text-soleur-bg-surface-1 disabled:cursor-not-allowed disabled:opacity-50 hover:opacity-90"
            >
              {submitting ? "Saving…" : "Save"}
            </button>
            <button
              type="button"
              onClick={() => {
                setEditing(false);
                setError(null);
              }}
              className="px-2 py-1.5 text-sm text-soleur-text-secondary hover:text-soleur-text-primary"
            >
              Cancel
            </button>
          </div>
          {error && (
            <p className="text-xs text-red-400" role="alert">
              {error}
            </p>
          )}
        </div>
      )}
    </div>
  );
}
