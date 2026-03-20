# Tasks: Merge knowledge-base/features/ into knowledge-base/project/

## Phase 1: Directory Moves

- [x] 1.1 `git add knowledge-base/features/` (ensure all files tracked)
- [x] 1.2 `git mv knowledge-base/features/brainstorms knowledge-base/project/brainstorms`
- [x] 1.3 `git mv knowledge-base/features/learnings knowledge-base/project/learnings`
- [x] 1.4 `git mv knowledge-base/features/plans knowledge-base/project/plans`
- [x] 1.5 `git mv knowledge-base/features/specs knowledge-base/project/specs`
- [x] 1.6 `git rm -r knowledge-base/specs/` (stale leftover)
- [x] 1.7 Commit: `refactor: move features/ contents into project/`

## Phase 2: Update Path References

- [x] 2.1 Shell scripts (2 files)
  - [x] 2.1.1 `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (7 refs)
  - [x] 2.1.2 `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` (4 refs)
- [x] 2.2 Skill SKILL.md files (12 files)
  - [x] 2.2.1 `plugins/soleur/skills/compound-capture/SKILL.md` (25 refs)
  - [x] 2.2.2 `plugins/soleur/skills/plan/SKILL.md` (24 refs)
  - [x] 2.2.3 `plugins/soleur/skills/compound/SKILL.md` (16 refs)
  - [x] 2.2.4 `plugins/soleur/skills/brainstorm/SKILL.md` (10 refs)
  - [x] 2.2.5 `plugins/soleur/skills/ship/SKILL.md` (8 refs)
  - [x] 2.2.6 `plugins/soleur/skills/deepen-plan/SKILL.md` (4 refs)
  - [x] 2.2.7 `plugins/soleur/skills/archive-kb/SKILL.md` (3 refs)
  - [x] 2.2.8 `plugins/soleur/skills/spec-templates/SKILL.md` (3 refs)
  - [x] 2.2.9 `plugins/soleur/skills/merge-pr/SKILL.md` (3 refs)
  - [x] 2.2.10 `plugins/soleur/skills/work/SKILL.md` (2 refs)
  - [x] 2.2.11 `plugins/soleur/skills/one-shot/SKILL.md` (1 ref)
  - [x] 2.2.12 `plugins/soleur/skills/brainstorm-techniques/SKILL.md` (1 ref)
- [x] 2.3 Skill references/assets (4 files)
  - [x] 2.3.1 `plugins/soleur/skills/compound-capture/references/yaml-schema.md` (13 refs)
  - [x] 2.3.2 `plugins/soleur/skills/work/references/work-lifecycle-parallel.md` (2 refs)
  - [x] 2.3.3 `plugins/soleur/skills/compound-capture/assets/critical-pattern-template.md` (2 refs)
  - [x] 2.3.4 `plugins/soleur/skills/compound-capture/assets/resolution-template.md` (1 ref)
- [x] 2.4 Agents (3 files)
  - [x] 2.4.1 `plugins/soleur/agents/engineering/research/learnings-researcher.md` (29 refs)
  - [x] 2.4.2 `plugins/soleur/agents/product/cpo.md` (1 ref)
  - [x] 2.4.3 `plugins/soleur/agents/engineering/infra/infra-security.md` (1 ref)
- [x] 2.5 Commands (1 file)
  - [x] 2.5.1 `plugins/soleur/commands/sync.md` (6 refs)
- [x] 2.6 Scripts (1 file)
  - [x] 2.6.1 `scripts/generate-article-30-register.sh` (1 ref)
- [x] 2.7 Project documentation — self-references (4 files, manual review)
  - [x] 2.7.1 `knowledge-base/project/components/knowledge-base.md` — update directory tree + paths (7 refs)
  - [x] 2.7.2 `knowledge-base/project/README.md` — update directory tree + convention path (1 ref)
  - [x] 2.7.3 `knowledge-base/project/constitution.md` — update convention path (1 ref)
  - [x] 2.7.4 `knowledge-base/project/components/agents.md` — update learnings-researcher description (1 ref)
- [x] 2.8 Domain documentation (1 file)
  - [x] 2.8.1 `knowledge-base/product/business-validation.md` — update brainstorm reference (1 ref)
- [x] 2.9 Commit: `refactor: update all path references features/ → project/`

## Phase 3: Verification

- [x] 3.1 Run comprehensive grep: zero hits for `knowledge-base/features/` across plugins/, scripts/, .github/, knowledge-base/
- [x] 3.2 Verify `knowledge-base/project/` contains brainstorms/, components/, constitution.md, learnings/, plans/, README.md, specs/
- [x] 3.3 Verify `knowledge-base/features/` no longer exists
- [x] 3.4 Verify `knowledge-base/specs/` no longer exists
