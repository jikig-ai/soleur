import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

/**
 * Structural source-side guard for the byok-RPC body-marker map (#5920).
 *
 * Companion to the LIVE probe added to
 * `.github/actions/dev-migration-drift-probe/action.yml`, which asserts the
 * same markers against `pg_get_functiondef` on dev-Supabase. This test guards
 * the OTHER side of that pair: that the committed migration SOURCE never
 * regresses the load-bearing markers, keeping the live-probe map honest and
 * self-updating as each RPC is redefined in later migrations.
 *
 * The marker map is the single source of truth shared with the bash probe:
 *   test/supabase-migrations/byok-rpc-markers.json   (read here + by jq in action.yml)
 *
 * Per-function marker map (NOT a flat set — #5920 Research Reconciliation):
 *   - record_byok_use_and_check_cap  → the cap RPC; `v_tripped := FOUND` is the
 *     #5917 fix marker (mig 121) and exists ONLY here.
 *   - check_and_record_byok_delegation_use → the delegation RPC (mig 084); caps
 *     via `RAISE EXCEPTION 'byok_delegations:hourly_cap_exceeded'/'…daily…'` and
 *     its own row `FOR UPDATE`. A flat marker set would false-fire this RPC.
 *
 * Marker-resolution rules (each mirrors a learning cited in the plan):
 *   - Anchor the definer-finder to `CREATE OR REPLACE FUNCTION public.<fn>(`
 *     (2026-06-19-sql-function-body-parser-must-anchor-to-create-not-bare-function):
 *     a bare `FUNCTION public.<fn>` also matches REVOKE/GRANT/COMMENT lines.
 *   - Pick the HIGHEST-numbered defining migration (a `CREATE OR REPLACE` in a
 *     later migration supersedes an earlier body).
 *   - Extract only that ONE function's definition (signature → matching
 *     dollar-quote close) so a marker in a SIBLING function in the same file
 *     cannot satisfy the assertion — this mirrors the live probe surface, which
 *     sees a single `pg_get_functiondef` per proname.
 *   - Comment-strip line comments (the `--` to end-of-line regex) before
 *     matching
 *     (2026-05-31-worm-bypass-migration-comment-literal-trips-comment-stripped-test):
 *     it removes line comments but NOT SQL string literals; our markers are
 *     verified executable-only today, so this is defense-in-depth.
 *   - `throw` fail-loud if no defining migration resolves (negative fixture).
 */

const MIGRATIONS_DIR = path.join(__dirname, "../../supabase/migrations");

const MARKER_MAP: Record<string, string[]> = JSON.parse(
  readFileSync(path.join(__dirname, "byok-rpc-markers.json"), "utf8"),
);

/** Numeric prefix of a `NNN_name.sql` migration filename, or -1 if none. */
function migrationNumber(filename: string): number {
  const m = /^(\d+)_/.exec(filename);
  return m ? Number.parseInt(m[1], 10) : -1;
}

/**
 * Extract the single `CREATE OR REPLACE FUNCTION public.<fn>(...)` definition
 * — signature through the matching dollar-quote close — from a migration body.
 * Returns null if this file does not define <fn>.
 */
function extractFunctionDef(sql: string, fn: string): string | null {
  const createRe = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${fn}\\s*\\(`,
  );
  const createMatch = createRe.exec(sql);
  if (!createMatch) return null;
  const start = createMatch.index;
  const rest = sql.slice(start);
  // Find the body's dollar-quote tag (`$$`, `$function$`, `$tag$`, …).
  const openRe = /\bAS\s+(\$[a-zA-Z_]*\$)/;
  const openMatch = openRe.exec(rest);
  if (!openMatch) {
    // Sanity: a LANGUAGE sql/plpgsql function we care about is dollar-quoted.
    throw new Error(
      `byok-rpc-body-markers: found CREATE for public.${fn} but no dollar-quoted body`,
    );
  }
  const tag = openMatch[1];
  const bodyOpenIdx = openMatch.index + openMatch[0].length;
  const closeIdx = rest.indexOf(tag, bodyOpenIdx);
  if (closeIdx === -1) {
    throw new Error(
      `byok-rpc-body-markers: unterminated dollar-quote (${tag}) for public.${fn}`,
    );
  }
  // signature + body, up to and including the closing tag.
  return rest.slice(0, closeIdx + tag.length);
}

/**
 * Resolve the highest-numbered migration that defines <fn> and return its
 * comment-stripped function definition. Fail loud if none defines it.
 */
function resolveFunctionDef(fn: string): string {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql") && !f.endsWith(".down.sql"))
    .sort((a, b) => migrationNumber(b) - migrationNumber(a)); // highest first
  for (const file of files) {
    const sql = readFileSync(path.join(MIGRATIONS_DIR, file), "utf8");
    const def = extractFunctionDef(sql, fn);
    if (def) return def.replace(/--[^\n]*/g, ""); // comment-strip
  }
  throw new Error(
    `byok-rpc-body-markers: no migration defines CREATE OR REPLACE FUNCTION public.${fn} — ` +
      "cannot verify body markers (map/source drift or renamed RPC)",
  );
}

describe("byok RPC body-marker map (source-side structural guard)", () => {
  it("maps exactly the two security-critical byok RPCs", () => {
    expect(Object.keys(MARKER_MAP).sort()).toEqual([
      "check_and_record_byok_delegation_use",
      "record_byok_use_and_check_cap",
    ]);
  });

  for (const [fn, markers] of Object.entries(MARKER_MAP)) {
    describe(`public.${fn}`, () => {
      const def = resolveFunctionDef(fn);

      it("has a non-empty resolved definition", () => {
        expect(def.length).toBeGreaterThan(0);
      });

      for (const marker of markers) {
        it(`body contains load-bearing marker: ${marker}`, () => {
          expect(def).toContain(marker);
        });
      }
    });
  }

  it("throws fail-loud when no migration defines the function", () => {
    expect(() => resolveFunctionDef("totally_missing_rpc_zzz")).toThrow(
      /no migration defines/,
    );
  });

  it("extractFunctionDef isolates one function (sibling marker does not leak)", () => {
    // Two functions in one synthetic file; the marker lives only in fn_b.
    const synthetic = `
CREATE OR REPLACE FUNCTION public.fn_a(x int) RETURNS int LANGUAGE sql AS $$
  SELECT x;
$$;
CREATE OR REPLACE FUNCTION public.fn_b(x int) RETURNS int LANGUAGE sql AS $$
  SELECT x; -- SENTINEL_MARKER lives here
$$;`;
    const defA = extractFunctionDef(synthetic, "fn_a");
    const defB = extractFunctionDef(synthetic, "fn_b");
    expect(defA).not.toBeNull();
    expect(defB).not.toBeNull();
    // Comment-strip removes the line comment, but the isolation is what matters:
    // fn_a's slice must NOT reach into fn_b's body.
    expect(defA).not.toContain("SENTINEL_MARKER");
    expect(defB).toContain("SENTINEL_MARKER");
  });
});
