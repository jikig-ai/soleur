# Decision Challenges — feat-one-shot-9323-escape-r3-rerule

Headless one-shot pipeline: technical forks are recorded as `pending - assumed:` rows for the
parent's batched technical-ruling-gate CTO (see technical-ruling-delegation.md). Operator-ruled
items are recorded as ruled, not pending. The plan prescribes the binding `soleur:engineering:cto`
spawn at work Phase 1 step 1 for the Item-1 fork below.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #9323 escape triage fork: widen the declaring array (ADR-262 R1) / revert the PR arm / fix the probe's escape classification in `scripts/followthroughs/pr-battery-gate-saving-9323.sh` | technical | Ruled by CTO agent, 2026-11-08: fix the probe's escape classification (Arm A) - an ADR-262 R1 escape is defined by what the path-gate could have let through, i.e. a failed job in the gated battery family (the test-scripts prefix the examine arm already derives at :281); a red merge-commit ci.yml push run is escape iff at least one failed job is in that family, a run red solely on jobs outside it is reported in a distinct bucket and never counted, and an unestablishable jobs read is pending never ok. Arm B has no array member to widen toward (lint-bot-statuses and tenant-integration name no battery subject; declaring infra jobs would arm the batteries on every flake and defeat the gate's measured saving). Arm C forfeits the measured ~295 suite-min/run realized saving to fix a false positive a roughly 40-line classifier edit removes. Dissent accepted: a battery break surfacing only in a non-ci.yml push workflow stays invisible to this probe either way (main-side red is paged separately); executed sequential-fallback, no subagent spawn available, disclosed |
| One PR carrying both residual items vs one PR per item | operator (scope) | ruled by operator 2026-11-08 (brief): "Both items land in ONE PR on this branch" |
| R3 receipts placement: `r3/` subdirectory vs flat files inside the schedule-named receipts dir | taste | r3/ subdirectory — keeps the R2 receipts intact and mirrors the `receipts/rerun/` precedent from the 10862 criterion-a re-run; leaf names kept per the receipts convention |
