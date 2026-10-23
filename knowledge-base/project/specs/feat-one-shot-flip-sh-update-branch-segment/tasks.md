# Tasks: fix flip.sh existing-override update payload

Plan: knowledge-base/project/plans/2026-10-23-fix-flip-sh-existing-override-update-segment-plan.md

## Phase 1: Red
- [x] 1.1 Write plugins/soleur/test/flip-update-existing-override.test.sh (pty + yes driver copied from flag-detach-shared.test.sh, FLIP env override, JSON-parsing stub that returns the live 400 for an update body without feature_segment.segment, featurestates matched before versions, role-prd/role-dev served by name).
- [x] 1.2 Run it against the current flip.sh; confirm scenario 1 fails with exit 3 and the live error JSON.

## Phase 2: Green
- [x] 2.1 Edit flip_segment_in_env update arm in plugins/soleur/skills/flag-set-role/scripts/flip.sh: add "segment":%d next to "id":%d, args "$existing_fs_id" "$segment_id" "$enabled".
- [x] 2.2 (new suite + 4 neighbours green; flag-org-scoping-pr2 and flag-detach-shared red in agent session, identical pre-fix) Run the new suite plus flag-detach-shared, flag-org-scoping-pr2, audit-flag-flip, flip-flag-map-parity, operator-ack-guard, flagsmith-stdin-config.
- [x] 2.3 Add scenario 3 (different ids) and, if not already covered, scenario 4 (create arm unchanged).

## Phase 3: Wire and ship
- [x] 3.1 Add the declared edge to scripts/lib/test-affected-paths.sh and the shard line to scripts/suite-shard-legs.tsv; confirm the leg runs in CI.
- [x] 3.2 One-time mutation rows 1-4 and harness rows H1-H2 via FLIP override on sed-mutated copies; record a one-line summary.
- 3.3 File the append-before-flip follow-up issue.
- 3.4 Open the PR (Changelog, semver:patch, audit-row note, recovery line, deviation sentence, API-verification caveat). Stop before merge.
