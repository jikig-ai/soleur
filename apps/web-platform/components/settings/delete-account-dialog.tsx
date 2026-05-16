"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface DeleteAccountDialogProps {
  userEmail: string;
}

export function DeleteAccountDialog({ userEmail }: DeleteAccountDialogProps) {
  const router = useRouter();
  const [isOpen, setIsOpen] = useState(false);
  const [confirmEmail, setConfirmEmail] = useState("");
  const [isDeleting, setIsDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

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

      // Redirect to login after successful deletion
      router.push("/login?deleted=true");
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
