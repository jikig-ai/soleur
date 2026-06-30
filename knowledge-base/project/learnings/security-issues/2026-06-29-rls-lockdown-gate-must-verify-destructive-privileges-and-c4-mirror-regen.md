# Learning: an RLS-lockdown verification gate must assert destructive privileges (TRUNCATE/DELETE), not just SELECT

## Problem

Remediating a Supabase `rls_disabled_in_public` finding on the production Inngest backing project
(`soleur-inngest-prd`), the first cut of the self-healing apply workflow's "authoritative" gate
asserted only `relrowsecurity=true` AND `has_table_privilege('anon', oid, 'SELECT')=false`. The
plan's brand-survival threshold is `single-user incident`, and the named brand-fatal vector is a
`TRUNCATE`/`DELETE` wiping durable run-state — but **RLS does not gate `TRUNCATE`** (it is
privilege-gated, not row-policy-gated), and `SELECT=false` does not imply `TRUNCATE=false`. So a
gate that passes green can leave the destructive vector wide open on any future regression.

A second, orthogonal trap: enabling RLS on a public table owned by a role **other than** the
connection role would block even that connection (the owner-bypass only helps the *owner*); the
single-table liveness probe (`public.events`) would still pass.

## Solution

The lockdown's load-bearing control is `REVOKE ALL` on every public relation + `ALTER DEFAULT
PRIVILEGES … REVOKE` (recurrence fix), applied as the `postgres` owner with **non-forced** RLS
(owner bypasses non-forced RLS, so Inngest keeps full access). The *verification* gate must mirror
what the remediation actually does:

```sql
select count(*) as violations
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind in ('r','p')   -- ordinary + partitioned
  and ( c.relrowsecurity = false
     or pg_get_userbyid(c.relowner) <> 'postgres'      -- non-owner table → RLS would block us
     or has_table_privilege('anon',c.oid,'SELECT') or has_table_privilege('anon',c.oid,'INSERT')
     or has_table_privilege('anon',c.oid,'UPDATE') or has_table_privilege('anon',c.oid,'DELETE')
     or has_table_privilege('anon',c.oid,'TRUNCATE')
     or has_table_privilege('authenticated',c.oid,'SELECT') /* …INSERT/UPDATE/DELETE/TRUNCATE */ );
```

Also revoke matview grants in the SQL (matviews have **no** RLS — a grant is their *only* access
control; `pg_matviews` is not in `pg_tables`, so a separate loop is needed).

## Key Insight

When you verify a privilege-lockdown, **assert the full privilege set you revoked, for every role
you revoked it from** — not just the one read privilege RLS happens to also cover. RLS and `GRANT`
are different planes: RLS filters rows for SELECT/UPDATE/DELETE/INSERT *policies*; `TRUNCATE`,
`REFERENCES`, `TRIGGER` are grant-only. "RLS on + SELECT denied" is necessary but not sufficient
proof that a `REVOKE ALL` landed. A self-heal gate that under-asserts becomes a silent false-pass
on the exact brand-fatal vector the plan named. Convergent multi-agent review (security-sentinel +
data-integrity-guardian + user-impact-reviewer all flagged it) is what surfaced this — no single
agent owned it.

## Session Errors

- **`.c4` source edit needs `model.likec4.json` regenerated in the same commit.** Editing a
  `model.c4` element *description* passed the c4 **vitest** suite (`c4-code-syntax.test.ts`,
  `c4-render.test.ts`) but FAILED a separate **shell** test (`plugins/soleur/test/c4-model-freshness.test.sh`)
  that diffs the committed rendered mirror against a fresh render — surfaced only at the full-suite
  exit gate (123/124), not the touched-file vitest. **Prevention:** when editing any `.c4` file, run
  `bash scripts/regenerate-c4-model.sh` and commit the updated `model.likec4.json` in the same commit.
- **GH Actions issue-body shell authoring (actionlint/shellcheck):** (a) markdown backticks inside a
  single-quoted `printf` trip SC2016 — use plain text for code identifiers in issue-body `printf`;
  (b) a quoted-heredoc body at column 0 breaks the YAML `run: |` block scalar — keep heredoc bodies
  indented or use `printf`; (c) a comment line beginning `# shellcheck …` is parsed as a *directive*
  (SC1073/1072) — don't start an explanatory comment with that token. **Prevention:** run
  `actionlint <file>` locally before commit (it runs shellcheck on `run:` blocks).
- **shellcheck `$cls[…]` (SC1087) + `A && B || C` (SC2015) in a bash test.** **Prevention:** brace
  scalar expansions adjacent to `[` (`${cls}`), and use `if/then/else` helpers, not `pred && ok || bad`.
- **psql/node-pg absent** for the direct pooler-role check — relied on convergent evidence
  (owner=postgres on all tables + Management-API `current_user=postgres` + the health workflow's
  documented `usename=='postgres'` assertion). Graceful degradation; not a blocker.

## Tags
category: security-issues
module: apps/web-platform/infra/inngest-rls
