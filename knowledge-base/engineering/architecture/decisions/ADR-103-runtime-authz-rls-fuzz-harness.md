# ADR-103: Runtime authz/RLS-fuzz harness on a Supabase-CLI-local disposable stack

- **Status:** adopting (harness build in progress on `feat-t3mp3st-security-eval`, #6256)
- **Date:** 2026-07-09
- **Deciders:** Operator; drafted via `/soleur:go` → brainstorm → CLO legal-threshold → plan (4-agent review panel) → this ADR. Provisioning fork ruled by the `cto` agent mid-`/work`.
- **Related:** #6256 (harness), #6257 (deferred user-facing defensive posture-check), ADR-064 (live-verify — the benign post-merge precedent), ADR-075/ADR-079 (agent-sandbox faithfulness; the shim anti-pattern precedent), mig 053 (`is_workspace_member` PERMISSIVE isolation policies), mig 068 (`*_jti_not_denied` RESTRICTIVE policies), `apps/web-platform/supabase/verify/068_*.sql` (the static presence-check sibling), `apps/web-platform/scripts/run-migrations.sh` (canonical filename-tracked applier). Origin: evaluating T3MP3ST (AGPL offensive red-team harness) → decision to **borrow the technique taxonomy, not adopt the tool**.

> **Ordinal.** ADR-103 is the next free ordinal against `origin/main` (highest existing is ADR-102). Provisional until `/ship` — the ADR-Ordinal Collision Gate re-verifies against `origin/main` at merge and after every Phase-7 sync; on collision, sweep `grep -rn 'ADR-103' knowledge-base/project/{plans,specs}/feat-t3mp3st-security-eval/` + this file + the harness code in the same edit.

## Context

Soleur's security stack is entirely **static/diff-time** (`security-sentinel` LLM review, `semgrep-sast` deterministic SAST, `infra-security` config-audit, `gdpr-gate`). Nothing proves *runtime exploitability* of tenant isolation — nothing drives one tenant's authenticated identity against another tenant's rows. Tenant-isolation is enforced by the PERMISSIVE `is_workspace_member(workspace_id, auth.uid())` policies (mig 053) + the RESTRICTIVE `*_jti_not_denied` policies (mig 068); `verify/068` asserts their *presence* statically but never *exercises* them. Brand-survival threshold: **single-user incident** — a cross-tenant leak is a single-user data breach, and a **false-green isolation test is worse than none**.

T3MP3ST (AGPL-3.0 autonomous offensive harness) demonstrates the technique but is rejected for adoption (~95% of its arsenal inapplicable; AGPL violates Soleur's MIT/BSD/Apache-2.0-only policy; blast-radius/supply-chain/cost). The decision is to **borrow its authz/IDOR kill-chain taxonomy as concepts** into a small, deterministic, in-repo harness.

## Decision

Build a deterministic runtime RLS/authz-fuzz harness that reproduces a Supabase authenticated request **at the DB layer** (`SET LOCAL ROLE authenticated` + `set_config('request.jwt.claims', …)` claim injection — no signed JWT, no PostgREST, attacker dimension = `sub`), enumerates targets **from the live `pg_policies` catalog** (isolation set ∪ jti-deny set), seeds a `service_role` tenant-A row per table (so a tenant-B `count=0` means *denied*, not *empty*), discriminates **SQLSTATE 42501** (RLS denial) from constraint errors, and runs against a **local, provider-detached disposable Postgres**. Coverage includes SECURITY DEFINER RPC bypass and `storage.objects` attachment isolation. A fail-closed local-DSN allowlist (never hosted Supabase) and a prod-vs-local catalog parity diff backstop faithfulness.

### Provisioning the faithful local Postgres (CTO ruling, 2026-07-09)

`supabase db reset` is **structurally incompatible** with the repo: the CLI derives each migration's tracking `version` from its numeric filename prefix and PKs on it, but the repo has **29 duplicate numeric prefixes across 152 forward migrations** (the repo's own `run-migrations.sh` tracks by full *filename* in `public._schema_migrations`, so duplicates are valid there). The CLI aborts on the 2nd `007_*` with `duplicate key … schema_migrations_pkey (23505)`.

**Ruling:** provision from the Supabase-CLI substrate but **disable the CLI's migration step**, applying app migrations via the repo's canonical mechanism:

1. **Substrate:** `supabase start` provides the real GoTrue `auth` schema (`auth.uid()`/`auth.jwt()`), real roles (`anon`/`authenticated` `bypassrls=false`, `service_role` `bypassrls=true` — verified), and extensions. The CLI's migration step is disabled via a **local-only `[db.migrations] enabled = false`** in `supabase/config.toml` (supported in the pinned CLI 2.84.2 — verified). This keeps the real migrations dir on disk and makes the "CLI provides substrate, repo applies migrations" split declarative rather than a fragile dir-shuffle.
2. **Migration application:** the repo's **canonical `run-migrations.sh`** (filename-ordered, `--single-transaction` per file, filename-tracked) pointed at the CLI DB (`postgres://postgres:postgres@127.0.0.1:54322/postgres`) via **`docker exec` on the CLI's bundled `psql`** — zero new deps, exact semantic parity with prod's applier. Do NOT fork the apply/track logic into a node `pg` runner (a second implementation that could drift — the same parallel-reimplementation hazard the panel rejected for the auth shim).

### Faithfulness contract (CTO risks 1–3)

A static catalog diff of {tables, columns, policies} is **insufficient**. The parity diff MUST be widened, and one risk is not diff-catchable:

1. **Role catalog (highest value for an authz harness):** diff `pg_roles` (`rolbypassrls`, `rolsuper`, `rolinherit`), `pg_auth_members`, and `information_schema.role_table_grants` local-vs-prod — a role with wrong BYPASSRLS/grant state silently changes every isolation verdict. Fail on drift.
2. **Extensions:** diff `pg_extension` (name + version); treat an apply-time "extension does not exist" as a **parity finding**, not a harness bug to patch around.
3. **GoTrue/`auth` behavioral skew (NOT diff-catchable):** claim-parsing behavior is version-coupled. **Pin the CLI/GoTrue version to prod's** in the harness + CI; record the pin here as a maintained parity contract. The diff catches shape, not behavior; the version pin is the control.

The parity-diff design routes through `soleur:engineering:review:data-integrity-guardian` — generic build agents won't independently know the role-catalog facets are load-bearing for an isolation verdict.

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| **Supabase-CLI substrate + `[db.migrations] disabled` + repo `run-migrations.sh` over `docker exec psql`** | **Chosen** | Only option preserving BOTH faithfulness (real GoTrue auth schema + roles) AND prod-parity migration application; zero new deps. |
| docker Postgres + hand-written `auth` shim | Rejected | ADR-079 anti-pattern: a shim reimplements the exact `auth.*`/JWT-claim surface under test → false-green vector. Rejected by the review panel + strong-model advisor. |
| Renumber the 29 duplicate-prefix migrations | Rejected | Highest blast radius: rewrites applied production migration history, breaks `run-migrations.sh` filename tracking (PK *is* the filename) + the disk-vs-tracked drift check + every in-repo reference. Mutating production truth to satisfy a test harness's tracker is inverted priority. |
| `pg` devDep + node apply runner | Rejected | Adds a dep and forks the apply/track logic into a second implementation that can drift from `run-migrations.sh`; buys nothing in faithfulness. |
| Hosted Supabase dev integration test (existing `*-cross-tenant.integration.test.ts` pattern) | Rejected | Brainstorm/CLO guardrail: no attack/scan traffic to rented infra even on our own account (Hetzner abuse desk, Supabase/Cloudflare AUPs). |
| Signed-JWT full-stack via local PostgREST | Rejected | Nondeterministic; tests PostgREST, not the RLS invariant; heavier. Claim injection at the DB layer is strictly more faithful to the isolation invariant. |
| Extend `verify/068` with runtime attack cases | Rejected | `verify/` runs via `run-verify.sh` against **prod** (`doppler -c prd`) — attack cases must never run there. The prod-parity diff is read-only catalog introspection (ordinary catalog reads via that same path), which is in-bounds; attack queries are not. |

## Consequences

- **Positive:** first runtime proof of tenant isolation; runtime backstop for the static `verify/068`; provider-detached (no ToS exposure); no AGPL code; deterministic + CI-gateable.
- **Cost / maintenance:** a maintained CLI/GoTrue-version pin tracking prod; a widened parity diff that needs read-only prod catalog access (via the existing `run-verify.sh` Doppler `prd` path); the harness enumerates from the live catalog so it self-tracks new tenant tables.
- **Open risk carried forward:** whether all 152 migrations apply cleanly to the CLI substrate is itself a parity signal — an apply failure on an out-of-band-provisioned prod object is a *finding*, not a bug to patch around (CTO risk 2).

## First-run findings

The harness earned its keep on the first full run: the RPC-bypass dimension (AC8)
surfaced **4 real cross-tenant bypasses** of the same root cause — a migration
granting EXECUTE to `service_role` only, but Supabase's default privileges left
`authenticated` (and `anon`) a residual EXECUTE grant that `revoke ... from public`
never removed, and the function trusts a caller-supplied `p_user_id`/reads across
tenants:

- `find_stuck_active_conversations` — returns `(id, user_id)` for **all** tenants'
  stuck conversations to any authenticated/anon caller.
- `acquire_conversation_slot` / `release_conversation_slot` / `touch_conversation_slot`
  — trust `p_user_id` → an authenticated caller can occupy/exhaust, delete, or
  keep-alive **another** tenant's concurrency slots (cap DoS).

Filed as **#6306** and baselined in `test/rls-fuzz/rpc-cases.ts` via `test.fails`
(green while tracked; flips RED the moment the grant is fixed, forcing un-baseline).
The 18-table base matrix + storage.objects showed **no** isolation leaks — RLS on
the workspace-isolated tables holds. One catalog caveat recorded: the
`workspace_invitations` SELECT policy subqueries `auth.users`, which `authenticated`
cannot read, so that table's authenticated SELECT is grant-blocked for *all*
tenants (its write-side attacks carry the isolation proof; the parity diff checks
whether prod shares the same `auth.users` grant posture).

## C4 impact

None. The harness is dev/CI tooling outside the modeled system boundary (like the existing test suite): no external actor, no external system/vendor (all-local disposable Postgres), no product-boundary data store, no production access-relationship change. Verified against `model.c4`/`views.c4`/`spec.c4` (architecture-strategist).
