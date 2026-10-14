# Tasks: Group KB Feature Dirs Under features/

## Phase 1: Setup

- [x] 1.1 Create `knowledge-base/features/` directory
- [x] 1.2 `git mv knowledge-base/specs knowledge-base/features/`
- [x] 1.3 `git mv knowledge-base/plans knowledge-base/features/`
- [x] 1.4 `git mv knowledge-base/brainstorms knowledge-base/features/`
- [x] 1.5 `git mv knowledge-base/learnings knowledge-base/features/`
- [x] 1.6 Commit: `refactor: move specs/plans/brainstorms/learnings under features/`

## Phase 2: Core Implementation -- Shell Scripts

- [x] 2.1 Update `archive-kb.sh` discovery globs (lines 98-110): `knowledge-base/{brainstorms,plans}/*` -> `knowledge-base/features/{brainstorms,plans}/*`; `knowledge-base/project/specs/feat-` -> `knowledge-base/features/specs/feat-`
- [x] 2.2 Update `worktree-manager.sh` `create_for_feature()`: spec_dir path (line 152), spec dir creation (lines 181-184), help text (line 194), help examples (line 617)
- [x] 2.3 Update `worktree-manager.sh` `cleanup_merged_worktrees()`: spec_dir (line 426), archive_dir (line 427), archive_kb_files calls for brainstorms/plans (lines 465-466)
- [x] 2.4 Update `scripts/generate-article-30-register.sh` spec path reference

## Phase 3: Core Implementation -- Skills

- [x] 3.1 Update `plan/SKILL.md`: all `knowledge-base/project/specs/`, `knowledge-base/project/plans/`, `knowledge-base/project/brainstorms/`, `knowledge-base/project/learnings/` references
- [x] 3.2 Update `brainstorm/SKILL.md`: brainstorms/, learnings/, specs/ references
- [x] 3.3 Update `brainstorm-techniques/SKILL.md`: brainstorms/ references
- [x] 3.4 Update `compound/SKILL.md`: specs/, learnings/, brainstorms/, plans/ references (including brace expansion on line 269)
- [x] 3.5 Update `compound-capture/SKILL.md`: specs/, brainstorms/, plans/, learnings/ references
- [x] 3.5.1 Update `compound-capture/assets/critical-pattern-template.md`: learnings/ references
- [x] 3.5.2 Update `compound-capture/assets/resolution-template.md`: learnings/ references
- [x] 3.5.3 Update `compound-capture/references/yaml-schema.md`: learnings/ references
- [x] 3.6 Update `deepen-plan/SKILL.md`: plans/, learnings/ references
- [x] 3.7 Update `work/SKILL.md`: specs/, plans/ references
- [x] 3.7.1 Update `work/references/work-lifecycle-parallel.md`: specs/ references
- [x] 3.8 Update `ship/SKILL.md`: specs/, plans/, brainstorms/, learnings/ references
- [x] 3.9 Update `merge-pr/SKILL.md`: specs/, plans/, brainstorms/ references
- [x] 3.10 Update `one-shot/SKILL.md`: specs/ references
- [x] 3.11 Update `spec-templates/SKILL.md`: specs/ references
- [x] 3.12 Update `archive-kb/SKILL.md`: specs/, brainstorms/, plans/ references

## Phase 4: Core Implementation -- Agents & Commands

- [x] 4.1 Update `learnings-researcher.md`: all 13 category paths in routing table + search paths
- [x] 4.2 Update `infra-security.md`: learnings/ references
- [x] 4.3 Update `cpo.md`: specs/ references
- [x] 4.4 Update `sync.md` command: learnings/ references (root + category paths: architecture/, technical-debt/)

## Phase 5: Project Documentation

- [x] 5.1 Update `constitution.md`: convention path (line 149)
- [x] 5.2 Update `knowledge-base.md` component doc: directory tree, examples, related files
- [x] 5.3 Update `agents.md` component doc: learnings/ references
- [x] 5.4 Update `project/README.md`: specs/, plans/ references

## Phase 6: Verification

- [x] 6.1 Run `grep -r 'knowledge-base/project/specs/' plugins/ scripts/ .github/ AGENTS.md` -- must return zero
- [x] 6.2 Run `grep -r 'knowledge-base/project/plans/' plugins/ scripts/ .github/ AGENTS.md` -- must return zero
- [x] 6.3 Run `grep -r 'knowledge-base/project/brainstorms/' plugins/ scripts/ .github/ AGENTS.md` -- must return zero
- [x] 6.4 Run `grep -r 'knowledge-base/project/learnings/' plugins/ scripts/ .github/ AGENTS.md` -- must return zero
- [x] 6.5 Run `archive-kb.sh --dry-run` and verify artifacts discovered under new paths
- [x] 6.6 Verify constitution.md has `knowledge-base/features/specs/feat-<name>/` convention
- [x] 6.7 Verify learnings-researcher has all 13 categories updated
- [x] 6.8 Verify yaml-schema.md has all 13 category mappings updated
- [x] 6.9 Verify compound/SKILL.md brace expansion pattern updated (line 269)
- [x] 6.10 Verify compound-capture/SKILL.md find commands updated (lines 350-352)

## Phase 7: Commit & Ship

- [ ] 7.1 Run compound
- [ ] 7.2 Commit: `refactor: update path references for features/ grouping`
- [ ] 7.3 Push and create PR (Closes #568)
