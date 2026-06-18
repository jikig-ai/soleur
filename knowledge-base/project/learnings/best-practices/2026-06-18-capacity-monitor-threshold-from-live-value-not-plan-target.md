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

## Session Errors

- **`SESSION_POOL_CAP=15` would false-alarm on first run** — Recovery: live-verified the cap (=30) and the session count (=17), set the env to the live value with a revert-linkage comment. Prevention: feeds `hr-observability-as-plan-quality-gate` (client≤server capacity assertion checked against the LIVE server limit at review time). See [[2026-06-18-self-enumerate-cannot-bridge-a-store-switching-cutover]].
- **Plan FR10 AC asserted `grep -c 'steps.probe.outputs.failure_mode' == 0`** — internally contradictory with the plan's own Phase 2 design, which requires the new step to read the upstream output (`PRIOR_FAIL_*`) to honour `inngest_down` precedence. Recovery: corrected the AC to scope the grep to downstream-consumer steps and allow the carry-forward refs. Prevention: a "repoint completeness" AC must exempt the legitimate carry-forward site, or assert per-consumer rather than a blanket `grep -c == 0`.
- **`fd` not found (exit 127)** — one-off; used `git ls-files` / `find` instead.
- **Edits on worktree `.tf`/`.yml` rejected "File has not been read yet"** — one-off; the parent session had Read the bare-repo copies, but the Edit tool tracks per-path, so the worktree copies needed a fresh Read. Prevention: in a worktree, Read the worktree path before editing even if the bare-repo copy was read earlier.

## Tags
category: best-practices
module: observability, inngest, infra
