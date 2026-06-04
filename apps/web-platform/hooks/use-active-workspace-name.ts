"use client";

import { useCallback, useEffect, useState } from "react";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";

// The active workspace NAME, for the collapsed rail band (which does NOT mount
// OrgSwitcherContainer and therefore has no membership data in scope — P0-3,
// #4915). Modeled on use-active-repo.ts: a module-level in-flight latch
// coalesces THIS hook's own concurrent callers into ONE GET. (It does NOT
// coalesce with OrgSwitcherContainer's separate raw fetch — that lives in the
// container's own effect; the two only overlap when both are mounted, which the
// `enabled` gate below avoids by only fetching in the collapsed state where the
// container is absent.)
//
// This is a HOOK, not a component — it is outside the scope of the
// nav-single-mount.test.ts import guard (which tracks OrgSwitcherContainer +
// LiveRepoBadge component imports), so reading membership data here does not
// violate the single-mount invariant.

let inFlight: Promise<string | null> | null = null;

async function fetchActiveWorkspaceNameCoalesced(): Promise<string | null> {
  if (inFlight) return inFlight;
  inFlight = (async () => {
    try {
      const res = await fetch("/api/workspace/list-memberships");
      if (!res.ok) return null; // transient — caller keeps last-known, no flash
      const json = (await res.json()) as {
        memberships: OrgMembershipSummary[];
      };
      const current =
        json.memberships.find((m) => m.isCurrent) ?? json.memberships[0];
      return current?.organizationName ?? null;
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
export function __resetActiveWorkspaceNameCoalesceForTests(): void {
  inFlight = null;
}

/**
 * @param enabled When false, the hook performs no fetch and registers no focus
 *   listener (returns last-known or null). The collapsed rail is the only
 *   consumer of the name, so the layout passes `collapsed` here — the expanded
 *   rail + mobile band already surface the name via OrgSwitcherContainer.
 */
export function useActiveWorkspaceName(enabled = true): string | null {
  const [name, setName] = useState<string | null>(null);

  const poll = useCallback(async () => {
    const next = await fetchActiveWorkspaceNameCoalesced();
    if (next) setName(next); // keep last-known on transient null
  }, []);

  useEffect(() => {
    if (!enabled) return;
    poll();
    const onFocus = () => poll();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [poll, enabled]);

  return name;
}
