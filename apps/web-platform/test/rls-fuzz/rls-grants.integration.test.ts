import { describe, test, expect, beforeAll, afterAll } from "vitest";
import type postgres from "postgres";
import { publicApiRelations, publicApiSequences } from "./catalog";
import {
  API_ROLES,
  TABLE_VERBS,
  TABLE_GRANT_REGISTRY,
  SNAPSHOT_RELATION_FLOOR,
  SNAPSHOT_PARSED_RELATION_COUNT,
  type ApiRole,
  type GrantSet,
} from "./table-grants";
import { connect, withTransientRetry } from "./harness-fixture";

// Api-role grant-coverage gate (ADR-303 — the AUTHORITATIVE tier of the
// two-tier table-grant guard; the PR-diff lint is the subordinate pre-filter).
//
// Asserts GRANT STATE, not access BEHAVIOR: a table denied by a missing grant
// and a table denied by RLS both read as 42501 to the fuzz matrix, so the
// property is verified with has_table_privilege/has_column_privilege/
// has_sequence_privilege against the registered classification — the
// false-green hole this file exists to close.
//
// Faithfulness precondition (P6): the assertions are only meaningful if the
// stack's effective privileges come from migration GRANTs alone, not the
// bootstrap default privileges. The `supabase-local.sh` post-start normalize
// revokes them; the FIRST test asserts that state on pg_default_acl so a stack
// started any other way cannot silently degrade the gate into measuring
// platform defaults.
//
// Gated behind RLS_FUZZ_LOCAL=1 against a LOCAL disposable Postgres.

const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

let sql: postgres.Sql<{}>;

interface PrivRow {
  relname: string;
  role: string;
  verb: string;
  held: boolean;
}

/** role -> verb -> held, keyed by relname, over the FULL probe universe. */
function indexByRelation(rows: PrivRow[]): Map<string, Map<string, Set<string>>> {
  const out = new Map<string, Map<string, Set<string>>>();
  for (const r of rows) {
    let per = out.get(r.relname);
    if (!per) {
      per = new Map();
      out.set(r.relname, per);
    }
    const verbs = per.get(r.role) ?? new Set<string>();
    if (r.held) verbs.add(r.verb);
    per.set(r.role, verbs);
  }
  return out;
}

/** Registered verbs for a role; absent role = empty set. */
function expectedVerbs(g: GrantSet, role: ApiRole): Set<string> {
  return g.privileges.get(role) ?? new Set();
}

const fmtSet = (s: ReadonlySet<string>) => `{${[...s].sort().join(",")}}`;

