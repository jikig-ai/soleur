"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { usePendingRouter } from "@/hooks/use-pending-router";

interface DisconnectRepoDialogProps {
  repoName: string;
}

export function DisconnectRepoDialog({ repoName }: DisconnectRepoDialogProps) {
  const router = usePendingRouter();
  const [isOpen, setIsOpen] = useState(false);
  const [isDisconnecting, setIsDisconnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleDisconnect() {
    setIsDisconnecting(true);
    setError(null);

    try {
      const res = await fetch("/api/repo/disconnect", {
        method: "DELETE",
      });

      const data = await res.json();

      if (!res.ok || !data.ok) {
        setError(data.error || "Failed to disconnect. Please try again.");
        setIsDisconnecting(false);
        return;
      }

      router.push("/connect-repo");
    } catch {
      setError("Network error. Please try again.");
      setIsDisconnecting(false);
    }
  }

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
      <p className="mb-4 text-sm text-soleur-text-secondary">
        This will unlink <span className="font-mono text-soleur-text-primary">{repoName}</span>{" "}
        from your account. Your workspace files will be removed. You can reconnect
        a repository at any time.
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
          className="text-soleur-text-secondary hover:text-soleur-text-primary"
        >
          Cancel
        </Button>
      </div>
    </div>
  );
}
