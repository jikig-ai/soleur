"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";

interface DeleteAccountDialogProps {
  userEmail: string;
}

export function DeleteAccountDialog({ userEmail }: DeleteAccountDialogProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [confirmEmail, setConfirmEmail] = useState("");
  const [error, setError] = useState<string | null>(null);

  const emailMatches = confirmEmail === userEmail;

  // feat-ui-action-feedback: the app's most destructive control gets the
  // shared pending contract — a hung DELETE previously stranded the disabled
  // button with no watchdog, and latch() marks only the hard-nav path
  // terminal (every error path releases for retry).
  const { run: handleDelete, pending: isDeleting, latch } = usePendingAction(
    async () => {
      if (!emailMatches) return;

      setError(null);

      let res: Response;
      let data: { success?: boolean; error?: string; gitDataErasurePending?: boolean } = {};
      try {
        res = await fetch("/api/account/delete", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ confirmEmail }),
        });
        // res.json() inside the try — a non-JSON error body must land in the
        // catch, not in the hook's error slot nobody renders.
        data = await res.json();
      } catch {
        setError("Network error. Please try again.");
        return;
      }

      if (!res.ok || !data.success) {
        setError(data.error || "Deletion failed. Please try again.");
        return;
      }

      // Redirect to login after successful deletion. GAP F (ADR-067 staleTimes):
      // account deletion is the strongest principal-LEAVING boundary — hard-nav
      // so the App Router Router Cache is fully wiped (a soft push would leave
      // the deleted user's warm RSC shells reachable on this device).
      //
      // (#8094) THE HARD NAV STAYS UNCONDITIONAL, and the pending fact rides the URL.
      // A first cut of this change rendered the erasure-pending notice HERE and left
      // navigation to a "Continue" button — which made GAP F user-discretionary. The
      // cookies are already cleared by the response this fetch consumed, so the server
      // side was closed; but the page underneath the notice is the full authenticated
      // settings page, and with staleTimes.dynamic=30 a soft nav serves warm RSC
      // segments from client memory with no middleware round-trip. A deleted principal
      // could browse their own shells for as long as the notice sat open. The notice
      // belongs on the unauthenticated side of the boundary, not in front of it.
      latch();
      window.location.assign(
        data.gitDataErasurePending
          ? "/login?deleted=true&erasure=pending"
          : "/login?deleted=true",
      );
    },
  );

  if (!isOpen) {
    return (
      <Button
        variant="danger"
        type="button"
        onClick={() => setIsOpen(true)}
      >
        Delete Account
      </Button>
    );
  }

  return (
    <div className="rounded-xl border border-red-800/50 bg-red-950/20 p-6">
      <h3 className="mb-2 text-lg font-semibold text-red-400">
        Permanently delete your account
      </h3>
      <p className="mb-4 text-sm text-soleur-text-secondary">
        This action cannot be undone. All your data, API keys, conversations,
        and workspace files will be permanently deleted.
      </p>

      <label className="mb-2 block text-sm text-soleur-text-secondary">
        Type <span className="font-mono text-soleur-text-primary">{userEmail}</span> to
        confirm:
      </label>
      <input
        type="email"
        value={confirmEmail}
        onChange={(e) => setConfirmEmail(e.target.value)}
        placeholder={userEmail}
        className="mb-4 w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted focus:border-red-700 focus:outline-none focus:ring-1 focus:ring-red-700"
        autoComplete="off"
        spellCheck={false}
      />

      {error && (
        <p role="alert" className="mb-4 text-sm text-red-400">{error}</p>
      )}

      <div className="flex gap-3">
        <Button
          variant="danger"
          type="button"
          onClick={handleDelete}
          disabled={!emailMatches || isDeleting}
          loading={isDeleting}
          loadingLabel="Deleting"
        >
          Confirm Deletion
        </Button>
        <Button
          variant="outlined"
          type="button"
          onClick={() => {
            setIsOpen(false);
            setConfirmEmail("");
            setError(null);
          }}
          disabled={isDeleting}
          className="text-soleur-text-secondary hover:text-soleur-text-primary"
        >
          Cancel
        </Button>
      </div>
    </div>
  );
}
