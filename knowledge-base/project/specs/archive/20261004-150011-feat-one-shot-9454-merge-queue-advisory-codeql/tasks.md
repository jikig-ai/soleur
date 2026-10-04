# Tasks: adopt merge queue on main via advisory CodeQL (#9454)

Plan: `knowledge-base/project/plans/2026-10-03-feat-adopt-merge-queue-advisory-codeql-plan.md`

## Phase 0: Empirical gates

- 0.1 Write the coverage guard first (Phase 1.1), run it on the base branch, and confirm it is RED for `cla-check` and `cla-evidence` only.
- 0.2 Re-probe the `Analyze (*)` check-runs and the per-commit analyses on the current main sha (plan Phase 0.2, 0.3) and paste the output in the PR body.
- 0.3 Probe the `merge_queue` block against provider 6.12.1 in a scratch directory with no backend (plan Phase 0.4).

## Phase 1: RED tests and fixtures

- 1.1 Create `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` and fixtures under `plugins/soleur/test/fixtures/merge-group-coverage/` (Guard 1, 8 mutation rows, 3 harness rows).
- 1.2 Create `plugins/soleur/test/codeql-main-alert-gate.test.sh`, the `gh` shim and synthesized fixtures under `plugins/soleur/test/fixtures/codeql-main-alert-gate/` (Guard 3, 11 mutation rows, 4 harness rows).
- 1.2b Create `plugins/soleur/test/merge-queue-cla-verify.test.sh` (latest-run-per-name, missing context, bad `head_ref`, `gh` error rows).
- 1.3 Update `tests/scripts/test-audit-ruleset-bypass.sh`: replace T-mq-1 with the Guard 2 parity and CodeQL-absent gate; update T-rsc-2/3/5b/6/7 for 23 entries and no CodeQL row.
- 1.3b (Dropped at design-pass review: no committed destroy-guard fixture or T9/T10; the live apply plan is the authority for the single `required_check` removal.)
- 1.4 Extend `plugins/soleur/test/sync-pr-behind.test.sh`: queued PR gives `kind=queued`, no push; GraphQL failure gives non-zero `kind=gh`.
- 1.5 Run all four suites and confirm each is RED for the stated reason before any implementation edit.

## Phase 2: CLA synthetics and stall probe

- 2.1 Restore `.github/workflows/merge-queue-cla-synthetics.yml` from `git show 4439c23c39^:...` and add `scripts/merge-queue-cla-verify.sh`: verify the PR head's real `cla-check`/`cla-evidence` (PR number from a strictly validated `merge_group.head_ref`, base_ref main, latest run per name, no parent-of-candidate check because a SQUASH candidate has one parent, `--paginate`) and fail closed; run from a DEFAULT-branch checkout; keep `GITHUB_TOKEN`.
- 2.2 Restore `.github/workflows/merge-queue-stall-check.yml` with `STALL_THRESHOLD_MINUTES: '45'`, a `*/10` cron and an updated header (60-minute timeout).
- 2.3 Re-run `bash plugins/soleur/test/c4-count-parity.test.sh` and the workflow-inventory guards.

## Phase 3: Alert gate

- 3.1 Create `scripts/codeql-main-alert-gate.sh` (check-run wait, analyses-settled poll (one newest-first page filtered to the commit), severity filter, bot-authored open-issue dedupe as the definition of new, `codeql-gate-degraded` upsert, red iff it filed, fail closed, no alert-controlled text in issues or annotations, validated `sha`/`dry_run` inputs, bounded `gh`).
- 3.2 Create `.github/workflows/codeql-main-alert-gate.yml` (push to main plus dispatch with `sha` and `dry_run`; non-cancelling concurrency; least-privilege permissions).
- 3.3 Verify no workflow or script keys on the gate's run conclusion.

## Phase 4: Tooling queue-awareness and merge-flow docs

