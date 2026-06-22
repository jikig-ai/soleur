"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { OrgSwitcher } from "@/components/dashboard/org-switcher";
import { useActiveRepo } from "@/hooks/use-active-repo";
import { getCurrentWorkspaceId } from "@/lib/session-claims";
import { reportSilentFallback } from "@/lib/client-observability";
import { WORKSPACE_LOGO_CHANGED_EVENT } from "@/lib/workspace-logo-events";
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

// #4917: the switch is a two-phase commit. `set_current_workspace_id` (the RPC)
// writes the DURABLE source of truth (user_session_state); `refreshSession()`
// re-mints the EPHEMERAL JWT. A failure BEFORE the RPC commits is safe to Cancel
// (nothing was written). A failure AFTER the RPC commits must NOT offer a Cancel
// that implies "nothing happened" — the durable state already points at the new
// workspace, and every server/* resolver reads it on the next render. The only
// honest path is forward: converge the client to /dashboard. We therefore split
// the single legacy "failed" state into pre- vs post-RPC discriminants so the
// render is exhaustive and the two failure UXs can diverge.
type SwitchStatus =
  | "idle"
  | "switching"
  | "syncing"
  | "failed_pre_rpc"
  | "failed_post_rpc";

// Cap the post-RPC offline retry so the UI never spins forever. After the cap,
// only the terminal converge-forward affordance (Continue) remains.
const MAX_POST_RPC_RETRIES = 2;

