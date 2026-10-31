# Tasks - feat-one-shot-post-merge-leftovers-npm-tally

Plan: `knowledge-base/project/plans/2026-10-31-fix-post-merge-leftovers-npm-oidc-diagnostics-and-tally-plan.md`
Draft PR: #11688. Use `Ref #11585` and `Ref #11633` in the PR body, never `Closes`.

## Phase 1 - npm Publish: self-diagnosing failure

- [ ] 1.1 RED first: extend `plugins/soleur/test/npm-publish-oidc.test.sh` with the `diagnose-on-failure` member, Guard 1 mutation rows (delete step, move before publish, drop `failure()`, vacuous dispatch, `continue-on-error` on publish, wrong step id in `if`, echo-only step, compliant superset) and the stubbed-`curl` Guard 2 cases (id-token missing / fetch failed, measured 401 body shape and 404, 2xx with a random per-run body string, 429/503, `::` log injection, request-URL join, leak-assertion mutant, stub-call-count floor, override env). Run it RED.
- [ ] 1.2 Add `id: publish` to the publish step in `.github/workflows/npm-publish.yml` (keep `npm publish --access public --ignore-scripts` byte-identical) and add the diagnose step with `if: failure() && steps.publish.outcome == 'failure'` running `bash .github/scripts/npm-oidc-diagnose.sh`; no credential keys in `env:`.
- [ ] 1.3 Create `.github/scripts/npm-oidc-diagnose.sh`: `set -uo pipefail` (no `-e`), `|| true` on every curl, refuse xtrace; fetch the id-token with `curl -G --data-urlencode audience=...` and `::add-mask::` it; replay the exchange POST (body to a temp file, deleted unread on 2xx); verdicts `id-token-missing`, `id-token-fetch-failed`, `exchange-ok`, `trusted-publisher-missing-or-mismatched` (401/403/404 only, with `status=`, `message=` if JSON, expected values, remediation line, runbook path), `registry-error` (anything else); every value printed via `say()` with a `key=` prefix and CR/LF stripped; `--connect-timeout 10 --max-time 20`, no retry flag; always exit 0.
- [ ] 1.4 Reword the publish failure hint to name `E404`, `ENEEDAUTH` and the runbook path; keep `exit 1`; the hint must not contain `NPM_TOKEN`, `_authToken`, `AUTH_TOKEN=` or `npm config set` (the `no-cred-wiring` member scans run bodies).
- [ ] 1.5 Add `.github/scripts/npm-oidc-diagnose.sh` to `AFFECTED_PLUGINS_SOLEUR_TEST_NPM_PUBLISH_OIDC_TEST_SH_PATHS` in `scripts/lib/test-affected-paths.sh`; update the `scripts/suite-durations.tsv` row only if the measured runtime exceeds it.
- [ ] 1.6 Create the runbook `knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md` (symptom table, reading `NPM_OIDC_VERDICT`, the single owner step and its verification, post-green steps, ADR-310 dissent fallback, no SSH).
- [ ] 1.7 Automation ladder (read-only, bounded; record each rung in `evidence.md`): (a) `npm trust list` with the stored token via `doppler run`; (b) Playwright MCP on `https://www.npmjs.com/package/@soleur/opencode/access` with a `playwright-attempt:` evidence line; (c) do not consume `NPM_RECOVERY_CODES` (decision row T-OP1).
- [ ] 1.8 Amend ADR-310 (`## Amendment 2026-10-31`); status stays `adopting`.
- [ ] 1.9 Run the gates by their own invocations: `actionlint`, `bash -n`, `shellcheck`, `bash plugins/soleur/test/npm-publish-oidc.test.sh`, `scripts/lint-orphan-test-suites.sh`, `lint-guard-contract.py`, `technical-ruling-gate.sh --branch`; stage new files before any check that reads `git ls-files`.

## Phase 2 - Infra Validation: verify and record

- [ ] 2.1 Record the green SHA/run URL for Infra Validation on main (`gh run list --workflow=infra-validation.yml --branch main --limit 5`).
- [ ] 2.2 If red again for the pin reason, report the known transient window and the open bot PR; do not edit bot-owned pins or add tolerance. Note the f532fb99d8 `cron-egress-nftables.test.sh` rc=124 as a one-off.

## Phase 3 - Tally: reconcile and fix

- [ ] 3.1 RED first: add Tests 30-34 to `plugins/soleur/scripts/pipeline-tally.test.sh` (init on `main` twice reports `default-branch-reset` with zero counts; detached `HEAD` does not reset; `--branch master`; `feat-main` and `main-x` unaffected and still `continued`; `show` on `main` carries the `note:` line while the `tally:` line is unchanged; stop-hook token parsing unaffected). Run RED.
- [ ] 3.2 Implement in `plugins/soleur/scripts/pipeline-tally.sh`: `T_BRANCH` in `_tally_paths`, `_tally_is_default_branch` (exact `main`/`master`), outcome `default-branch-reset` (after `repaired`, before `capped-reset`), counts-clearing arm, `show` note line, header docs.
- [ ] 3.3 Amend ADR-268 with the default-branch clause and the rejected alternatives.
- [ ] 3.4 Write `## Tally reconciliation` in `evidence.md`: branch ledger 19/2/2/4, merged body 19/1/2/4, `main-88d050` ledger 83/15/1/12 (mtime before the merge), sibling ledger sharing `ci_cycles=15`, 10 gh-observed pushed head SHAs, corrected line for #11622. Do not edit PR #11622.

## Phase 4 - Production state check (read-only, orchestrator-run)

- [ ] 4.1 Run the read-only counts query (command shape in the plan) through `doppler run -p soleur -c prd` with `DATABASE_URL_POOLER`; record counts against the 2026-10-30 baseline (1903 github drafts, 45 kb-drift drafts, 0 archived).
- [ ] 4.2 Run the Sentry Discover query for op `discard-send-race` (14d); record the count.
- [ ] 4.3 Record both in `evidence.md` under `## Production state check (read-only)`; if `archived` is still 0, say so and why it is expected.

## Phase 5 - Ship hygiene

- [ ] 5.1 Confirm the frozen migration is untouched (`git diff --quiet origin/main...HEAD -- apps/web-platform/supabase/migrations/181_messages_owner_draft_update.sql`) and that #10926 and issues #11628, #11629, #11630, #11655, #11656 are untouched.
- [ ] 5.2 Re-fetch and re-check ADR ordinals are unchanged (no new ADR is created; only amendments).
- [ ] 5.3 After merge, confirm the next npm Publish run prints `NPM_OIDC_VERDICT=` (`gh run view <id> --log | grep NPM_OIDC_VERDICT`); the leg stays red until #11633 lands.
- [ ] 5.4 File a deferred-scope issue (labels verified with `gh label list`) for the stale `ADR-309` ordinal in the `github -> npmRegistry` edge prose of `knowledge-base/engineering/architecture/diagrams/model.c4` (should read ADR-310); milestone from `knowledge-base/product/roadmap.md`.
