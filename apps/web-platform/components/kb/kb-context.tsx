"use client";

import { createContext, useContext } from "react";
import type { TreeNode } from "@/server/kb-reader";
import type { KbSyncHistoryRow } from "@/components/kb/kb-sync-status";

export interface KbContextValue {
  tree: TreeNode | null;
  loading: boolean;
  error: "workspace-not-ready" | "not-found" | "unknown" | null;
  expanded: Set<string>;
  toggleExpanded: (path: string) => void;
  refreshTree: () => Promise<void>;
  // #4224 — last `kb_sync_history` row surfaced by `/api/kb/tree`.
  // `null` for never-synced operators. `KbContentHeader` reads this from
  // context and renders `<KbSyncStatus lastSync={...} />`.
  lastSync: KbSyncHistoryRow | null;
}

export const KbContext = createContext<KbContextValue | null>(null);

export function useKb(): KbContextValue {
  const ctx = useContext(KbContext);
  if (!ctx) throw new Error("useKb must be used within KbLayout");
  return ctx;
}
