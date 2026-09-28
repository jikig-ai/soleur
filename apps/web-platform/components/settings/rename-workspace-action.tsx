"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";
import {
  UNTITLED_FALLBACK,
  WORKSPACE_NAME_MAX,
  validateWorkspaceName,
} from "@/lib/workspace-name";

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
  const [error, setError] = useState<string | null>(null);

  // The validation early-return stays inside asyncFn: an invalid draft
  // resolves immediately — never starts a fetch, releases normally.
  // asyncFn never throws: failures land on the local `error` surface.
  const { run: save, pending: submitting } = usePendingAction(async () => {
    const validated = validateWorkspaceName(draft);
    if (!validated.ok) {
      setError(`Workspace name must be 1–${WORKSPACE_NAME_MAX} characters.`);
      return;
    }
    const trimmed = validated.trimmed;
    setError(null);
    try {
      const res = await fetch("/api/workspace/rename", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ organizationId, name: trimmed }),
      });
      if (!res.ok) {
        setError("Couldn't rename workspace. Please try again.");
        return;
      }
      setName(trimmed);
      setEditing(false);
    } catch {
      setError("Couldn't rename workspace. Please try again.");
    }
  });

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
          {name || UNTITLED_FALLBACK}
        </span>
        {isOwner && !editing && (
          <Button
            variant="ghost"
            type="button"
            onClick={() => {
              setDraft(name);
              setError(null);
              setEditing(true);
            }}
            className="text-xs underline decoration-dotted underline-offset-2"
            // text-soleur-accent-gold-fg loses Tailwind emit-order against the
            // ghost variant's text-soleur-text-secondary — preserve the gold
            // affordance via the token directly.
            style={{ color: "var(--soleur-accent-gold-fg)" }}
          >
            Rename
          </Button>
        )}
      </div>
      {editing && (
        <div className="flex flex-col gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <input
              aria-label="Workspace name"
              value={draft}
              maxLength={WORKSPACE_NAME_MAX}
              onChange={(e) => setDraft(e.target.value)}
              className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-2/50 px-3 py-1.5 text-sm text-soleur-text-primary outline-none focus:border-soleur-border-emphasized"
            />
            <Button
              variant="gold"
              type="button"
              onClick={save}
              disabled={submitting}
              loading={submitting}
              loadingLabel="Saving"
              className="rounded-md"
            >
              Save
            </Button>
            <Button
              variant="ghost"
              type="button"
              onClick={() => {
                setEditing(false);
                setError(null);
              }}
              className="hover:text-soleur-text-primary"
            >
              Cancel
            </Button>
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
