# Tasks: fix-worktree-manager-archive-stamp-format

Plan: `knowledge-base/project/plans/2026-09-28-fix-worktree-manager-archive-stamp-format-plan.md`
Issue: #9091

## Phase 1: Setup

- [ ] 1.1 Confirm the two stamp sites: `grep -n 'date +' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` shows the dashed literal only at `archive_kb_files`'s `ts=` (~line 2484) and `archive_name=` (~line 3333).

## Phase 2: Core Implementation

- [ ] 2.1 In `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`, change `archive_name="$(date +%Y-%m-%d-%H%M%S)-$safe_branch"` (~line 3333, spec-archive block of `cleanup_merged_worktrees`) to `date +%Y%m%d-%H%M%S`.
- [ ] 2.2 In the same file, change `ts="$(date +%Y-%m-%d-%H%M%S)"` inside `archive_kb_files` (~line 2484) to `date +%Y%m%d-%H%M%S` — this site covers `brainstorms/archive` and `plans/archive` entries (callers at ~lines 3349–3350).
- [ ] 2.3 Do NOT touch `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` and do NOT rename any existing dashed entries under `knowledge-base/project/{specs,plans,brainstorms}/archive/` (forward-only).

## Phase 3: Testing

- [ ] 3.1 Extend `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh`: in the A3 must-PASS reap arm (or an adjacent arm), add fixture `mkdir -p "$A3/clone/knowledge-base/project/specs/feat-a3-reapme"` and a `knowledge-base/project/plans/*a3-reapme*` file before `run_reaper`, using `assert_fixture_dir` per suite convention.
- [ ] 3.2 Assert the produced `specs/archive/` entry basename matches `^[0-9]{8}-[0-9]{6}-feat-a3-reapme$` AND a produced `plans/archive` (or `brainstorms/archive`) entry basename matches `^[0-9]{8}-[0-9]{6}-` — existence required, never a vacuous pass.
- [ ] 3.3 Verify `MIN_ASSERTIONS` floor still satisfied (it is a floor; added rows only raise `ASSERTED`).
- [ ] 3.4 Run `bash plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh` — exits 0 with its pass line.
- [ ] 3.5 Verify `grep -c 'date +%Y-%m-%d-%H%M%S' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` prints `0`.
