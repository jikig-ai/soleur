# Tasks: Clean Up Stale KB Project References

Issue: #604
Plan: `knowledge-base/plans/2026-03-13-chore-clean-stale-kb-project-refs-plan.md`

## Phase 1: High-Priority Files (Executable Code Snippets)

- [ ] 1.1 Update `plugins/soleur/skills/compound-capture/SKILL.md` (25 occurrences)
  - [ ] 1.1.1 Replace `knowledge-base/project/learnings/` with `knowledge-base/learnings/` in all `find`, `grep -r`, `mkdir -p`, `cat >>`, and descriptive references
  - [ ] 1.1.2 Replace `knowledge-base/project/brainstorms/` with `knowledge-base/brainstorms/`
  - [ ] 1.1.3 Replace `knowledge-base/project/plans/` with `knowledge-base/plans/`
  - [ ] 1.1.4 Replace `knowledge-base/project/specs/` with `knowledge-base/specs/`
  - [ ] 1.1.5 Preserve any references to `knowledge-base/project/constitution.md` and `knowledge-base/project/components/`
- [ ] 1.2 Update `plugins/soleur/skills/compound/SKILL.md` (16 occurrences)
  - [ ] 1.2.1 Replace all four stale path patterns
  - [ ] 1.2.2 Preserve `knowledge-base/project/constitution.md` references (grep -c command)
- [ ] 1.3 Update `plugins/soleur/agents/engineering/research/learnings-researcher.md` (29 occurrences)
  - [ ] 1.3.1 Replace all 13 category directory paths from `knowledge-base/project/learnings/<category>/` to `knowledge-base/learnings/<category>/`
  - [ ] 1.3.2 Replace remaining learnings references
- [ ] 1.4 Update `plugins/soleur/commands/sync.md` (5 occurrences)
  - [ ] 1.4.1 Update `mkdir -p` command to create at top-level paths (keep `knowledge-base/project/components`)
  - [ ] 1.4.2 Replace remaining stale path references
- [ ] 1.5 Update `plugins/soleur/skills/compound-capture/references/yaml-schema.md` (13 occurrences)
  - [ ] 1.5.1 Replace all category-to-directory mappings
- [ ] 1.6 Update `plugins/soleur/skills/compound-capture/assets/critical-pattern-template.md` (2 occurrences)
- [ ] 1.7 Update `plugins/soleur/skills/compound-capture/assets/resolution-template.md` (1 occurrence)

## Phase 2: Medium-Priority Files (Descriptive References in Plugin)

- [ ] 2.1 Update `plugins/soleur/skills/plan/SKILL.md` (24 occurrences)
  - [ ] 2.1.1 Replace all four stale path patterns in output examples, ls commands, spec dir references
  - [ ] 2.1.2 Preserve `knowledge-base/project/constitution.md` reference
- [ ] 2.2 Update `plugins/soleur/skills/brainstorm/SKILL.md` (10 occurrences)
- [ ] 2.3 Update `plugins/soleur/skills/ship/SKILL.md` (8 occurrences)
- [ ] 2.4 Update `plugins/soleur/skills/deepen-plan/SKILL.md` (4 occurrences)
- [ ] 2.5 Update `plugins/soleur/skills/spec-templates/SKILL.md` (3 occurrences)
  - [ ] 2.5.1 Preserve `knowledge-base/project/components/` references
- [ ] 2.6 Update `plugins/soleur/skills/merge-pr/SKILL.md` (3 occurrences)
- [ ] 2.7 Update `plugins/soleur/skills/archive-kb/SKILL.md` (3 occurrences)
  - [ ] 2.7.1 Update table -- relabel legacy paths, do not remove (scripts still search them)
- [ ] 2.8 Update `plugins/soleur/skills/work/SKILL.md` (2 occurrences)
  - [ ] 2.8.1 Preserve `knowledge-base/project/constitution.md` reference
- [ ] 2.9 Update `plugins/soleur/skills/work/references/work-lifecycle-parallel.md` (2 occurrences)
- [ ] 2.10 Update `plugins/soleur/skills/one-shot/SKILL.md` (1 occurrence)
- [ ] 2.11 Update `plugins/soleur/skills/brainstorm-techniques/SKILL.md` (1 occurrence)
- [ ] 2.12 Update `plugins/soleur/agents/product/cpo.md` (1 occurrence)
- [ ] 2.13 Update `plugins/soleur/agents/engineering/infra/infra-security.md` (1 occurrence)

## Phase 2.5: Knowledge-Base Documentation Files (Discovered During Deepening)

- [ ] 2.14 Update `knowledge-base/project/components/knowledge-base.md` (7 occurrences)
  - [ ] 2.14.1 Update `grep -r "auth" knowledge-base/project/learnings/` command
  - [ ] 2.14.2 Update `ls knowledge-base/project/specs/feat-*/` command
  - [ ] 2.14.3 Update convention path and directory listing
- [ ] 2.15 Update `knowledge-base/project/constitution.md` (1 occurrence)
  - [ ] 2.15.1 Update line 153: convention path `knowledge-base/project/specs/feat-<name>/` to `knowledge-base/specs/feat-<name>/`
- [ ] 2.16 Update `knowledge-base/project/README.md` (1 occurrence)
  - [ ] 2.16.1 Update specs path in directory description
- [ ] 2.17 Update `knowledge-base/project/components/agents.md` (1 occurrence)
  - [ ] 2.17.1 Update learnings-researcher path in agent table
- [ ] 2.18 Update `knowledge-base/product/business-validation.md` (1 occurrence)
  - [ ] 2.18.1 Verify brainstorm exists at new path before updating; if not, leave as-is

## Phase 3: Verification

- [ ] 3.1 Run `grep -rn 'knowledge-base/project/\(learnings\|brainstorms\|plans\|specs\)' plugins/soleur/ --include='*.md'` -- expect zero matches
- [ ] 3.2 Run `grep -rn 'knowledge-base/project/\(learnings\|brainstorms\|plans\|specs\)' knowledge-base/project/constitution.md knowledge-base/project/README.md knowledge-base/project/components/ knowledge-base/product/ --include='*.md'` -- expect zero matches
- [ ] 3.3 Verify `knowledge-base/project/constitution.md` references unchanged: `grep -c 'knowledge-base/project/constitution' plugins/soleur/skills/compound/SKILL.md plugins/soleur/skills/work/SKILL.md plugins/soleur/skills/plan/SKILL.md plugins/soleur/commands/sync.md` -- should match pre-change baseline
- [ ] 3.4 Verify `knowledge-base/project/components/` references unchanged: `grep -rn 'knowledge-base/project/components' plugins/soleur/ --include='*.md'` -- should return same count as before
- [ ] 3.5 Verify shell scripts untouched: `git diff plugins/soleur/skills/archive-kb/scripts/archive-kb.sh plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` -- expect no changes
- [ ] 3.6 Run compound before commit
