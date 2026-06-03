"use client";

import { useReconnect } from "@/components/repo/use-reconnect";

interface ReconnectNoticeProps {
  /**
   * `card`  — inside the settings ProjectSetupCard body (constrained width).
   * `banner` — full-width above the KB tree. Variant only adjusts layout.
   */
  variant: "card" | "banner";
  /**
   * Surface-specific refresh on a successful reconnect. Settings passes
   * `router.refresh()` (server-rendered prop); the KB view passes
   * `refreshTree` (client-fetched state) — NOT `router.refresh()`.
   */
  onReconnected: () => void;
}

// Single honest copy string — no per-surface drift.
const COPY =
  "This project can't sync — reconnect to restore Knowledge Base updates. " +
  "Reconnect re-authorizes GitHub access so syncing can resume.";

export function ReconnectNotice({ variant, onReconnected }: ReconnectNoticeProps) {
  const { reconnect, isPending } = useReconnect(onReconnected);

  // Amber notice family, mirroring the existing red treatment
  // (`border-red-800 bg-red-950/50 text-red-400`) in amber.
  return (
    <div
      role="alert"
      className={`flex flex-col gap-3 rounded-lg border border-amber-800 bg-amber-950/50 p-4 text-amber-400 sm:flex-row sm:items-center sm:justify-between ${
        variant === "banner" ? "w-full" : ""
      }`}
    >
      <p className="text-sm">{COPY}</p>
      <button
        type="button"
        onClick={reconnect}
        disabled={isPending}
        className="inline-flex shrink-0 items-center justify-center rounded-lg border border-amber-800 bg-amber-950/50 px-4 py-2 text-sm font-medium text-amber-300 transition-colors hover:bg-amber-900/50 hover:text-amber-200 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending ? "Reconnecting…" : "Reconnect"}
      </button>
    </div>
  );
}
