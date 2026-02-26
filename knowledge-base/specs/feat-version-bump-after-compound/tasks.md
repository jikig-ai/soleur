# Tasks: Move version bump after compound

## Phase 1: Ship Skill Reordering

- [ ] 1.1 Move Phase 4 (version bump) to after Phase 6 (tests), renumber as Phase 5
- [ ] 1.2 Renumber Phase 5 (final checklist) to Phase 6
- [ ] 1.3 Renumber Phase 6 (tests) to Phase 4
- [ ] 1.4 Remove pre-push compound gate from Phase 7 (lines 216-230)
- [ ] 1.5 Update all internal phase references within ship/SKILL.md

## Phase 2: One-Shot Skill Version Bump Recheck

- [ ] 2.1 Add step 6.5 after compound: conditional version-bump-recheck
- [ ] 2.2 Add explicit push step after version-bump-recheck if new commit was created
- [ ] 2.3 Verify step numbering and sequencing is consistent

## Phase 3: Work Skill Description Sync

- [ ] 3.1 Update inline ship phase description in work/SKILL.md (lines 280-290) to reflect new ordering

## Phase 4: Constitution Update

- [ ] 4.1 Add principle to Architecture > Always: version bump must run after compound

## Phase 5: Version Bump and Finalize

- [ ] 5.1 Bump version (PATCH) in plugin.json, CHANGELOG.md, README.md
- [ ] 5.2 Sync version to root README.md badge and bug_report.yml placeholder
