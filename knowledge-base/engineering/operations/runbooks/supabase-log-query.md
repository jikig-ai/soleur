---
category: observability
tags: [supabase, logs, clickhouse, management-api, coverage-verdict, dsar, gdpr]
date: 2026-08-26
# Deliberately EMPTY, not omitted. incident/SKILL.md Phase 3 routes by symptom over this key;
# this runbook documents a TOOL rather than an incident procedure, so it should never be
# offered as a symptom match. The investigation runbook that USES this tool
# (breach-access-log-investigation.md) carries the real triggers. An absent block and an
# empty one look the same to a reader and different to a reviewer asking "was this
# considered?" -- hence the empty list plus this note.
triggers: []
---

# Runbook: Querying Supabase platform logs (postgres / auth / postgrest / supavisor)

**TL;DR:** Use [`scripts/supabase-logs-query.sh`](../../../../scripts/supabase-logs-query.sh) under
`doppler run -p soleur -c prd`. It queries the Supabase Management API's unified analytics
endpoint in **ClickHouse** SQL and always prints a coverage verdict alongside the row count.

```bash
# --ref IS REQUIRED. There is no default, deliberately: the ONE failure no other check in
# this tool catches is a format-valid ref pointing at the wrong project, which returns real
# rows and a clean verdict over data that was never in scope. Naming it is the assertion.
#
#   ifsccnjhymdmidffkzhl   soleur-web-platform   the APPLICATION project — user data, DSAR,
#                                          PostgREST/auth access questions
#   pigsfuxruiopinouvjwy   soleur-inngest-prd    the Inngest backing project — subject of the
#                                          2026-06-29 RLS determination

# Last 24h of Postgres logs on the application project:
doppler run -p soleur -c prd -- \
  scripts/supabase-logs-query.sh --ref ifsccnjhymdmidffkzhl --source postgres_logs --since 24h

# Two sources, machine-readable (one JSON object, never a bare array):
doppler run -p soleur -c prd -- \
  scripts/supabase-logs-query.sh --ref ifsccnjhymdmidffkzhl \
    --source auth_logs --source postgrest_logs --since 6h --json
```

`--since` / `--until` / `--limit` deliberately match
[`betterstack-query.sh`](../../../../scripts/betterstack-query.sh), so the two log surfaces are
driven the same way. `--help` documents every flag and the exit-code table.

## The one thing this runbook exists to protect

**A zero row count is never emitted without a coverage verdict.** Count, resolved project ref +
project name, the window actually covered, and per-source instrumentation status are one
inseparable block — not a number with a verdict printed somewhere nearby — because the consumer
is usually an agent transcribing a figure into a determination or an incident record. `--json`
emits the same block as a single object for exactly that reason: a machine path that dropped the
verdict would make "no bare zero" true only for a human reader.

There are exactly **two** top-line verdict tokens: `COVERED` and `INCONCLUSIVE`. Everything
else — `UNINSTRUMENTED`, `PARTIAL_COVERAGE`, `ZERO_SOURCE_COVERAGE_UNESTABLISHED`,
`WINDOW_PREDATES_RETENTION` — is a *reason* attached to one of them, never a third token to
scan for. The token is derived from the reason and never set independently, because two
independently-set fields drift and the drift that matters (reason says UNINSTRUMENTED, token
says COVERED) is the exact false all-clear.

## Exit codes

| Code | Verdict | What it means | Next action |
|---|---|---|---|
| `0` | `COVERED` | The requested window was fully covered and every named source is instrumented. The count is usable. | Use the number. |
| `1` | transient | A 5xx that survived a re-issue at half width, or a network failure. | Retry. |
| `2` | auth / config | Creds absent, malformed or missing `--ref`, a dialect error, an unparseable response. | Fix the invocation — see below. |
| `3` | `INCONCLUSIVE` | The window was not fully covered; **or** an unknown `--source` (it matched nothing and would otherwise have returned a clean zero); **or** a named source is uninstrumented over the pinned span; **or** a named source returned no row in the window, so nothing establishes it was recording during it. | **Do not report the count as an absence.** Read the reason line. |
| `64` | usage | An unknown flag. No evidence block is emitted on this path. | Fix the invocation. |

Exit **3** is the load-bearing one: an `INCONCLUSIVE` that exited 0 would read as success to
`if helper; then …`, to `set -e`, and to any agent reading `$?` — the false all-clear this whole
tool exists to make impossible. Note the deliberate divergence from `betterstack-query.sh`, which
uses exit **3** for *missing creds*; the helper's `--help` states this rather than leaving it to
be discovered.

## A "no creds" / transient error is NOT "no access"

Like `betterstack-query.sh`, this script does **not** read Doppler itself — `SUPABASE_ACCESS_TOKEN`
must be **injected**. Run it in a bare shell and it exits 2. That does not mean the session lacks
Supabase access; it means the call was not wrapped. The fix is always the same:

```bash
doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh <args>
```

Do NOT conclude "I can't verify from here" and stop — a degraded probe output is *inconclusive*,
never proof of a capability gap (`hr-verify-repo-capability-claim-before-assert`,
`hr-no-dashboard-eyeball-pull-data-yourself`).

## Do not hand-write the query

The helper builds the SQL. If it reports a dialect error, the helper is **stale** — file an issue.
Reaching for `curl` against the endpoint reintroduces precisely the failure class the helper
replaced: the old per-source endpoint answered a timestamp-less query with a clean
`[{"c":0}]` and `error: null`, and the replacement endpoint accepts several inputs that return
HTTP 200 with a wrong or truncated answer. The measured behaviour of both endpoints — the source
enumeration, the non-monotonic window cap, the mandatory timestamp bounds, and the
`edge_logs` instrumentation gap — is recorded in
[`supabase-management-api-log-contract.md`](../../../project/specs/feat-one-shot-supabase-analytics-logs-endpoint-migration/supabase-management-api-log-contract.md);
cite that file rather than re-measuring or restating its numbers here.

## When a source comes back uninstrumented

The helper has already computed per-source counts over the pinned instrumentation span, so it
names the instrumented alternatives in the same block. Take the routing it offers: choosing a
source that has never emitted on this project is how an access-log question gets answered with a
zero that means nothing. `edge_logs` is the known case.

## Deprecated-endpoint guard (advisory)

`scripts/lint-supabase-deprecated-endpoints.sh` censuses references to the retired per-source
endpoint. It is **advisory, not merge-blocking** — `lint-bot-statuses` is absent from
`scripts/required-checks.txt` and from the branch ruleset, so a PR can merge with it red. Treat a
red guard as a finding to read, never as a gate that will stop the merge for you.

## Related

- [`betterstack-log-query.md`](./betterstack-log-query.md) — the app's own pino stream. Same
  invocation shape, different warehouse, and the same class of trap (its `remote()` hot window
  silently answers a wide `--since` with a much shorter span).
- [`breach-access-log-investigation.md`](./breach-access-log-investigation.md) — the procedure
  that consumes this helper when the question is whether exposed credentials were used.
