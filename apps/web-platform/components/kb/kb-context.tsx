"use client";

import { createContext, useContext } from "react";
import type { TreeNode } from "@/server/kb-reader";

export interface KbContextValue {
  tree: TreeNode | null;
  loading: boolean;
  error: "workspace-not-ready" | "not-found" | "unknown" | null;
  expanded: Set<string>;
  toggleExpanded: (path: string) => void;
  refreshTree: () => Promise<void>;
}

export const KbContext = createContext<KbContextValue | null>(null);

export function useKb(): KbContextValue {
  const ctx = useContext(KbContext);
  if (!ctx) throw new Error("useKb must be used within KbLayout");
  return ctx;
}
