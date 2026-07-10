import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

/**
 * Pre-merge gate for `verify/068` `jti_deny_policies_count_N` drift (#6273).
 *
 * The deploy-time `verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql` sentinel
 * hard-codes the number of RESTRICTIVE `*_jti_not_denied` RLS policies. It runs
 * ONLY in the post-merge `verify-migrations` job against a real Postgres — never
 * in PR CI. So a migration that adds (or drops) a `*_jti_not_denied` policy
 * without keeping `verify/068` in sync passes every PR check, merges, then FAILS
 * the release `verify-migrations` job → `deploy` is skipped (a deploy freeze).
 * This recurred twice (mig 126 → hotfix #6229; mig 127 → hotfix #6270); prose
 * prevention did not stop the second recurrence.
 *
 * This test is a fast, offline SOURCE-side mirror of the same invariant, parsed
 * entirely from committed migration + verify SQL text. It moves detection from
 * deploy-time to PR-time. The real-DB sentinel remains the authoritative ground
 * truth for the RESTRICTIVE property; this test is a name-and-RESTRICTIVE-anchored
 * subset mirror that catches the recurrence class before merge.
 *
 * Template: `byok-rpc-body-markers.test.ts` (readdir + set assertion + fail-loud
 * negative fixtures on in-test string constants).
 *
 * INVARIANT (all parseable offline):
 *   SET_M = tenant tables carrying a RESTRICTIVE `<table>_jti_not_denied` policy,
 *           folded across up-migrations in filename order:
 *             + the `tenant_tables text[] := ARRAY[…]` loop producer's entries
 *             + inline static `CREATE POLICY <t>_jti_not_denied ... AS RESTRICTIVE`
 *             − net (unpaired) `DROP POLICY [IF EXISTS] <t>_jti_not_denied`
 *   SET_V = tables asserted by `<t>_jti_not_denied_policy_present` rows in verify/068
 *   N     = the integer in verify/068's `jti_deny_policies_count_N` sentinel,
 *           read from BOTH the check-name suffix AND the `count(*) = N` literal.
 *   Assert: SET_M === SET_V ; |SET_M| === N === |SET_V| ; suffix-N === literal-N.
 *
 * DESIGN NOTES (from deepen-plan review — architecture / test-design / spec-flow):
 *   - Producer detection is CONTENT-based, not migration-number-based: migration
 *     files share numeric prefixes (e.g. `068_attachments_*` AND `068_jti_deny_*`),
 *     so the ARRAY/loop producer is identified by the presence of the
 *     `tenant_tables text[] := ARRAY[` block, not by number 068.
 *   - Parse whole-file, comment-stripped, with ONE shared case-insensitive
 *     `[a-z0-9_]+` identifier class, so SET_M and SET_V can never drift on
 *     multi-line statements, `--` comments, or digit-bearing table names.
 *   - Anchor inline creates on `AS RESTRICTIVE` to mirror the sentinel's
 *     `permissive='RESTRICTIVE'` predicate — a name-only match would admit a
 *     PERMISSIVE `*_jti_not_denied` policy that the sentinel does not count
 *     (false-green).
 *   - PRODUCER-COMPLETENESS GUARD: the sanctioned loop producer generates its
 *     policies via a `format('CREATE POLICY %I_jti_not_denied ...')` loop, which
 *     emits no static `CREATE POLICY` token — handled via the ARRAY parse. Any
 *     OTHER migration that introduces its own dynamic/loop producer (a format
 *     loop with NO paired `tenant_tables` ARRAY) would be invisible to the static
 *     parser → false-green. We fail loud on it.
 *   - Fold in filename order (not a global union-minus) so a
 *     create→drop→recreate across separate migrations resolves correctly.
 *   - Commit NO hardcoded totals as assertions (21/6/27) — that would re-import
 *     the exact drift-coupling this test exists to kill. Only the self-updating
 *     relational checks + a fail-loud `size > 0` are asserted.
 */

const MIGRATIONS_DIR = path.join(__dirname, "../../supabase/migrations");
const VERIFY_DIR = path.join(__dirname, "../../supabase/verify");
const VERIFY_068 = "068_jti_deny_rls_predicate_and_revoke_rpc.sql";

// ── Shared parsing primitives (pure; also exercised by fixtures below) ──────────

/**
 * Strip `--` line comments (mirrors the byok template). Removes line comments
 * but NOT SQL string literals; our tokens are executable-only, so this is
 * defense-in-depth against a commented-out `CREATE POLICY` / ARRAY entry / prose
 * `<table>_jti_not_denied` being miscounted.
 */