describe.skipIf(!ENABLED)("RLS/authz-fuzz — api-role grant coverage (local, catalog-driven)", () => {
  beforeAll(async () => {
    sql = connect(DSN); // assertLocalDsn + max:1 pinned in the shared fixture
  });
  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  // P6 faithfulness pin: the normalize must have run. Without it the stack
  // still carries the bootstrap default privileges and every assertion below
  // measures platform defaults — the circular proof the whole guard exists to
  // prevent. Checks defaclobjtype 'r' (tables) AND 'S' (sequences) for any
  // api-role (or PUBLIC, which confers to every api role) grantee, owned by
  // ANY role — not just postgres — per the CTO ruling's "owner set may be
  // broader" note.
  test("pg_default_acl carries no api-role default table/sequence privileges (normalize ran)", async () => {
    const [row] = await withTransientRetry(() => sql<{ bad: number; offenders: string }[]>`
      select count(*)::int as bad,
             coalesce(string_agg(distinct offender, ', '), '') as offenders
      from (
        select own.rolname || '.' || d.defaclobjtype || ' -> '
               || coalesce(g.rolname, 'PUBLIC') || ' ' || a.privilege_type as offender
        from pg_default_acl d
        join pg_roles own on own.oid = d.defaclrole
        join pg_namespace n on n.oid = d.defaclnamespace
        cross join lateral aclexplode(d.defaclacl) a
        left join pg_roles g on g.oid = a.grantee
        where n.nspname = 'public'
          and d.defaclobjtype in ('r', 'S')
          and (a.grantee = 0 or g.rolname in ('anon', 'authenticated', 'service_role'))
      ) x`);
    expect(row.bad, `pg_default_acl still grants api roles on new public relations — the supabase-local.sh normalize did not run or could not establish the state (offenders: ${row.offenders})`).toBe(0);
  });

  test("registry is non-vacuous (snapshot parse produced the full prd set)", () => {
    // The 2026-10-26 prd audit enumerated 62 relations. The floor asserts on the
    // PARSED-snapshot count only — never the registry total: INTERNAL/OVERRIDES/
    // RETIRED entries are hand-authored and must not feed a floor that exists to
    // prove the parser produced the prd set. A dead parser yields 0 either way;
    // this keeps it loud independent of a live DB.
    expect(SNAPSHOT_PARSED_RELATION_COUNT).toBeGreaterThanOrEqual(SNAPSHOT_RELATION_FLOOR);
    for (const [name, entry] of TABLE_GRANT_REGISTRY) {
      if (entry.kind === "INTERNAL" || entry.kind === "RETIRED") {
        expect(entry.reason.trim().length, `${entry.kind} '${name}' must carry a reason`).toBeGreaterThan(0);
      } else {
        const total = [...entry.grants.privileges.values()].reduce((n, s) => n + s.size, 0);
        expect(total, `EXPOSED '${name}' must grant at least one verb to at least one api role`).toBeGreaterThan(0);
      }
    }
  });

  test("catalog⇔registry parity: every public relation/sequence is classified; no stale entries", async () => {
    const rels = await publicApiRelations(sql);
    const seqs = await publicApiSequences(sql);
    const catalog = new Set([...rels.map((r) => r.relname), ...seqs.map((s) => s.relname)]);
    // Non-vacuity: an empty catalog means the wrong DB is being enumerated —
    // a satisfied-by-nothing gate must not pass.
    expect(catalog.size).toBeGreaterThan(0);
    const registered = new Set(TABLE_GRANT_REGISTRY.keys());
    const unclassified = [...catalog].filter((n) => !registered.has(n)).sort();
    // RETIRED entries are EXPECTED absent (the relation was dropped/renamed —
    // that absence is the classification), so they are exempt from `stale`; a
    // RETIRED name that still EXISTS is the error instead.
    const stale = [...registered].filter(
      (n) => TABLE_GRANT_REGISTRY.get(n)!.kind !== "RETIRED" && !catalog.has(n),
    ).sort();
    const resurrected = [...registered].filter(
      (n) => TABLE_GRANT_REGISTRY.get(n)!.kind === "RETIRED" && catalog.has(n),
    ).sort();
    expect(
      { unclassified, stale, resurrected },
      "every live public relation/sequence needs a table-grants.ts classification (EXPOSED or INTERNAL); every non-RETIRED registry entry must name a live relation — stale entries rot silently; a RETIRED entry whose relation still exists is a wrong retirement record",
    ).toEqual({ unclassified: [], stale: [], resurrected: [] });
  });

  test("effective table/view privileges equal the registered set (both directions)", async () => {
    const rels = await publicApiRelations(sql);
    const rows = await withTransientRetry(() => sql<PrivRow[]>`
      select c.relname, r.role, v.verb,
             has_table_privilege(r.role, c.oid, v.verb) as held
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      cross join unnest(array['anon','authenticated','service_role']) as r(role)
      cross join unnest(array['DELETE','INSERT','MAINTAIN','REFERENCES','SELECT','TRIGGER','TRUNCATE','UPDATE']) as v(verb)
      where n.nspname = 'public'
        and c.relkind in ('r', 'v', 'm', 'p', 'f')
        and not c.relispartition
      order by c.relname, r.role, v.verb`);

    const held = indexByRelation(rows);
    const violations: string[] = [];
    let falseProbes = 0;

    // Assertion INSIDE the enumeration: a gate that returns after the first
    // member cannot catch a mis-grant on the second.
    for (const { relname } of rels) {
      const entry = TABLE_GRANT_REGISTRY.get(relname);
      const perRole = held.get(relname);
      if (!perRole) {
        violations.push(`${relname}: catalog member produced no probe rows`);
        continue;
      }
      for (const role of API_ROLES) {
        const actual = perRole.get(role) ?? new Set<string>();
        falseProbes += TABLE_VERBS.length - actual.size;
        if (entry?.kind === "INTERNAL") {
          if (actual.size > 0) {
            violations.push(`${relname}: INTERNAL (${entry.reason}) but ${role} holds ${fmtSet(actual)} — over-grant`);
          }
          continue;
        }
        const expected = entry?.kind === "EXPOSED" ? expectedVerbs(entry.grants, role) : new Set<string>();
        const missing = [...expected].filter((v) => !actual.has(v));
        const extra = [...actual].filter((v) => !expected.has(v));
        if (missing.length || extra.length) {
          violations.push(
            `${relname} ${role}: expected ${fmtSet(expected)}, effective ${fmtSet(actual)}` +
              (missing.length ? ` missing=${fmtSet(new Set(missing))}` : "") +
              (extra.length ? ` extra=${fmtSet(new Set(extra))}` : ""),
          );
        }
      }
    }
    // Vacuity guard: an always-true has_table_privilege stub produces zero
    // false probes AND reds the extra-direction check — this pins both.
    expect(falseProbes, "probe matrix is all-true — an always-true has_table_privilege stub is indistinguishable from a correct gate").toBeGreaterThan(0);
    expect(violations).toEqual([]);
  });

  test("effective sequence privileges equal the registered set", async () => {
    const seqs = await publicApiSequences(sql);
    // NON-VACUOUS: the corpus guarantees >=1 public sequence
    // (agent_engine_events_id_seq — mig 138's identity column, snapshotted by
    // 174). An early `return` on zero rows would let a broken enumerator or a
    // stack missing the identity column exit green having asserted nothing.
    expect(seqs.length, "no public sequences enumerated — the corpus guarantees agent_engine_events_id_seq; a zero here means the enumerator or the stack is broken").toBeGreaterThan(0);
    const rows = await withTransientRetry(() => sql<PrivRow[]>`
      select c.relname, r.role, v.verb,
             has_sequence_privilege(r.role, c.oid, v.verb) as held
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      cross join unnest(array['anon','authenticated','service_role']) as r(role)
      cross join unnest(array['USAGE','SELECT','UPDATE']) as v(verb)
      where n.nspname = 'public'
        and c.relkind = 'S'
      order by c.relname, r.role, v.verb`);

    const held = indexByRelation(rows);
    const violations: string[] = [];
    for (const { relname } of seqs) {
      const entry = TABLE_GRANT_REGISTRY.get(relname);
      const perRole = held.get(relname);
      if (!perRole) {
        violations.push(`${relname}: sequence produced no probe rows`);
        continue;
      }
      for (const role of API_ROLES) {
        const actual = perRole.get(role) ?? new Set<string>();
        if (entry?.kind === "INTERNAL") {
          if (actual.size > 0) {
            violations.push(`${relname}: INTERNAL (${entry.reason}) but ${role} holds ${fmtSet(actual)} — over-grant`);
          }
          continue;
        }
        const expected = entry?.kind === "EXPOSED" ? expectedVerbs(entry.grants, role) : new Set<string>();
        const missing = [...expected].filter((v) => !actual.has(v));
        const extra = [...actual].filter((v) => !expected.has(v));
        if (missing.length || extra.length) {
          violations.push(
            `${relname} ${role}: expected ${fmtSet(expected)}, effective ${fmtSet(actual)}` +
              (missing.length ? ` missing=${fmtSet(new Set(missing))}` : "") +
              (extra.length ? ` extra=${fmtSet(new Set(extra))}` : ""),
          );
        }
      }
    }
    expect(violations).toEqual([]);
  });

  // The deliberate column-level splits (006/079 shapes): where table-level was
  // revoked and access materialized per-column. For each registered
  // (rel, role, verb) column split, EVERY column of the relation is probed —
  // registered columns must hold, every OTHER column must NOT (has_column_
  // privilege is false exactly when neither table-level nor column-level
  // grants the verb, so this catches a column grant widened to `*` or a
  // table-level re-grant sneaking back).
  test("column-level grants equal the registered splits exactly", async () => {
    const flagged: { relname: string; role: ApiRole; verb: string; cols: ReadonlySet<string> }[] = [];
    for (const [relname, entry] of TABLE_GRANT_REGISTRY) {
      if (entry.kind !== "EXPOSED") continue;
      for (const [role, cols] of entry.grants.columnPrivileges) {
        const byVerb = new Map<string, Set<string>>();
        for (const [col, verbs] of cols) {
          for (const verb of verbs) {
            const set = byVerb.get(verb) ?? new Set<string>();
            set.add(col);
            byVerb.set(verb, set);
          }
        }
        for (const [verb, colset] of byVerb) flagged.push({ relname, role, verb, cols: colset });
      }
    }
    // workspaces.authenticated SELECT split is the pinned corpus case; a
    // registry that loses it must not let this test pass vacuously.
    expect(flagged.length).toBeGreaterThanOrEqual(1);
    const relnames = [...new Set(flagged.map((f) => f.relname))];
    const rows = await withTransientRetry(() => sql<{ relname: string; col: string; role: string; verb: string; held: boolean }[]>`
      select c.relname, a.attname as col, r.role, v.verb,
             has_column_privilege(r.role, c.oid, a.attname, v.verb) as held
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
      cross join unnest(array['anon','authenticated','service_role']) as r(role)
      cross join unnest(array['SELECT','INSERT','UPDATE','REFERENCES']) as v(verb)
      where n.nspname = 'public'
        and c.relname in ${sql(relnames)}
      order by c.relname, a.attname, r.role, v.verb`);

    const violations: string[] = [];
    for (const f of flagged) {
      const relevant = rows.filter((r) => r.relname === f.relname && r.role === f.role && r.verb === f.verb);
      if (relevant.length === 0) {
        violations.push(`${f.relname}: no columns enumerated for ${f.role} ${f.verb}`);
        continue;
      }
      for (const r of relevant) {
        const shouldHold = f.cols.has(r.col);
        if (r.held && !shouldHold) {
          violations.push(`${f.relname}.${r.col}: ${f.role} ${f.verb} held at column level but NOT registered — column split widened`);
        } else if (!r.held && shouldHold) {
          violations.push(`${f.relname}.${r.col}: ${f.role} ${f.verb} registered but not held — column split lost`);
        }
      }
    }
    expect(violations).toEqual([]);
  });

  // The registered-splits loop above only probes relations that HAVE
  // columnPrivileges — a NEW column grant on a relation registered without
  // them (e.g. `GRANT SELECT (newcol) ON t TO authenticated` where SELECT is
  // not held at table level) changes effective privileges yet never enters
  // `flagged`. This sweep enumerates EVERY api-role column ACL in the catalog
  // (aclexplode(pg_attribute.attacl)) and requires each to be registered —
  // unless the same verb is already registered at table level for that role
  // (a redundant-but-harmless column grant; effective state was already
  // asserted equal by the table-level probe).
  test("every live column-level ACL is registered or covered by a table-level grant", async () => {
    const aclRows = await withTransientRetry(() => sql<{ relname: string; col: string; grantee: string; verb: string }[]>`
      select c.relname, a.attname as col,
             case when x.grantee = 0 then 'PUBLIC' else g.rolname end as grantee,
             x.privilege_type as verb
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
      cross join lateral aclexplode(a.attacl) x
      left join pg_roles g on g.oid = x.grantee
      where n.nspname = 'public'
        and c.relkind in ('r', 'v', 'm', 'p', 'f')
        and not c.relispartition
        and (x.grantee = 0 or g.rolname in ('anon','authenticated','service_role'))
      order by c.relname, a.attname, grantee, verb`);

    const violations: string[] = [];
    for (const r of aclRows) {
      // PUBLIC is effective for every role; expand it to the api roles.
      const roles: readonly string[] = r.grantee === "PUBLIC" ? API_ROLES : [r.grantee];
      for (const role of roles) {
        const entry = TABLE_GRANT_REGISTRY.get(r.relname);
        if (!entry) continue; // unclassified — the parity test owns that red
        if (entry.kind === "INTERNAL" || entry.kind === "RETIRED") {
          violations.push(
            `${r.relname}.${r.col}: ${role} ${r.verb} held at column level but the relation is ${entry.kind} — over-grant`,
          );
          continue;
        }
        const registeredCol = entry.grants.columnPrivileges.get(role as ApiRole)?.get(r.col)?.has(r.verb) === true;
        const coveredByTable = entry.grants.privileges.get(role as ApiRole)?.has(r.verb) === true;
        if (!registeredCol && !coveredByTable) {
          violations.push(
            `${r.relname}.${r.col}: ${role} ${r.verb} held at column level but NOT registered — register the split in table-grants.ts columnPrivileges or revoke the grant`,
          );
        }
      }
    }
    expect(violations).toEqual([]);
  });
});
