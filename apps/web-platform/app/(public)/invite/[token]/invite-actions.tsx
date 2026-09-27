"use client";

import { NavLink } from "@/components/ui/nav-link";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";
import { usePendingRouter } from "@/hooks/use-pending-router";
import { reasonToMessage } from "./invite-reason-messages";

interface Props {
  invitationId: string;
  token: string;
  isAuthenticated: boolean;
  /** Email the invitation was addressed to (lower-cased server-side). */
  inviteeEmail: string;
  /** True when the signed-in account matches the invited email. Computed in page.tsx. */
  isIntendedInvitee: boolean;
  /** Email of the currently signed-in account (for the mismatch notice). */
  signedInEmail: string;
}

export function InviteActions({
  invitationId,
  token,
  isAuthenticated,
  inviteeEmail,
  isIntendedInvitee,
  signedInEmail,
}: Props) {
  const router = usePendingRouter();

  // Accept/decline share one logical action-group: while either is in flight
  // BOTH controls disable (`busy` below) so a decline can never race an
  // accept on the same invitation.
  // Accept latches on redirect — success ends in window.location.assign
  // (cross-workspace boundary) so pending must not release mid-nav. latch()
  // is explicit: only the nav path is terminal, every earlier path throws.
  const accept = usePendingAction(
    async () => {
      let res: Response;
      try {
        res = await fetch("/api/workspace/accept-invite", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ invitationId }),
        });
      } catch {
        throw new Error("Network error. Please try again.");
      }
      const data = await res.json();
      if (!res.ok) {
        throw new Error(
          reasonToMessage(data.error) || "Failed to accept invitation",
        );
      }
      // GAP E/workspace-switch (ADR-067 staleTimes): accept-invite calls
      // `set_current_workspace_id` server-side, so this is a CROSS-WORKSPACE
      // boundary for the same principal — the warm Router Cache still holds the
      // PREVIOUS workspace's RSC. Hard-nav to wipe it (mirrors the workspace
      // switch in components/dashboard/org-switcher-container.tsx); a soft push
      // would render the prior workspace's cached content under the new tenant.
      accept.latch();
      window.location.assign("/dashboard/settings/team");
    },
  );

  const decline = usePendingAction(async () => {
    let res: Response;
    try {
      res = await fetch("/api/workspace/decline-invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ invitationId }),
      });
    } catch {
      throw new Error("Network error. Please try again.");
    }
    const data = await res.json();
    if (!res.ok) {
      throw new Error(
        reasonToMessage(data.error) || "Failed to decline invitation",
      );
    }
    router.push("/dashboard");
  });

  const busy = accept.pending || decline.pending;
  const actionError = accept.error ?? decline.error;

  if (!isAuthenticated) {
    return (
      <div className="space-y-3">
        <NavLink
          href={`/signup?redirectTo=/invite/${token}`}
          className="block w-full rounded-md bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end px-4 py-3 text-center font-medium text-soleur-text-on-accent hover:opacity-90 transition-opacity"
        >
          Create an account to join
        </NavLink>
        <p className="text-center text-sm text-soleur-text-secondary">
          Already have an account?{" "}
          <NavLink
            href={`/login?redirectTo=/invite/${token}`}
            className="text-soleur-accent-gold-fg hover:underline"
          >
            Sign in
          </NavLink>
        </p>
      </div>
    );
  }

  // Signed in, but not the intended invitee: gate both actions and explain
  // (neutral copy, NOT the red failed-action box) which account to use.
  if (!isIntendedInvitee) {
    return (
      <div className="space-y-3">
        <p id="invite-mismatch-notice" className="text-sm text-soleur-text-secondary">
          This invitation was sent to{" "}
          <span className="font-medium text-soleur-text-primary">
            {inviteeEmail}
          </span>
          .{" "}
          {signedInEmail ? (
            <>
              You&apos;re signed in as{" "}
              <span className="font-medium text-soleur-text-primary">
                {signedInEmail}
              </span>
              .{" "}
            </>
          ) : null}
          Sign in with the invited account to accept.
        </p>
        <Button
          variant="gold"
          type="button"
          disabled
          aria-describedby="invite-mismatch-notice"
          className="w-full"
        >
          Accept invitation
        </Button>
        <NavLink
          href={`/login?redirectTo=/invite/${token}`}
          className="block w-full rounded-md border border-soleur-border-default px-4 py-3 text-center font-medium text-soleur-text-secondary hover:border-soleur-border-emphasized hover:text-soleur-text-primary transition-colors"
        >
          Sign in with a different account
        </NavLink>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {actionError && (
        <p role="alert" className="rounded-md bg-red-500/10 px-3 py-2 text-sm text-red-400">
          {actionError.message}
        </p>
      )}
      <Button
        variant="gold"
        onClick={accept.run}
        loading={accept.pending}
        loadingLabel="Accepting"
        disabled={busy}
        className="w-full"
      >
        Accept invitation
      </Button>
      <Button
        variant="outlined"
        onClick={decline.run}
        loading={decline.pending}
        loadingLabel="Declining"
        disabled={busy}
        className="w-full text-soleur-text-secondary"
      >
        Decline
      </Button>
    </div>
  );
}
