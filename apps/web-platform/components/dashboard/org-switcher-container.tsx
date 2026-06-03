"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { OrgSwitcher } from "@/components/dashboard/org-switcher";
import { getCurrentWorkspaceId } from "@/lib/session-claims";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";

// Container pairs OrgSwitcher (pure UI) with the runtime data plumbing.
//
// ADR-044 (#4543): the switch is now WORKSPACE-grain. Confirming a switch calls
// the membership-checked `set_current_workspace_id` RPC (migration 079), which
// writes BOTH current_workspace_id and current_organization_id to
// user_session_state, then `refreshSession()` re-mints the JWT so the hook
// claims propagate, then reload so server components re-render against the new
// active workspace's repo.
//
// The claim is read back from the SESSION JWT via getCurrentWorkspaceId(session)
// — NOT getUser(), whose raw_app_meta_data omits hook-injected claims
// (2026-05-27 learning). The confirm + status chain (switching → syncing →
// failed/retry) is inlined here, not split into a separate component (DHH).
//
// AC-C is enforced by OrgSwitcher itself (returns null when count <= 1). Until
// the fetch resolves we render null too — no spinner — so the chip never
// "flashes in then out" for solo users.

type SwitchStatus = "idle" | "switching" | "syncing" | "failed";

export function OrgSwitcherContainer() {
  const [memberships, setMemberships] = useState<OrgMembershipSummary[] | null>(null);
  const [pending, setPending] = useState<OrgMembershipSummary | null>(null);
  const [status, setStatus] = useState<SwitchStatus>("idle");

  useEffect(() => {
    let cancelled = false;
    fetch("/api/workspace/list-memberships")
      .then((res) => (res.ok ? res.json() : Promise.reject(res.status)))
      .then((json: { memberships: OrgMembershipSummary[] }) => {
        if (!cancelled) setMemberships(json.memberships);
      })
      .catch(() => {
        // Silent failure — the chip stays hidden. No Sentry breadcrumb: a
        // transient 5xx would otherwise alarm on every page load for solo users.
        if (!cancelled) setMemberships([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // Step 1: a row click arms the confirm step (confirm-then-switch). The target
  // is resolved to a full membership so we have the workspaceId for the RPC.
  const handleSelect = useCallback(
    (organizationId: string) => {
      const target = memberships?.find((m) => m.organizationId === organizationId);
      if (!target || target.isCurrent) return;
      setPending(target);
      setStatus("idle");
    },
    [memberships],
  );

  // Step 2: confirm executes the workspace switch + JWT refresh, then reloads.
  const executeSwitch = useCallback(async (target: OrgMembershipSummary) => {
    setStatus("switching");
    const supabase = createClient();
    const { error } = await supabase.rpc("set_current_workspace_id", {
      p_workspace_id: target.workspaceId,
    });
    if (error) {
      console.error("[workspace-switch] set_current_workspace_id failed:", error);
      setStatus("failed");
      return;
    }
    setStatus("syncing");
    try {
      const { data } = await supabase.auth.refreshSession();
      // AC9: verify the active-workspace claim from the SESSION JWT (hook
      // claims live in the decoded access token, not getUser()'s
      // raw_app_meta_data). A mismatch is logged but non-fatal — the source of
      // truth (user_session_state) is already written, and the reload re-reads
      // it server-side.
      const claimed = getCurrentWorkspaceId(data.session);
      if (claimed !== target.workspaceId) {
        console.warn(
          "[workspace-switch] claim not yet propagated to JWT; reloading anyway",
        );
      }
    } catch (err) {
      console.error("[workspace-switch] refreshSession failed:", err);
      setStatus("failed");
      return;
    }
    // RQ2 (brand-critical) — HARD navigation to the neutral /dashboard route,
    // NOT a soft router.push. The previous window.location.reload() was
    // load-bearing for correctness (it forced server components to re-render
    // against the freshly-minted JWT above); a soft nav would serve cached RSC
    // and land the user on STALE prior-tenant data. assign("/dashboard") gives
    // BOTH the neutral landing (never a tenant-sensitive pane for the new
    // workspace) AND the full RSC re-render. executeSwitch is shared by the
    // confirm AND failure→Retry paths, so this one change covers both.
    window.location.assign("/dashboard");
  }, []);

  const handleConfirm = useCallback(() => {
    if (pending) void executeSwitch(pending);
  }, [pending, executeSwitch]);

  const handleCancel = useCallback(() => {
    setPending(null);
    setStatus("idle");
  }, []);

  // No flash before the membership fetch resolves.
  if (memberships === null) return null;
  // RQ7: the band always surfaces the active-workspace name for orientation.
  // OrgSwitcher decides the affordance: an interactive switcher for multi-org
  // users, a non-interactive identity chip for solo users (and nothing at all
  // when there are zero memberships). The container no longer self-hides on
  // `<= 1` — the band owns the single render path for workspace identity.

  return (
    // No horizontal padding here — the WorkspaceContextBand identity row already
    // supplies px-3. A nested px-3 here double-padded the pill (#4810 follow-up
    // Bug 1: the bordered switch box painted past the rail's right edge).
    <div className="border-b border-soleur-border-default py-3">
      <OrgSwitcher memberships={memberships} onSwitch={handleSelect} />

      {pending && (
        <div
          data-testid="workspace-switch-confirm"
          role="dialog"
          aria-label="Confirm workspace switch"
          className="mt-3 rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 p-3 text-sm"
        >
          {status === "failed" ? (
            <>
              <p className="text-soleur-text-primary">
                Couldn&apos;t switch to{" "}
                <span className="font-medium">{pending.organizationName}</span>.
                Please try again.
              </p>
              <div className="mt-3 flex gap-2">
                <button
                  type="button"
                  onClick={handleConfirm}
                  className="rounded-md bg-soleur-accent-gold-fg/80 px-3 py-1.5 font-medium text-soleur-text-primary hover:bg-soleur-accent-gold-fg"
                >
                  Retry
                </button>
                <button
                  type="button"
                  onClick={handleCancel}
                  className="rounded-md border border-soleur-border-default px-3 py-1.5 text-soleur-text-muted hover:text-soleur-text-primary"
                >
                  Cancel
                </button>
              </div>
            </>
          ) : status === "switching" || status === "syncing" ? (
            <p
              data-testid="workspace-switch-status"
              className="text-soleur-text-muted"
            >
              {status === "switching"
                ? `Switching to ${pending.organizationName}…`
                : `Syncing ${pending.organizationName}…`}
            </p>
          ) : (
            <>
              <p className="text-soleur-text-primary">
                Switch to{" "}
                <span className="font-medium">{pending.organizationName}</span>?
                Your agents will run against that workspace&apos;s repo.
              </p>
              <div className="mt-3 flex gap-2">
                <button
                  type="button"
                  onClick={handleConfirm}
                  className="rounded-md bg-soleur-accent-gold-fg/80 px-3 py-1.5 font-medium text-soleur-text-primary hover:bg-soleur-accent-gold-fg"
                >
                  Confirm
                </button>
                <button
                  type="button"
                  onClick={handleCancel}
                  className="rounded-md border border-soleur-border-default px-3 py-1.5 text-soleur-text-muted hover:text-soleur-text-primary"
                >
                  Cancel
                </button>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}
