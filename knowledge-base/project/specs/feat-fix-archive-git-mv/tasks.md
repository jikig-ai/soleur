# Tasks: fix archive git mv untracked files

## Phase 1: Core Implementation

- [ ] 1.1 Update `plugins/soleur/skills/compound-capture/SKILL.md` Step E: reposition trailing fallback note as a preamble before the three `git mv` blocks; remove the old trailing paragraph at line 446
- [ ] 1.2 Update `plugins/soleur/skills/brainstorm/SKILL.md` line 280: append `git add` fallback sentence after the `git mv` archive instruction
- [ ] 1.3 Update `plugins/soleur/skills/plan/SKILL.md` line 392: append `git add` fallback sentence after the `git mv` archive instruction
- [ ] 1.4 Update `plugins/soleur/skills/compound/SKILL.md` line 181: append `git add` fallback sentence after the `git mv` archive instruction

## Phase 2: Verification

- [ ] 2.1 Run `bun test` to verify no regressions
- [ ] 2.2 Run markdownlint on all 4 modified files
- [ ] 2.3 Grep `plugins/soleur/**/*.md` for any remaining bare `git mv` archive instructions without fallback
- [ ] 2.4 Verify the fallback specifies `git add <specific-source-file>` (not `git add -A` or `git add .`)

## Phase 3: Version Bump and Ship

- [ ] 3.1 PATCH version bump (`plugin.json`, `CHANGELOG.md`, `README.md`)
- [ ] 3.2 Commit, push, create PR referencing #290
