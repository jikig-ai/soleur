# Tasks: feat-one-shot-2258-2264

Source plan: `knowledge-base/project/plans/2026-04-15-fix-rule-metrics-aggregator-pr-pattern-and-prune-backfill-plan.md`

## 0. Pre-flight (deepening Phase 0)

- [ ] 0.1 `gh api repos/jikig-ai/soleur --jq '.allow_auto_merge'` returns `true`. If `false`, enable before merging.
- [ ] 0.2 `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context'` returns exactly `test`, `dependency-review`, `e2e`. If different, update synthetic check-run names in 2.2.6.
- [ ] 0.3 `gh api repos/jikig-ai/soleur/rulesets/13304872 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[]'` returns `cla-check` with `integration_id: 15368`.

## 1. Setup

- [ ] 1.1 Confirm worktree is on branch `feat-one-shot-2258-2264` and remote is set.
- [ ] 1.2 Re-read `.github/workflows/rule-metrics-aggregate.yml` and `.github/workflows/scheduled-weekly-analytics.yml` for line-level reference.

## 2. Workflow conversion (#2258)

- [ ] 2.1 Edit `.github/workflows/rule-metrics-aggregate.yml`: expand `permissions:` block to include `checks: write`, `pull-requests: write`, `statuses: write` (keep existing `contents: write`). Do NOT add `actions: write` (least-privilege; this workflow dispatches no other workflows).
- [ ] 2.2 Replace the `Commit rule-metrics.json if changed` step with `Create PR with rule-metrics snapshot` step modelled on `scheduled-weekly-analytics.yml` lines 68–119.
  - [ ] 2.2.1 Use git author email `41898282+github-actions[bot]@users.noreply.github.com`.
  - [ ] 2.2.2 Branch name: `ci/rule-metrics-$(date -u +%Y-%m-%d)`.
  - [ ] 2.2.3 Commit message: `chore(rule-metrics): weekly aggregate`.
  - [ ] 2.2.4 PR title: `chore(rule-metrics): weekly aggregate $(date -u +%Y-%m-%d)`.
  - [ ] 2.2.5 PR body: short single-line `--body` referencing the source script and pointing reviewers at the diff (no heredoc).
  - [ ] 2.2.6 Post four synthetic **Check Runs** (NOT commit Statuses) via `gh api repos/${{ github.repository }}/check-runs`: `test`, `cla-check`, `dependency-review`, `e2e`, all `status=completed conclusion=success`. Use `GH_TOKEN: ${{ github.token }}` (required to satisfy `cla-check` `integration_id: 15368`).
  - [ ] 2.2.7 Final `gh pr merge "$BRANCH" --squash --auto`.
  - [ ] 2.2.8 Early-exit with `exit 0` if `git diff --cached --quiet` (no changes path).
- [ ] 2.3 Update workflow header comment: replace "commits when materially changed" with "opens a PR when materially changed" and link issue #2258.
- [ ] 2.4 Leave the existing `Email notification (failure)` step untouched.
- [ ] 2.5 Verify no left-aligned heredocs and no multi-line `--body` args (per `hr-in-github-actions-run-blocks-never-use`).

## 3. Backfill script removal (#2264)

- [ ] 3.1 `git rm scripts/backfill-rule-ids.py`
- [ ] 3.2 `git rm tests/scripts/test_backfill_rule_ids.py`
- [ ] 3.3 Edit `scripts/test-all.sh`: remove the line `run_suite "tests/scripts/backfill-rule-ids" python3 -m unittest tests.scripts.test_backfill_rule_ids`.
- [ ] 3.4 Confirm the `run_suite "tests/scripts/lint-rule-ids" ...` line is preserved.
- [ ] 3.5 `grep -rn "backfill-rule-ids\|test_backfill_rule_ids" --exclude-dir=.git --exclude-dir=node_modules .` — only doc/plan references should remain.

## 4. Local verification

- [ ] 4.1 `bash scripts/test-all.sh 2>&1 | tail -n 40` — passes; suite count drops by exactly 1.
- [ ] 4.2 `python3 -m unittest tests.scripts.test_lint_rule_ids` standalone pass.
- [ ] 4.3 `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-15-*.md knowledge-base/project/specs/feat-one-shot-2258-2264/*.md`.
- [ ] 4.4 Optional: `actionlint .github/workflows/rule-metrics-aggregate.yml` if installed.

## 5. Ship

- [ ] 5.1 Run `skill: soleur:compound` to capture any learnings.
- [ ] 5.2 Commit on `feat-one-shot-2258-2264`. Suggested message: `fix(rule-metrics): use PR-based commit pattern; remove backfill migration`.
- [ ] 5.3 Push branch.
- [ ] 5.4 Open PR with body containing `Closes #2258` and `Closes #2264` (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] 5.5 Set semver label (likely `version:patch` — CI/dead code, no behaviour change for users).
- [ ] 5.6 `gh pr merge <N> --squash --auto`. Poll until MERGED via Monitor tool (per `hr-never-use-sleep-2-seconds-in-foreground`).

## 6. Post-merge verification

- [ ] 6.1 `gh workflow run rule-metrics-aggregate.yml` to dispatch one run.
- [ ] 6.2 Poll `gh run list --workflow=rule-metrics-aggregate.yml --limit 1 --json status,conclusion,databaseId` via Monitor tool until `completed`.
- [ ] 6.3 If `success` and a PR was opened: confirm it auto-merged and `knowledge-base/project/rule-metrics.json` updated on main.
- [ ] 6.4 If `success` with no PR (no material change): confirm log shows the "No changes to commit" path.
- [ ] 6.5 If `failure`: investigate immediately (per `hr-when-a-command-exits-non-zero-or-prints`); do not close issues until green.
- [ ] 6.6 Run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`.
