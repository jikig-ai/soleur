"use client";

import { useCallback, useEffect, useState } from "react";

// ADR-044 (#4543): the active-workspace repo, kept truthful by run-time
// revalidation (poll on mount + window focus), NOT a realtime subscription. The
// active-repo endpoint reads workspaces-only (never users.repo_url) and
// self-heals J5 (access revocation) by resetting the claim to the personal
// workspace; consumers surface that via the `fellBackToSolo` signal.
//
// Extracted from live-repo-badge.tsx so BOTH the workspace pill (via
// OrgSwitcherContainer, which renders the repo as a subtitle) AND LiveRepoBadge
// (which owns the J5 revocation interstitial) can read the same active-repo
// state WITHOUT a second component mount — the single-mount invariant
// (nav-single-mount.test.ts) tracks component imports, and a hook is outside
// its scope.
//
// Fetch coalescing (module-level `inFlight`): the band mounts TWICE (CSS-
// exclusive mobile + rail), and each band now has two consumers of this hook,
// so a naive per-instance fetch would fire up to 4 concurrent GETs — and 4
// racing J5 corrective writes — on every mount/focus. All concurrent callers
// share one in-flight request; the latch self-clears when it settles.

export interface ActiveRepo {
  workspaceId: string;
  repoUrl: string | null;
  repoName: string | null;
  repoStatus: string;
  fellBackToSolo: boolean;
}

let inFlight: Promise<ActiveRepo | null> | null = null;

async function fetchActiveRepoCoalesced(): Promise<ActiveRepo | null> {
  if (inFlight) return inFlight;
  inFlight = (async () => {
    try {
      const res = await fetch("/api/workspace/active-repo");
      if (!res.ok) return null; // transient — caller keeps last-known, no flash
      return (await res.json()) as ActiveRepo;
    } catch {
      return null; // network blip — caller keeps last-known
    } finally {
      inFlight = null;
    }
  })();
  return inFlight;
}

// Test-only: clear the coalescing latch between tests so a deliberately
// never-resolving fetch stub in one test cannot poison the next.
export function __resetActiveRepoCoalesceForTests(): void {
  inFlight = null;
}

export function useActiveRepo(): { data: ActiveRepo | null } {
  const [data, setData] = useState<ActiveRepo | null>(null);

  const poll = useCallback(async () => {
    const next = await fetchActiveRepoCoalesced();
    if (next) setData(next); // keep last-known on transient null
  }, []);

  useEffect(() => {
    poll();
    const onFocus = () => poll();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [poll]);

  // #5394 — while the repo is `cloning`, poll every 2s so the chat composer
  // auto-transitions to ready (or error) WITHOUT a manual refresh (AC4). The
  // interval is keyed on `repoStatus`: it starts only while cloning and the
  // effect cleanup clears it the moment the status leaves cloning (ready /
  // error / not_connected) — self-stopping, no fetch after settle. Cleared on
  // unmount too. The module-level `inFlight` latch keeps this coalesced with the
  // mount+focus revalidation (no fetch multiplication with the nav badge).
  const repoStatus = data?.repoStatus;
  useEffect(() => {
    if (repoStatus !== "cloning") return;
    const id = setInterval(() => {
      poll();
    }, 2_000);
    return () => clearInterval(id);
  }, [repoStatus, poll]);

  return { data };
}
