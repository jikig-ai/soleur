# Tasks: bot-opened weakness-digest PRs get real CI runs without manual approval

Plan: `knowledge-base/project/plans/2026-10-11-fix-bot-digest-pr-ci-runs-held-for-approval-plan.md`
Ref #9454 (item 4). Do not close or comment "canary closed" on #9454. Do not reopen or close 10019.

## Phase 1 - Guard first

- 1.1 Add `t_workflow_pr_identity` to `tests/scripts/test-weakness-miner.sh` (derived caller population with floor of 1, per-member checks, workflows-dir override, positive control and must-PASS non-canonical fixture).
- 1.2 Write its mutation battery (Guard Contract rows 1-10 plus harness rows H1 and H2); confirm it is RED on today's tree.
- 1.3 Keep it static (no network, no git fixtures).

## Phase 2 - Composite and caller

- 2.1 Edit `.github/actions/bot-pr-with-synthetic-checks/action.yml`: add `pr-token` input and `PR_TOKEN` env; refuse empty and refuse equal to `gh-token` at the top of the run step (before the no-change exit); run `gh pr create`, `gh pr edit` and `gh pr merge --squash --auto` under `GH_TOKEN="$PR_TOKEN"`; push under the App via the env-only extra header (pattern of `.github/scripts/bump-inngest-bootstrap-pin.sh` `git_remote`, GIT_TRACE* unset); keep check-runs on `gh-token`; update description. Do not touch earned-green, allowlist or off-main blocks. `bash -n` the extracted run body; no actionlint on action.yml.
- 2.2 Edit `.github/workflows/weakness-miner.yml`: job `if: github.ref == 'refs/heads/main'`, `environment: infra-privileged`, `timeout-minutes` 12, checkout `persist-credentials: false`, Doppler CLI install, mint step (narrow shape, installation 166065653, permissions contents+pull_requests write, repository soleur) after the miner step and before the composite, pass `pr-token`, workflow permissions `contents: read` + `checks: write`, fix header comment. No separate presence-check step (the mint composite refuses an empty token).
- 2.3 Add v4 entry to the composite `CHANGELOG.md`.

## Phase 3 - Governance gates

- 3.1 Census `tests/scripts/test-infra-privileged-tier-census.sh`: G7f caller count 3 to 4 with a dated comment; update any fixture row assuming three; diff the row list before and after.
- 3.2 Runbook `infra-credential-tiers-8209.md` Group 4: add `weakness-miner.yml::mine` row.
- 3.3 Read all three `.c4` files, edit `model.c4` `github -> doppler` prose (the consumer set and its follow-on sentence), regenerate the tracked `model.likec4.json`; run `c4-count-parity.test.sh` and c4 syntax/render tests.
- 3.4 ADR-232 dated amendment (2026-10-11, evidence-worded, states key-level exposure); ADR-241 amendment-log line. Leave ADR-270, ADR-032 and the canary-log runbook untouched.

## Phase 4 - Verify

- 4.1 Run the guard suite and mutation battery; run `test-weakness-miner.sh`, the census, `required-checks-canonical-parity.test.sh`, `lint-bot-synthetic-completeness.test.sh`, `c4-count-parity.test.sh`, `scripts/lint-guard-contract.py` on the plan.
- 4.2 `actionlint` on `weakness-miner.yml` only; `bash -n` on the extracted composite `run:` body; `lint-shell-trace-credential-refusal.test.sh` and `test-argv-bearer-sweep.sh` still green; `bash scripts/lint-orphan-test-suites.sh`.
- 4.3 PR body: `Ref #9454`, prose mention of the stall-watchdog issue 10019, no close keyword, no ADR-270-accepted claim.

## Phase 5 - Tracking issues

- 5.1 File: retire synthetic check-runs for App-authored bot PRs (re-evaluate 2026-11-01 or after two measured runs); fold in: lower-grant App for digest PRs, and a census of other workflows opening PRs with the workflow token.
- 5.2 File: `audit-bot-codeql-coverage.sh` author filter (`app/github-actions`) vs `app/soleur-infra` (relates to #3595).
- 5.3 Link both from the PR body as prose.

## Post-merge (carried by #9454 item 4)

- P.1 First real run that produces a PR (Sunday 2026-10-18 06:00 UTC cron, or `gh workflow run weakness-miner.yml --ref main` with a Monitor armed if the digest changed; "No changes to commit" means not evaluable): confirm `app-token` notice, PR author `app/soleur-infra`, zero `action_required` runs, CI `success` and every required context success, `added_to_merge_queue` by `soleur-infra[bot]` then `merge_group` runs, no stall issue within 90 minutes.
- P.2 If runs are still held although push, PR and auto-merge all ran as the App, stop and re-investigate.
- P.3 Post a facts-only comment on #9454; leave it open.
