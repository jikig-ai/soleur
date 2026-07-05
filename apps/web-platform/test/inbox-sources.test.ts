import { describe, it, expect } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchInboxSources } from "@/server/inbox-sources";

// Regression guard for the "never hide a statutory clock" invariant AT THE FETCH
// LAYER (review: user-impact P1). The merge (lib/inbox-severity) pins EVERY
// non-archived statutory row including status='acknowledged', but the fetch must
// return them UNCAPPED — a pinned query filtered to status='new' would let an
// acknowledged statutory clock fall into the capped rest tail and be dropped
// past LIST_LIMIT. We record the query-builder calls per `.from()` and assert
// the pinned email query fetches all non-archived statutory (not just 'new').

interface Recorder {
  table: string;
  calls: Array<[string, ...unknown[]]>;
}

function recordingClient(rowsByFrom: Record<string, unknown[][]>): {
  client: SupabaseClient;
  recorders: Recorder[];
} {
  const recorders: Recorder[] = [];
  const counters: Record<string, number> = {};
  const client = {
    from(table: string) {
      const rec: Recorder = { table, calls: [] };
      recorders.push(rec);
      const idx = (counters[table] = (counters[table] ?? 0) + 1) - 1;
      const chain: Record<string, unknown> = {};
      const method =
        (name: string) =>
        (...args: unknown[]) => {
          rec.calls.push([name, ...args]);
          return chain;
        };
      for (const m of ["select", "not", "neq", "eq", "or", "is", "order", "limit"]) {
        chain[m] = method(m);
      }
      // Thenable: awaiting the chain resolves to the fixture rows for this
      // (table, nth-from-call).
      chain.then = (resolve: (v: unknown) => void) =>
        resolve({ data: rowsByFrom[table]?.[idx] ?? [], error: null });
      return chain;
    },
  } as unknown as SupabaseClient;
  return { client, recorders };
}

describe("fetchInboxSources — pinned statutory is uncapped for ALL non-archived statuses", () => {
  it("pins acknowledged statutory (neq status archived), not just status='new'", async () => {
    const { client, recorders } = recordingClient({
      email_triage_items: [
        [{ id: "stat-ack", statutory_class: "dsar", status: "acknowledged" }], // pinned query result
        [], // rest query result
      ],
      inbox_item: [[]],
    });

    const { emailRows } = await fetchInboxSources(client, { archived: false });

    // The acknowledged statutory row is returned via the (uncapped) pinned query.
    expect(emailRows.some((r) => (r as { id: string }).id === "stat-ack")).toBe(true);

    // The FIRST email_triage_items query is the pinned one. It must filter to
    // non-archived (any status), NEVER pin to status='new' (the bug).
    const pinned = recorders.find((r) => r.table === "email_triage_items")!;
    const hasStatutoryNotNull = pinned.calls.some(
      ([m, col, op]) => m === "not" && col === "statutory_class" && op === "is",
    );
    const hasNeqArchived = pinned.calls.some(
      ([m, col, val]) => m === "neq" && col === "status" && val === "archived",
    );
    const hasEqNew = pinned.calls.some(
      ([m, col, val]) => m === "eq" && col === "status" && val === "new",
    );
    expect(hasStatutoryNotNull).toBe(true);
    expect(hasNeqArchived).toBe(true);
    expect(hasEqNew).toBe(false); // regression: the old status='new' pin is gone
  });

  it("the pinned query carries NO .limit() (statutory is never capped)", async () => {
    const { client, recorders } = recordingClient({
      email_triage_items: [[], []],
      inbox_item: [[]],
    });
    await fetchInboxSources(client, { archived: false });
    const pinned = recorders.find((r) => r.table === "email_triage_items")!;
    expect(pinned.calls.some(([m]) => m === "limit")).toBe(false);
  });
});
