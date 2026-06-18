# Learning: a capacity-monitor threshold must be set from the LIVE-verified value, not the plan's post-change target

## Problem

#5562 added a leading-indicator pool-utilization probe to `scheduled-inngest-health.yml`: it reads `pg_stat_activity` on the inngest Supabase project and alerts at ~70% of the session-pool cap. The plan hardcoded `SESSION_POOL_CAP: '15'` because task (c) of the same plan *decided to revert* the pool's live `default_pool_size` from the #5558 stopgap 30 back to the project default 15.

But the revert is a deferred operator action (PM2 — explicitly NOT done in this PR). So at merge time the LIVE cap is still 30. A live verification during review (`GET /v1/projects/<ref>/config/database/pgbouncer` → `{"default_pool_size":30}`) plus the actual session count (`select state,count(*) from pg_stat_activity` → total 17) showed that with `SESSION_POOL_CAP=15`:

- `17 >= 15` → the probe would have classified the **currently healthy** pool as `pool_exhausted` on its very first scheduled run, filing a P1 `[ci/inngest-pool]` issue and a Sentry `error` — a guaranteed false alarm.

The monitor was tuned to the *target* (post-revert) state, not the *current* (pre-revert) state, and the two were transposed by a deferred follow-up.

## Solution

Set the threshold from the LIVE-verified value, with a comment tying it to the deferred change:

```yaml
# Verified live 2026-06-18 via the Management API: currently 30 — the #5558
# stopgap raise that the #5562 decision will revert to 15. Drop to 15 once
# that revert lands; a stale 15 here while the live cap is 30 would over-alert.
SESSION_POOL_CAP: '30'
```

Verify the live value yourself (`hr-no-dashboard-eyeball-pull-data-yourself`) rather than trusting the plan's narrative — the same Management-API call that the probe uses returns the real config.

## Key Insight

When a plan **defers** a state change (a config revert, a flag flip, a capacity resize) AND ships a **monitor whose threshold depends on that state**, the monitor must reflect the state that is live AT MERGE, not the post-change target. The deferral creates a window where target ≠ live; a threshold set to the target mis-fires for the entire window. The general rule for any client≤server capacity monitor: the server-side limit it compares against is a **live fact to be verified**, not a plan-quoted constant — plan-quoted infra values are preconditions to verify, never facts (this is the capacity-monitor instance of that rule). This is exactly the class `hr-observability-as-plan-quality-gate` should require: a NEW external stateful dependency's monitor must assert the CLIENT threshold ≤ the LIVE SERVER limit, checked at review time, not plan time.

Corollary surfaced the same session: the multi-agent review's git-history + code-quality agents both flagged the `default_pool_size=30` claim as "uncorroborated in-repo" — correctly, because it was an out-of-band Management-API mutation that lives in the project config, not any committed file. The resolution was not to reframe the claim speculatively but to **pull the live value and cite it** — turning an unverifiable narrative into evidence-backed IaC documentation.

## AMENDMENT (#5563 — post-deploy live verification corrected the metric)

The "set the threshold from the live cap" framing above is **necessary but not sufficient**, and as originally applied it led to the WRONG cap. Running the shipped probe against prod revealed the real lesson:

**Set the threshold from the cap that bounds the THING YOU ARE PROTECTING, measured by a count that ISOLATES that thing — not a convenient nearby number measured by a convenient nearby query.** The first probe counted *total* `pg_stat_activity` against the pooler's `default_pool_size` (30). But:
1. The COUNT was wrong: total `pg_stat_activity` is dominated by the monitored service's *infrastructure* (Supavisor pooler warm connections, PostgREST, pg_net, pg_cron, postgres_exporter, walsenders, and the probe's own query), not by inngest. Baseline alone (17→43) crossed the 70%-of-30 threshold → guaranteed false positives.
2. The CAP was wrong: `default_pool_size` is the pooler's server-side fan-in, not the ceiling on the thing being protected. The actual ceiling on *inngest* sessions is inngest's own client cap (`--postgres-max-open-conns 10`).

Corrected metric (CTO-ruled): count ONLY inngest-attributable client backends (role `postgres`, minus the pooler's `Supavisor` warm connections and the probe's own session, via `query not ilike '%pg_stat_activity%'`) against the CLIENT cap (10) at an 80% threshold — and log the full per-backend breakdown each run so the discriminator stays auditable. This also DECOUPLED the probe from the deferred `default_pool_size` revert entirely (the original "drop SESSION_POOL_CAP to 15 when the revert lands" lockstep was itself a symptom of binding to the wrong cap).

**The deeper rule:** a capacity monitor over a SHARED substrate (a pooler/DB/cache used by many tenants + infra) must filter the count to the subject before comparing to a cap, and the cap must be the subject's own limit — or it measures ambient noise. Verify BOTH against live data (`hr-no-dashboard-eyeball-pull-data-yourself`): run the exact query the probe will run and read the actual composition before trusting the threshold. Post-deploy functional verification (running the real workflow, not just static review) is what surfaced this — multi-agent static review approved the (executable-but-wrong) metric.

## Session Errors

- **`SESSION_POOL_CAP=15` would false-alarm on first run** — Recovery: live-verified the cap (=30) and the session count (=17), set the env to the live value with a revert-linkage comment. Prevention: feeds `hr-observability-as-plan-quality-gate` (client≤server capacity assertion checked against the LIVE server limit at review time). See [[2026-06-18-self-enumerate-cannot-bridge-a-store-switching-cutover]].
- **Plan FR10 AC asserted `grep -c 'steps.probe.outputs.failure_mode' == 0`** — internally contradictory with the plan's own Phase 2 design, which requires the new step to read the upstream output (`PRIOR_FAIL_*`) to honour `inngest_down` precedence. Recovery: corrected the AC to scope the grep to downstream-consumer steps and allow the carry-forward refs. Prevention: a "repoint completeness" AC must exempt the legitimate carry-forward site, or assert per-consumer rather than a blanket `grep -c == 0`.
- **P1 (post-deploy): `pool_exhausted` mis-routed to `[ci/inngest-down]`** — the controlled `failure_mode` enum was passed through `strip_log_injection`, whose `tr -d '\r\n\f\v\x7f\x85'` deletes the LITERAL chars `x,7,f,8,5` (GNU `tr` does not parse `\xNN` as hex), turning `pool_exhausted`→`pool_ehausted` → failed the downstream `case` match → fell through to the down class (and corrupted body digits). Recovery: emit `failure_mode` RAW (it is a controlled enum, never untrusted; only the body/breakdown-bearing `fail_detail` needs sanitizing). Prevention: NEVER route a controlled enum through a lossy sanitizer; sanitize only genuinely-untrusted strings. The shared `strip_log_injection` `\x7f\x85` bug also affects `scheduled-realtime-probe.yml` — flagged for a separate fix (it strips x/7/f/8/5 instead of DEL/NEL).
- **P1 (post-deploy): metric false-fired `pool_exhausted` on infra baseline (43 sessions)** — see the AMENDMENT above. Recovery: CTO-ruled redesign to count inngest-attributable backends vs the client cap (10). Prevention: filter the count to the subject + use the subject's own cap; verify composition against live data.
- **`fd` not found (exit 127)** — one-off; used `git ls-files` / `find` instead.
- **Edits on worktree `.tf`/`.yml` rejected "File has not been read yet"** — one-off; the parent session had Read the bare-repo copies, but the Edit tool tracks per-path, so the worktree copies needed a fresh Read. Prevention: in a worktree, Read the worktree path before editing even if the bare-repo copy was read earlier.

## Tags
category: best-practices
module: observability, inngest, infra
