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
        className="rounded-lg border border-neutral-700 px-4 py-2 text-sm font-medium text-neutral-400 transition-colors hover:bg-neutral-800 hover:text-white"
      >
        Disconnect
      </button>
    );
  }

  return (
    <div className="rounded-xl border border-neutral-700/50 bg-neutral-900/50 p-6">
      <h3 className="mb-2 text-lg font-semibold text-white">
        Disconnect repository
      </h3>
      <p className="mb-4 text-sm text-neutral-400">
        This will unlink <span className="font-mono text-white">{repoName}</span>{" "}
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
          className="rounded-lg border border-neutral-700 bg-neutral-800 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-neutral-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {isDisconnecting ? "Disconnecting..." : "Confirm Disconnect"}
        </button>
        <button
          type="button"
          onClick={() => {
            setIsOpen(false);
            setError(null);
          }}
          className="rounded-lg border border-neutral-700 px-4 py-2 text-sm text-neutral-400 transition-colors hover:bg-neutral-800 hover:text-white"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
