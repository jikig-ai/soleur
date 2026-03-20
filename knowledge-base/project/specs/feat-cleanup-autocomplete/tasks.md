# Tasks: Clean Up Plugin Loader Autocomplete Pollution

## Phase 1: Setup

- [x] 1.1 Create `references/` directories in 4 skill directories (brainstorm, plan, work, review)

## Phase 2: Move Reference Files

- [x] 2.1 Move brainstorm references (3 files) from `commands/soleur/references/` to `skills/brainstorm/references/`
- [x] 2.2 Move plan references (3 files) from `commands/soleur/references/` to `skills/plan/references/`
- [x] 2.3 Move review references (2 files) from `commands/soleur/references/` to `skills/review/references/`
- [x] 2.4 Move work references (2 files) from `commands/soleur/references/` to `skills/work/references/`
- [x] 2.5 Remove empty `commands/soleur/references/` directory

## Phase 3: Update Path References

- [x] 3.1 Update `skills/brainstorm/SKILL.md` -- change 3 `Read` paths from `plugins/soleur/commands/soleur/references/` to `plugins/soleur/skills/brainstorm/references/`
- [x] 3.2 Update `skills/plan/SKILL.md` -- change 3 `Read` paths from `plugins/soleur/commands/soleur/references/` to `plugins/soleur/skills/plan/references/`
- [x] 3.3 Update `skills/review/SKILL.md` -- change 2 `Read` paths from `plugins/soleur/commands/soleur/references/` to `plugins/soleur/skills/review/references/`
- [x] 3.4 Update `skills/work/SKILL.md` -- change 2 `Read` paths from `plugins/soleur/commands/soleur/references/` to `plugins/soleur/skills/work/references/`

## Phase 4: Verification

- [x] 4.1 Search all plugin `.md` files for old path `commands/soleur/references/` -- must return zero results
- [x] 4.2 Verify reference files are accessible at new paths
- [x] 4.3 Verify `commands/soleur/` contains only go.md, sync.md, help.md (no subdirectories)

## Phase 5: Version Bump and Ship

- [x] 5.1 Update context-compaction learning with note about reference relocation
- [ ] 5.2 Version bump (PATCH): plugin.json, CHANGELOG.md, README.md
- [ ] 5.3 Ship via `/ship` workflow
