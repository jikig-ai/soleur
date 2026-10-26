// dump-api-grants.ts — snapshot the prd Data-API grant surface as explicit DDL.
//
// WHY (2026-10-30 Supabase change): hosted Supabase stops auto-granting Data API
// access to new `public`-schema tables. Anything replaying this repo's migration
// corpus on a fresh environment (new project, preview branch, `supabase db
// reset`, the rls-authz-fuzz stack) gets `permission denied` on every relation
// that lacks explicit GRANTs. Migration 174 reproduces prd's EFFECTIVE
// privileges verbatim — this script is what generates it.
//
// The source of truth is the live catalog, NOT the migration files: effective
// privileges compose default-era auto-grants + explicit GRANT/REVOKE and cannot
// be reconstructed from source text (a REVOKE leaves no trace in earlier files).
// We read `aclexplode(pg_class.relacl)` (exact per-role table/sequence ACLs) and
// `aclexplode(pg_attribute.attacl)` (exact column ACLs — NOT
// information_schema.column_privileges, which is scoped to privileges the
// connecting role may grant and silently under-reports for a non-superuser
// DSN). The column shapes exist for the 006/079 splits where table-level was
// deliberately revoked — a table-level GRANT would silently subsume and
// re-expose every column; Postgres resolution, see
// learnings/2026-03-20-supabase-column-level-grant-override.md.
//
// The emitted artifact IS the migration shape: a GENERATED header plus, per
// relation, the FK-lint-convention `DO $$ BEGIN IF to_regclass(…) IS NOT NULL
// THEN … END IF; END $$;` wrapper — no manual transform between this script's
// output and the committed file (hand-authored header prose aside).
//
// Run (prd, read-only catalog introspection — same access class as
// run-verify.sh):
//   doppler run -p soleur -c prd -- npx tsx scripts/dump-api-grants.ts \
//     --out ../supabase/migrations/174_api_data_grants_snapshot.sql \
//     --report /tmp/api-grants-report.md
//
// Exit: 0 = dump written; 2 = connection/query error; 1 = usage error.

import postgres from "postgres";
import { writeFileSync } from "node:fs";

const API_ROLES = ["anon", "authenticated", "service_role"] as const;
const RELKIND_LABEL: Record<string, string> = {
  r: "table",
  v: "view",
  m: "matview",
  S: "sequence",
  p: "partitioned table",
  f: "foreign table",
};
// PostgREST serves all of r,v,m,p,f — keep the dump's scope identical to the
// rls-fuzz catalog enumerator (test/rls-fuzz/catalog.ts › publicApiRelations)
// so a partitioned parent or foreign table cannot escape the snapshot.
const RELKINDS_REL = "'r','v','m','p','f'";
const RELKINDS_ALL = `'r','v','m','p','f','S'`;

interface AclRow {
  relname: string;
  relkind: string;
  grantee: string; // 'PUBLIC' is materialized per-role downstream
  privilege: string;
}
interface ColRow {
  table_name: string;
  column_name: string;
  grantee: string;
  privilege: string;
}
interface ClassRow {
  relname: string;
  relkind: string;
  rls: boolean;
  force_rls: boolean;
  policies: string; // permissive policy names, "role:cmd"
  identity_cols: string;
  serial_cols: string;
}

function q(ident: string): string {
  return `"${ident.replace(/"/g, '""')}"`;
}

function usage(): never {
  console.error("usage: dump-api-grants.ts --out <sql-path> --report <md-path>");
  process.exit(1);
}

const args = process.argv.slice(2);
let outPath = "";
let reportPath = "";
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--out") outPath = args[++i] ?? "";
  else if (args[i] === "--report") reportPath = args[++i] ?? "";
}
if (!outPath || !reportPath) usage();

const DSN = process.env.DATABASE_URL_POOLER ?? process.env.DATABASE_URL ?? "";
if (!DSN) {
  console.error("[dump-api-grants] no DSN (DATABASE_URL_POOLER|DATABASE_URL) — run under `doppler run -c prd`.");
  process.exit(2);
}

