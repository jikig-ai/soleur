# Tasks: merge-pr

## Phase 1: Write SKILL.md

- [x] 1.1 Create `plugins/soleur/skills/merge-pr/SKILL.md` with YAML frontmatter (name, description in third person)
- [x] 1.2 Write Phase 0: Context detection (branch name, worktree path, starting commit SHA)
- [x] 1.3 Write Phase 1: Pre-condition validation
  - [x] 1.3.1 Check current branch is not main
  - [x] 1.3.2 Check `git status --porcelain` is empty
  - [x] 1.3.3 Check compound has run (search unarchived KB artifacts; on failure, direct to `/soleur:compound`)
- [x] 1.4 Write Phase 2: Merge main (`git fetch origin main && git merge origin/main`)
- [x] 1.5 Write Phase 3: Conflict resolution
  - [x] 1.5.1 Detect conflicted files (`git diff --name-only --diff-filter=U`)
  - [x] 1.5.2 Deterministic heuristics for version files (accept main's version)
  - [x] 1.5.3 CHANGELOG merge via `git show :2:` and `git show :3:` (preserve both entries, verify line count)
  - [x] 1.5.4 Claude-assisted resolution for code conflicts
  - [x] 1.5.5 Abort path: `git merge --abort` if resolution fails
- [x] 1.6 Write Phase 4: Version bump (conditional -- skip if no plugin files changed)
  - [x] 1.6.1 Check `git diff --name-only origin/main...HEAD -- plugins/soleur/`
  - [x] 1.6.2 Update versioning triad + 2 sync targets
- [x] 1.7 Write Phase 5: Push and PR (`git push -u`, `gh pr create` or verify existing)
- [x] 1.8 Write Phase 6: CI and merge (`gh pr checks --watch --fail-fast`, `gh pr merge --squash`)
- [x] 1.9 Write Phase 7: Cleanup (navigate to repo root, `cleanup-merged`, print report)
- [x] 1.10 Write rollback instructions (reset to starting SHA noted in Phase 0)

## Phase 2: Documentation and Ship

- [x] 2.1 Register skill in plugin README skills table (Workflow category)
- [x] 2.2 Update component counts (skills count in README, plugin.json description, root README)
- [ ] 2.3 Version bump: MINOR (new skill)
- [x] 2.4 Register in `docs/_data/skills.js` SKILL_CATEGORIES if it exists (does not exist -- skipped)
