import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// Phase 5 file-parse lint per AC30 + C1 of plan rev-2.
//
// Walks `apps/web-platform/server/dsar-export.ts` and asserts that
// every `service.from("<allowlisted-table>").select(...)` chain is
// followed (in the same statement) by a positive predicate over the
// owner column declared in `DSAR_TABLE_ALLOWLIST` — `.eq(<owner>, ...)`
// for direct-owner tables, or `.in(<parent-fk>, ...)` for `joinVia`
// tables.
//
// Failure mode this prevents: a future refactor drops the `.eq(...)`
// from one table's read path (e.g., to "factor out a helper"). The
// runtime `assertReadScope` still catches the rows that come back,
// but the lint catches the mistake at PR time — orders of magnitude
// cheaper than a Sentry P0 in prd.
//
// Per the Sharp Edges section of the plan: "A reviewer who accepts a
// refactor that drops the .eq() is approving a cross-tenant footgun —
// and assertReadScope is the runtime catch but the lint is the
// no-runtime-failures-make-it-to-prod first line."

import { DSAR_TABLE_ALLOWLIST } from "../server/dsar-export-allowlist";

const WORKER_PATH = resolve(__dirname, "../server/dsar-export.ts");

interface FromCall {
  table: string;
  /** The full chained call expression including .from..close-paren. */
  chain: string;
  /** Index in source — used for error messages. */
  offset: number;
}

function extractServiceFromChains(src: string): FromCall[] {
  // Match `service.from("X")` (or single-quotes) followed by the rest
  // of its chain until the next top-level statement boundary (await
  // result destructure assignment).
  //
  // The pattern: capture the table name in group 1, then greedily
  // capture the chain body until we hit a semicolon or the start of
  // a new `await` statement. This is a hand-rolled tokeniser — full
  // TS AST parsing would be overkill for a single-file lint.
  const out: FromCall[] = [];
  const chainStart = /service\s*\.\s*from\(\s*["']([a-z_][a-z0-9_]*)["']\s*\)/g;
  for (const match of src.matchAll(chainStart)) {
    const table = match[1];
    const startIdx = match.index ?? 0;
    // Walk forward until we either hit a `\n  await` (next statement)
    // or a balanced `;` at depth zero outside any string.
    let depth = 0;
    let inString: '"' | "'" | "`" | null = null;
    let end = startIdx;
    for (let i = startIdx; i < src.length; i++) {
      const ch = src[i];
      const prev = i > 0 ? src[i - 1] : "";
      if (inString) {
        if (ch === inString && prev !== "\\") inString = null;
        continue;
      }
      if (ch === '"' || ch === "'" || ch === "`") {
        inString = ch as '"' | "'" | "`";
        continue;
      }
      if (ch === "(") depth++;
      else if (ch === ")") depth--;
      else if (ch === ";" && depth === 0) {
        end = i;
        break;
      }
    }
    out.push({ table, chain: src.slice(startIdx, end), offset: startIdx });
  }
  return out;
}

describe("DSAR worker per-row WHERE lint (AC30)", () => {
  const src = readFileSync(WORKER_PATH, "utf-8");
  const chains = extractServiceFromChains(src);

  it("extracts at least one service.from() chain per allowlisted table", () => {
    // Sanity: the parser is finding chains in dsar-export.ts.
    expect(chains.length).toBeGreaterThan(0);
    const tablesSeen = new Set(chains.map((c) => c.table));
    for (const tableName of Object.keys(DSAR_TABLE_ALLOWLIST)) {
      expect(
        tablesSeen.has(tableName),
        `Allowlisted table "${tableName}" has no service.from("${tableName}") ` +
          `call in dsar-export.ts. Every allowlisted table MUST be read by ` +
          `the worker — silent absence is an Art. 15 completeness regression.`,
      ).toBe(true);
    }
  });

  it("every direct-owner table read carries .eq(<ownerField>, ...)", () => {
    for (const c of chains) {
      const spec = DSAR_TABLE_ALLOWLIST[c.table];
      if (!spec) continue; // not an allowlisted table — out of lint scope
      if (spec.joinVia) continue; // join-via tables checked in next test

      // OR-semantic tables (audit logs with actor + target columns)
      // declare extra owner columns in `additionalOwnerFields`. Each
      // chain must carry .eq() on AT LEAST ONE of the declared owner
      // columns. The worker writes one chain per column and merges
      // results; this lint accepts any of them on a given chain.
      const ownerFields = [spec.ownerField, ...(spec.additionalOwnerFields ?? [])];
      const matched = ownerFields.some((col) =>
        new RegExp(`\\.eq\\(\\s*["']${col}["']`).test(c.chain),
      );
      expect(
        matched,
        `service.from("${c.table}") chain at offset ${c.offset} is missing ` +
          `\`.eq("<owner>", expectedUserId)\` for any of: ` +
          `${ownerFields.join(", ")}. Per AC30 every worker read of an ` +
          `allowlisted table MUST carry a positive per-row predicate over ` +
          `at least one owner column. Chain snippet: ${c.chain.slice(0, 200)}…`,
      ).toBe(true);
    }
  });

  it("every declared owner column has at least one .eq(<col>, ...) chain in the worker (inverse lint)", () => {
    // Symmetric to the previous lint. The forward lint ensures every chain
    // carries .eq() on AT LEAST ONE declared column; the inverse ensures
    // every declared column has AT LEAST ONE chain — otherwise a future
    // refactor that drops the `target_user_id` chain leaves the actor chain
    // satisfying the forward lint alone, and Art. 15 silently loses the
    // target-side rows. Same failure class as the FAQ-parity drift the
    // pattern-recognition Sharp Edges document warns about.
    for (const [tableName, spec] of Object.entries(DSAR_TABLE_ALLOWLIST)) {
      if (spec.joinVia) continue; // join-via tables have their own scope check
      const ownerFields = [spec.ownerField, ...(spec.additionalOwnerFields ?? [])];
      if (ownerFields.length < 2) continue; // single-column tables covered by the chain-presence test above
      const tableChains = chains.filter((c) => c.table === tableName);
      for (const col of ownerFields) {
        const covered = tableChains.some((c) =>
          new RegExp(`\\.eq\\(\\s*["']${col}["']`).test(c.chain),
        );
        expect(
          covered,
          `Allowlisted table "${tableName}" declares owner column "${col}" ` +
            `(via ownerField or additionalOwnerFields) but NO service.from("${tableName}") ` +
            `chain in dsar-export.ts carries \`.eq("${col}", expectedUserId)\`. ` +
            `Art. 15 completeness REQUIRES one read chain per declared owner ` +
            `column; silent omission would drop rows where the user appears ` +
            `via this column only. Add a per-column chain or remove the column ` +
            `from additionalOwnerFields with a documented rationale.`,
        ).toBe(true);
      }
    }
  });

  it("every join-via table read carries .in(<parentJoinColumn>, ...)", () => {
    for (const c of chains) {
      const spec = DSAR_TABLE_ALLOWLIST[c.table];
      if (!spec?.joinVia) continue;

      const expected = new RegExp(
        `\\.in\\(\\s*["']${spec.joinVia.parentJoinColumn}["']`,
      );
      expect(
        expected.test(c.chain),
        `service.from("${c.table}") chain at offset ${c.offset} is a join-via ` +
          `table but is missing \`.in("${spec.joinVia.parentJoinColumn}", ` +
          `ownedParentIds)\`. Per AC30 join-via reads MUST scope to the ` +
          `owner-verified parent ID set; an unconstrained read returns ` +
          `every row in the table.`,
      ).toBe(true);
    }
  });
});
