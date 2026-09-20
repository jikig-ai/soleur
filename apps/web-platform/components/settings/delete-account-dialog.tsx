"use client";

import { useState } from "react";

interface DeleteAccountDialogProps {
  userEmail: string;
}

export function DeleteAccountDialog({ userEmail }: DeleteAccountDialogProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [confirmEmail, setConfirmEmail] = useState("");
  const [isDeleting, setIsDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // (#8094) The account is gone, but the git-data bare-repo erasure was not observed to
  // complete. We do NOT redirect straight to /login in that case: the redirect is the
  // dialog's way of saying "done", and saying "done" is the thing we must not do when
  // the server could not confirm the repository was erased.
  const [erasurePending, setErasurePending] = useState(false);

  const emailMatches = confirmEmail === userEmail;

  async function handleDelete() {
    if (!emailMatches) return;

    setIsDeleting(true);
    setError(null);

    try {
      const res = await fetch("/api/account/delete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ confirmEmail }),
      });

      const data = await res.json();

      if (!res.ok || !data.success) {
        setError(data.error || "Deletion failed. Please try again.");
        setIsDeleting(false);
        return;
      }

      // (#8094) Honest reporting: the cascade succeeded, but if the repository erasure
      // was refused or unconfirmed, tell the user that BEFORE navigating away. Three
      // published statements (DPD s10.3(b), T&C s14.1b and this dialog's own copy) say
      // the data is erased; an unacknowledged redirect here would assert all three
      // against something the server never observed.
      if (data.gitDataErasurePending) {
        setErasurePending(true);
        setIsDeleting(false);
        return;
      }

      // Redirect to login after successful deletion. GAP F (ADR-067 staleTimes):
      // account deletion is the strongest principal-LEAVING boundary — hard-nav
      // so the App Router Router Cache is fully wiped (a soft push would leave
      // the deleted user's warm RSC shells reachable on this device).
      window.location.assign("/login?deleted=true");
    } catch {
      setError("Network error. Please try again.");
      setIsDeleting(false);
    }
  }

  if (!isOpen) {
    return (
      <button
        type="button"
        onClick={() => setIsOpen(true)}
        className="rounded-lg border border-red-800 bg-red-950/50 px-4 py-2 text-sm font-medium text-red-400 transition-colors hover:bg-red-900/50 hover:text-red-300"
      >
        Delete Account
      </button>
    );
  }

  // (#8094) Terminal state: the account IS deleted (sign-out still happens on continue),
  // but one piece of stored data could not be confirmed erased. Stated plainly, with what
  // happens next, rather than buried behind a success redirect.
  if (erasurePending) {
    return (
      <div className="rounded-xl border border-amber-700/50 bg-amber-950/20 p-6">
        <h3 className="mb-2 text-lg font-semibold text-amber-400">
          Your account is deleted — one step is still pending
        </h3>
        <p role="status" className="mb-4 text-sm text-soleur-text-secondary">
          Your account and its data have been deleted. We could not confirm that your
          stored repository was erased from its host, so we are not going to tell you it
          was. It is recorded as outstanding and our team has been alerted to complete
          it. If you would like written confirmation once it is done, contact support and
          reference this deletion.
        </p>
        <button
          type="button"
          onClick={() => window.location.assign("/login?deleted=true")}
          className="rounded-lg bg-soleur-bg-surface-2 px-4 py-2 text-sm font-medium text-soleur-text-primary transition-colors hover:bg-soleur-bg-surface-3"
        >
          Continue
        </button>
      </div>
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
        <button
          type="button"
          onClick={handleDelete}
          disabled={!emailMatches || isDeleting}
          className="rounded-lg bg-red-700 px-4 py-2 text-sm font-medium text-soleur-text-on-accent transition-colors hover:bg-red-600 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {isDeleting ? "Deleting..." : "Confirm Deletion"}
        </button>
        <button
          type="button"
          onClick={() => {
            setIsOpen(false);
            setConfirmEmail("");
            setError(null);
          }}
          className="rounded-lg border border-soleur-border-default px-4 py-2 text-sm text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
