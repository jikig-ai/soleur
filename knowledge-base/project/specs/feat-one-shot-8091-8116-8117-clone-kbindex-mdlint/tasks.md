# Tasks: feat-one-shot-8091-8116-8117-clone-kbindex-mdlint

TDD order is load-bearing. Do not implement a GREEN edit before its RED tests fail.

## Phase 1: Setup

- [ ] 1.1 Confirm CWD is the feature worktree and branch is `feat-one-shot-8091-8116-8117-clone-kbindex-mdlint`.
- [ ] 1.2 Reproduce the depth-1 merge-base failure against a synthesized file:// repo (the Phase 2 fixture shape), not against the live origin.

## Phase 2: #8117 markdown-lint gc race

- [ ] 2.1 RED: in `scripts/markdown-lint.test.sh` `build_sandbox`, assert `git config --get gc.auto` is `0` before `cp -a`. Confirm the suite dies on origin/main.
- [ ] 2.2 GREEN: after `git init -q` in `build_sandbox`, run `git config gc.auto 0` (before add/commit).
- [ ] 2.3 Confirm `grep -c 'gc.auto' scripts/markdown-lint.test.sh` ≥ 1 and `bash scripts/markdown-lint.test.sh` exits 0.

## Phase 3: #8091 hosted ship merge-base

- [ ] 3.1 RED: add `plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh` (SUITE_GLOBS already includes `plugins/soleur/test/*.test.sh`):
  - synthesize main with ≥3 commits and a branch from commit 1
  - `git clone --depth=1`, checkout the branch
  - assert `git merge-base origin/main HEAD` fails
  - run `git fetch --unshallow origin` then assert merge-base succeeds and `git status --porcelain` is empty
- [ ] 3.2 RED: add source-shape anchors in `apps/web-platform/test/server/inngest/event-ship-merge.test.ts` for `--unshallow` and `merge-base`.
- [ ] 3.3 GREEN: in `event-ship-merge.ts` `checkout-pr`, after successful `gh pr checkout`:
  - `spawnSimple("git", ["fetch", "--unshallow", "origin"], { cwd })`
  - exit 0 continue; non-zero whose stderr contains `complete repository` continue; other non-zero throw redacted
  - `spawnSimple("git", ["merge-base", "origin/main", "HEAD"], { cwd })`; non-zero throw
  - `logger.info({ fn, prNumber, mergeBaseOk: true }, ...)`
- [ ] 3.4 Do not edit `_cron-claude-eval-substrate.ts` clone `"--depth=1"`.
- [ ] 3.5 Confirm `git grep -cE -- '--deepen|--unshallow' apps/web-platform/server/inngest/functions/event-ship-merge.ts` ≥ 1.

## Phase 4: #8116 DIRTY-but-locally-clean

- [ ] 4.1 RED: `pr-merge-poll.test.ts` — `shouldResyncBeforePoll("DIRTY")` true; CLEAN still false.
- [ ] 4.2 RED: `plugins/soleur/test/sync-pr-behind.test.sh` — CLEAN no-op; BEHIND clean merge-tree syncs; DIRTY merge-tree rc=0 syncs; DIRTY merge-tree rc≠0 exits 6.
- [ ] 4.3 RED: `ship-phase-7-poll-fixtures.test.sh` — scenario 4 overrides `git merge-tree` to rc=1 and still expects `[ship.phase7.dirty]`; add 4b DIRTY + merge-tree rc=0 expects auto-sync, not dirty-exit.
- [ ] 4.4 GREEN: `shouldResyncBeforePoll` true for BEHIND or DIRTY.
- [ ] 4.5 GREEN: `sync-pr-behind.sh` treats `*BEHIND*` or `*DIRTY*` as sync-needed; fetch; `git merge-tree --write-tree origin/main HEAD`; rc=0 merge --no-edit + push; rc≠0 exit 6. Keep `[pr-behind-sync]` / `auto-sync` stdout tokens.
- [ ] 4.6 GREEN: Phase 7 poll DIRTY arm in `ship/SKILL.md` and `merge-pr/SKILL.md`: merge-tree rc=0 → set `s=OPEN BEHIND` and fall through to the existing BEHIND auto-sync (counts against `MAX_BEHIND_SYNCS`); rc≠0 → existing dirty exit. Admin-hatch stays BEHIND-only.
- [ ] 4.7 Confirm `grep -c DIRTY plugins/soleur/scripts/sync-pr-behind.sh` ≥ 1 and poll-fixture mirror parity still holds.

## Phase 5: Testing

- [ ] 5.1 `bash scripts/markdown-lint.test.sh`
- [ ] 5.2 `bash plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh`
- [ ] 5.3 `bash plugins/soleur/test/sync-pr-behind.test.sh`
- [ ] 5.4 `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`
- [ ] 5.5 `bun test plugins/soleur/test/pr-merge-poll.test.ts`
- [ ] 5.6 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/event-ship-merge.test.ts`
- [ ] 5.7 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
