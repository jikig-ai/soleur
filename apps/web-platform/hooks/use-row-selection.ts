"use client";

// Row multi-select for the inbox surface (feat-inbox-bulk-archive, #9284).
// A `Set<key>` where key is `keyOf({kind,id})` — the format contract shared
// with the bulk-archive request body, results intersection, and prune.
// Extracted from inbox-surface (CTO plan-review): the select/toggle/select-all/
// prune bundle is the highest-bug-density logic in the feature and the
// template a second bulk surface should inherit.

import { useCallback, useEffect, useState } from "react";
import {
  archiveEligibility,
  keyOf,
  type BulkItemRef,
} from "@/lib/inbox-archive-eligibility";
import type { MergedInboxItem } from "@/lib/inbox-severity";

export function useRowSelection(items: MergedInboxItem[] | undefined) {
  const [selected, setSelected] = useState<ReadonlySet<string>>(new Set());

  // Prune on every data update: intersect the selection against keys that are
  // still rendered AND still archivable. This is what keeps the residual set
  // (guarded/conflict rows) selected after a bulk archive while dropping the
  // rows that just archived.
  useEffect(() => {
    if (!items) return;
    const archivable = new Set(
      items.filter((i) => archiveEligibility(i) === "ok").map(keyOf),
    );
    setSelected((prev) => {
      if ([...prev].every((k) => archivable.has(k))) return prev;
      return new Set([...prev].filter((k) => archivable.has(k)));
    });
  }, [items]);

  const toggle = useCallback((ref: BulkItemRef) => {
    const key = keyOf(ref);
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }, []);

  /** Toggle-all over a section's archivable rendered rows: if every archivable
   * row is selected, deselect them; otherwise select them all. */
  const toggleSection = useCallback((section: MergedInboxItem[]) => {
    const archivable = section.filter((i) => archiveEligibility(i) === "ok");
    setSelected((prev) => {
      const next = new Set(prev);
      const allSelected =
        archivable.length > 0 && archivable.every((i) => next.has(keyOf(i)));
      for (const i of archivable) {
        if (allSelected) next.delete(keyOf(i));
        else next.add(keyOf(i));
      }
      return next;
    });
  }, []);

  const clear = useCallback(() => setSelected(new Set()), []);

  /** Replace the selection with a computed set (post-mutation residual). */
  const setKeys = useCallback((keys: Iterable<string>) => {
    setSelected(new Set(keys));
  }, []);

  return { selected, toggle, toggleSection, clear, setKeys };
}
