# Tasks: fix cleanup-merged [gone] branches skip gh merge query (#8490)

Plan: `knowledge-base/project/plans/2026-09-21-fix-cleanup-merged-gone-branches-gh-query-plan.md`

## 1. Setup

- [ ] 1.1 Read `worktree-manager.sh:2785-2818` (set builders) and `:3050-3062` (merge-evidence guard).
- [ ] 1.2 Read A9/A10 arms and `mk_squash_merged_branch` in `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh`.

## 2. RED test

- [ ] 2.1 Add arm A14 after A13 (before `S.`): one fixture, two backdated branches with worktrees, both upstreams deleted + `fetch --prune --no-tags` ([gone]).
- [ ] 2.2 gh stub keyed on `--head`: `1` for `feat-a14-merged`, `0` otherwise; logs each head to `$TMP/a14-gh.log`; exit 64 on other call shapes.
- [ ] 2.3 Assertions A14a (merged reaped), A14b (`^SOLEUR_WORKTREE_REAPED branch=feat-a14-merged sha=[0-9a-f]{40} `), A14c (unmerged branch + worktree kept), A14d (`no merge evidence` skip line), A14e (both heads queried).
- [ ] 2.4 Raise `MIN_ASSERTIONS` by the number of added assertions.
- [ ] 2.5 Run the suite; confirm A14a/A14b/A14e RED against the unfixed script.

## 3. GREEN fix

- [ ] 3.1 Drop `$gone_branches` from the gh-loop exclusion at `worktree-manager.sh:~2809`; keep `$merged_branches`; add a #8490 comment; refresh the stale header comment.
- [ ] 3.2 Re-run `worktree-manager-cleanup-merged-no-worktree.test.sh`, `lease-protects-active.test.sh`, `orphan-reaper-honest-count.test.sh` — all exit 0.

## 4. Constraints

- [ ] 4.1 No edits to `plugins/soleur/skills/ship/SKILL.md` or `plugins/soleur/skills/postmerge/SKILL.md` (PR #8492).
- [ ] 4.2 PR body: `Closes #8490`.
