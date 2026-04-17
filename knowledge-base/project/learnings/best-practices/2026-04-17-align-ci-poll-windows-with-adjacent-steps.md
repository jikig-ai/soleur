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

## See Also

- `knowledge-base/project/learnings/2026-03-21-async-webhook-deploy-cloudflare-timeout.md`
  (documents the 60-180s Docker pull + restart realistic window that the 300s ceiling
  accommodates)
- `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md`
  (prior fix to the same verify-completion step — non-JSON body guard)
- Issue #2519, PR #2523
