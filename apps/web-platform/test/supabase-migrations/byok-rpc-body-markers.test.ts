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
 *   - check_and_record_byok_delegation_use → the delegation RPC (mig 084,
 *     redefined by mig 137); its own row `FOR UPDATE`, the audit INSERT that
 *     every branch owes, and the two cap `refusal_reason` assignments. A flat
 *     marker set would false-fire this RPC.
 *
 * #7829 reconciliation — the cap markers used to be the bare reason literals,
 * pinned there because mig 084 signalled a cap breach by RAISEing them. Mig 137
 * converts refusal from an exception to a RETURNED value (an unhandled plpgsql
 * RAISE rolls back the audit row the branch just inserted), so the bare literals
 * would now be satisfied by the INSERT's column value alone even if the return
 * were dropped. They are pinned as `refusal_reason := '<reason>'` instead, and
 * the INSERT-shaped marker guards the row itself — the whole point of #7829.
 *
 * Marker-resolution rules (each mirrors a learning cited in the plan):
 *   - Anchor the definer-finder to `CREATE [OR REPLACE] FUNCTION public.<fn>(`
 *     (2026-06-19-sql-function-body-parser-must-anchor-to-create-not-bare-function):
 *     a bare `FUNCTION public.<fn>` also matches REVOKE/GRANT/COMMENT lines,
 *     and `DROP FUNCTION IF EXISTS public.<fn>(` must not be mistaken for a
 *     definition. `OR REPLACE` is OPTIONAL: a RETURN-TYPE change cannot use
 *     `CREATE OR REPLACE`, so mig 137 is a `DROP` + bare `CREATE`. Requiring
 *     `OR REPLACE` silently resolved the SUPERSEDED 084 body and left the map
 *     guarding a function that no longer exists (#7829).
 *   - Pick the HIGHEST-numbered defining migration (a later `CREATE` supersedes
 *     an earlier body).
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
 * Extract the single `CREATE [OR REPLACE] FUNCTION public.<fn>(...)` definition
 * — signature through the matching dollar-quote close — from a migration body.
 * Returns null if this file does not define <fn>.
 *
 * `OR REPLACE` is optional on purpose: a return-type change is illegal under
 * `CREATE OR REPLACE`, so such a migration is `DROP FUNCTION IF EXISTS` + a
 * bare `CREATE FUNCTION` (mig 137). `CREATE` stays mandatory so DROP / REVOKE /
 * GRANT / COMMENT lines naming the same function can never match.
 */
function extractFunctionDef(sql: string, fn: string): string | null {
  const createRe = new RegExp(
    `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${fn}\\s*\\(`,
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

  it("extractFunctionDef accepts a bare CREATE FUNCTION (return-type change; #7829)", () => {
    // A return-type change cannot use CREATE OR REPLACE, so mig 137 is
    // `DROP FUNCTION IF EXISTS` + `CREATE FUNCTION`. An `OR REPLACE`-only
    // anchor skipped it and silently resolved the superseded 084 body — the
    // map would have gone on guarding a function that no longer exists.
    const synthetic = `
DROP FUNCTION IF EXISTS public.fn_c(uuid);
CREATE FUNCTION public.fn_c(x uuid) RETURNS TABLE(reason text) LANGUAGE sql AS $$
  SELECT 'NEW_SHAPE_MARKER';
$$;`;
    const def = extractFunctionDef(synthetic, "fn_c");
    expect(def).not.toBeNull();
    expect(def).toContain("NEW_SHAPE_MARKER");
    // The DROP line precedes the CREATE and must not become the slice start.
    expect(def!.startsWith("CREATE FUNCTION")).toBe(true);
  });

  it("extractFunctionDef does not treat DROP/REVOKE/GRANT/COMMENT as a definition", () => {
    const synthetic = `
DROP FUNCTION IF EXISTS public.fn_d(uuid);
REVOKE ALL ON FUNCTION public.fn_d(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_d(uuid) TO service_role;
COMMENT ON FUNCTION public.fn_d(uuid) IS 'no body here';`;
    expect(extractFunctionDef(synthetic, "fn_d")).toBeNull();
  });

  it("resolves the delegation RPC to the return-status body, not the superseded RAISE body", () => {
    // Behavioural pin for the reconciliation above: whichever migration wins,
    // the resolved body must signal a cap refusal by RETURNING it. A body that
    // still RAISEs the cap reason is the pre-#7829 shape, whose INSERT the
    // RAISE rolls back.
    const def = resolveFunctionDef("check_and_record_byok_delegation_use");
    expect(def).toContain("RETURNS TABLE(refusal_reason text)");
    expect(def).not.toMatch(
      /RAISE\s+EXCEPTION\s+'byok_delegations:(hourly|daily)_cap_exceeded/,
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
