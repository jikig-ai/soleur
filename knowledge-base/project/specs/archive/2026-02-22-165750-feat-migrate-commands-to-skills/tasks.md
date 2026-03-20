---
title: "Tasks: Migrate Workflow Commands to Skills"
plan: "../plans/2026-02-22-feat-migrate-commands-to-skills-plan.md"
---

# Tasks: Migrate Workflow Commands to Skills

## Phase 1: Rename Conflicting Skills

- [ ] 1.1 Rename `skills/brainstorming/` -> `skills/brainstorm-techniques/`
  - [ ] 1.1.1 `git mv skills/brainstorming/ skills/brainstorm-techniques/`
  - [ ] 1.1.2 Update `SKILL.md` frontmatter `name: brainstorm-techniques`
  - [ ] 1.1.3 Update references in `commands/soleur/brainstorm.md` (2 refs)
  - [ ] 1.1.4 Update reference in `commands/soleur/plan.md` (1 ref)
  - [ ] 1.1.5 Update `docs/_data/skills.js` entry
  - [ ] 1.1.6 Update `README.md` skill table row
- [ ] 1.2 Rename `skills/compound-docs/` -> `skills/compound-capture/`
  - [ ] 1.2.1 `git mv skills/compound-docs/ skills/compound-capture/`
  - [ ] 1.2.2 Update `SKILL.md` frontmatter `name: compound-capture`
  - [ ] 1.2.3 Update references in `commands/soleur/compound.md` (2 refs)
  - [ ] 1.2.4 Update references in `commands/soleur/sync.md` (3 refs)
  - [ ] 1.2.5 Update reference in `agents/engineering/research/learnings-researcher.md` (1 ref)
  - [ ] 1.2.6 Update `docs/_data/skills.js` entry
  - [ ] 1.2.7 Update `README.md` skill table row

## Phase 2: Migrate Commands to Skills

- [ ] 2.1 Migrate `brainstorm` command to skill
  - [ ] 2.1.1 Create `skills/brainstorm/SKILL.md` with adapted frontmatter
  - [ ] 2.1.2 Update internal `/soleur:` references to Skill tool syntax
  - [ ] 2.1.3 Update `brainstorming` refs to `brainstorm-techniques` (already done)
  - [ ] 2.1.4 Delete `commands/soleur/brainstorm.md`
- [ ] 2.2 Migrate `plan` command to skill
  - [ ] 2.2.1 Create `skills/plan/SKILL.md` with adapted frontmatter
  - [ ] 2.2.2 Update internal `/soleur:` references to Skill tool syntax
  - [ ] 2.2.3 Delete `commands/soleur/plan.md`
- [ ] 2.3 Migrate `work` command to skill
  - [ ] 2.3.1 Create `skills/work/SKILL.md` with adapted frontmatter
  - [ ] 2.3.2 Update internal `/soleur:` references to Skill tool syntax
  - [ ] 2.3.3 Delete `commands/soleur/work.md`
- [ ] 2.4 Migrate `review` command to skill
  - [ ] 2.4.1 Create `skills/review/SKILL.md` with adapted frontmatter
  - [ ] 2.4.2 Update internal `/soleur:` references to Skill tool syntax
  - [ ] 2.4.3 Delete `commands/soleur/review.md`
- [ ] 2.5 Migrate `compound` command to skill
  - [ ] 2.5.1 Create `skills/compound/SKILL.md` with adapted frontmatter
  - [ ] 2.5.2 Update internal `/soleur:` references to Skill tool syntax
  - [ ] 2.5.3 Delete `commands/soleur/compound.md`
- [ ] 2.6 Migrate `one-shot` command to skill
  - [ ] 2.6.1 Create `skills/one-shot/SKILL.md` with adapted frontmatter
  - [ ] 2.6.2 Rewrite pipeline to use Skill tool syntax
  - [ ] 2.6.3 Delete `commands/soleur/one-shot.md`

## Phase 3: Update Remaining Commands

- [ ] 3.1 Update `commands/soleur/go.md` prose table references
- [ ] 3.2 Update `commands/soleur/help.md` -- remove "WORKFLOW COMMANDS" section, add skills note
- [ ] 3.3 Verify `commands/soleur/sync.md` references (compound-docs already done)

## Phase 4: Update External Skills

- [ ] 4.1 Update `skills/ship/SKILL.md` -- `/soleur:compound` refs (4)
- [ ] 4.2 Update `skills/deepen-plan/SKILL.md` -- `/soleur:plan`, `/soleur:work`, `/soleur:compound` refs
- [ ] 4.3 Update `skills/git-worktree/SKILL.md` -- `/soleur:review`, `/soleur:work` refs
- [ ] 4.4 Update `skills/brainstorm-techniques/SKILL.md` -- `/soleur:plan` refs
- [ ] 4.5 Update `skills/test-fix-loop/SKILL.md` -- `/soleur:work` ref
- [ ] 4.6 Update `skills/merge-pr/SKILL.md` -- `/soleur:compound` ref
- [ ] 4.7 Update `skills/xcode-test/SKILL.md` -- `/soleur:review` ref
- [ ] 4.8 Update `skills/file-todos/SKILL.md` -- `/soleur:review` ref

## Phase 5: Update Agents

- [ ] 5.1 Update `agents/engineering/research/learnings-researcher.md` -- `compound-docs` ref

## Phase 6: Update Documentation and Infrastructure

- [ ] 6.1 Update root `AGENTS.md` -- feature lifecycle, workflow protocol, command naming
- [ ] 6.2 Update `knowledge-base/overview/constitution.md` -- lines 48, 81, 90, 110
- [ ] 6.3 Update `plugins/soleur/AGENTS.md` -- command naming section
- [ ] 6.4 Update `plugins/soleur/README.md` -- workflow diagram, command table (-6 rows), skill table (+6, rename 2), counts
- [ ] 6.5 Update root `README.md` -- version badge (3.0.0), component counts
- [ ] 6.6 Update `docs/_data/skills.js` -- add 6 new skills, update 2 renamed
- [ ] 6.7 Update `docs/pages/getting-started.md` -- rewrite workflow section
- [ ] 6.8 Update `.claude-plugin/plugin.json` -- version 3.0.0, description counts
- [ ] 6.9 Update `CHANGELOG.md` -- 3.0.0 entry with migration guide
- [ ] 6.10 Update `.github/ISSUE_TEMPLATE/bug_report.yml` -- version placeholder

## Phase 7: Test and Verify

- [ ] 7.1 Run `bun test` -- all tests pass
- [ ] 7.2 Verify skill count = 52
- [ ] 7.3 Verify command count = 3
- [ ] 7.4 Grep for orphaned `/soleur:` references (only CHANGELOG.md historical)
- [ ] 7.5 Grep for orphaned `brainstorming` / `compound-docs` references (only CHANGELOG.md)
