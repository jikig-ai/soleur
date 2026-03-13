---
feature: archive-kb skill
branch: feat/archive-skill
created: 2026-02-24
---

# Tasks: archive-kb Skill

## Phase 1: Setup

- [x] 1.1 Create skill directory structure: `plugins/soleur/skills/archive-kb/{SKILL.md,scripts/}`
- [x] 1.2 Initialize `scripts/archive-kb.sh` with shebang, `set -euo pipefail`, usage function, and argument parsing

## Phase 2: Core Implementation

- [x] 2.1 Implement slug derivation from current git branch (strip `feat/`, `feat-`, `fix/`, `fix-` prefixes)
- [x] 2.2 Implement artifact discovery: glob brainstorms, plans, and specs directories; exclude `archive/` paths
- [x] 2.3 Implement `--list` mode: print discovered artifacts and exit
- [x] 2.4 Implement `--dry-run` mode: print what would be archived without executing
- [x] 2.5 Implement archival: `mkdir -p`, `git add`, `git mv` with internal timestamp generation
- [x] 2.6 Implement structured output (one line per archived artifact)
- [x] 2.7 Write SKILL.md with proper frontmatter and invocation instructions (no `$()`)

## Phase 3: Consumer Updates

- [x] 3.1 Update `skills/compound-capture/SKILL.md` Step E to invoke `archive-kb.sh`
- [x] 3.2 Update `skills/compound/SKILL.md` archival section to reference `archive-kb.sh`
- [x] 3.3 Update `skills/brainstorm/SKILL.md` archival section to reference `archive-kb.sh`
- [x] 3.4 Update `skills/plan/SKILL.md` archival section to reference `archive-kb.sh`
- [x] 3.5 Verify no `$()` remains in archival instructions across all updated files

## Phase 4: Registration and Testing

- [x] 4.1 Register skill in `docs/_data/skills.js` SKILL_CATEGORIES
- [x] 4.2 Run `bun test` to verify no regressions (893 pass)
- [x] 4.3 Manual test: run `archive-kb.sh --list` on a branch with artifacts
- [x] 4.4 Manual test: run `archive-kb.sh --dry-run` and verify output
- [ ] 4.5 Manual test: run `archive-kb.sh` and verify `git mv` executed correctly

## Phase 5: Ship

- [ ] 5.1 Update `plugins/soleur/README.md` skill count and table
- [ ] 5.2 Version bump (MINOR): `plugin.json`, `CHANGELOG.md`, `README.md`
- [ ] 5.3 Sync version to root `README.md` badge and `bug_report.yml`
