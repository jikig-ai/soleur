# Tasks: fix Ralph Loop frontmatter scope

Source: `knowledge-base/plans/2026-03-05-fix-ralph-frontmatter-scope-plan.md`
Issue: #455

## Phase 1: Core Fix

- [x] 1.1 Replace sed frontmatter parser with scoped awk (`plugins/soleur/hooks/stop-hook.sh` line 24)
- [x] 1.2 Replace sed update pass with scoped awk (`plugins/soleur/hooks/stop-hook.sh` lines 146-148)
- [x] 1.3 Update inline comments to reflect awk usage

## Phase 2: Testing

- [x] 2.1 Add test: prompt body containing `---` does not leak into FRONTMATTER (`plugins/soleur/test/ralph-loop-stuck-detection.test.sh`)
- [x] 2.2 Add test: prompt body containing `iteration:` text is preserved verbatim after update
- [x] 2.3 Add test: prompt body containing `stuck_count:` text is preserved verbatim after update
- [x] 2.4 Run full existing test suite to verify no regressions

## Phase 3: Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit, push, create PR with `Closes #455`
- [ ] 3.3 Merge via auto-merge and cleanup
