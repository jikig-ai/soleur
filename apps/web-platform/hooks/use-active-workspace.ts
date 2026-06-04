"use client";

import { useCallback, useEffect, useState } from "react";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";

// The active workspace identity (name + id + hasLogo), for the collapsed rail
// band (which does NOT mount OrgSwitcherContainer and therefore has no
// membership data in scope — P0-3, #4915). Modeled on use-active-repo.ts: a
// module-level in-flight latch coalesces THIS hook's own concurrent callers
// into ONE GET. `workspaceId` + `hasLogo` ride the SAME fetch (extra fields on
// the existing /api/workspace/list-memberships payload — no new data path), so
// the collapsed band can render the logo (via the stable proxy `src`) with no
// extra request (#4916).
//
// This is a HOOK, not a component — it is outside the scope of the
// nav-single-mount.test.ts import guard.

export interface ActiveWorkspaceInfo {
  name: string | null;
  workspaceId: string | null;
  hasLogo: boolean;
}

const EMPTY: ActiveWorkspaceInfo = { name: null, workspaceId: null, hasLogo: false };

let inFlight: Promise<ActiveWorkspaceInfo | null> | null = null;

async function fetchActiveWorkspaceCoalesced(): Promise<ActiveWorkspaceInfo | null> {
  if (inFlight) return inFlight;
  inFlight = (async () => {
    try {
      const res = await fetch("/api/workspace/list-memberships");
      if (!res.ok) return null; // transient — caller keeps last-known, no flash
      const json = (await res.json()) as { memberships: OrgMembershipSummary[] };
      const current =
        json.memberships.find((m) => m.isCurrent) ?? json.memberships[0];
      if (!current) return null;
      return {
        name: current.organizationName ?? null,
        workspaceId: current.workspaceId,
        hasLogo: current.hasLogo,
      };
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
export function __resetActiveWorkspaceCoalesceForTests(): void {
  inFlight = null;
}

/**
 * @param enabled When false, the hook performs no fetch and registers no focus
 *   listener (returns last-known or empty). The collapsed rail is the only
 *   consumer, so the layout passes `collapsed` here — the expanded rail + mobile
 *   band already surface identity via OrgSwitcherContainer.
 */
export function useActiveWorkspace(enabled = true): ActiveWorkspaceInfo {
  const [info, setInfo] = useState<ActiveWorkspaceInfo>(EMPTY);

  const poll = useCallback(async () => {
    const next = await fetchActiveWorkspaceCoalesced();
    if (next) setInfo(next); // keep last-known on transient null
  }, []);

  useEffect(() => {
    if (!enabled) return;
    poll();
    const onFocus = () => poll();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [poll, enabled]);

  return info;
}
