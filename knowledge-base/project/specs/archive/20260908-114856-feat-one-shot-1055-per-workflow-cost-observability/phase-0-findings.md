# Phase 0 — Precondition readings (dev, read-only, 2026-09-07)

Source: `DATABASE_URL_POOLER` (Doppler `soleur/dev`), session-mode `:5432`, node-pg.
Project ref confirmed dev per `hr-dev-prd-distinct-supabase-projects`.

## 0.1 — Bucket distribution (`active_workflow`)

| bucket | n | cost (USD) |
|---|---:|---:|
| `<null-legacy>` | 158 | 0.158000 |

**Every costed conversation on dev has `active_workflow IS NULL`.** Not a majority — 100%.
Zero rows carry `__unrouted__` or any named workflow.

### 0.1.1 branch — FIRED

The plan's condition was "if `<null-legacy>` + `__unrouted__` hold a **majority** of dev MTD
spend, Phase 3's copy leads with that rather than burying it." The actual share is **100%**,
so the condition holds a fortiori. **Phase 3 copy must lead with the legacy bucket.** A
breakdown UI that presents legacy as a footnote would, on today's data, render a panel whose
every row is the footnote.

### 0.1.2 — Grouped by `domain_leader`

| leader | n | cost |
|---|---:|---:|
| `<null>` | 158 | 0.158000 |

Also 100% null. **This does not settle UC-2** (the CPO-vs-CTO primary-cut disagreement) the
way the task anticipated: the task assumed the two cuts would differ and that the data would
adjudicate. Both cuts are degenerate on dev, so the reading is *no evidence either way* —
record it as unresolved rather than as a win for either side.

## 0.2 — Write-once attribution

Deferred to the Phase 2 code read (no live-DB component). The 100%-null result above makes
the R2 shape question moot for *dev verification* but not for production semantics.

## 0.3 — R4 skew — FIRED, and larger than the plan contemplated

| | n | cost |
|---|---:|---:|
| costed conversations created **before** this month | 158 | 0.158000 |
| costed conversations created **in** this month | **0** | **0** |

**100% skew.** All 158 costed conversations date to 2026-05 (64 users) and 2026-06 (94
users) — three months stale. Every value is exactly `0.001000`, i.e. synthetic seed data,
not organic traffic.

## Consequence: three ACs cannot be satisfied against dev as it stands

This is the finding that changes Phase 1.6, and it is a *vacuity* risk, not a blocker:

- **AC1** requires "a user with ≥ 2 buckets in-month". Dev has **zero** in-month costed rows
  and **zero** non-null buckets. No such user exists.
- **AC4** requires "> `MAX_USAGE_ROWS` costed conversations spanning two months". The two
  months present are both historical; neither is the MTD window the function reads.
- **AC2** (cross-function parity) *would run* — and would pass with both sides returning
  empty. That is precisely the fixture-cardinality trap: a comparison satisfied by a
  degenerate population proves the two functions agree about nothing.

**Required before Phase 1.6:** seed a fixture user with in-month, multi-bucket,
`> MAX_USAGE_ROWS` conversations spanning the month boundary, so AC1/AC2/AC4 assert over a
population that can distinguish a correct aggregate from a broken one. Seeding is
synthesized-only per `cq-test-fixtures-synthesized-only`. Without it these ACs pass
vacuously and the migration ships unverified.

## 1.1 — `sum_user_mtd_cost` live grants (AC5 baseline)

| field | value |
|---|---|
| owner | `postgres` |
| `proacl` | `{postgres=X/postgres,service_role=X/postgres}` |
| `proconfig` | `{search_path=public}` |

Two things settled:

1. **AC5's expected literal** is `{postgres=X/postgres,service_role=X/postgres}` — the owner
   is `postgres`. The plan's placeholder `<owner>` resolves accordingly, and the AC's own
   note is confirmed: the owner retains EXECUTE, so "no other role" would have been false.
2. **The repin is real work.** `proconfig` is `{search_path=public}` — `pg_temp` is genuinely
   absent from the live 027 function, so migration 136's repin fixes an actual gap rather
   than restating one.

## Bucket enum (for the migration's `CASE` arms)

`conversations_active_workflow_chk`:

```
CHECK (active_workflow IS NULL OR active_workflow = ANY (ARRAY[
  '__unrouted__','one-shot','brainstorm','plan','work','review','drain-labeled-backlog'
]))
```

Seven permitted non-null values plus NULL. The migration's `CASE` maps NULL → `legacy` and
`__unrouted__` → `unrouted`, passing the remaining five through unmodified.

> **Corrected 2026-09-08 (#7916 review):** the remaining count is **six**, not five —
> `one-shot`, `brainstorm`, `plan`, `work`, `review`, `drain-labeled-backlog`. Seven non-null
> enum values minus the one sentinel leaves six, and the enum quoted directly above this
> paragraph is the arithmetic. The original sentence is left in place because it is a dated
> reading; only the count was wrong, and the mapping it describes is right. Nothing downstream
> consumed the number — the migration's `CASE` has no per-workflow arm, it passes through
> whatever is not NULL and not the sentinel — so this is a transcription error in the record,
> not a defect in the shipped function.
