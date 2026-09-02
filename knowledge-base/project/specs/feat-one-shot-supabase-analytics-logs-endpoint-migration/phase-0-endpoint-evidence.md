# Phase 0 — Replacement contract, re-measured live

> **DO NOT ARCHIVE THIS FILE WITHOUT REPOINTING ITS CITATIONS.** It sits under
> `specs/feat-*/`, which is by convention ephemeral and archived at feature close — but 20
> files cite it as the canonical contract, including two PRODUCTION scripts
> (`scripts/supabase-logs-query.sh`, `scripts/lint-supabase-deprecated-endpoints.sh`), the
> 2026-06-29 GDPR determination's addendum, ADR-197, both Supabase log runbooks, and ten test
> fixtures. Its siblings in this directory were archived at feature close; this one was
> deliberately left, because moving it breaks all 20.
>
> A production script citing an ephemeral spec path is a latent breakage, so the durable fix is
> to promote this file to an engineering reference path and repoint every citation in one
> commit — tracked, not done here, because a 20-file sweep late in an already-large PR is the
> blanket-rewrite hazard this repo has been bitten by before.


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

**Omitting `iso_timestamp_start` / `iso_timestamp_end` makes the replacement endpoint fail —
and the vendor's own spec says it should not.**

| Endpoint | `sql` only, no timestamp params | HTTP |
|---|---|---|
| `analytics/endpoints/logs` (new) | `{"result":null,"error":"Backend error! Retry your query. Please contact support if this continues."}` | 200 |
| `analytics/endpoints/logs.all` (old) | `{"result":[{"c":0}],"error":null}` | 200 |

Both endpoints' OpenAPI descriptions carry the identical sentence: *"If both are not provided,
only the last 1 minute of logs will be queried."* The deprecated endpoint honours it — its
`{"c":0}` is a real (empty) one-minute window. The replacement does not: it errors instead,
reproducibly, minutes apart, so this is not the transient `Backend error!` of finding D.

Two consequences:

1. The plan's §Replacement Contract says the parameter set is **identical**. It is identical in
   NAME and in DOCUMENTED semantics, but not in BEHAVIOUR: the timestamp bounds are effectively
   required on the replacement. The helper must always send both.
2. The failure is LOUD, so it needs no new verdict branch — but the helper must never construct
   a request without both bounds, and a fixture should pin it so a future refactor that drops a
   bound is caught rather than being read as a dialect error.

## The documented 24-hour cap is NOT enforced

Both descriptions state: *"The timestamp range must be no more than 24 hours ... If the range is
more than 24 hours, a validation error will be thrown."*

Measured on the replacement: a **25-hour** range returns HTTP 200 with `{"c":5146}`, and a
**61-day** range returns HTTP 200 with `{"c":185301}`. No validation error at any width. The
real cap is the undocumented, non-monotonic truncation in the table above, sitting somewhere
between 61 and 70 days — a boundary that can move.

This matters for the helper's design: the vendor's documented guard cannot be relied on to
reject a too-wide window, which is precisely why the monotonicity probe and the coverage verdict
have to exist client-side.

## Five paths are deprecated, not two

`jq '.paths | to_entries[] | ... select(.value.deprecated == true)'` over the live spec:

| Path | In-repo non-doc callers |
|---|---|
| `GET /v1/projects/{ref}/analytics/endpoints/logs.all` | 0 — removal announced 2026-09-23 |
| `GET /v1/projects/{ref}/advisors/security` | **2 live callers** — `apply-inngest-rls.yml`, `scripts/supabase-advisor-scan.sh`. The guard's census counts **3** call sites: it also enumerates a mutation stub in `tests/scripts/test-supabase-advisor-scan.sh` that runs under a stubbed `curl` and never reaches the network. Both figures are correct for what they count — live callers vs. deprecated-path literals the extractor can see — and they are reconciled here because two documents in one PR asserting 2 and 3 for the same population is the drift this file exists to prevent. |
| `GET /v1/projects/{ref}/advisors/performance` | 0 |
| `GET /v1/projects/{ref}/database/context` | 0 |
| `POST /v1/projects/{ref}/functions` | 0 |

The plan enumerated the first three. `database/context` and `POST .../functions` are also
deprecated and also have zero callers, so they change no decision here — but the denylist is
therefore a hand-maintained subset of a set the vendor publishes, which is the argument for
PR-C's spec-diff poller deriving it rather than a human curating it.

None of the five carries a sunset date in the spec; `logs.all`'s 2026-09-23 removal date exists
only in the vendor's email. So a spec diff detects DEPRECATION but cannot detect an announced
REMOVAL — the poller must not be described as covering the deadline case.

## The vendor cannot attribute the traffic — the sweep's open item is not API-closable

The plan's §Second-Caller Sweep prescribes, before 2026-09-23: *"pull Supabase's own Management
API request log for `logs.all` over the last 30 days and attribute the traffic."*

**There is no such endpoint.** The live spec contains zero paths matching `audit`, and the two
usage endpoints are about the PROJECT's API traffic (PostgREST / auth / storage), not Management
API calls by path — `usage.api-counts?interval=1day` returns `{"result":[],"error":null}`.

So that action is not achievable with the PAT. Attribution requires a vendor support ticket, or
it is accepted as unknown with the blast radius named. Recorded so the open item is not carried
forward as though a probe would discharge it.

## Preconditions

- `SUPABASE_ACCESS_TOKEN` resolves from `soleur/prd` (length 44).
- `scripts/test-all.sh --print-suite-globs` does NOT list `scripts/*.test.sh` or
  `tests/scripts/**` — it does list `scripts/lib/*.test.sh`. Both new suites therefore need
  explicit `run_suite` lines; a `scripts/lib/` helper test auto-registers.
- ADR-197 is free across all 60 `origin/*` refs (max observed: ADR-196).
- `#5697` is `OPEN`, `priority/p2-medium`, `type/chore`, `domain/engineering`, `observability`.