function stripSqlLineComments(sql: string): string {
  return sql.replace(/--[^\n]*/g, "");
}

const ARRAY_HEADER_RE = /tenant_tables\s+text\[\]\s*:=\s*ARRAY\[/i;

/** Whether a migration declares the `tenant_tables text[] := ARRAY[…]` producer. */
function hasArrayProducer(sql: string): boolean {
  return ARRAY_HEADER_RE.test(stripSqlLineComments(sql));
}

/**
 * Inline STATIC producers: `CREATE POLICY <t>_jti_not_denied ON <table>
 * AS RESTRICTIVE ...`. Whole-string, case-insensitive, `AS RESTRICTIVE`-anchored,
 * `\s+` spanning newlines (the qualifier sits on a separate line in every real
 * producer). Does NOT match the `%I_jti_not_denied` loop form (the `%`
 * placeholder is outside `[a-z0-9_]`) — those are handled by parseArrayProducer.
 */
const INLINE_CREATE_RE =
  /\bCREATE\s+POLICY\s+([a-z0-9_]+)_jti_not_denied\s+ON\s+[a-z0-9_."]+\s+AS\s+RESTRICTIVE\b/gi;

function parseInlineCreates(sql: string): string[] {
  const stripped = stripSqlLineComments(sql);
  const out: string[] = [];
  for (const m of stripped.matchAll(INLINE_CREATE_RE)) out.push(m[1]);
  return out;
}

/** `DROP POLICY [IF EXISTS] <t>_jti_not_denied` — IF EXISTS optional. */
const DROP_RE =
  /\bDROP\s+POLICY\s+(?:IF\s+EXISTS\s+)?([a-z0-9_]+)_jti_not_denied\b/gi;

function parseDrops(sql: string): string[] {
  const stripped = stripSqlLineComments(sql);
  const out: string[] = [];
  for (const m of stripped.matchAll(DROP_RE)) out.push(m[1]);
  return out;
}

/**
 * Loop producer: parse the `tenant_tables text[] := ARRAY[ … ];` literal into its
 * quoted entries. Fail LOUD if the block cannot be located or yields zero entries
 * — otherwise a future refactor that moves the table list would silently zero the
 * baseline and the guard would dark while reading green.
 */
function parseArrayProducer(sql: string): string[] {
  const stripped = stripSqlLineComments(sql);
  const start = ARRAY_HEADER_RE.exec(stripped);
  if (!start) {
    throw new Error(
      "068-jti-deny-count: could not locate `tenant_tables text[] := ARRAY[` " +
        "block — parser is stale vs the loop producer.",
    );
  }
  const afterOpen = stripped.slice(start.index + start[0].length);
  const closeIdx = afterOpen.indexOf("];");
  if (closeIdx === -1) {
    throw new Error(
      "068-jti-deny-count: `tenant_tables` ARRAY block has no `];` terminator.",
    );
  }
  const block = afterOpen.slice(0, closeIdx);
  const entries: string[] = [];
  for (const m of block.matchAll(/'([a-z0-9_]+)'/gi)) entries.push(m[1]);
  if (entries.length === 0) {
    throw new Error(
      "068-jti-deny-count: `tenant_tables` ARRAY parsed to zero entries — " +
        "the loop producer's baseline would silently vanish.",
    );
  }
  return entries;
}

/**
 * Detect a DYNAMIC (loop/runtime-generated) `*_jti_not_denied` producer. These
 * build the policy name at runtime, emit no static CREATE token, and are
 * invisible to parseInlineCreates. Two forms are recognised:
 *   - a bare `CREATE POLICY %<x>_jti_not_denied` (format-placeholder name), and
 *   - any `EXECUTE … CREATE POLICY … _jti_not_denied` statement — this covers
 *     BOTH `EXECUTE format('CREATE POLICY %I_jti_not_denied …')` and the
 *     string-concatenation form `EXECUTE 'CREATE POLICY ' || quote_ident(t ||
 *     '_jti_not_denied') || …` (so a future loop that swaps format() for `||`
 *     concatenation cannot silently evade the guard).
 * The sanctioned loop is the one paired with the `tenant_tables` ARRAY
 * declaration; any other is a false-green hazard.
 */
function hasDynamicJtiProducer(sql: string): boolean {
  const stripped = stripSqlLineComments(sql);
  return (
    /\bCREATE\s+POLICY\s+%[a-z0-9]*_?jti_not_denied/i.test(stripped) ||
    /\bEXECUTE\b[^;]*CREATE\s+POLICY[^;]*_jti_not_denied/is.test(stripped)
  );
}

/**
 * Fold up-migrations in filename order into SET_M. Pure over an in-memory list so
 * fixtures exercise the exact production code path. A file with the ARRAY producer
 * contributes its loop entries; every file contributes its inline static creates;
 * unpaired drops (not re-created in the SAME file) remove; a dynamic producer that
 * is NOT paired with the ARRAY declaration fails loud.
 */
function foldMigrations(migrations: { name: string; sql: string }[]): Set<string> {
  const sorted = [...migrations].sort((a, b) =>
    a.name < b.name ? -1 : a.name > b.name ? 1 : 0,
  );
  const set = new Set<string>();
  for (const { name, sql } of sorted) {
    const arrayOwner = hasArrayProducer(sql);
    if (hasDynamicJtiProducer(sql) && !arrayOwner) {
      throw new Error(
        `068-jti-deny-count: migration ${name} contains a DYNAMIC (loop/format) ` +
          "*_jti_not_denied producer with no paired `tenant_tables` ARRAY. Only " +
          "the sanctioned ARRAY-owning migration may generate these via a loop; a " +
          "new dynamic producer is invisible to the static parser and would let " +
          "the count drift silently (false-green → deploy freeze). Extend the " +
          "parser (or convert to static CREATE POLICY statements).",
      );
    }
    if (arrayOwner) for (const t of parseArrayProducer(sql)) set.add(t);
    const creates = parseInlineCreates(sql);
    for (const t of creates) set.add(t);
    const createdHere = new Set(creates);
    for (const t of parseDrops(sql)) if (!createdHere.has(t)) set.delete(t);
  }
  return set;
}

/** Build SET_M from the real committed migrations. */
function computeMigrationSet(): Set<string> {
  const migrations = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql") && !f.endsWith(".down.sql"))
    .map((f) => ({ name: f, sql: readFileSync(path.join(MIGRATIONS_DIR, f), "utf8") }));
  return foldMigrations(migrations);
}

/** SET_V: tables asserted present by verify/068. */
const VERIFY_TABLE_RE = /'([a-z0-9_]+)_jti_not_denied_policy_present'/gi;

function parseVerifyTables(verifySql: string): Set<string> {
  const stripped = stripSqlLineComments(verifySql);
  const set = new Set<string>();
  for (const m of stripped.matchAll(VERIFY_TABLE_RE)) set.add(m[1]);
  return set;
}

/**
 * N from verify/068's count sentinel, read from BOTH forms bound to the SAME
 * SELECT: the `jti_deny_policies_count_<N>` check-name suffix and the following
 * `count(*) = <N>` literal. Returns null if the sentinel is absent.
 */
const SENTINEL_RE =
  /'jti_deny_policies_count_(\d+)'\s*,\s*CASE\s+WHEN\s+count\(\*\)\s*=\s*(\d+)/i;

function parseVerifyN(
  verifySql: string,
): { suffix: number; literal: number } | null {
  const stripped = stripSqlLineComments(verifySql);
  const m = SENTINEL_RE.exec(stripped);
  if (!m) return null;
  return { suffix: Number(m[1]), literal: Number(m[2]) };
}

function symmetricDiff(a: Set<string>, b: Set<string>): string[] {
  const only = (x: Set<string>, y: Set<string>) =>
    [...x].filter((v) => !y.has(v));
  return [
    ...only(a, b).map((t) => `+${t} (in migrations, missing from verify/068)`),
    ...only(b, a).map((t) => `-${t} (in verify/068, missing from migrations)`),
  ].sort();
}

// ── Live-source assertions (self-updating; NO hardcoded totals) ─────────────────

describe("verify/068 jti_deny_policies_count drift gate (#6273)", () => {
  const migrationSet = computeMigrationSet();
  const verifySql = readFileSync(path.join(VERIFY_DIR, VERIFY_068), "utf8");
  const verifySet = parseVerifyTables(verifySql);
  const n = parseVerifyN(verifySql);

  it("parses a non-empty producer set (parsers are not silently darking)", () => {
    expect(migrationSet.size).toBeGreaterThan(0);
    expect(verifySet.size).toBeGreaterThan(0);
  });

  it("SET_M === SET_V (migrations and verify/068 agree, by table name)", () => {
    const diff = symmetricDiff(migrationSet, verifySet);
    expect(
      diff,
      diff.length
        ? `verify/068 is out of sync with migrations:\n  ${diff.join("\n  ")}\n` +
            "Update verify/068 (add/remove the *_jti_not_denied_policy_present " +
            "row and bump jti_deny_policies_count_N in both the check-name and " +
            "the count(*) literal)."
        : undefined,
    ).toEqual([]);
  });

  it("verify/068 exposes the count sentinel", () => {
    expect(n, "jti_deny_policies_count_N sentinel not found in verify/068").not.toBeNull();
  });

  it("sentinel N === |SET_M| === |SET_V| (count matches both sides)", () => {
    expect(n).not.toBeNull();
    expect(n!.suffix).toBe(migrationSet.size);
    expect(n!.suffix).toBe(verifySet.size);
  });

  it("sentinel check-name suffix === count(*) literal (self-consistent)", () => {
    expect(n).not.toBeNull();
    expect(n!.suffix).toBe(n!.literal);
  });

  it("exactly one sanctioned loop producer, and it owns the tenant_tables ARRAY", () => {
    const files = readdirSync(MIGRATIONS_DIR).filter(
      (f) => f.endsWith(".sql") && !f.endsWith(".down.sql"),
    );
    const read = (f: string) => readFileSync(path.join(MIGRATIONS_DIR, f), "utf8");
    const dynamicFiles = files.filter((f) => hasDynamicJtiProducer(read(f)));
    const arrayFiles = files.filter((f) => hasArrayProducer(read(f)));
    // one ARRAY producer, one dynamic producer, and they are the same file.
    expect(arrayFiles.length).toBe(1);
    expect(dynamicFiles).toEqual(arrayFiles);
  });
});

// ── Committed negative/behaviour fixtures (in-test string constants) ────────────
// These exercise the SAME pure parsers on synthetic SQL so the failure paths run
// on EVERY PR, not once on a laptop. Each maps to a deepen-plan edge case.

describe("068-jti-deny-count parser fixtures", () => {
  it("counts a RESTRICTIVE inline create (incl. multi-line AS RESTRICTIVE)", () => {
    const sql =
      "CREATE POLICY foo_jti_not_denied ON public.foo\n" +
      "  AS RESTRICTIVE FOR ALL TO authenticated USING (true);";
    expect(parseInlineCreates(sql)).toEqual(["foo"]);
  });

  it("counts a digit-bearing table name (unified [a-z0-9_] class)", () => {
    const sql =
      "CREATE POLICY oauth2_tokens_jti_not_denied ON public.oauth2_tokens\n" +
      "  AS RESTRICTIVE FOR ALL TO authenticated USING (true);";
    expect(parseInlineCreates(sql)).toEqual(["oauth2_tokens"]);
  });

  it("does NOT count a PERMISSIVE (non-RESTRICTIVE) *_jti_not_denied policy", () => {
    const sql =
      "CREATE POLICY foo_jti_not_denied ON public.foo FOR ALL TO authenticated USING (true);";
    expect(parseInlineCreates(sql)).toEqual([]);
  });

  it("does NOT count a commented-out create (line-comment stripped)", () => {
    const sql =
      "-- CREATE POLICY draft_jti_not_denied ON public.draft AS RESTRICTIVE FOR ALL;";
    expect(parseInlineCreates(sql)).toEqual([]);
  });

  it("recognises DROP with and without IF EXISTS", () => {
    expect(parseDrops("DROP POLICY IF EXISTS foo_jti_not_denied ON public.foo;")).toEqual(["foo"]);
    expect(parseDrops("DROP POLICY bar_jti_not_denied ON public.bar;")).toEqual(["bar"]);
  });

  it("a paired DROP+CREATE in one migration nets PRESENT (idempotency guard, migs 126/127)", () => {
    // The `DROP IF EXISTS … ; CREATE …` idempotency pattern LEAVES the policy in
    // place — the drop is paired with a same-file create, so it is not a net drop.
    const paired = {
      name: "200_paired.sql",
      sql:
        "DROP POLICY IF EXISTS foo_jti_not_denied ON public.foo;\n" +
        "CREATE POLICY foo_jti_not_denied ON public.foo\n  AS RESTRICTIVE FOR ALL;",
    };
    expect([...foldMigrations([paired])]).toEqual(["foo"]);
  });

  it("an unpaired DROP removes a table added by an earlier migration", () => {
    const set = foldMigrations([
      { name: "100_add.sql", sql: "CREATE POLICY foo_jti_not_denied ON public.foo\n  AS RESTRICTIVE FOR ALL;" },
      { name: "200_drop.sql", sql: "DROP POLICY IF EXISTS foo_jti_not_denied ON public.foo;" },
    ]);
    expect([...set]).toEqual([]);
  });

  it("folds in filename order: create → unpaired drop → recreate ⇒ present", () => {
    const set = foldMigrations([
      { name: "300_recreate.sql", sql: "CREATE POLICY foo_jti_not_denied ON public.foo\n  AS RESTRICTIVE FOR ALL;" },
      { name: "100_add.sql", sql: "CREATE POLICY foo_jti_not_denied ON public.foo\n  AS RESTRICTIVE FOR ALL;" },
      { name: "200_drop.sql", sql: "DROP POLICY IF EXISTS foo_jti_not_denied ON public.foo;" },
    ]);
    // sorted by name: 100 add → 200 drop → 300 recreate ⇒ foo present
    expect([...set]).toEqual(["foo"]);
  });

  it("fails loud on a dynamic (loop) producer with no paired ARRAY", () => {
    const rogue = {
      name: "130_rogue.sql",
      sql:
        "DO $$ BEGIN FOREACH t IN ARRAY tbls LOOP\n" +
        "  EXECUTE format('CREATE POLICY %I_jti_not_denied ON public.%I AS RESTRICTIVE FOR ALL', t, t);\n" +
        "END LOOP; END $$;",
    };
    expect(() => foldMigrations([rogue])).toThrow(/DYNAMIC .*producer/i);
  });

  it("fails loud on a string-concatenation dynamic producer (no format())", () => {
    const rogue = {
      name: "131_concat_rogue.sql",
      sql:
        "DO $$ BEGIN FOREACH t IN ARRAY tbls LOOP\n" +
        "  EXECUTE 'CREATE POLICY ' || quote_ident(t || '_jti_not_denied') ||\n" +
        "    ' ON public.' || quote_ident(t) || ' AS RESTRICTIVE FOR ALL';\n" +
        "END LOOP; END $$;",
    };
    expect(() => foldMigrations([rogue])).toThrow(/DYNAMIC .*producer/i);
  });

  it("allows a dynamic producer when paired with the tenant_tables ARRAY", () => {
    const sanctioned = {
      name: "068_jti.sql",
      sql:
        "DECLARE tenant_tables text[] := ARRAY[\n  'a',\n  'b'\n];\n" +
        "BEGIN FOREACH t IN ARRAY tenant_tables LOOP\n" +
        "  EXECUTE format('CREATE POLICY %I_jti_not_denied ON public.%I AS RESTRICTIVE FOR ALL', t, t);\n" +
        "END LOOP; END $$;",
    };
    expect([...foldMigrations([sanctioned])].sort()).toEqual(["a", "b"]);
  });

  it("fails loud when the ARRAY block is missing", () => {
    expect(() => parseArrayProducer("BEGIN\n  -- no array here\nEND;")).toThrow(
      /could not locate/i,
    );
  });

  it("set-vs-count: a swap (drop A, add B) keeps |SET| but changes membership", () => {
    // Count-only would pass; set equality is what catches the identity failure.
    const before = foldMigrations([
      { name: "100_a.sql", sql: "CREATE POLICY a_jti_not_denied ON public.a\n  AS RESTRICTIVE FOR ALL;" },
    ]);
    const after = foldMigrations([
      { name: "100_a.sql", sql: "CREATE POLICY a_jti_not_denied ON public.a\n  AS RESTRICTIVE FOR ALL;" },
      { name: "200_drop_a.sql", sql: "DROP POLICY IF EXISTS a_jti_not_denied ON public.a;" },
      { name: "201_add_b.sql", sql: "CREATE POLICY b_jti_not_denied ON public.b\n  AS RESTRICTIVE FOR ALL;" },
    ]);
    expect(before.size).toBe(after.size); // both 1 — a count check sees no change
    expect([...before]).toEqual(["a"]);
    expect([...after]).toEqual(["b"]); // set membership differs — the real signal
  });

  it("parseVerifyN reads suffix and literal; symmetricDiff names offenders", () => {
    const verify =
      "SELECT 'jti_deny_policies_count_2',\n" +
      "  CASE WHEN count(*) = 2 THEN 0 ELSE 1 END::int\n" +
      "SELECT 'a_jti_not_denied_policy_present', 0\n" +
      "SELECT 'b_jti_not_denied_policy_present', 0\n";
    const parsed = parseVerifyN(verify);
    expect(parsed).toEqual({ suffix: 2, literal: 2 });
    expect(parseVerifyTables(verify)).toEqual(new Set(["a", "b"]));
    expect(symmetricDiff(new Set(["a", "c"]), new Set(["a", "b"]))).toEqual([
      "+c (in migrations, missing from verify/068)",
      "-b (in verify/068, missing from migrations)",
    ]);
  });
});
