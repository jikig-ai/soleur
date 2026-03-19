# Tasks: Remove community and report-bug skills from plugin loader

## Phase 1: Remove Skills

- [ ] 1.1 `git rm plugins/soleur/skills/community/SKILL.md`
- [ ] 1.2 `git rm -r plugins/soleur/skills/report-bug/`
- [ ] 1.3 Verify `plugins/soleur/skills/community/scripts/` still exists (3 shell scripts)

## Phase 2: Update References

- [ ] 2.1 Update `plugins/soleur/agents/support/community-manager.md` -- remove `/soleur:community setup` references (lines 17, 19, 209)
- [ ] 2.2 Remove `community` and `report-bug` entries from `plugins/soleur/docs/_data/skills.js` SKILL_CATEGORIES (lines 48, 53) and update comment count (line 7)
- [ ] 2.3 Remove `community` and `report-bug` rows from `plugins/soleur/README.md` skills table
- [ ] 2.4 Update skill count from 52 to 50 in `plugins/soleur/README.md` (line 44)
- [ ] 2.5 Update skill count from 52 to 50 in `plugins/soleur/.claude-plugin/plugin.json` description (line 4)
- [ ] 2.6 Update skill count from 52 to 50 in root `README.md` (line 14)
- [ ] 2.7 Update skill count from 52 to 50 in `knowledge-base/overview/brand-guide.md` (lines 21, 51)

## Phase 3: Version Bump and Ship

- [ ] 3.1 Bump PATCH version in `plugins/soleur/.claude-plugin/plugin.json` (3.0.3 -> 3.0.4)
- [ ] 3.2 Add changelog entry to `plugins/soleur/CHANGELOG.md` under `### Removed`
- [ ] 3.3 Verify no remaining references: `grep -rn 'soleur:community\|soleur:report-bug' plugins/soleur/ --include='*.md' --include='*.js'` (expect only CHANGELOG hits)
- [ ] 3.4 Verify skill count: `find plugins/soleur/skills -name "SKILL.md" -type f | wc -l` (expect 50)
- [ ] 3.5 Verify all "52 skills" updated: `grep -rn '\b52 skills\b' .` (expect only knowledge-base/plans/ and CHANGELOG hits)
- [ ] 3.6 Run review, compound, commit, push, PR
