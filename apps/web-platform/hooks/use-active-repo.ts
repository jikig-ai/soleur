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

export interface ActiveRepo {
  workspaceId: string;
  repoUrl: string | null;
  repoName: string | null;
  repoStatus: string;
  fellBackToSolo: boolean;
}

export function useActiveRepo(): { data: ActiveRepo | null } {
  const [data, setData] = useState<ActiveRepo | null>(null);

  const poll = useCallback(async () => {
    try {
      const res = await fetch("/api/workspace/active-repo");
      if (!res.ok) return; // transient — keep last-known state, no flash
      const json = (await res.json()) as ActiveRepo;
      setData(json);
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

  return { data };
}
