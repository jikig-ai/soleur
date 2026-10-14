# Migration 136 — live acceptance evidence (dev, 2026-09-07)

Applied to **dev** (`hr-dev-prd-distinct-supabase-projects`) with the migration body and its
`_schema_migrations` tracking row (`content_sha ee5ef2f3…`) in **one transaction**, mirroring
`apps/web-platform/scripts/run-migrations.sh`. A bare `BEGIN; <migration>; COMMIT;` would have
left a phantom-applied state where the schema reflects the migration but the tracker does not.

## The fixture problem, and how it was solved

Phase 0 established that dev has **zero in-month costed conversations** — every one of the 158
predates the current month, and all have `active_workflow IS NULL`. Run against dev as it
stands, AC1 and AC2 would have compared **empty to empty** and reported `true`. That is a
vacuous pass, and it is exactly the failure mode these ACs exist to prevent.

So the fixture is **synthesized inside the verification transaction and rolled back**
(`cq-test-fixtures-synthesized-only`). This also satisfies AC2's own requirement that both
calls share one snapshot, and `cq-ac-must-not-depend-on-concurrent-sessions`: nothing
persists, and no concurrent writer can land between the two reads.

Fixture: 60 in-month conversations cycling 7 buckets (`NULL`, `__unrouted__`, and five of the
six named workflows) — above `MAX_USAGE_ROWS` (50) — **plus** 5 prior-month conversations at
$99.00 each, which exist solely to prove the window predicate excludes them.

