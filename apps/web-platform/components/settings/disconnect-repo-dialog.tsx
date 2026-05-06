"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface DisconnectRepoDialogProps {
  repoName: string;
}

export function DisconnectRepoDialog({ repoName }: DisconnectRepoDialogProps) {
  const router = useRouter();
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
      <button
        type="button"
        onClick={() => setIsOpen(true)}
        className="rounded-lg border border-soleur-border-default px-4 py-2 text-sm font-medium text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
      >
        Disconnect
      </button>
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
        <button
          type="button"
          onClick={handleDisconnect}
          disabled={isDisconnecting}
          className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 px-4 py-2 text-sm font-medium text-soleur-text-primary transition-colors hover:bg-soleur-bg-surface-2 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {isDisconnecting ? "Disconnecting..." : "Confirm Disconnect"}
        </button>
        <button
          type="button"
          onClick={() => {
            setIsOpen(false);
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
