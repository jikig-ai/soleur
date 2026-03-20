# Tasks: fix bare-repo git pull session startup

## Phase 1: Core Fixes

- [ ] 1.1 Update `plugins/soleur/skills/work/SKILL.md` Option A -- replace `git pull origin [default_branch]` with `git fetch origin <default_branch>` + `git checkout -b ... origin/<default_branch>`
- [ ] 1.2 Update `plugins/soleur/skills/one-shot/SKILL.md` Step 0b -- replace "pull latest" prose with explicit `git fetch` + `git checkout -b ... origin/main` commands
- [ ] 1.3 Verify no other skill SKILL.md files contain `git pull` instructions (grep check)

## Phase 2: Prevention

- [ ] 2.1 Add "Never use git pull" rule to `knowledge-base/project/constitution.md` Architecture > Never section
- [ ] 2.2 Update AGENTS.md session-start instruction (line 31) to add bare-root fallback and explicit "never git pull" guidance

## Phase 3: Verification

- [ ] 3.1 Grep all `plugins/soleur/` for remaining `git pull` usage -- verify only campaign-calendar CI path remains
- [ ] 3.2 Verify `git fetch origin main` + `origin/main` branching works from bare repo root context
- [ ] 3.3 Run compound (`skill: soleur:compound`)
