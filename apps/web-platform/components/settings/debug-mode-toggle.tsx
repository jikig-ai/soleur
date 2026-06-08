"use client";

import { useState, useCallback } from "react";

/**
 * feat-debug-mode-stream — per-workspace internal "debug mode" toggle (FR2).
 *
 * When ON, the conversation surface shows a separate collapsed debug panel that
 * streams REDACTED harness SDK events for this workspace. Unlike autonomous
 * mode this is NOT an approval bypass — it is render-only, ephemeral, and
 * dev-cohort-only — so there is no risk interstitial; turning it on streams
 * nothing the operator can't already see, just in raw harness form.
 *
 * Visible ONLY to the Soleur `dev` cohort (the caller gates on
 * `isDebugModeAvailable`). Owner-WRITE: the underlying RPC raises for
 * non-owners; a non-owner dev sees the current state as a disabled (read-only)
 * switch rather than a flip they can't perform.
 */
export function DebugModeToggle({
  initialDebugMode,
  isOwner,
}: {
  initialDebugMode: boolean;
  isOwner: boolean;
}) {
  const [debugMode, setDebugMode] = useState(initialDebugMode);
  const [loading, setLoading] = useState(false);

  const persist = useCallback(async (value: boolean) => {
    setLoading(true);
    try {
      const res = await fetch("/api/workspace/debug-mode", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ value }),
      });
      if (res.ok) {
        const data = (await res.json()) as { debugMode?: boolean };
        setDebugMode(data.debugMode ?? value);
      } else {
        // Never silently swallow a non-OK response — a failed write must be
        // visible, not a toggle that snaps back with no signal.
        console.error("[debug-mode-toggle] write failed:", res.status);
        window.alert(
          res.status === 403
            ? "Only a workspace owner can change debug mode."
            : "Couldn't update debug mode. Please try again.",
        );
      }
    } catch (err) {
      console.error("[debug-mode-toggle] request failed:", err);
      window.alert(
        "Something went wrong. Please check your connection and try again.",
      );
    } finally {
      setLoading(false);
    }
  }, []);

  const handleToggleClick = useCallback(() => {
    if (loading || !isOwner) return;
    void persist(!debugMode);
  }, [debugMode, loading, isOwner, persist]);

  return (
    <div className="flex items-center justify-between gap-4">
      <div className="flex flex-col gap-1">
        <span className="text-sm font-semibold text-soleur-text-primary">
          Debug mode (internal)
        </span>
        <span className="text-xs text-soleur-text-muted">
          Show a separate panel streaming this workspace&apos;s harness events
          (redacted tool inputs, reasoning, results). Render-only and{" "}
          <strong>not saved</strong>. Visible only to the Soleur team.
          {!isOwner && " Owner-only — read-only for you."}
        </span>
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={debugMode}
        aria-label="Debug mode"
        disabled={loading || !isOwner}
        onClick={handleToggleClick}
        className={`relative inline-flex h-5 w-9 shrink-0 rounded-full border-2 border-transparent transition-colors ${
          debugMode ? "bg-soleur-accent-gold-fg" : "bg-soleur-bg-surface-2"
        } ${loading || !isOwner ? "cursor-not-allowed opacity-50" : "cursor-pointer"}`}
      >
        <span
          className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform ${
            debugMode ? "translate-x-4" : "translate-x-0"
          }`}
        />
      </button>
    </div>
  );
}
