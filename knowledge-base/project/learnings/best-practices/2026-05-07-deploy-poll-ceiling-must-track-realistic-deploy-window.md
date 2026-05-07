---
module: System
date: 2026-05-07
problem_type: best_practice
component: development_workflow
symptoms:
  - "Verify deploy script completion step timed out at 300s while deploy was healthy"
  - "gh run rerun --failed POSTed a fresh deploy that hit flock lock_contention"
  - "Successful prod deploy reported as failed release workflow (silent-success inverse)"
root_cause: config_error
resolution_type: config_change
severity: medium
tags: [ci, deploy, polling, timeout, observability, web-platform-release, recurrence]
---

# Deploy Poll Ceiling Must Track Realistic Deploy Window (Recurrence Pattern)

## Problem

The `Verify deploy script completion` poll ceiling in `.github/workflows/web-platform-release.yml` outgrew its realistic deploy window for the second time:

- **2026-04-17 (issue #2519, PR #2523):** ceiling raised from 120s to 300s after run 24583922171 timed out during a healthy v0.43.0 deploy.
- **2026-05-06 (issue #3398):** ceiling proved insufficient again — runs 25461549363 (PR #3391, v0.66.10) and 25463360079 (PR-B/#3395, v0.67.0) both ran the full 60 attempts in `running` state while prod was healthy. v0.67.0 was published to ghcr at 22:00:29Z and live on prod by 22:23Z (~22 min wall clock from initial workflow trigger; ~13 min from webhook POST to "container live"). The 300s ceiling was hit at attempt 60/60 ~5 min into the deploy.

The retry pattern made it worse: `gh run rerun --failed` re-POSTs to `/hooks/deploy` while the original `ci-deploy.sh` is still in its critical section. The new POST loses `flock -n`, writes `reason=lock_contention`, and exits non-zero — masking the original deploy's actual fate. This is **not** a lock-release leak (FD-200 advisory flock releases on process exit, full stop); it is the correct loser-behavior of `flock -n` when two webhook invocations overlap.

## Solution

1. Raise `STATUS_POLL_MAX_ATTEMPTS` from 60 to 180 (300s → 900s ceiling). Keep `INTERVAL_S=5` to preserve fail-fast on early non-zero exits (`insufficient_disk_space`, `lock_contention`, `unhandled` trap fire within seconds).
2. Raise `HEALTH_POLL_MAX_ATTEMPTS` from 30 to 90 (300s → 900s ceiling). Required to maintain the `cq-align-ci-poll-windows-with-adjacent-steps` invariant — adjacent-step ceilings in the same workflow must match or one step's tolerance outruns the other's.
3. Add a per-attempt elapsed-time annotation: parse `.start_ts` from the JSON body via `jq -r '.start_ts // 0'`, compute `elapsed=$(($(date +%s) - $STARTED))s`, append to the existing "still running" log line. The `start_ts` field is already populated by `ci-deploy.sh:43` and emitted by `write_state` — no prod-side code change is needed.
4. Add a comment block on the ci-deploy.sh `flock -n 200` block documenting that release is implicit on FD close (no manual `flock -u` path), to forestall future "audit the lock-release path" diagnostic detours.
5. Add a `Rerun Safety` section to `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` explaining why `gh run rerun --failed` is unsafe during an in-flight deploy.

## Key Insight

**Deploy duration grows asymmetrically with each new safety phase** — canary boot + canary probes, sandbox bwrap verify, plugin seed, additional health gates. The poll ceiling that matched the deploy script's 95th-percentile when set will no longer match it 4-6 weeks later if the script grows new phases. The 2026-04-17 prevention checklist ("when introducing a new `*_POLL_*` pair, grep the file") was workflow-side only — it did not cover the **script-side** case where the deploy duration outgrew a stable ceiling.

The right invariant is: **the workflow poll ceiling must be re-measured every time the deploy script grows a phase**, not only when a new poll pair is added.

## Prevention

When a PR adds a new phase to `apps/web-platform/infra/ci-deploy.sh` that runs after `flock -n 200` succeeds (new `docker run`, `docker pull`, container-swap, extended health probe, sandbox verify, plugin seed): after merge, read `elapsed=` from the next 3 successful deploy logs. If any exceeds 75% of `STATUS_POLL_MAX_ATTEMPTS × STATUS_POLL_INTERVAL_S`, bump the ceiling in a follow-up PR (and `HEALTH_POLL_*` symmetrically per the alignment invariant). The elapsed-time annotation is the load-bearing signal — let it fire before another false-negative incident does.

## Observability

The per-attempt elapsed-time annotation added in this PR surfaces ceiling drift in the workflow log directly:

```
Attempt 47/180: ci-deploy.sh still running (reason=running, elapsed=234s)
```

When `elapsed` regularly approaches `MAX_ATTEMPTS × INTERVAL_S` on healthy deploys, that is the signal to bump the ceiling — not after a false-negative incident. This eliminates the need for post-hoc forensics (cross-referencing run timestamps against ghcr publish timestamps and prod container `Up` times to reconstruct the deploy timeline).

## Session Errors

**PreToolUse `security_reminder_hook.py` false-blocked the workflow edit again** — same pattern as the 2026-04-17 learning's session-errors note. Diff was an integer-value bump + comment lines only; no `run:` block changes and no `${{ github.event.* }}` interpolation. Recovery: retry the identical Edit call (second attempt succeeded). The 2026-04-17 learning's prevention recommendation (tighten the hook to only fire on diffs that actually add untrusted-input interpolations) remains unimplemented; recurrence reinforces the case for the fix.

## See Also

- `knowledge-base/project/learnings/best-practices/2026-04-17-align-ci-poll-windows-with-adjacent-steps.md` (the original 120s → 300s bump and its prevention checklist; this learning extends that checklist to the script-side phase-addition case)
- `knowledge-base/project/learnings/2026-03-21-async-webhook-deploy-cloudflare-timeout.md` (deploy-time realistic-window context)
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` (the `Rerun Safety` section added in this PR)
- Issue #2519, PR #2523, Issue #3398
