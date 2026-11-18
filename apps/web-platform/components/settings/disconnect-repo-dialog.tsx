"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { usePendingRouter } from "@/hooks/use-pending-router";
import { usePendingAction } from "@/hooks/use-pending-action";
import { disconnectHeldBody, disconnectHeldWarning, type HeldRouteState } from "@/lib/kb-sync-held-copy";

interface DisconnectRepoDialogProps {
  repoName: string;
  /** #12704 V8 — the held-files count of the card (display-only); a renderable count adds the warning paragraph. */
  heldFiles?: number | null;
  /** #12704 V8 — the publish route; only "available" adds the publish step (a blip or an unknown role gives none). */
  heldRoute?: HeldRouteState;
}

export function DisconnectRepoDialog({ repoName, heldFiles = null, heldRoute = "unknown" }: DisconnectRepoDialogProps) {
  // V8: a caution above the dialog's own paragraph (nothing failed, so not a red error); Disconnect is never blocked.
  const heldWarning = disconnectHeldWarning(heldFiles, heldRoute);
  const body = disconnectHeldBody(heldFiles);
  const router = usePendingRouter();
  const [isOpen, setIsOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // feat-ui-action-feedback: shared pending contract — a hung DELETE
  // previously stranded the disabled Confirm with no watchdog. No latch():
  // success is a SOFT push (the nav bar owns feedback to commit), so the
  // episode releases normally on resolve.
  const { run: handleDisconnect, pending: isDisconnecting } = usePendingAction(
    async () => {
      setError(null);

      let res: Response;
      let data: { ok?: boolean; error?: string } = {};
      try {
        res = await fetch("/api/repo/disconnect", {
          method: "DELETE",
        });
        // res.json() inside the try — a non-JSON error body throws into the
        // catch, not into the hook's error slot nobody renders.
        data = await res.json();
      } catch {
        setError("Network error. Please try again.");
        return;
      }

      if (!res.ok || !data.ok) {
        setError(data.error || "Failed to disconnect. Please try again.");
        return;
      }

      router.push("/connect-repo");
    },
  );

  if (!isOpen) {
    return (
      <Button
        variant="outlined"
        type="button"
        onClick={() => setIsOpen(true)}
        className="text-soleur-text-secondary hover:text-soleur-text-primary"
      >
        Disconnect
      </Button>
    );
  }

  return (
    <div className="rounded-xl border border-soleur-border-default/50 bg-soleur-bg-surface-1/50 p-6">
      <h3 className="mb-2 text-lg font-semibold text-soleur-text-primary">
        Disconnect repository
      </h3>
      {heldWarning && (
        <p
          data-testid="disconnect-held-warning"
          role="note"
          className="mb-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 px-4 py-3 text-sm leading-relaxed text-soleur-text-primary"
        >
          {heldWarning}
        </p>
      )}
      <p className="mb-4 text-sm text-soleur-text-secondary">
        {body.before}
        <span className="font-mono text-soleur-text-primary">{repoName}</span>
        {body.after}
      </p>

      {error && (
        <p role="alert" className="mb-4 text-sm text-red-400">{error}</p>
      )}

      <div className="flex gap-3">
        <Button
          variant="outlined"
          type="button"
          onClick={handleDisconnect}
          disabled={isDisconnecting}
          loading={isDisconnecting}
          loadingLabel="Disconnecting"
        >
          Confirm Disconnect
        </Button>
        <Button
          variant="outlined"
          type="button"
          onClick={() => {
            setIsOpen(false);
            setError(null);
          }}
          disabled={isDisconnecting}
          className="text-soleur-text-secondary hover:text-soleur-text-primary"
        >
          Cancel
        </Button>
      </div>
    </div>
  );
}
