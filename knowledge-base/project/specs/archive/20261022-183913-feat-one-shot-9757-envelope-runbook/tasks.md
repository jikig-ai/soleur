# Tasks: commit the delegated-merge 10789 envelope runbook

Plan: `knowledge-base/project/plans/2026-10-22-docs-delegated-merge-10789-envelope-runbook-plan.md`
Umbrella #9757 stays open (`Ref #9757` only).

## Phase 1 - Bring the file in

- 1.1 Copy `/var/tmp/soleur-9663/delegated-merge-10789-envelope.md` to `knowledge-base/engineering/operations/runbooks/delegated-merge-10789-envelope.md` (fallback: cherry-pick `f0fe42d2b9`).
- 1.2 `sha256sum` the new path; it must equal `1076fca70602fbdf2e6abb81fee73d46186afd4338ac0b4ea0214dafedb54504`. Mismatch is a hard stop; never edit the file.

## Phase 2 - Lint exemption

- 2.1 Add the 10789 path to `.markdownlintignore` directly after the 10663 entry (line 50).
- 2.2 Run markdownlint; confirm the file is not reported; re-run the sha256.

## Phase 3 - Commit, PR, merge

- 3.1 Pathspec commit (runbook + `.markdownlintignore`); no `git add -A`/`.`, no stash.
- 3.2 After any merge of `main`, recompute `PJ_TRIPLES` (currently 292) per `.claude/hooks/grep-q-pipe-guard.test.sh`; edit the pin only if it moved. Long suites detached under `/var/tmp`.
- 3.3 Open the PR with `Ref #9757` (no closing keyword); `gh pr merge <N> --squash --auto`, never `--admin`.
- 3.4 If the merge is held in an attended run, ask ONE plain delegation question per `operator-holds.md` section 3.

## Phase 4 - Clean up

- 4.1 Confirm the runbook is committed on this branch and the PR exists.
- 4.2 `git -C .worktrees/deleg-env-10789 status --short` is empty.
- 4.3 `git worktree remove .worktrees/deleg-env-10789`, then `git branch -D deleg-env-10789`.
