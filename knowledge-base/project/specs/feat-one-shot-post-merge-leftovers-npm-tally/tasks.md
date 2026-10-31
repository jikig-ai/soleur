# Tasks - feat-one-shot-post-merge-leftovers-npm-tally

Plan: `knowledge-base/project/plans/2026-10-31-fix-post-merge-leftovers-npm-oidc-diagnostics-and-tally-plan.md`
Draft PR: #11688. Use `Ref #11585` and `Ref #11633` in the PR body, never `Closes`.

## Phase 1 - npm Publish: self-diagnosing failure

- [ ] 1.1 RED first (details in the plan's Guard Contract and Test implementation notes): extend `plugins/soleur/test/npm-publish-oidc.test.sh` with the member-scoped `diagnose-on-failure` probe (`&&` conjunct-set equality on the `if:`), Guard 1 rows 1-9 via `expect_red_member`, and the stubbed-`curl` Guard 2 cases parameterized on `$DIAG_SCRIPT` (sandbox-copy mutants with placement assertions and pristine GREEN controls, argv-log assertions, `env -i` isolation, injection allow-list, classification table). Route every new assertion through the `CASES`-counting helpers, raise the `>= 20` floor, print `NPM_PUBLISH_OIDC_SUITE=PASS` as the last line only when `FAIL == 0`. Run it RED.
- [ ] 1.2 Add `id: publish` to the publish step in `.github/workflows/npm-publish.yml` (keep `npm publish --access public --ignore-scripts` byte-identical) and add the diagnose step with `if: failure() && steps.publish.outcome == 'failure'` running `bash .github/scripts/npm-oidc-diagnose.sh`; no credential keys in `env:`.
- [ ] 1.3 Create `.github/scripts/npm-oidc-diagnose.sh` per plan task 1.3: bearers only via curl stdin config (charset-validated, `--disable`, `--noproxy '*'`), `set +x`/no xtrace, `set -uo pipefail`, `curl -G --data-urlencode audience=...`, body in a `umask 077` temp dir removed by trap and never read on 2xx, verdicts `id-token-missing` / `id-token-fetch-failed` / `exchange-ok` / `trusted-publisher-missing-or-mismatched` (401/403/404, worded "most likely") / `registry-error`, `say()` with `key=` prefix and C0/DEL/U+2028/U+2029 stripped, static-text `::error`, timeouts, no retry, always exit 0.
- [ ] 1.4 Reword the publish failure hint to name `E404`, `ENEEDAUTH` and the runbook path; keep `exit 1`; the hint must not contain `NPM_TOKEN`, `_authToken`, `AUTH_TOKEN=` or `npm config set` (the `no-cred-wiring` member scans run bodies).
- [ ] 1.4a Add `NPM_OIDC_VERDICT=not-exercised (...)` to the `npm view ... already published` early-exit branch (no forbidden tokens in the line).
- [ ] 1.5 Add `.github/scripts/npm-oidc-diagnose.sh` to `AFFECTED_PLUGINS_SOLEUR_TEST_NPM_PUBLISH_OIDC_TEST_SH_PATHS` in `scripts/lib/test-affected-paths.sh`; update the `scripts/suite-durations.tsv` row only if the measured runtime exceeds it.
- [ ] 1.6 Create the runbook `knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md` (symptom table, reading `NPM_OIDC_VERDICT`, the single owner step, first-green-run checklist incl. `gh workflow run npm-publish.yml` and `npm trust list`, skipped versions not backfilled, `not-exercised` is not proof, residual of the 2xx replay, pointers to #11633 and ADR-310, no SSH).
- [ ] 1.7 Automation ladder (read-only up to the authorization gate; record each rung in `evidence.md`): (a) `npm trust list` with the stored token via `doppler run`; (b) Playwright MCP on the package access page with a `playwright-attempt:` line - navigate and record only; the entry-creating click needs the owner's explicit authorization in the work session (T-OP1); (c) do not consume `NPM_RECOVERY_CODES`.
- [ ] 1.8 Amend ADR-310 (`## Amendment 2026-10-31`); status stays `adopting`.
- [ ] 1.9 Run the gates by their own invocations: `actionlint`, `bash -n`, `shellcheck`, `bash plugins/soleur/test/npm-publish-oidc.test.sh`, `scripts/lint-orphan-test-suites.sh`, `lint-guard-contract.py`, `technical-ruling-gate.sh --branch`; stage new files before any check that reads `git ls-files`.

## Phase 2 - Infra Validation: verify and record

- [ ] 2.1 Record the green SHA/run URL for Infra Validation on main (`gh run list --workflow=infra-validation.yml --branch main --limit 5`).
- [ ] 2.2 If red again for the pin reason, report the known transient window and the open bot PR; do not edit bot-owned pins or add tolerance. Note the f532fb99d8 `cron-egress-nftables.test.sh` rc=124 as a one-off.

## Phase 3 - Tally: reconcile and fix

- [ ] 3.1 RED first: add Tests 30-34 to `plugins/soleur/scripts/pipeline-tally.test.sh` (init on `main` twice reports `default-branch-reset` with zero counts; precedence rows `fresh`/`reset`/`repaired`/`default-branch-reset`/capped-raised; exact-line asserts; `new_repo_on` and `cf_path_for` helpers; detached `HEAD` (real commit) does not reset; `--branch master`; `feat-main` and `main-x` unaffected and still `continued`; `show` on `main` carries the `note:` line while the `tally:` line is unchanged; stop-hook token parsing unaffected). Run RED.
- [ ] 3.2 Implement in `plugins/soleur/scripts/pipeline-tally.sh`: `T_BRANCH` in `_tally_paths`, `_tally_is_default_branch` (exact `main`/`master`), outcome `default-branch-reset` (after `repaired`, before `capped-reset`), counts-clearing arm, `show` note line, header docs.
- [ ] 3.3 Amend ADR-268 with the default-branch clause and the rejected alternatives.
- [ ] 3.4 Write `## Tally reconciliation` in `evidence.md` (delivered to the live PR body as in 4.3): branch ledger 19/2/2/4, merged body 19/1/2/4, `main-88d050` ledger 83/15/1/12 (mtime before the merge), sibling ledger sharing `ci_cycles=15`, 10 gh-observed pushed head SHAs, corrected line for #11622. Do not edit PR #11622.

## Phase 4 - Production state check (read-only, orchestrator-run)

- [ ] 4.1 Run the read-only counts query (command shape in the plan) through `doppler run -p soleur -c prd` with `DATABASE_URL_POOLER`; record counts against the 2026-10-30 baseline (1903 github drafts, 45 kb-drift drafts, 0 archived).
- [ ] 4.2 Run the Sentry Discover query for op `discard-send-race` (14d) with the bearer on curl's stdin config (command shape in the plan); record the count.
- [ ] 4.3 Record both in `evidence.md` under `## Production state check (read-only)`; if `archived` is still 0, say so and why it is expected. After `ship` writes the PR body, append the four evidence sections to the live PR #11688 body (idempotent read-modify-write) and read it back to confirm each heading (`ship` neither reads nor keeps `evidence.md`).

## Phase 5 - Ship hygiene

- [ ] 5.1 Confirm the frozen migration is untouched (`git diff --quiet origin/main...HEAD -- apps/web-platform/supabase/migrations/181_messages_owner_draft_update.sql`) and that #10926 and issues #11628, #11629, #11630, #11655, #11656 are untouched.
- [ ] 5.2 Re-fetch and re-check ADR ordinals are unchanged (no new ADR is created; only amendments).
- [ ] 5.3 After merge, confirm the next npm Publish run prints `NPM_OIDC_VERDICT=` (`gh run view <id> --log | grep NPM_OIDC_VERDICT`); the leg stays red until #11633 lands.
- [ ] 5.4 File a deferred-scope issue (labels verified with `gh label list`) for the stale `ADR-309` ordinal in the `github -> npmRegistry` edge prose of `knowledge-base/engineering/architecture/diagrams/model.c4` (should read ADR-310); milestone from `knowledge-base/product/roadmap.md`.
