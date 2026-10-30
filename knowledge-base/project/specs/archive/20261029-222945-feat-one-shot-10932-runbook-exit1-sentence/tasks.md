# Tasks — feat-one-shot-10932-runbook-exit1-sentence

Plan: `knowledge-base/project/plans/2026-10-29-chore-runbook-exit1-sentence-header-table-plan.md`

## 1. Edit

- 1.1 Re-read `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`; locate the paragraph under "Restore exit codes — one operator action each" by content (`Its own header table does not`), not by line number.
- 1.2 Confirm on `origin/main` (`git grep -n "tracked on #10932" origin/main -- knowledge-base/engineering`) that the sentence is still stale.
- 1.3 Replace the sentence per the plan's After block; reflow "Codes consumed ..." inside the same paragraph. Leave the `1` table row and the line-477 "except exit 1" untouched.

## 2. Verify

- 2.1 Run the plan's Acceptance Criteria 1-4 commands (grep counts, diff scope, engine header row present, workflow `1)` arm present).
- 2.2 Run `tests/scripts/test-registry-d10-workflow-wiring.sh` (47/0), `tests/scripts/test-registry-pull-path-health.sh` (63/0), `tests/scripts/test-registry-restore-from-ghcr.sh` (98/0), each in its own Bash call; read `gate.log` before reporting a gate as running. If the local battery queues behind a sibling worktree, CI's required `test` context is the gate.
- 2.3 Confirm `git diff --name-only origin/main...HEAD` has no `scripts/` path and not `.github/workflows/apply-web-platform-infra.yml`.

## 3. Ship

- 3.1 Secret scan before every push. Never `git stash`; no `pgrep -f`.
- 3.2 PR #11557 body: `Ref #10932`, `Ref #9757` only. No Closes/Fixes/Resolves.
- 3.3 `gh pr merge 11557 --squash --auto` (no `--delete-branch`). Do not touch #11312, #11379, #10924; do not close #9757 or #10932. Known unrelated red: advisory `affected-index-ratchet`.
