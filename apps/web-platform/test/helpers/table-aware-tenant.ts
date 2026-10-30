// A table-aware fake tenant client: routes on the table name and honours every `.eq()` filter, so a
// decoy row for another conversation / another creator is never served. The credential-lease tests
// historically used a table-blind `from: () =>` mock, which cannot prove a read is scoped (#11591).

export type FakeRow = Record<string, unknown>;

export interface TableAwareTenant {
  tables: Record<string, FakeRow[]>;
  /** Every `[table, column, value]` filter the code under test applied, in order. */
  eqs: Array<[string, string, unknown]>;
  /** Make every read of `table` fail with a database error. */
  failTables: Set<string>;
  client: {
    from(table: string): unknown;
  };
}

export function makeTableAwareTenant(tables: Record<string, FakeRow[]> = {}): TableAwareTenant {
  const state: TableAwareTenant = { tables, eqs: [], failTables: new Set(), client: { from: () => null } };
  state.client = {
    from(table: string) {
      const filters: Array<[string, unknown]> = [];
      // biome-ignore lint/suspicious/noExplicitAny: test fake chain
      const chain: any = {
        select: () => chain,
        limit: () => chain,
        eq: (col: string, val: unknown) => {
          filters.push([col, val]);
          state.eqs.push([table, col, val]);
          return chain;
        },
        maybeSingle: async () => {
          if (state.failTables.has(table)) return { data: null, error: { message: "boom SECRETROW" } };
          const hit = (state.tables[table] ?? []).find((row) => filters.every(([c, v]) => row[c] === v));
          return { data: hit ?? null, error: null };
        },
      };
      return chain;
    },
  };
  return state;
}

export function boundRun(over: FakeRow): FakeRow {
  return {
    id: "run-1",
    execution_kind: "conversation",
    workspace_id: "ws-1",
    engine_id: "claude",
    adapter_version: "1",
    created_at: "2026-10-30T00:00:00Z",
    ...over,
  };
}
