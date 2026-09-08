---
title: "Live cap-RPC atomicity tests: aged-seed daily isolation + audit==K (not N) for throw-on-breach RPCs"
date: 2026-07-03
category: best-practices
module: apps/web-platform/test/server
tags: [byok, postgres, integration-test, cap-rpc, atomicity, for-update, tenant-isolation]
issue: 5938
ref: 5920
---

# Live cap-RPC atomicity tests: aged-seed daily isolation + audit==K

## Problem

Writing a live-DB semantic/atomicity test for a rolling-window cap RPC
(`check_and_record_byok_delegation_use`, mig 084) that enforces BOTH an hourly
and a daily cap. Two non-obvious traps make a naïvely-written test either
impossible to trigger or assert the wrong invariant.

## Key Insight

**1. A daily cap that is checked AFTER the hourly cap can NEVER trip from live
calls alone — you must aged-seed the daily window.**
When the RPC sums an hourly window (`ts > clock_timestamp() - interval '1 hour'`)
BEFORE the daily window (`- interval '24 hours'`), and a table CHECK forces
`hourly_cap ≤ daily_cap`, any single-hour burst that would exceed `daily` first
exceeds `hourly` — so the hourly branch always raises first and the daily branch
is dead code from the test's perspective. Isolate the daily branch by
pre-seeding `audit_byok_use` rows with `ts = now() − 2h`: **inside** the 24h
daily window, **outside** the 1h hourly window. The RPC's cap SUM filters on
`delegation_id` + `ts` only (not `founder_id`/`workspace_id`), so grantor-
attributed seed rows count. `ts` is client-insertable (WORM triggers are
`BEFORE UPDATE/DELETE` only); seed rows must still satisfy NOT NULL columns
(`workspace_id` since mig 059, `founder_id`, `invocation_id` UNIQUE).

**2. For a THROW-on-breach RPC, the double-spend invariant is `audit == K`
(admitted calls), NOT `audit == N` (all calls).** This is the load-bearing
difference from the cap-RPC precedent (`record_byok_use_and_check_cap`, #5920):
that RPC returns a `kill_tripped` signal row and ALWAYS inserts an audit row
first → its concurrency invariant is `N` rows. The delegation RPC `RAISE`s
P0001 on breach with NO preceding INSERT (084:449-454 / 463-468), inserting
only on the pass path — so under N concurrent `FOR UPDATE`-serialized calls,
exactly `K = cap/cost` are admitted and audit rows == K. Copying the precedent's
`N`-row assertion 1:1 would false-fail a correct RPC. **A passing 1:1 mirror is
not proof of correctness; enumerate the new RPC's insert/raise control flow.**

**3. Strict-`>` boundary needs the `== cap` call.** To prove `>` didn't drift to
`>=`, the cumulative-at-exactly-cap call must be asserted to PASS (a `>=`
regression makes it raise). Pick `cap` an exact multiple of per-call `cost`
(assert `cap % cost === 0` in `beforeAll`) so the boundary call lands on a real
cumulative value.

## Solution

`apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts`
— gated by `TENANT_INTEGRATION_TEST=1`, mirrors the #5920 self-diagnosing
pattern (embed live `pg_get_functiondef` body in the failing `expect()` message
via a guarded fetch that never throws / never runs on green). The
`.tenant-isolation.test.ts` suffix is load-bearing for the
`tenant-integration.yml` path filter. Verified live (3/3 pass against dev
Supabase).

## Addendum — 2026-09-07 (#7829, migration 137): Key Insight #2's `audit == K` is superseded by a partition

**The dated text above stands as written and is not edited** — it recorded the
correct invariant for the RPC as it existed on 2026-07-03. What follows is what
changed underneath it.

**What Key Insight #2 said.** *"For a THROW-on-breach RPC, the double-spend
invariant is `audit == K` (admitted calls), NOT `audit == N` (all calls) … The
delegation RPC `RAISE`s P0001 on breach with NO preceding INSERT (084:449-454 /
463-468), inserting only on the pass path — so under N concurrent
`FOR UPDATE`-serialized calls, exactly `K = cap/cost` are admitted and audit rows
== K."*

**Why it no longer holds, and one detail in it that was never quite right.**

`137_byok_cap_breach_audit_row.sql` converts
`check_and_record_byok_delegation_use` from `RETURNS void` to
`RETURNS TABLE(refusal_reason text)`. All five refusal branches now INSERT their
`audit_byok_use` row and **return** the reason; only validation failures (missing
arguments, unresolvable delegation, anonymised row, caller-not-grantee) still
raise. So the count is no longer `K`.

The forcing constraint is the part this file could not have seen from the two cap
branches alone: **an unhandled plpgsql `RAISE EXCEPTION` aborts its own
transaction and discards the INSERT made in that same transaction.** The 084 body
declares no `EXCEPTION WHEN` handler, so the three sibling refusal branches that
*visibly* INSERT before raising (`revoked_post_grace`, `consent_withdrawn`,
`expired`) never persisted a row either. "Inserting only on the pass path" was
therefore true of all five branches, not only of the two cap ones — the
insert/raise control-flow enumeration this file recommends was done, and it read
the source ordering rather than the transaction semantics. That is the sharper
form of its own closing rule: **enumerate the control flow, then ask what the
transaction does to it.**

**The invariant for the post-136 RPC.** `audit == K` becomes a **partition**, and
the total is a derived consequence rather than the load-bearing assertion:

- `rows WHERE attribution_shift_reason IS NULL === K` — the admitted calls,
  summing to `CAP_CENTS`. This is the original no-double-spend / TOCTOU proof and
  it is preserved unchanged.
- `rows WHERE attribution_shift_reason = '<cap reason>' === N − K` — the refusals,
  which now persist.
- `total === N` follows from the two above. Asserting only the total proves
  nothing: it is forced by a fixture of N calls with one row each and holds even
  against an RPC that ignored caps entirely.

**Also superseded: the assertion that a uniform per-call cost discriminates
include-from-exclude.** It does not — every post-breach call breaches either way.
Separating "the refusal row counts toward the window that refused it" from "it is
excluded" needs **heterogeneous** per-call cost (`K−1` calls at the base cost, one
at `2×` that trips and writes its row, then one more at the base cost: included →
refused, excluded → admitted).

Insights **#1** (aged-seed the daily window at `ts = now() − 2h`) and **#3**
(the strict-`>` boundary needs the exactly-`== cap` call to PASS) are unaffected
by 137 and still apply verbatim.

See [ADR-208](../../../engineering/architecture/decisions/ADR-208-a-delegation-refusal-returns-its-reason-because-a-raise-discards-the-audit-row.md)
for the decision and the rejected alternatives.

## Session Errors

- **CWD drift in worktree pipeline** — `cd apps/web-platform` / `./node_modules/.bin/vitest` / `git add apps/web-platform/...` variously failed because the Bash tool's CWD drifted between worktree-root and `apps/web-platform`. **Recovery:** prefix `cd <abs> &&` or use repo-root-relative paths. **Prevention:** already covered by work SKILL.md's `cd <worktree-abs> && <cmd>` rule — apply it to EVERY file/test/git command, not just test runs.
- **Background trailing-echo exit masking** — a backgrounded `tsc … > log; echo "TSC_EXIT=$?"` reported the notification "exit code 0" (the echo's exit) while `tsc` itself exited 127. **Recovery:** read the redirected log for the real `*_EXIT=` line. **Prevention:** already covered — never trust the bg completion notification's exit for a command whose real status is in a redirected log; grep the log's own summary/exit line.

## Tags
category: best-practices
module: apps/web-platform/test/server