> **Corrected 2026-09-08 (#7916 review):** this said "all 7 buckets", which over-claims. There
> are **eight** possible buckets (NULL + seven enum values); the fixture exercises seven and
> omits `drain-labeled-backlog`, which is why it is absent from the AC4 table below. The AC
> being evidenced is that ROLLUP emits one row per present bucket plus a super-aggregate — a
> property of the GROUP BY, indifferent to WHICH buckets are present — so seven distinct
> buckets discharge it and the eighth would add no discriminating power. Recorded because
> "all" invites a reader to treat the table as an enum-coverage check, which it is not; the
> enum's completeness is pinned separately by the migration-shape test's synthetic-key
> collision assertion against migration 032.

## AC5 — live grants

| proname | owner | proacl | proconfig |
|---|---|---|---|
| `sum_user_mtd_cost` | postgres | `{postgres=X/postgres,service_role=X/postgres}` | `{"search_path=public, pg_temp"}` |
| `sum_user_mtd_cost_by_workflow` | postgres | `{postgres=X/postgres,service_role=X/postgres}` | `{"search_path=public, pg_temp"}` |

**PASS.** Exactly the shape the AC predicted: EXECUTE for `service_role` and the owner, and
**no entry for `PUBLIC`, `anon`, or `authenticated`**. The AC's own caveat is confirmed — the
owner always retains EXECUTE, so the earlier "and no other role" draft would have been
unpassable.

`proconfig` also confirms the inline repin landed on the **live** 027 function: it read
`{search_path=public}` before this migration (recorded in `phase-0-findings.md`) and reads
`public, pg_temp` now.

## AC4 — breakdown over a >`MAX_USAGE_ROWS`, two-month fixture

| bucket | total | n | is_total |
|---|---:|---:|---|
| *(null)* | 0.297000 | 60 | **true** |
| brainstorm | 0.045000 | 9 | false |
| one-shot | 0.045000 | 9 | false |
| plan | 0.045000 | 9 | false |
| unrouted | 0.045000 | 9 | false |
| legacy | 0.044000 | 8 | false |
| work | 0.037000 | 8 | false |
| review | 0.036000 | 8 | false |

**PASS.** All 7 buckets plus the super-aggregate. The emitted ordering is the one the
`ORDER BY` specifies: total row first (`GROUPING(b.bucket) DESC`), then total descending, then
bucket name ascending as the tiebreak — visible in the four-way 0.045000 tie resolving
alphabetically. `bucket` is `NULL` on the super-aggregate row (ROLLUP's own output), which is
unambiguous only because the `CASE` can never return NULL; `is_total` is returned as the
explicit signal regardless, so the loader never has to rely on that reasoning.

## AC1 — the sum invariant

| sum_buckets | total_row | totals_match | sum_n | total_n | counts_match |
|---|---|---|---|---|---|
| 0.297000 | 0.297000 | **true** | 60 | 60 | **true** |

**PASS.** Asserted in SQL on `NUMERIC` — not a JS float comparison, no epsilon tolerance
(CFO F3/F4).

## AC2 — cross-function parity, one snapshot

| rollup_total | legacy_total | parity | n_parity |
|---|---|---|---|
| 0.297000 | 0.297000 | **true** | **true** |

**PASS.** The `is_total` row equals `sum_user_mtd_cost(uid, since)` for the same arguments,
both inside the same transaction.

## Window non-vacuity — the check that makes the above mean something

| prior_month_rows | prior_month_cost |
|---|---:|
| 5 | 495.000000 |

**This is the load-bearing control.** Five prior-month conversations totalling **$495.00**
exist for the same user throughout the run above. The MTD total reads **0.297000**, not
495.297000 — so the `created_at >= since` predicate demonstrably excludes them.

Without this row the whole table above is consistent with a function that ignores `since`
entirely, or with one that returns nothing at all. A sum invariant over an empty set is `true`
and proves nothing; this is what distinguishes a measurement from a tautology.

## Not covered here

- **AC3** (exactly one statement) is a file-parse assertion in
  `test/supabase-migrations/136-workflow-cost-rollup.test.ts`, mutation-proven 14/14. Testing
  it live by interleaving a real `increment_conversation_cost` would violate
  `cq-ac-must-not-depend-on-concurrent-sessions`.
- **AC5b** (tenant-JWT `42501` denial) is a committed regression test in
  `test/server/api-usage.tenant-isolation.test.ts`, not a transcript.

---

## Phase 4 — Verification (2026-09-08)

### 4.1 / 4.2 — typecheck and suites

- `./node_modules/.bin/tsc --noEmit` → **rc=0** (pinned binary, not `npx`).
- `./node_modules/.bin/vitest run` over all 8 touched suites → **rc=0, 143 passed**:
  `136-workflow-cost-rollup`, `migration-rpc-grants`, `workflow-copy`,
  `api-usage-workflow-rollup`, `api-usage`, `api-usage-parity`, `api-usage-section`,
  `api-usage-breakdown`.

### 4.3 — full battery: NOT run, and why

`bash scripts/test-all.sh --capacity` reported **`CAPACITY_CONTENDED`**:
`measured_runs=2 measured_suites=1`, `tmp_avail_mb=1243` against `tmp_floor_mb=1024`. Two
sibling full-gate runs were in flight from *other* worktrees
(`feat-one-shot-7909-…`, `feat-one-shot-7867-…`), and this box had already OOM-killed three
background tasks earlier in the session.

Launching a third battery would have produced a result not attributable to this diff. Rather
than run it and reason around the noise, the **specific value 4.3 offers — orphan-suite
discovery** — was obtained directly:

```
git grep -l "<symbol>" -- '*.test.ts' '*.test.tsx' '*.test.sh' 'tests/'
```

over every symbol this branch changed (`sum_user_mtd_cost_by_workflow`, `sum_user_mtd_cost`,
`LEGACY_SEARCH_PATH_NO_PG_TEMP`, `byWorkflow`, `workflow-copy`, `workflowLabel`,
`136_workflow_cost_rollup`). **Every suite returned is in the 8 already run — no orphans.**

The merge gate is unaffected: CI's required `test` context runs the same shards on the PR head
independently of anything done locally (ADR-183).

### 4.4 — `c4-count-parity`

`bash plugins/soleur/test/c4-count-parity.test.sh` → **rc=0, Passed: 10, Failed: 0**.

### 4.5 — AC walk

| AC | Check | Result |
|---|---|---|
| AC15 | exactly one `'__unrouted__'` literal in the function body | **1** |
| — | sentinel containment: `__unrouted__` in *executable* code across `workflow-copy.ts`, `api-usage-section.tsx`, `api-usage.ts` | **0 / 0 / 0** |
| AC19 | ADR exists, anchored on filename | `ADR-209-conversation-grain-cost-attribution.md` |
| — | `op: "mtd-by-workflow"` is unique | **1** |

The sentinel-containment check is worth a note. A bare `git grep '__unrouted__'` returns two
hits in `workflow-copy.ts` — both in **comments** explaining the normalisation. That is the
comment-prose false-match class (`cq-assert-anchor-not-bare-token`): the bare grep cannot
distinguish an explanation of the invariant from a violation of it. The check above strips
comments first, and the type itself (`WorkflowBucket = WorkflowName | "unrouted" | "legacy"`)
admits only normalised keys.

### AC5b — proven non-vacuous against dev

The tenant-JWT denial suite is opt-in (`TENANT_INTEGRATION_TEST=1`) and passes 5/5 against
dev. A denial test that would also pass against a *widened* grant proves nothing, so it was
mutation-tested on live dev:

| step | `proacl` | suite |
|---|---|---|
| baseline | `{postgres=X/postgres,service_role=X/postgres}` | 5 passed |
| `GRANT EXECUTE … TO authenticated` — **mutation confirmed landed** | `…,authenticated=X/postgres` | **1 failed / 4 passed** (`expected null not to be null`) |
| `REVOKE EXECUTE … FROM authenticated` | `{postgres=X/postgres,service_role=X/postgres}` | 5 passed |

Dev was returned to the exact AC5 literal and re-verified green.

**A methodology note, because the first attempt produced a false result.** The initial run
reported `SURVIVED` — which would have read as "AC5b is vacuous". It was not: `/tmp` had been
swept between turns, so the helper script no longer existed, the `GRANT` never executed, and
the suite re-measured the unmutated baseline. A mutation that does not land reports the
baseline, and that is indistinguishable from a pass. The rerun above asserts the mutation
landed (by reading `proacl` back and checking for `authenticated=X`) **before** trusting any
verdict, and aborts rather than reporting if it did not.

## Addendum — 2026-09-08, post-review re-apply

Review found that 136 re-created `sum_user_mtd_cost` with **no REVOKE trio**
(security-sentinel F1, data-integrity P3 — two agents, one gap). The REVOKEs
were added and the migration re-applied to dev inside one transaction, with
`_schema_migrations.content_sha` reconciled in the same statement:

| | value |
|---|---|
| sha at first apply | `ee5ef2f34798ba80d36bedea4f1ff4226d5d001e` |
| sha after the fix | `c60357e0a250af7e00f1df11a74024c6afab8994` |
| tracked sha now | `c60357e0a250af7e00f1df11a74024c6afab8994` |

Post-re-apply live state, both functions:

| proname | proacl | proconfig |
|---|---|---|
| `sum_user_mtd_cost` | `{postgres=X/postgres,service_role=X/postgres}` | `{"search_path=public, pg_temp"}` |
| `sum_user_mtd_cost_by_workflow` | `{postgres=X/postgres,service_role=X/postgres}` | `{"search_path=public, pg_temp"}` |

AC5b re-run green after the re-apply.

**Why the original live check could not have caught this.** The `proacl` read is
only takeable on a database where 027 has already applied — which is precisely
the state in which a missing REVOKE on a `CREATE OR REPLACE` is invisible, since
REPLACE preserves the existing ACL. The defect is reachable only on a *first*
create (a `db reset` against a squashed baseline postdating 027, a fresh project
bootstrapped from `db diff`, or a `DROP FUNCTION` during incident recovery
followed by forward-only replay), where Postgres default-grants EXECUTE to
PUBLIC. Live verification and static assertion cover different states here, and
the static one was the load-bearing half.
