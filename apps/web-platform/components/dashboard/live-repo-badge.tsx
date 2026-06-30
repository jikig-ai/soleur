"use client";

import { useEffect, useRef, useState } from "react";
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

  // A fresh fellBackToSolo signal re-arms the interstitial — but ONLY on a
  // genuine regained→revoked (false→true) transition. Gating on the previous
  // value (not just "fellBackToSolo is true") is load-bearing: the bare
  // `if (data?.fellBackToSolo) setDismissed(false)` form also fired on the
  // initial mount (undefined→true), and React runs this passive effect AFTER
  // commit, so if it landed after the user's dismiss click it reset
  // `dismissed` back to false and re-surfaced the alert (#5796 — an intermittent
  // ~10% race that timed out live-repo-badge.test.tsx's dismiss waits and
  // re-blocked deploys). On mount and on steady-state re-polls of the SAME
  // revocation, `prev` is undefined/true, so the dismissal is never undone;
  // only a regain (false) followed by a fresh revocation (true) re-arms.
  const prevFellBackToSolo = useRef<boolean | undefined>(undefined);
  useEffect(() => {
    const prev = prevFellBackToSolo.current;
    const curr = data?.fellBackToSolo;
    prevFellBackToSolo.current = curr;
    if (prev === false && curr === true) setDismissed(false);
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
