"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";
import { ResponsiveModal } from "@/components/ui/responsive-modal";

export function TransferOwnershipDialog({
  targetEmail,
  confirmationTarget,
  workspaceId,
  targetUserId,
  onClose,
  onSuccess,
}: {
  targetEmail: string;
  confirmationTarget: string;
  workspaceId: string;
  targetUserId: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  const matches = confirmation.trim().toLowerCase() === confirmationTarget.toLowerCase();

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // feat-ui-action-feedback: shared pending contract — the hand-rolled
  // version had NO catch on the fetch, so a transport failure left
  // `loading` true forever on an irreversible-action dialog (and an
  // unhandled rejection to boot). The watchdog + release covers it.
  const { run: runTransfer, pending: loading } = usePendingAction(
    async () => {
      if (!matches) return;
      setError("");

      const attestationText = `I voluntarily transfer ownership of this workspace to ${targetEmail}. I understand I will lose owner privileges including audit log access, member management, and GDPR controller designation.`;

      let res: Response;
      try {
        res = await fetch("/api/workspace/transfer-ownership", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            workspaceId,
            newOwnerUserId: targetUserId,
            attestationText,
          }),
        });
      } catch {
        setError("Transfer failed — network error. Please try again.");
        return;
      }

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        const message =
          data.error === "self_transfer"
            ? "Cannot transfer ownership to yourself."
            : data.error === "target_not_member"
              ? "Target user is not a member of this workspace."
              : data.error === "target_already_owner"
                ? "Target user is already the owner."
                : data.error === "workspace_mismatch"
                  ? "Workspace mismatch. Please reload and try again."
                  : "Transfer failed. Please try again.";
        setError(message);
        return;
      }

      onSuccess();
    },
  );

  const handleTransfer = useCallback(() => runTransfer(), [runTransfer]);

  return (
    <ResponsiveModal
      open={true}
      // Don't let Escape / backdrop dismiss the dialog mid-transfer — the POST
      // has no AbortController, so dismissing would hide an in-flight
      // irreversible ownership change. Matches the pre-refactor `!loading` guard.
      onClose={() => {
        if (!loading) onClose();
      }}
      closeOnBackdrop={!loading}
      desktopMaxWidth="max-w-md"
      aria-labelledby="transfer-ownership-title"
    >
      <h2
        id="transfer-ownership-title"
        className="text-lg font-semibold text-soleur-text-primary"
      >
        Transfer ownership
      </h2>

      <div className="mt-4 rounded-md border border-red-500/30 bg-red-500/5 p-3">
        <p className="text-sm font-medium text-red-400">
          This action cannot be undone by you.
        </p>
        <p className="mt-1 text-sm text-soleur-text-secondary">
          You will lose:
        </p>
        <ul className="mt-1 list-inside list-disc text-sm text-soleur-text-secondary">
          <li>Ability to invite and remove members</li>
          <li>Access to the workspace audit log</li>
          <li>GDPR controller designation for this workspace</li>
        </ul>
      </div>

      <p className="mt-4 text-sm text-soleur-text-secondary">
        To confirm, type{" "}
        <span className="font-mono font-medium text-soleur-text-primary">
          {confirmationTarget}
        </span>{" "}
        below:
      </p>

      <input
        ref={inputRef}
        type="text"
        value={confirmation}
        onChange={(e) => setConfirmation(e.target.value)}
        disabled={loading}
        className="mt-2 w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted focus:border-soleur-accent-gold-fg focus:outline-none focus:ring-1 focus:ring-soleur-accent-gold-fg disabled:opacity-50"
        placeholder={confirmationTarget}
        autoComplete="off"
        spellCheck={false}
      />

      {error && (
        <p className="mt-2 text-sm text-red-400">{error}</p>
      )}

      <div className="mt-4 flex justify-end gap-3">
        <Button
          variant="ghost"
          type="button"
          onClick={onClose}
          disabled={loading}
          className="rounded-md hover:text-soleur-text-primary"
        >
          Cancel
        </Button>
        <Button
          variant="danger"
          type="button"
          onClick={handleTransfer}
          disabled={!matches || loading}
          loading={loading}
          loadingLabel="Transferring"
          modal
          className="rounded-md hover:bg-red-700"
        >
          {`Transfer ownership to ${targetEmail.split("@")[0]}`}
        </Button>
      </div>
    </ResponsiveModal>
  );
}
