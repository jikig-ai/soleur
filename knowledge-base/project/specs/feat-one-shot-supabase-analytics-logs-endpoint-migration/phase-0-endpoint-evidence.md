# Phase 0 — Replacement contract, re-measured live

Measured 2026-08-26 against prd ref `pigsfuxruiopinouvjwy` via the Management API with
`SUPABASE_ACCESS_TOKEN` from Doppler `soleur/prd`. This file is the single source for the
contract; do not restate these numbers elsewhere — cite this file.

## Confirmed from the plan

| Property | Measured |
|---|---|
| Unified stream + `source` column | `select source, count(*) from logs group by source` returns rows keyed by source |
| Old per-source table == new `source` filter | `postgres_logs` 24h: old endpoint `1404`, new endpoint `1404` — exact |
| Timestamp encoding | ISO string `"2026-08-26T14:06:20.544000"` — NOT integer microseconds |
| `count(*)` accepted | Every probe used it; all HTTP 200 with populated `result`. The secondary-source claim that `COUNT(*)` is rejected stays REFUTED. |
| Non-monotonic window (finding C) | 1d `5154` · 7d `5365` · 30d `15444` · 61d `185301` · **70d `3230`** · **80d `0`** — every one HTTP 200 with `error: null` |
| `edge_logs` uninstrumented (finding E) | Absent from the 30d `group by source` result set entirely. Sources present: `supavisor_logs` 13873, `postgres_logs` 1480, `postgrest_logs` 71, `auth_logs` 21. |

`edge_logs` returning zero across the full 30-day live period independently reproduces the
plan's §Retention conclusion: its zero on the recovered 2026-06 tail is finding E, not
evidence of no traffic. The 2026-06-29 determination's `INCONCLUSIVE` verdict stands.

## NEW — finding G, not in the plan's six

**Omitting `iso_timestamp_start` / `iso_timestamp_end` makes the replacement endpoint fail,
and makes the deprecated endpoint lie.**

| Endpoint | `sql` only, no timestamp params | HTTP |
|---|---|---|
| `analytics/endpoints/logs` (new) | `{"result":null,"error":"Backend error! Retry your query. Please contact support if this continues."}` | 200 |
| `analytics/endpoints/logs.all` (old) | `{"result":[{"c":0}],"error":null}` | 200 |

Reproduced twice on the new endpoint minutes apart, so it is deterministic, not the transient
`Backend error!` of finding D. Two consequences:

1. The plan's §Replacement Contract says the parameter set is **identical**. It is identical
   in NAME, but not in OBLIGATION: the timestamp bounds are effectively required on the
   replacement and optional on the deprecated endpoint. The helper must always send both.
2. The old endpoint's timestamp-less answer is a **clean zero with `error: null`** — the exact
   bare-zero shape this whole plan exists to make impossible. It is worth recording that the
   endpoint being retired had one more false-zero mode than the one replacing it.

Finding G is a fail-LOUD on the new endpoint, so it needs no new verdict branch — but the
helper must never construct a request without both bounds, and the guard's fixture set should
carry it so a future refactor that drops a bound is caught.

## Preconditions

- `SUPABASE_ACCESS_TOKEN` resolves from `soleur/prd` (length 44).
- `scripts/test-all.sh --print-suite-globs` does NOT list `scripts/*.test.sh` or
  `tests/scripts/**` — it does list `scripts/lib/*.test.sh`. Both new suites therefore need
  explicit `run_suite` lines; a `scripts/lib/` helper test auto-registers.
- ADR-197 is free across all 60 `origin/*` refs (max observed: ADR-196).
- `#5697` is `OPEN`, `priority/p2-medium`, `type/chore`, `domain/engineering`, `observability`.