- 4.1 `plugins/soleur/scripts/sync-pr-behind.sh`: skip a queued PR (GraphQL `isInMergeQueue`), fail non-zero on a GraphQL error; update `--help` and the exit table.
- 4.2 CONDITIONAL: `plugins/soleur/lib/pr-merge-poll.ts` (and its test) only if the fence tests show `kind=queued` exit 0 is miscounted as a pushed sync.
- 4.3 Only if needed: `plugins/soleur/skills/merge-pr/SKILL.md` section 5.2 and, at most one sentence (<= 200 bytes net), `plugins/soleur/skills/ship/SKILL.md` Phase 7; run `python3 scripts/lint-skill-body-budget.py --base origin/main`.
- 4.4 `plugins/soleur/skills/drain-prs/SKILL.md` section 4: flip the conditional bullet to the active-queue bullet and add the dequeue arm (temp-ref CI via `gh run list --event merge_group`, merge `origin/main` locally and re-arm, one re-enqueue cap).
- 4.5 Verify `plugins/soleur/scripts/admin-merge-ready.sh` and `plugins/soleur/skills/ship/scripts/battery-owed.sh` against a rules shape with `merge_queue` and without a CodeQL context; edit only if verification fails or a comment is now false.

## Phase 5: Terraform and lockstep

- 5.1 `infra/github/ruleset-ci-required.tf`: remove the CodeQL `required_check`, add the `merge_queue` block (SQUASH, ALLGREEN, 1/1, wait 0, build 2, timeout 60), rewrite the revert comments; keep `variable "codeql_integration_id"` with a comment.
- 5.2 `scripts/ci-required-ruleset-canonical-required-status-checks.json`: drop the CodeQL row.
- 5.3 `scripts/create-ci-required-ruleset.sh`: DR skeleton gains the queue rule with all seven REST parameters and a sync guard, drops CodeQL, keeps `bypass_actors` and `conditions`; restore the DR verification `jq`; document the emergency path as a PUT of a queue-less payload to the existing ruleset id (no script knob).
- 5.4 Comments in `scripts/lib/canonicalize-required-status-checks.sh`, `scripts/required-checks.txt`, `.github/actions/bot-pr-with-synthetic-checks/action.yml`.
- 5.5 Put a line that is exactly `[ack-destroy]` in the BODY of one commit message (not a subject) and verify it in the final squash message before merging.

## Phase 6: Records

- 6.1 ADR-270 via `soleur:architecture` (status `adopting`; re-verify the ordinal across all `origin/*` refs before merge); ADR-032 amendment pointer.
- 6.2 `infra/github/README.md` merge-queue section; `.github/workflows/scheduled-terraform-drift.yml` comment; `.github/workflows/codeql-1537-revisit-watch.yml` header; `knowledge-base/engineering/operations/runbooks/codeql-bot-coverage.md`.
- 6.3 Legal records: `knowledge-base/legal/article-30-register.md` PA12, `knowledge-base/legal/compliance-posture.md` line 59, one-line CLO determination in the 2026-08-17 cla-evidence ruling.
- 6.4 C4: read all three `.c4` files in full and record the "no C4 impact" citation; run `c4-count-parity`.

## Phase 7: Ship, apply and canary

- 7.1 Elevated risk-tier review; PR body first line states merge applies `infra/github` to production; `Ref #9454`, `Ref #4856`, `Ref #5840` (close #9454 and #4856 with canary evidence in 7.5).
- 7.2 Present the exact consequence and wait for the per-command go-ahead; do not arm auto-merge.
- 7.3 Confirm the apply plan shows exactly one `required_check` removal, then merge with `[ack-destroy]`; watch the apply run; run the post-merge verification table; dispatch the gate (`dry_run=true`) and the stall check.
- 7.4 Canary human PR through the queue, canary bot PR (decision rule if `GITHUB_TOKEN`-armed entries stall), MANDATORY admin bypass, list and confirm PRs armed before the apply; record enqueue-to-merge minutes and the observed `mergeStateStatus`.
- 7.5 Flip ADR-270 to `accepted`; close #9454 and #4856 with evidence; leave #5840 open. On any failure, execute the rollback in the plan and reopen both issues.
