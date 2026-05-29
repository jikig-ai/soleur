"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

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

/**
 * Map a server reason code to human-readable copy so a raw code
 * (e.g. `not_intended_invitee`) never leaks into the UI, even on the
 * defensive 403 path the server enforces.
 */
function reasonToMessage(reason: string | undefined): string {
  switch (reason) {
    case "not_intended_invitee":
      return "This invitation isn't addressed to your account.";
    case "expired":
      return "This invitation has expired.";
    case "already_accepted":
    case "already_member":
      return "You've already joined this workspace.";
    case "already_declined":
      return "This invitation has already been declined.";
    case "invitation_not_found":
      return "This invitation is no longer available.";
    default:
      return reason ? "Something went wrong. Please try again." : "";
  }
}

export function InviteActions({
  invitationId,
  token,
  isAuthenticated,
  inviteeEmail,
  isIntendedInvitee,
  signedInEmail,
}: Props) {
  const router = useRouter();
  const [loading, setLoading] = useState<"accept" | "decline" | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (!isAuthenticated) {
    return (
      <div className="space-y-3">
        <Link
          href={`/signup?redirectTo=/invite/${token}`}
          className="block w-full rounded-md bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end px-4 py-3 text-center font-medium text-soleur-text-on-accent hover:opacity-90 transition-opacity"
        >
          Create an account to join
        </Link>
        <p className="text-center text-sm text-soleur-text-secondary">
          Already have an account?{" "}
          <Link
            href={`/login?redirectTo=/invite/${token}`}
            className="text-soleur-accent-gold-fg hover:underline"
          >
            Sign in
          </Link>
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
        <button
          type="button"
          disabled
          aria-describedby="invite-mismatch-notice"
          className="w-full rounded-md bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end px-4 py-3 font-medium text-soleur-text-on-accent opacity-50"
        >
          Accept invitation
        </button>
        <Link
          href={`/login?redirectTo=/invite/${token}`}
          className="block w-full rounded-md border border-soleur-border-default px-4 py-3 text-center font-medium text-soleur-text-secondary hover:border-soleur-border-emphasized hover:text-soleur-text-primary transition-colors"
        >
          Sign in with a different account
        </Link>
      </div>
    );
  }

  async function handleAccept() {
    setLoading("accept");
    setError(null);
    try {
      const res = await fetch("/api/workspace/accept-invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ invitationId }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(reasonToMessage(data.error) || "Failed to accept invitation");
        return;
      }
      router.push("/dashboard/settings/team");
    } catch {
      setError("Network error. Please try again.");
    } finally {
      setLoading(null);
    }
  }

  async function handleDecline() {
    setLoading("decline");
    setError(null);
    try {
      const res = await fetch("/api/workspace/decline-invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ invitationId }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(reasonToMessage(data.error) || "Failed to decline invitation");
        return;
      }
      router.push("/dashboard");
    } catch {
      setError("Network error. Please try again.");
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="space-y-3">
      {error && (
        <p role="alert" className="rounded-md bg-red-500/10 px-3 py-2 text-sm text-red-400">
          {error}
        </p>
      )}
      <button
        onClick={handleAccept}
        disabled={loading !== null}
        className="w-full rounded-md bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end px-4 py-3 font-medium text-soleur-text-on-accent hover:opacity-90 transition-opacity disabled:opacity-50"
      >
        {loading === "accept" ? "Accepting..." : "Accept invitation"}
      </button>
      <button
        onClick={handleDecline}
        disabled={loading !== null}
        className="w-full rounded-md border border-soleur-border-default px-4 py-3 font-medium text-soleur-text-secondary hover:border-soleur-border-emphasized hover:text-soleur-text-primary transition-colors disabled:opacity-50"
      >
        {loading === "decline" ? "Declining..." : "Decline"}
      </button>
    </div>
  );
}
