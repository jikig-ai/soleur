---
title: "chore: remove the retained dead-man destroy targets and census rows"
date: 2026-11-01
slug: remove-retained-deadman-destroy-targets
branch: feat-one-shot-11672-deadman-retained-targets-cleanup
issue: 11672
lane: single-domain
type: chore
---

## Overview

The first green per-merge infra apply that contains the archive-fed dead-man heartbeats (run 41239555181, 2 added, 4 destroyed exactly as planned) has applied the four destroys. The four bare `-target=logtail_exploration[_alert].{claude_cost_capture_dark,luks_monitor_host_timer_dark}` lines in `.github/workflows/apply-web-platform-infra.yml` and the four `INTENDED_DESTROYS` census rows are now stale. This plan removes them and flips the three guards that pinned their presence into guards that pin their absence. Scope: the first checklist row of #11672 only.

## Research Insights

- Premise validation: #11672 is open; the trigger (green apply containing the merge commit, four destroys applied) is met per run 41239555181. The state-absent check holds: no `.tf` declares the four addresses.
- Property List: (1) the apply workflow has no stale destroy targets; (2) the census lists no destroy intent for addresses main no longer declares; (3) a re-added line or row goes red.
- Cut List: no new mechanism; the guards are flipped in place.
- Other open PRs touching these files: one edits `deadman-heartbeat-feeder.test.sh` (a separate hunk), others edit `apply-web-platform-infra.yml` elsewhere; `betterstack-logs-alerts.tf` is untouched.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` (remove four lines)
- `tests/scripts/test-infra-privileged-tier-census.sh` (remove four rows and their comment)
- `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh` (presence checks become absence checks; rows M5, M5b, M18, M29 flipped; floors unchanged)
- `apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh` (count 4 becomes 0)
- `apps/web-platform/infra/betterstack-alert-structure.test.sh` (comment only; the list is read from the census)

## Acceptance Criteria

- [ ] No `-target=logtail_exploration*.{claude_cost_capture_dark,luks_monitor_host_timer_dark}` line remains in the apply workflow.
- [ ] No `#11631` row remains in `INTENDED_DESTROYS`.
- [ ] `logs-alert-query-period-ceiling.test.sh`, `betterstack-alert-structure.test.sh`, `deadman-heartbeat-feeder.test.sh` and `test-infra-privileged-tier-census.sh` pass; every flipped mutation row lands and reddens (or stays green where must-PASS).
- [ ] PR body uses `Ref #11672`, not `Closes`.

## Test Scenarios

- Re-adding one retired `-target` line turns the ceiling guard red (M5); re-adding one census row turns it red (M5b, M29); a commented-out row stays green (M18).

## Observability

Code-class infra files only change by deletion; no new surface. No new signal is required.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; a broken apply would delay infra changes.
**If this leaks, the user's data is exposed via:** no exposure vector; deletion of stale CI lines.
**Brand-survival threshold:** none
