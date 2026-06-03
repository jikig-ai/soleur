"use client";

import { useEffect, useState } from "react";
import { useActiveRepo } from "@/hooks/use-active-repo";

// ADR-044 (#4543): the J5 (access-revocation) interstitial for the user's
// ACTIVE workspace. The active-repo endpoint reads workspaces-only (never
// users.repo_url) and self-heals J5 by resetting the claim to the personal
// workspace; this component surfaces that as the revocation alert.
//
// The "Working on: owner/repo" string this component used to render now lives
// as a muted subtitle inside the workspace pill (OrgSwitcher), fed by the same
// shared useActiveRepo() hook — so the band no longer burns a standalone row on
// it. This component is now interstitial-ONLY: it renders the alert when the
// API reports fellBackToSolo, else nothing. It stays mounted in
// workspace-context-band.tsx as the band's sole import (nav-single-mount).

export function LiveRepoBadge() {
  const { data } = useActiveRepo();
  const [dismissed, setDismissed] = useState(false);

  // A fresh fellBackToSolo signal re-arms the interstitial.
  useEffect(() => {
    if (data?.fellBackToSolo) setDismissed(false);
  }, [data?.fellBackToSolo]);

  // Nothing to surface: no data yet, no revocation, or already dismissed.
  if (!data || !data.fellBackToSolo || dismissed) return null;

  return (
    <div className="px-3 pb-2 pt-1">
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
    </div>
  );
}