export function OrgSwitcherContainer({
  collapsed = false,
}: {
  /** Collapsed rail (md:w-14): render the icon-only identity via OrgSwitcher and
   *  suppress the switch-confirm dialog (no room at 56px). The container STAYS
   *  mounted across the collapse toggle, so `memberships` + the confirm
   *  (`pending`/`status`) state persist and the dialog reappears on expand —
   *  this is the fix for the band's former remount-on-collapse bug (ADR-047). */
  collapsed?: boolean;
} = {}) {
  const [memberships, setMemberships] = useState<OrgMembershipSummary[] | null>(null);
  const [pending, setPending] = useState<OrgMembershipSummary | null>(null);
  const [status, setStatus] = useState<SwitchStatus>("idle");
  // Counts post-RPC refresh re-attempts while offline (bounded by
  // MAX_POST_RPC_RETRIES). Reset at the start of every executeSwitch.
  const [postRpcRetries, setPostRpcRetries] = useState(0);
  // The active-repo name folds into the pill face as a muted subtitle. Same
  // self-healing source LiveRepoBadge uses; the hook coalesces concurrent
  // callers into one in-flight request, so the pill + interstitial share a
  // single active-repo fetch surface (no doubled poll despite two consumers).
  const { data: repo } = useActiveRepo();

  // Liveness latch so a refetch resolving after unmount never sets state.
  const mountedRef = useRef(true);
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  const loadMemberships = useCallback(() => {
    fetch("/api/workspace/list-memberships")
      .then((res) => (res.ok ? res.json() : Promise.reject(res.status)))
      .then((json: { memberships: OrgMembershipSummary[] }) => {
        if (mountedRef.current) setMemberships(json.memberships);
      })
      .catch(() => {
        // Silent failure — the chip stays hidden. No Sentry breadcrumb: a
        // transient 5xx would otherwise alarm on every page load for solo users.
        // Keep last-known on a refetch (never blank a populated switcher); fall
        // to [] only on the very first load so the chip stays hidden.
        if (mountedRef.current) setMemberships((prev) => prev ?? []);
      });
  }, []);

  useEffect(() => {
    loadMemberships();
    // A same-tab logo upload/removal nudges a memberships refetch so the
    // switcher reflects the new logo without a full reload (H1, AC4).
    const onLogoChange = () => loadMemberships();
    window.addEventListener(WORKSPACE_LOGO_CHANGED_EVENT, onLogoChange);
    return () => window.removeEventListener(WORKSPACE_LOGO_CHANGED_EVENT, onLogoChange);
  }, [loadMemberships]);

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

  // Converge the client forward to the durable truth. The RPC already committed
  // user_session_state to the new workspace; a HARD navigation to the neutral
  // /dashboard route forces server components to re-read it and re-mints the JWT
  // on the next load. This is the SINGLE navigation point — both the success
  // path and the post-RPC force-complete funnel through here, so there is no
  // double-`assign` even if a partial success races a catch (try/catch are
  // mutually exclusive). NOT a soft router.push: a soft nav would serve cached
  // RSC and land the user on STALE prior-tenant data.
  const forceComplete = useCallback(() => {
    window.location.assign("/dashboard");
  }, []);

  // Phase 2 of the two-phase commit: re-mint the JWT (refreshSession) AFTER the
  // RPC has committed, then converge. Extracted from executeSwitch so the
  // post-RPC offline retry can re-run JUST this phase — the RPC is already
  // durable and must not be re-issued.
  const attemptRefresh = useCallback(
    async (target: OrgMembershipSummary) => {
      setStatus("syncing");
      const supabase = createClient();
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
        forceComplete();
      } catch (err) {
        // POST-RPC failure: WRITE 1 (user_session_state) is ALREADY committed.
        // This is the brand-critical DB/JWT divergence path — mirror it to
        // Sentry (cq-silent-fallback-must-mirror-to-sentry) so an aggregate
        // pattern of refreshSession-after-commit failures is visible, unlike the
        // membership-fetch catch which stays console-only (transient/expected).
        console.error("[workspace-switch] refreshSession failed:", err);
        reportSilentFallback(err, {
          feature: "workspace-switch",
          op: "refresh-session-post-rpc",
          message:
            "[workspace-switch] refreshSession failed after committed RPC (DB/JWT divergence)",
        });
        // The durable state already reflects the user's intent (they clicked
        // Confirm). Converge forward — never offer a Cancel that lies. If we're
        // ONLINE, navigate now: the server is the source of truth and the JWT
        // re-mints on load. If we're OFFLINE, a navigation would hang, so park
        // in an honest "saved / will finish on reconnect" state whose only
        // affordances are a bounded Try-again and an always-present Continue.
        const offline =
          typeof navigator !== "undefined" && navigator.onLine === false;
        if (offline) {
          setStatus("failed_post_rpc");
          return;
        }
        forceComplete();
      }
    },
    [forceComplete],
  );

  // Step 2: confirm executes the workspace switch (RPC = WRITE 1, durable) then
  // hands off to the JWT re-mint phase.
  const executeSwitch = useCallback(
    async (target: OrgMembershipSummary) => {
      setStatus("switching");
      setPostRpcRetries(0);
      const supabase = createClient();
      const { error } = await supabase.rpc("set_current_workspace_id", {
        p_workspace_id: target.workspaceId,
      });
      if (error) {
        // PRE-RPC failure: nothing committed. Safe to Cancel back to the old
        // workspace. Transient/expected — console-only, no Sentry mirror.
        console.error("[workspace-switch] set_current_workspace_id failed:", error);
        setStatus("failed_pre_rpc");
        return;
      }
      await attemptRefresh(target);
    },
    [attemptRefresh],
  );

  const handleConfirm = useCallback(() => {
    if (pending) void executeSwitch(pending);
  }, [pending, executeSwitch]);

  // Bounded post-RPC retry: re-run ONLY the refresh phase (the RPC is already
  // durable). Each attempt increments the counter; once it reaches
  // MAX_POST_RPC_RETRIES the render withdraws Try-again, leaving only Continue.
  const handlePostRpcRetry = useCallback(() => {
    if (!pending) return;
    setPostRpcRetries((n) => n + 1);
    void attemptRefresh(pending);
  }, [pending, attemptRefresh]);

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
    // Phase 2 (#4915): D4 borderless — the outer wrapper sheds its border-b;
    // grouping is conveyed by spacing/elevation, not a hard divider.
    <div className={collapsed ? "flex justify-center py-3" : "py-3"}>
      <OrgSwitcher
        memberships={memberships}
        onSwitch={handleSelect}
        repoName={repo?.repoName ?? null}
        collapsed={collapsed}
      />

      {/* Confirm dialog: suppressed in the cramped 56px collapsed rail, but the
          container is NOT unmounted — `pending`/`status` persist and the dialog
          re-renders on expand (the switch can only be armed from the expanded
          dropdown anyway, so nothing is stranded). */}
      {pending && !collapsed && (
        <div
          data-testid="workspace-switch-confirm"
          role="dialog"
          aria-label="Confirm workspace switch"
          className="mt-3 rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 p-3 text-sm"
        >
          {status === "failed_pre_rpc" ? (
            // PRE-RPC failure: nothing was committed. Retry re-issues the whole
            // switch; Cancel safely returns to the old workspace.
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
          ) : status === "failed_post_rpc" ? (
            // POST-RPC failure (offline only — the online branch force-completes
            // without rendering this state). The switch is ALREADY saved
            // server-side, so the copy is honest about that and there is NO
            // Cancel (it would imply nothing happened). Try-again re-runs just
            // the refresh and is bounded; Continue is the always-present
            // terminal converge-forward affordance.
            <>
              <p className="text-soleur-text-primary">
                You&apos;re offline — your switch to{" "}
                <span className="font-medium">{pending.organizationName}</span>{" "}
                is saved and will finish when you reconnect.
              </p>
              <div className="mt-3 flex gap-2">
                {postRpcRetries < MAX_POST_RPC_RETRIES && (
                  <button
                    type="button"
                    onClick={handlePostRpcRetry}
                    className="rounded-md border border-soleur-border-default px-3 py-1.5 text-soleur-text-muted hover:text-soleur-text-primary"
                  >
                    Try again
                  </button>
                )}
                <button
                  type="button"
                  onClick={forceComplete}
                  className="rounded-md bg-soleur-accent-gold-fg/80 px-3 py-1.5 font-medium text-soleur-text-primary hover:bg-soleur-accent-gold-fg"
                >
                  Continue
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
