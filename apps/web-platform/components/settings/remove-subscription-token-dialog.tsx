"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";
import type { CredentialBasis } from "@/lib/credential-basis";

interface RemoveSubscriptionTokenDialogProps {
  /**
   * Result of `describeCredentialBasis` for the stored row. The SAME object
   * feeds the Settings status line, so the confirm copy and the status line
   * cannot disagree (decision-challenges.md item 29).
   */
  basis: CredentialBasis;
  /**
   * Called once on a successful removal, with the basis the user confirmed
   * against. The parent owns the post-removal notice: this component renders
   * nothing after success and unmounts when `router.refresh()` makes the
   * `basis` prop null.
   */
  onRemoved: (confirmedAgainst: CredentialBasis) => void;
  /** Variant B only: switch the form to the API-key field and focus it. */
  onAddApiKey: () => void;
}

/**
 * Inline expand-in-place confirm for removing a stored subscription token
 * (#11524). Mirrors `disconnect-repo-dialog.tsx`. Never claims Soleur revokes
 * the token at Anthropic; the billing consequence is named from props.
 */
export function RemoveSubscriptionTokenDialog({
  basis,
  onRemoved,
  onAddApiKey,
}: RemoveSubscriptionTokenDialogProps) {
  const router = useRouter();
  const [isOpen, setIsOpen] = useState(false);
  const [removed, setRemoved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // asyncFn never throws: failures land on the local `error` surface. No
  // latch(): success renders nothing here and the parent's refresh unmounts
  // us, so the episode releases normally on resolve.
  const { run: handleRemove, pending: isRemoving } = usePendingAction(
    async () => {
      setError(null);

      let res: Response;
      try {
        res = await fetch("/api/keys", {
          method: "DELETE",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ credential_type: "oauth_token" }),
        });
      } catch {
        setError("Network error. Please try again.");
        return;
      }

      if (!res.ok) {
        setError("Failed to remove the token. Please try again.");
        return;
      }

      setRemoved(true);
      onRemoved(basis);
      router.refresh();
    },
  );

  if (removed) return null;

  if (!isOpen) {
    return (
      <div className="mt-6 border-t border-soleur-border-default pt-6">
        <h3 className="mb-1 text-sm font-semibold text-soleur-text-primary">
          Subscription token
        </h3>
        <p className="mb-3 text-sm text-soleur-text-secondary">
          A Claude subscription token is saved for this account. It is stored
          encrypted and never shown here.
        </p>
        <Button
          variant="outlined"
          type="button"
          onClick={() => {
            setError(null);
            setIsOpen(true);
          }}
          className="border-red-900/50 text-red-400 hover:text-red-300"
        >
          Remove subscription token
        </Button>
      </div>
    );
  }

  return (
    <div
      className={`mt-6 rounded-xl border bg-soleur-bg-surface-1/50 p-6 ${
        basis.variant === "B"
          ? "border-red-500/60"
          : "border-soleur-border-default/50"
      }`}
    >
      <h3 className="mb-2 text-lg font-semibold text-soleur-text-primary">
        Remove subscription token?
      </h3>
      <p className="mb-4 text-sm text-soleur-text-secondary">
        {basis.dialogBody}
      </p>

      {error && (
        <p role="alert" className="mb-4 text-sm text-red-400">
          {error}
        </p>
      )}

      <div className="flex flex-wrap items-center gap-3">
        {basis.variant === "B" && (
          <Button
            variant="ghost"
            type="button"
            onClick={() => {
              setIsOpen(false);
              onAddApiKey();
            }}
            disabled={isRemoving}
            className="mr-auto text-soleur-accent-gold-fg"
          >
            Add an API key first
          </Button>
        )}
        <Button
          variant="outlined"
          type="button"
          autoFocus
          onClick={() => setIsOpen(false)}
          disabled={isRemoving}
        >
          Keep token
        </Button>
        <Button
          variant="danger"
          type="button"
          onClick={handleRemove}
          disabled={isRemoving}
          loading={isRemoving}
          loadingLabel="Removing"
        >
          Remove token
        </Button>
      </div>
    </div>
  );
}
