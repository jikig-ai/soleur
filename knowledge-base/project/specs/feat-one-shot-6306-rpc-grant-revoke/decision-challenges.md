# Decision Challenges — feat-one-shot-6306-rpc-grant-revoke

Issue: #6306 — revoke residual anon/authenticated EXECUTE on service-role-only
SECURITY DEFINER RPCs.

## Re-scoped issue premises (Phase 0.6 premise validation)

Two premises in the issue body were stale and did not survive verification against
the codebase. Both are recorded here so a downstream reader (or the #6256 harness
author) does not re-inherit them.

### 1. AC4 "un-baseline the `test.fails` entry in `test/rls-fuzz/rpc-cases.ts`" — NOT satisfiable

`test/rls-fuzz/` and `rpc-cases.ts` **do not exist** in this repo yet. The runtime
RLS/authz-fuzz harness that owns them (#6256, the "ADR-103" the issue cites — see
premise 2) is **OPEN / not merged**. `find … -iname '*rpc-cases*'` returns nothing.

**Resolution:** the un-baseline AC cannot be actioned — there is no file to edit. This
fix's durable regression guard is the always-on deploy-time sentinel
`verify/128_definer_rpc_residual_grants_revoked.sql` (fails the release pipeline on
any `bad>0`), NOT a test-harness baseline flip.

**Cross-reference follow-up (owned by #6256, not this PR):** when the #6256 fuzz
harness lands, its `test/rls-fuzz/rpc-cases.ts` entry for
`find_stuck_active_conversations` (and the four sibling slot RPCs) MUST be a plain
denial assertion — never a baselined `test.fails` known-exposure, since migration 128
has now closed the exposure. `/ship` posts a cross-ref comment on #6256 recording this.
**This P1 fix does NOT block on the unmerged harness.**

### 2. "Discovered by the harness (#6256, **ADR-103**)" — ADR mis-numbered

`ADR-103` is `ADR-103-dedicated-host-boot-heartbeats-require-guarded-reprovision-path.md`,
unrelated to the fuzz harness. The citation is harmless to the fix (the harness itself,
#6256, is real). Noted so the plan/PR does not inherit a false ADR reference. No new ADR
is authored — migration 128 restores an already-decided service-role-only intent
(migration 037) and moves no ownership/tenancy/trust boundary.

## Deferred root-cause hardening (tracked, not silent)

Migration 128 remediates the **five existing** residual grants (the live exposure). It
does NOT close the *class*: Supabase's default `ALTER DEFAULT PRIVILEGES` still grants
EXECUTE to anon/authenticated on every *future* `public` SECURITY DEFINER function, and
the audit criterion (revoke-from-public-only) cannot detect a definer function that
manages **no grants at all**. `/ship` files a tracked `type/security` follow-up issue
(PM4) for a repo-wide baseline: either an `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE …
FROM anon, authenticated` migration OR a migration-lint gate that fails CI on a
revoke-from-public-only DEFINER function. This is a concrete tracked deferral, not a soft
"province of #6256" handoff.
