---
module: System
date: 2026-04-17
problem_type: best_practice
component: development_workflow
symptoms:
  - "Verify deploy script completion step timed out at 120s while deploy was healthy"
  - "gh run rerun --failed POSTed a second deploy that hit flock lock_contention"
root_cause: config_error
resolution_type: config_change
severity: medium
tags: [ci, deploy, polling, timeout, web-platform-release, alignment]
---

# Align CI Poll Windows with Adjacent Steps in the Same Workflow

## Problem

The `Verify deploy script completion` step in `.github/workflows/web-platform-release.yml`
used `STATUS_POLL_MAX_ATTEMPTS=24` × `STATUS_POLL_INTERVAL_S=5` = 120s. The adjacent
downstream step `Verify deploy health and version` used `HEALTH_POLL_MAX_ATTEMPTS=30` ×
`HEALTH_POLL_INTERVAL_S=10` = 300s.

The 120s ceiling was tighter than the ci-deploy.sh realistic worst case (prune + pull +
canary + health + promote routinely hits 120-240s per the 2026-03-21 async-webhook
learning). Run 24583922171 produced a false-negative timeout during a healthy v0.43.0
deploy. The retry (`gh run rerun --failed`) POSTed a second deploy to /hooks/deploy,
which failed `flock -n` in `ci-deploy.sh` and wrote `lock_contention` — a cascading
false negative driven entirely by the first false negative.

## Solution

Bumped `STATUS_POLL_MAX_ATTEMPTS` from 24 to 60 (keeping INTERVAL_S=5 → 300s total),
aligning with the sibling `HEALTH_POLL_*` ceiling. Kept INTERVAL_S=5 to preserve
fail-fast detection of early non-zero exits (`insufficient_disk_space`,
`lock_contention`, `unhandled` EXIT trap) that `ci-deploy.sh` writes within seconds.

## Key Insight

When multiple poll loops exist in the same workflow file, they should share the same
**ceiling** (`MAX_ATTEMPTS × INTERVAL_S`) so one step's false-negative timeout cannot
outrun what the next step already tolerates. Interval asymmetry is fine — the tighter
interval goes on the step that benefits from fail-fast on early error states (here, the
local webhook status endpoint that can report `insufficient_disk_space` in < 5s). The
looser interval goes on the step polling an external HTTPS endpoint where a 10s cadence
is cheaper.

**Checklist for future CI poll bounds:**

1. Identify all poll loops in the workflow file (`grep -n "MAX_ATTEMPTS\|_POLL_" .github/workflows/<file>.yml`).
2. Compute each loop's ceiling.
3. If ceilings differ across loops that share a cause chain (e.g., deploy → verify
   completion → verify health), align on the longer ceiling.
4. Interval choice is independent — pick the shortest interval that still gives the
   endpoint breathing room, so early-exit states surface fast.

## Prevention

- When introducing a new `*_POLL_*` pair in a CI workflow, grep the file for existing
  poll pairs and confirm the new ceiling matches or exceeds the downstream ceiling.
- Document the ceiling choice in a comment above the env vars so future engineers can
  see why the value was picked (this PR added such a comment block to
  `web-platform-release.yml:100-105`).

## Session Errors

**PreToolUse `security_reminder_hook.py` false-blocked a benign workflow edit.** The
hook printed a generic workflow-injection advisory and returned a tool error when
editing `.github/workflows/web-platform-release.yml` — even though the diff only
changed an integer env value (24 → 60) and added 5 comment lines, with no `run:`
block changes and no `${{ github.event.* }}` interpolation anywhere near the diff.
Recovery: retry the identical Edit call (second attempt succeeded). **Prevention:**
Tighten the hook to only fire when the diff actually adds or modifies a `run:` block
containing `${{ github.event.*.title }}`, `${{ github.event.*.body }}`, or similar
untrusted-input interpolations. Filed as GitHub issue for hook improvement.

## 2026-05-07 update

The 300s ceiling set in PR #2523 proved insufficient 6 weeks later (#3398 incidents on 2026-05-06: runs 25461549363, 25463360079). Both ran the full 60 attempts in `running` state while the prod-side deploy was healthy — image v0.66.10 (PR #3391) and v0.67.0 (PR-B/#3395) became live on prod within 11 min of the deploy webhook POST. The realistic deploy duration grew because new safety phases were added to `ci-deploy.sh` between #2523 and #3398 (canary boot + 3-layer canary probe set, plugin seed, sandbox bwrap verify).

Raised to 900s in the #3398 PR with `STATUS_POLL_MAX_ATTEMPTS=180 × INTERVAL_S=5` and matching `HEALTH_POLL_MAX_ATTEMPTS=90 × INTERVAL_S=10`. The per-attempt elapsed-time annotation added in the same PR (parses `start_ts` from the state file's JSON body via `jq`) will surface the next ceiling drift in the workflow log directly, before it produces an incident.

The original 300s reasoning above is preserved as historical record. The refreshed prevention checklist now includes: **when a new phase is added to `ci-deploy.sh` (any new `docker run`, `docker pull`, or extended health probe), measure its 95th-percentile end-to-end duration on prod and update the workflow poll ceiling in the same PR.** See `knowledge-base/project/learnings/best-practices/2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`.

## See Also

- `knowledge-base/project/learnings/2026-03-21-async-webhook-deploy-cloudflare-timeout.md`
  (documents the 60-180s Docker pull + restart realistic window that the 300s ceiling
  accommodates)
- `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md`
  (prior fix to the same verify-completion step — non-JSON body guard)
- `knowledge-base/project/learnings/best-practices/2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`
  (recurrence pattern + script-side phase-addition prevention checklist)
- Issue #2519, PR #2523, Issue #3398
