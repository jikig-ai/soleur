// Prod-vs-local security-catalog parity diff (#6256, ADR-103, AC6).
//
// The runtime RLS-fuzz harness only proves isolation on a LOCAL disposable
// Supabase stack. Its guarantee is only as good as that stack's faithfulness to
// prod. This script converts "we hope local matches prod" into a CHECKED
// invariant: it reads the security-relevant catalog (policies, RLS flags, table
// + function grants, role attributes, auth/helper fn definitions) from BOTH the
// local stack and prod, and fails on ANY diff.
//
// The prod read is ORDINARY read-only catalog introspection over the existing
// run-verify doppler path (DATABASE_URL_POOLER | DATABASE_URL under `doppler run
// -c prd`) — NOT attack traffic. Run:
//   doppler run -p soleur -c prd -- npx tsx scripts/rls-parity-check.ts
//
// Exit: 0 = catalogs match (or prod creds absent → skipped with a warning);
//       1 = at least one diff; 2 = a connection/query error.

import postgres from "postgres";

const LOCAL_DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";
const PROD_DSN = process.env.DATABASE_URL_POOLER ?? process.env.DATABASE_URL ?? "";

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);

/** Fail-closed: the "local" side must resolve to a loopback host (never a hosted target). */
function assertLocalHost(dsn: string): void {
  let host: string;
  try {
    host = new URL(dsn).hostname.replace(/^\[|\]$/g, "");
  } catch {
    throw new Error(`rls-parity: unparseable local DSN`);
  }
  if (!LOCAL_HOSTS.has(host)) throw new Error(`rls-parity: local DSN host '${host}' is not loopback — refusing`);
}

// Each query returns one text column; the row set (sorted) is the section snapshot.
const SECTIONS: { name: string; sql: string }[] = [
  {
    name: "policies",
    sql: `select schemaname||'|'||tablename||'|'||policyname||'|'||permissive||'|'||array_to_string(roles,',')
            ||'|'||cmd||'|'||coalesce(qual,'')||'|'||coalesce(with_check,'') as line
          from pg_policies where schemaname in ('public','storage') order by line`,
  },
  {
    name: "rls_flags",
    sql: `select n.nspname||'.'||c.relname||'|rls='||c.relrowsecurity||'|force='||c.relforcerowsecurity as line
          from pg_class c join pg_namespace n on n.oid=c.relnamespace
          where n.nspname in ('public','storage') and c.relkind='r' and c.relrowsecurity order by line`,
  },
  {
    name: "table_grants",
    sql: `select table_schema||'.'||table_name||'|'||grantee||'|'||privilege_type as line
          from information_schema.role_table_grants
          where table_schema in ('public','storage') and grantee in ('anon','authenticated') order by line`,
  },
  {
    name: "role_attrs",
    sql: `select rolname||'|super='||rolsuper||'|bypassrls='||rolbypassrls as line
          from pg_roles where rolname in ('anon','authenticated','authenticator','service_role') order by line`,
  },
  {
    name: "secdef_fn_grants",
    sql: `select p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
            ||'|secdef='||p.prosecdef
            ||'|auth='||has_function_privilege('authenticated',p.oid,'EXECUTE')
            ||'|anon='||has_function_privilege('anon',p.oid,'EXECUTE') as line
          from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public' and p.prosecdef order by line`,
  },
  {
    name: "auth_fn_defs",
    sql: `select p.proname||'|'||md5(pg_get_functiondef(p.oid)) as line
          from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where (n.nspname='auth' and p.proname in ('uid','jwt','role'))
             or (n.nspname='public' and p.proname in ('is_workspace_member','is_workspace_owner','is_jti_denied','is_jti_denied_from_jwt'))
          order by line`,
  },
];

async function snapshot(dsn: string): Promise<Map<string, string[]>> {
  const sql = postgres(dsn, { max: 1, prepare: false, onnotice: () => {}, idle_timeout: 5 });
  try {
    const out = new Map<string, string[]>();
    for (const s of SECTIONS) {
      const rows = await sql.unsafe(s.sql);
      out.set(s.name, rows.map((r) => (r as unknown as { line: string }).line));
    }
    return out;
  } finally {
    await sql.end({ timeout: 5 });
  }
}

function diffSection(local: string[], prod: string[]): { onlyLocal: string[]; onlyProd: string[] } {
  const L = new Set(local);
  const P = new Set(prod);
  return {
    onlyLocal: local.filter((x) => !P.has(x)),
    onlyProd: prod.filter((x) => !L.has(x)),
  };
}

async function main(): Promise<number> {
  if (!PROD_DSN) {
    console.warn("[rls-parity] no prod DSN (DATABASE_URL_POOLER|DATABASE_URL) — skipping. Run under `doppler run -c prd`.");
    return 0;
  }
  assertLocalHost(LOCAL_DSN);

  const [local, prod] = await Promise.all([snapshot(LOCAL_DSN), snapshot(PROD_DSN)]);

  let diffs = 0;
  for (const { name } of SECTIONS) {
    const { onlyLocal, onlyProd } = diffSection(local.get(name) ?? [], prod.get(name) ?? []);
    if (onlyLocal.length || onlyProd.length) {
      diffs += onlyLocal.length + onlyProd.length;
      console.error(`\n=== DIFF in section "${name}" ===`);
      for (const l of onlyProd) console.error(`  - only in PROD:  ${l}`);
      for (const l of onlyLocal) console.error(`  + only in LOCAL: ${l}`);
    }
  }

  if (diffs > 0) {
    console.error(`\n[rls-parity] FAIL — ${diffs} catalog difference(s) between local and prod. The local stack is not faithful; the harness's guarantee is void until this is zero.`);
    return 1;
  }
  console.log("[rls-parity] OK — local security catalog matches prod across all sections.");
  return 0;
}

main()
  .then((code) => process.exit(code))
  .catch((err) => {
    console.error(`[rls-parity] ERROR: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(2);
  });
