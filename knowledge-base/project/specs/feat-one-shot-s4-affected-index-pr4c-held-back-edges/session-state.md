# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-26-ci-s4-affected-index-pr4c-held-back-edges-plan.md
- Status: work and review complete; the review panel (10 of 10 seats returned) found a merge-time P1 (accept anchors stale after #10893), fixed by merging origin/main and re-deriving; ship next
- review=10 of 10 seats, coverage full; fix=merged origin/main 39ba94781f, dropped the rung2 SUT edge (cloud-init-git-data.yml is never read by the suite), 8 edges declared, 26 accept rows, baseline 1627 -> 1619
- cto_spawns=2 (second spawn: row 7, the 43 deferred-sweep pairs, ruled out of PR4c/PR4d into PR5)

### Decisions
- CTO: one ascending pool (re-testable held edges + out-of-slice) cut once at 130 (34 edges, 117 pairs); grep-q-pipe-guard to PR5; at most one PR4d (needs 10 declared edges), then PR5; hot-F exception with zero accept rows; floor of one edge.
