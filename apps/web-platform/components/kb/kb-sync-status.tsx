"use client";

import { useState } from "react";

// #4224 — single merged badge+button. Two primary states (synced / desync)
// plus an implicit in-flight overlay. Empty-state renders the synced variant
// with "Workspace ready" copy (Kieran #10 + Simplicity #1 — avoids a third
// dedicated state).
//
// Inline 12-line discriminator handles the heterogeneous JSONB array:
//   - legacy `{ date, count }` rows (recordKbSyncHistory)        → treated as synced
//   - new rich `{ at, trigger, ok, … }` rows (appendKbSyncRow)   → ok flag drives state
//
// Do NOT extract a normalizer module until a second consumer exists
// (Simplicity #1, DHH #2).

export type KbSyncHistoryRow =
  | { date: string; count: number }
  | {
      at: string;
      trigger: "webhook_push" | "manual" | "session";
      ok: boolean;
      sha_before?: string;
      sha_after?: string;
      error_class?: string;
      push_received_at?: number;
      sync_completed_at: number;
    };

type SyncErrorPayload = {
  error?: string;
  code?: string;
  status: number;
};

export interface KbSyncStatusProps {
  /** Latest entry from the user's `kb_sync_history` JSONB array, or null
   * for never-synced operators. */
  lastSync: KbSyncHistoryRow | null;
  /** Called after a successful manual sync. The caller is expected to
   * refetch the latest row + KB tree. */
  onSynced?: () => void;
  /** Called when /api/kb/sync returns a non-2xx response. */
  onError?: (err: SyncErrorPayload) => void;
}

type Variant = "synced" | "desync";

function discriminate(row: KbSyncHistoryRow | null): {
  variant: Variant;
  label: string;
} {
  if (row === null) {
    return { variant: "synced", label: "Workspace ready" };
  }
  // Legacy {date, count} rows always treated as synced — they predate the
  // ok/error_class schema and only convey the daily file count.
  if ("date" in row && "count" in row) {
    return { variant: "synced", label: `Synced ${row.date}` };
  }
  if ("ok" in row && row.ok) {
    return { variant: "synced", label: relativeLabel(row.at) };
  }
  return { variant: "desync", label: "Workspace out of sync" };
}

function relativeLabel(at: string): string {
  const ms = Date.now() - new Date(at).getTime();
  if (!Number.isFinite(ms) || ms < 0) return "Synced just now";
  const sec = Math.floor(ms / 1000);
  if (sec < 60) return "Synced just now";
  const min = Math.floor(sec / 60);
  if (min < 60) return `Synced ${min}m ago`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `Synced ${hr}h ago`;
  return `Synced ${Math.floor(hr / 24)}d ago`;
}

export function KbSyncStatus({ lastSync, onSynced, onError }: KbSyncStatusProps) {
  const [pending, setPending] = useState(false);
  const { variant, label } = discriminate(lastSync);

  async function handleSyncNow() {
    if (pending) return;
    setPending(true);
    try {
      const res = await fetch("/api/kb/sync", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{}",
      });
      if (!res.ok) {
        let payload: { error?: string; code?: string } = {};
        try {
          payload = await res.json();
        } catch {
          // ignore body parse errors
        }
        onError?.({ ...payload, status: res.status });
        return;
      }
      onSynced?.();
    } catch (err) {
      onError?.({
        status: 0,
        error: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setPending(false);
    }
  }

  const chipClass =
    variant === "desync"
      ? "text-soleur-text-warning"
      : "text-soleur-text-secondary";

  return (
    <div className="inline-flex items-center gap-2">
      <span className={`text-xs ${chipClass}`} data-testid="kb-sync-chip">
        {label}
      </span>
      <button
        type="button"
        onClick={handleSyncNow}
        disabled={pending}
        aria-label="Sync now"
        className="inline-flex items-center gap-1.5 rounded-lg border border-soleur-border-default px-2 py-1 text-xs font-medium text-soleur-text-secondary transition-colors hover:border-soleur-border-emphasized hover:text-soleur-text-primary disabled:opacity-60"
      >
        {pending ? "Syncing…" : "Sync now"}
      </button>
    </div>
  );
}
