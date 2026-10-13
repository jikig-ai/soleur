# Tasks: fix bare-repo git pull session startup

## Phase 1: Core Fixes

- [ ] 1.1 Update `plugins/soleur/skills/work/SKILL.md` -- remove Option A (`git pull` + `git checkout -b`), make worktree-manager.sh the sole branch creation method (current Option B becomes the only path)
- [ ] 1.2 Update `plugins/soleur/skills/one-shot/SKILL.md` Step 0b -- replace "pull latest" + implicit `git checkout -b` with `worktree-manager.sh --yes create`
- [ ] 1.3 Verify no other skill SKILL.md files contain `git pull` or `git checkout -b` instructions that run from bare context (grep check -- campaign-calendar CI path is acceptable)

## Phase 2: Prevention

- [ ] 2.1 Add "Never use git pull or git checkout" rule to `knowledge-base/project/constitution.md` Architecture > Never section -- covers both commands since both require a working tree
- [ ] 2.2 Update AGENTS.md session-start instruction (line 31) to add bare-root worktree creation guidance and explicit prohibition of `git pull`/`git checkout` from bare root

## Phase 3: Verification

- [ ] 3.1 Grep all `plugins/soleur/` for remaining `git pull` and `git checkout -b` usage -- verify only campaign-calendar CI path and worktree-manager.sh internal (IS_BARE-guarded) paths remain
- [ ] 3.2 Run compound (`skill: soleur:compound`)
