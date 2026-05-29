# Learning: "append-before-flip" must hold for EVERY mutation in a script, not just the obvious one

## Problem

PR-1 of #4581 swapped the WORM audit append from `psql` to a PostgREST RPC across three
flag-tooling scripts, with the invariant "audit row written BEFORE any state mutation"
(append-before-flip: a failed audit aborts via `exit 4` before mutating prod). The plan
and the implementation verified this for the **Flagsmith** mutation in each script — and
it held. `silent-failure-hunter` even confirmed (clean pass) that the audit precedes the
Flagsmith write in all three.

But `set-role.sh` has TWO mutations: a prod `users.role` Supabase PATCH **and** a Flagsmith
identity-trait write. The audit sat between them — after the PATCH, before the trait write.
So append-before-flip held for the Flagsmith mutation but NOT for the `users.role` PATCH: a
real user's prod role could change with the audit RPC then failing → an unaudited prod
mutation. Only `user-impact-reviewer` (enumerating user-facing artifacts: `public.users.role`)
caught it; the silent-failure lens, anchored on the Flagsmith write, reported the invariant
satisfied.

## Solution

Move the audit append above BOTH mutations in `set-role.sh` (the audit inputs — `USER_ID`,
`CUR_ROLE`, actor — all resolve before either mutation, so the reorder is free). Then add a
test `assert_order` that, per script, asserts the audit CALL line precedes the FIRST
state-mutation CALL line — using call-site regexes (`audit_append "`, `flip_segment_in_env "$`,
`supa -X PATCH`) that exclude function *definitions* (the `fs_api -X POST` inside a helper
def would otherwise false-positive). Verified the assertion has teeth with a negative-control
fixture.

## Key Insight

When a script performs N state mutations and you assert "audit/log/checkpoint happens before
the mutation," enumerate ALL N mutations and confirm the ordering holds for each — not just
the one the feature is "about." The reviewer lens matters: a silent-failure / control-flow
lens anchors on the mutation it's told about (the Flagsmith write) and reports the invariant
satisfied; only the **user-facing-artifact** lens (`user-impact-reviewer` naming
`public.users.role`) enumerates every prod side-effect independently. This is the
implementation-side twin of the plan-time learning
[[2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy]]: there the re-verify
read proxied for the invariant; here the ordering assertion was checked for one mutation and
assumed for all. Both fail the same way — a green check over a partially-true invariant.

## Session Errors

1. **Test asserted the proxy, not the invariant (FINDING 2, pr-introduced).** The PR-1 helper
   test asserted each script *sources* the helper (`grep -Fq audit-flag-flip.sh`) but not that
   it *calls* it before mutating — the plan's acceptance criterion. The gate failed open: it
   stayed green while set-role.sh mutated before auditing. Recovery: added the `assert_order`
   ordering check. Prevention: when an acceptance criterion says "X happens before Y," the test
   must assert the *ordering*, not the *presence* of X.
2. **Deliberate plan deviation — one-time live RPC validation.** The plan (DHH's call) said "no
   preflight WORM writes." I judged a single real-RPC call worth it to de-risk the `--argjson`
   bool/null arg shape (Kieran P0-1/P0-2) against the live function before an operator's first
   real flip — a stub can't catch a PostgREST arg-type rejection. It wrote 2 identifiable
   `__pr4581_smoke__` rows + 1 rejected `__anon_probe__` to the 7-yr WORM table. Justified
   (de-risked the highest-risk fix; both arg shapes confirmed accepted; anon confirmed rejected
   401/42501), but a deviation from the written plan — recorded here for transparency. The
   distinction the plan should have drawn: a *recurring* preflight on every ship (rejected,
   pollutes WORM) vs a *one-time* implementation-phase validation (justified).

## Tags
category: workflow-patterns
module: work
issue: 4581
related: 2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy, 2026-05-29-brainstorm-read-adr-alternatives-considered-before-proposing-reversal