async function main(): Promise<number> {
  const sql = postgres(DSN, { max: 1, prepare: false, idle_timeout: 10 });

  try {
    // Table/view/matview/sequence-level ACLs — exact effective state.
    const acls = await sql.unsafe<AclRow[]>(`
      select c.relname, c.relkind,
             case when a.grantee = 0 then 'PUBLIC' else g.rolname end as grantee,
             a.privilege_type as privilege
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      cross join lateral aclexplode(c.relacl) a
      left join pg_roles g on g.oid = a.grantee
      where n.nspname = 'public'
        and c.relkind in (${RELKINDS_ALL})
        and (a.grantee = 0 or g.rolname in ('anon','authenticated','service_role'))
        and not c.relispartition
      order by c.relkind, c.relname, grantee, privilege
    `);

    // Column-level grants (the revoked-table-level shapes: 006 users, 079
    // repos). Read aclexplode(pg_attribute.attacl) — information_schema.
    // column_privileges is permission-scoped to the CONNECTING role's
    // grantable set and silently under-reports under a non-superuser DSN.
    const cols = await sql.unsafe<ColRow[]>(`
      select c.relname as table_name, a.attname as column_name,
             case when x.grantee = 0 then 'PUBLIC' else g.rolname end as grantee,
             x.privilege_type as privilege
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
      cross join lateral aclexplode(a.attacl) x
      left join pg_roles g on g.oid = x.grantee
      where n.nspname = 'public'
        and c.relkind in (${RELKINDS_REL})
        and not c.relispartition
        and (x.grantee = 0 or g.rolname in ('anon','authenticated','service_role'))
      order by c.relname, grantee, privilege, a.attname
    `);

    // Classification inputs: RLS flags, permissive policies, identity/serial cols.
    const cls = await sql.unsafe<ClassRow[]>(`
      with pol as (
        select tablename,
               string_agg(distinct array_to_string(p.roles,',')||':'||p.cmd, ' ') as policies
        from pg_policies p
        where p.schemaname = 'public' and p.permissive = 'PERMISSIVE'
        group by tablename
      ),
      ident as (
        select c.relname,
               string_agg(distinct a.attname, ',') filter (where a.attidentity in ('a','d')) as identity_cols,
               string_agg(distinct a.attname, ',') filter (
                 where a.attidentity = '' and pg_get_expr(d.adbin, d.adrelid) like 'nextval(%'
               ) as serial_cols
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        left join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
        left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
        where n.nspname = 'public' and c.relkind in (${RELKINDS_ALL})
        group by c.relname
      )
      select c.relname, c.relkind, c.relrowsecurity as rls, c.relforcerowsecurity as force_rls,
             coalesce(pol.policies, '') as policies,
             coalesce(ident.identity_cols, '') as identity_cols,
             coalesce(ident.serial_cols, '') as serial_cols
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      left join pol on pol.tablename = c.relname
      left join ident on ident.relname = c.relname
      where n.nspname = 'public' and c.relkind in (${RELKINDS_ALL})
        and not c.relispartition
      order by c.relkind, c.relname
    `);

    // ---- Emit -------------------------------------------------------------
    // Map rel -> role -> Set(verbs) at TABLE level. A PUBLIC grantee expands to
    // all three api roles (PUBLIC privileges are effective for every role).
    const tableLevel = new Map<string, Map<string, Set<string>>>();
    const publicOrigin = new Set<string>(); // "rel|role" — verb came via PUBLIC
    for (const a of acls) {
      const targets = a.grantee === "PUBLIC" ? [...API_ROLES] : [a.grantee];
      for (const role of targets) {
        if (!tableLevel.has(a.relname)) tableLevel.set(a.relname, new Map());
        const m = tableLevel.get(a.relname)!;
        if (!m.has(role)) m.set(role, new Set());
        m.get(role)!.add(a.privilege);
        if (a.grantee === "PUBLIC") publicOrigin.add(`${a.relname}|${role}|${a.privilege}`);
      }
    }

    // Column grants NOT already covered by a table-level grant of the same verb
    // to the same role (or to PUBLIC) — those must be emitted per-column.
    const colGrants = new Map<string, Map<string, Map<string, Set<string>>>>(); // rel -> role -> verb -> cols
    const tblByName = new Map<string, string>(); // relname -> relkind
    for (const a of acls) tblByName.set(a.relname, a.relkind);
    for (const c of cls) if (!tblByName.has(c.relname)) tblByName.set(c.relname, c.relkind);

    for (const cp of cols) {
      const coveredByTable = (role: string) =>
        tableLevel.get(cp.table_name)?.get(role)?.has(cp.privilege) === true;
      const targets = cp.grantee === "PUBLIC" ? [...API_ROLES] : [cp.grantee];
      for (const role of targets) {
        if (coveredByTable(role)) continue; // redundant — table-level already covers
        if (!colGrants.has(cp.table_name)) colGrants.set(cp.table_name, new Map());
        const m1 = colGrants.get(cp.table_name)!;
        if (!m1.has(role)) m1.set(role, new Map());
        const m2 = m1.get(role)!;
        if (!m2.has(cp.privilege)) m2.set(cp.privilege, new Set());
        m2.get(cp.privilege)!.add(cp.column_name);
      }
    }

    const relOrder = (k: string) => ({ r: 0, p: 1, f: 2, v: 3, m: 4, S: 5 })[k] ?? 9;
    // Codepoint compare, NOT localeCompare: locale ordering is environment-
    // dependent and would let the emitted file's ordering drift by machine.
    const rels = [...tblByName.keys()].sort(
      (a, b) => relOrder(tblByName.get(a)!) - relOrder(tblByName.get(b)!) || (a < b ? -1 : a > b ? 1 : 0),
    );

    // Emit the committed-artifact shape directly: per relation, the FK-lint
    // `to_regclass` precondition wrapper around its GRANTs, so the file this
    // command produces needs no manual transform to become the migration.
    const lines: string[] = [
      `-- GENERATED by scripts/dump-api-grants.ts on ${new Date().toISOString().slice(0, 10)}.`,
      `-- Provenance: effective api-role privileges of every public relation`,
      `-- (relkind r,v,m,p,f,S) extracted from the live prd catalog via`,
      `-- aclexplode(pg_class.relacl) + aclexplode(pg_attribute.attacl), emitted`,
      `-- verbatim. See 174_api_data_grants_snapshot.sql's header for the full`,
      `-- rationale (changelog 45329, ADR-303) — keep regenerated headers aligned`,
      `-- with it; known snapshot warts are documented there, not here.`,
      `--`,
      `-- Per-relation grants sit behind to_regclass preconditions (FK-lint`,
      `-- convention): a relation that does not exist on a given replay is`,
      `-- skipped rather than aborting the file.`,
      ``,
    ];
    for (const rel of rels) {
      const kind = tblByName.get(rel)!;
      const objKw = kind === "S" ? "SEQUENCE" : "TABLE";
      const grantLines: string[] = [];
      const roles = tableLevel.get(rel);
      if (roles) {
        for (const role of API_ROLES) {
          const verbs = roles.get(role);
          if (!verbs?.size) continue;
          grantLines.push(`    GRANT ${[...verbs].sort().join(", ")} ON ${objKw} public.${q(rel)} TO ${role};`);
        }
      }
      const cg = colGrants.get(rel);
      if (cg) {
        for (const role of API_ROLES) {
          const verbs = cg.get(role);
          if (!verbs) continue;
          for (const [verb, colset] of [...verbs].sort()) {
            const colsList = [...colset].sort().map(q).join(", ");
            grantLines.push(`    GRANT ${verb} (${colsList}) ON TABLE public.${q(rel)} TO ${role};`);
          }
        }
      }
      if (!grantLines.length) continue;
      lines.push(`DO $$ BEGIN IF to_regclass('public.${q(rel)}') IS NOT NULL THEN`);
      lines.push(...grantLines);
      lines.push(`END IF; END $$;`, ``);
    }

    // ---- Report -------------------------------------------------------------
    const report: string[] = [
      `# api-grants snapshot report — ${new Date().toISOString().slice(0, 10)}`,
      "",
      `Relations: ${rels.length} | table-level grant lines: ${lines.filter((l) => l.trimStart().startsWith("GRANT")).length}`,
      "",
      "| relation | kind | RLS | force | permissive policies | identity | serial | api-role grants | notes |",
      "|---|---|---|---|---|---|---|---|---|",
    ];
    const clsByName = new Map(cls.map((c) => [c.relname, c]));
    for (const rel of rels) {
      const c = clsByName.get(rel);
      const grants = tableLevel.get(rel);
      const summary = API_ROLES.map((r) => {
        const v = grants?.get(r);
        if (!v?.size) return `${r}:—`;
        const viaPublic = [...v].every((verb) => publicOrigin.has(`${rel}|${r}|${verb}`));
        return `${r}:${[...v].sort().join("/")}${viaPublic ? "(via PUBLIC)" : ""}`;
      }).join(" ");
      const colNote = colGrants.has(rel) ? " column-level grants present (table-level not held for some verbs)" : "";
      report.push(
        `| ${rel} | ${RELKIND_LABEL[tblByName.get(rel)!]} | ${c?.rls ? "on" : "off"} | ${c?.force_rls ? "yes" : "no"} | ${c?.policies || "—"} | ${c?.identity_cols || "—"} | ${c?.serial_cols || "—"} | ${summary} |${colNote} |`,
      );
    }

    writeFileSync(outPath, lines.join("\n") + "\n");
    writeFileSync(reportPath, report.join("\n") + "\n");
    console.log(`[dump-api-grants] wrote ${lines.filter((l) => l.trimStart().startsWith("GRANT")).length} grant statements for ${rels.length} relations -> ${outPath}`);
    console.log(`[dump-api-grants] classification report -> ${reportPath}`);
    return 0;
  } catch (e) {
    console.error("[dump-api-grants] query error:", e instanceof Error ? e.message : e);
    return 2;
  } finally {
    await sql.end({ timeout: 5 });
  }
}

process.exit(await main());
