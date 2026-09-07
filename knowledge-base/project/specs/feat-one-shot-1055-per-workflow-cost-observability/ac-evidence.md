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

Fixture: 60 in-month conversations cycling all 7 buckets (`NULL`, `__unrouted__`, and the five
named workflows) — above `MAX_USAGE_ROWS` (50) — **plus** 5 prior-month conversations at
$99.00 each, which exist solely to prove the window predicate excludes them.

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
