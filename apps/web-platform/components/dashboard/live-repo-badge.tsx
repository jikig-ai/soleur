"use client";

import { useCallback, useEffect, useState } from "react";

// ADR-044 (#4543): a persistent "Working on: owner/repo" badge for the user's
// ACTIVE workspace, kept truthful by run-time revalidation (poll on mount +
// window focus), NOT a realtime subscription. The active-repo endpoint reads
// workspaces-only (never users.repo_url) and self-heals J5 (access revocation)
// by resetting the claim to the personal workspace; this component surfaces
// that as the J5 interstitial.
//
// J6 (post-backfill default landing = personal workspace) needs no special
// handling here — with no current_workspace_id claim the endpoint resolves the
// solo workspace, and the badge shows its repo. J1/J7 (empty-workspace +
// connect-a-repo CTA) are deferred to #4560; the no-repo state renders minimal
// copy only.

interface ActiveRepo {
  workspaceId: string;
  repoUrl: string | null;
  repoName: string | null;
  repoStatus: string;
  fellBackToSolo: boolean;
}

export function LiveRepoBadge() {
  const [data, setData] = useState<ActiveRepo | null>(null);
  const [dismissed, setDismissed] = useState(false);

  const poll = useCallback(async () => {
    try {
      const res = await fetch("/api/workspace/active-repo");
      if (!res.ok) return; // transient — keep last-known state, no flash
      const json = (await res.json()) as ActiveRepo;
      setData(json);
      // A fresh fellBackToSolo signal re-arms the interstitial.
      if (json.fellBackToSolo) setDismissed(false);
    } catch {
      // Network blip — keep last-known state. The next focus/mount re-polls.
    }
  }, []);

  useEffect(() => {
    poll();
    const onFocus = () => poll();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [poll]);

  // No flash for solo users until the first poll resolves.
  if (!data) return null;

  return (
    <div className="flex flex-col gap-2">
      {data.fellBackToSolo && !dismissed && (
        <div
          role="alert"
          data-testid="revocation-interstitial"
          className="flex items-start justify-between gap-3 rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm text-soleur-text-primary"
        >
          <span>
            You no longer have access to that workspace — returning to your
            personal workspace.
          </span>
          <button
            type="button"
            onClick={() => setDismissed(true)}
            aria-label="Dismiss notice"
            className="shrink-0 text-soleur-text-muted hover:text-soleur-text-primary"
          >
            ✕
          </button>
        </div>
      )}
      {data.repoName ? (
        <span
          data-testid="live-repo-badge"
          className="inline-flex items-center gap-1.5 text-xs text-soleur-text-muted"
        >
          <span aria-hidden="true" className="text-soleur-accent-gold-fg">
            ●
          </span>
          <span>
            Working on:{" "}
            <span className="font-medium text-soleur-text-primary">
              {data.repoName}
            </span>
          </span>
        </span>
      ) : (
        <span
          data-testid="live-repo-badge-empty"
          className="text-xs text-soleur-text-muted"
        >
          No repo connected
        </span>
      )}
    </div>
  );
}
