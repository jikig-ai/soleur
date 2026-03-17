# Tasks: Consolidate KB Artifact Dirs Under project/

## Phase A: File Moves (merge root-level → project/)

### A1: Merge root brainstorms/ → project/brainstorms/

- [ ] A1.1 `git add knowledge-base/brainstorms/` then move all `*.md` files to `knowledge-base/project/brainstorms/`
- [ ] A1.2 Move all archive contents from `brainstorms/archive/` to `knowledge-base/project/brainstorms/archive/`
- [ ] A1.3 Verify `knowledge-base/brainstorms/` is empty

### A2: Merge root learnings/ → project/learnings/

- [ ] A2.1 `git add knowledge-base/learnings/` then move all flat `*.md` files to `knowledge-base/project/learnings/`
- [ ] A2.2 Verify `knowledge-base/learnings/` is empty

### A3: Merge root plans/ → project/plans/

- [ ] A3.1 `git add knowledge-base/plans/` then move all `*.md` files to `knowledge-base/project/plans/`
- [ ] A3.2 Move all archive contents from `plans/archive/` to `knowledge-base/project/plans/archive/`
- [ ] A3.3 Verify `knowledge-base/plans/` is empty

### A4: Merge root specs/ → project/specs/

- [ ] A4.1 Move all non-overlapping `feat-*` directories from root `specs/` to `knowledge-base/project/specs/`
- [ ] A4.2 Move `knowledge-base/specs/feat-plausible-goals/session-state.md` into `knowledge-base/project/specs/feat-plausible-goals/`
- [ ] A4.3 Move `knowledge-base/specs/feat-weekly-analytics-improvements/session-state.md` into `knowledge-base/project/specs/feat-weekly-analytics-improvements/`
- [ ] A4.4 Move all archive contents from root `specs/archive/` to `knowledge-base/project/specs/archive/`
- [ ] A4.5 Verify `knowledge-base/specs/` is empty

### A5: Merge features/specs/ → project/specs/

- [ ] A5.1 `git add knowledge-base/features/specs/` then `git mv` feat-linkedin-presence to `knowledge-base/project/specs/`
- [ ] A5.2 `git mv` feat-ralph-loop-idle-detection to `knowledge-base/project/specs/`
- [ ] A5.3 `git mv` archive entry to `knowledge-base/project/specs/archive/`
- [ ] A5.4 Verify `knowledge-base/features/` is empty

## Phase B: Update References

### B1: Shell Scripts

- [ ] B1.1 Update `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — change all `knowledge-base/specs/`, `knowledge-base/brainstorms/`, `knowledge-base/plans/` to `knowledge-base/project/specs/`, etc. Remove `features/specs/` fallback. Consolidate legacy fallback arrays.
- [ ] B1.2 Update `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` — change primary paths to `knowledge-base/project/brainstorms`, `knowledge-base/project/plans`, `knowledge-base/project/specs`. Remove `features/specs` and legacy fallback entries.

### B2: Skill Definitions

- [ ] B2.1 Update `plugins/soleur/skills/plan/SKILL.md` — all four artifact paths
- [ ] B2.2 Update `plugins/soleur/skills/brainstorm/SKILL.md` — all four artifact paths
- [ ] B2.3 Update `plugins/soleur/skills/brainstorm-techniques/SKILL.md` — brainstorms path
- [ ] B2.4 Update `plugins/soleur/skills/compound/SKILL.md` — learnings, specs paths
- [ ] B2.5 Update `plugins/soleur/skills/compound-capture/SKILL.md` — all four artifact paths
- [ ] B2.6 Update `plugins/soleur/skills/ship/SKILL.md` — all four artifact paths
- [ ] B2.7 Update `plugins/soleur/skills/deepen-plan/SKILL.md` — plans, learnings paths
- [ ] B2.8 Update `plugins/soleur/skills/merge-pr/SKILL.md` — brainstorms, plans, specs paths
- [ ] B2.9 Update `plugins/soleur/skills/archive-kb/SKILL.md` — all artifact paths + remove features/ refs
- [ ] B2.10 Update `plugins/soleur/skills/one-shot/SKILL.md` — specs path
- [ ] B2.11 Update `plugins/soleur/skills/spec-templates/SKILL.md` — specs path
- [ ] B2.12 Update `plugins/soleur/skills/work/SKILL.md` — specs path

### B3: Agent Definitions

- [ ] B3.1 Update `plugins/soleur/agents/engineering/research/learnings-researcher.md` — learnings path
- [ ] B3.2 Grep for any other agents referencing root-level artifact paths and update

### B4: Documentation

- [ ] B4.1 Update `knowledge-base/project/components/knowledge-base.md` — directory tree, examples
- [ ] B4.2 Update `knowledge-base/project/README.md` — directory structure section
- [ ] B4.3 Check and update `AGENTS.md` if needed
- [ ] B4.4 Check and update `knowledge-base/project/constitution.md` if needed

## Phase C: Verification

- [ ] C1 `knowledge-base/brainstorms/` does not exist
- [ ] C2 `knowledge-base/learnings/` does not exist
- [ ] C3 `knowledge-base/plans/` does not exist
- [ ] C4 `knowledge-base/specs/` does not exist
- [ ] C5 `knowledge-base/features/` does not exist
- [ ] C6 `knowledge-base/project/brainstorms/` has 33+ files
- [ ] C7 `knowledge-base/project/learnings/` has 198+ files including 12 category subdirs
- [ ] C8 `knowledge-base/project/plans/` has 100+ files
- [ ] C9 `knowledge-base/project/specs/` has 104+ dirs
- [ ] C10 `feat-plausible-goals` has both `tasks.md` and `session-state.md`
- [ ] C11 `feat-weekly-analytics-improvements` has both `tasks.md` and `session-state.md`
- [ ] C12 `grep -rn 'knowledge-base/brainstorms\|knowledge-base/learnings\|knowledge-base/plans\|knowledge-base/specs' plugins/ scripts/ .github/ AGENTS.md` returns zero hits
- [ ] C13 No references to `knowledge-base/features/` remain in operational files
