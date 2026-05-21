"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { OrgSwitcher } from "@/components/dashboard/org-switcher";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";

// Container pairs OrgSwitcher (pure UI) with the runtime data plumbing:
//   - on mount: GET /api/workspace/list-memberships
//   - on switch: POST /api/workspace/set-current-organization, then call
//     supabase.auth.refreshSession() so the JWT custom claim (migration 056)
//     re-mints with the new app_metadata.current_organization_id, then reload
//     so server components re-render against the new claim.
//
// AC-C is enforced by OrgSwitcher itself (returns null when count <= 1). Until
// the fetch resolves we render null too — no spinner — so the chip never
// "flashes in then out" for solo users.

export function OrgSwitcherContainer() {
  const [memberships, setMemberships] = useState<OrgMembershipSummary[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/workspace/list-memberships")
      .then((res) => (res.ok ? res.json() : Promise.reject(res.status)))
      .then((json: { memberships: OrgMembershipSummary[] }) => {
        if (!cancelled) setMemberships(json.memberships);
      })
      .catch(() => {
        // Silent failure — the chip stays hidden. Sentry-side breadcrumb is
        // not added here because a transient 5xx from the API would otherwise
        // alarm on every page load for solo users.
        if (!cancelled) setMemberships([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const handleSwitch = useCallback(async (organizationId: string) => {
    const res = await fetch("/api/workspace/set-current-organization", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ organizationId }),
    });
    if (!res.ok) {
      console.error("[org-switcher] set-current-organization failed:", res.status);
      window.alert("Failed to switch workspace. Please try again.");
      return;
    }
    // Force JWT custom-claim refresh so all tabs pick up the new
    // app_metadata.current_organization_id within ~1s (AC-FLOW3).
    try {
      const supabase = createClient();
      await supabase.auth.refreshSession();
    } catch (err) {
      console.error("[org-switcher] refreshSession failed:", err);
    }
    window.location.reload();
  }, []);

  if (memberships === null) return null;
  // AC-C: collapse the sidebar band entirely for solo users — no border, no
  // padding — so the dashboard chrome is indistinguishable from before
  // multi-tenant support landed.
  if (memberships.length <= 1) return null;
  return (
    <div className="border-b border-soleur-border-default px-3 py-3">
      <OrgSwitcher memberships={memberships} onSwitch={handleSwitch} />
    </div>
  );
}
