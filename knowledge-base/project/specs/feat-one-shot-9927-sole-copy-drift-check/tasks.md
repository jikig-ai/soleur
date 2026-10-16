# Tasks: sole-copy protection drift check (#9927 item 9)

Plan: knowledge-base/project/plans/2026-10-16-feat-sole-copy-protection-drift-check-plan.md

PR body: `Ref #9927` only (no closing keyword); after every body edit assert `closingIssuesReferences` is `[]`.

## Phase 1: RED first

- [ ] 1.1 Create `plugins/soleur/test/sole-copy-drift-check.test.sh`: one python3 -I extractor for run/env/if of job `sole-copy-protection-check` by job id and step id (`probe`, `tf_commit`, `file_finding`, `file_unreadable`, `clear`, `notify`, `gate`), an expression resolver (an unresolvable reference is FATAL), the heartbeat suite's GitHub-expression interpreter, and the outer/inner conservation structure with a floor at the realized count
- [ ] 1.2 Build the stubs: `curl` (models `-o`, `-w`, `--config -`, applies the `name=` filter, refuses unmodelled argv), `doppler` (one call, project and config env required), stateful `gh` (in-memory issue store, rejects unknown flags), shared `$SEQ` log; run bodies under `env -u BASH_ENV ... bash --noprofile --norc -e` with a scratch `GITHUB_WORKSPACE` holding a `cmp`-verified copy of `scripts/lib/bearer-curl.sh`
- [ ] 1.3 Add the verdict case table (Guard 1 rows 1, 3, 7, 8, 9) comparing the whole `$GITHUB_OUTPUT` (exact key set, one line each) and the exit code per case
- [ ] 1.4 Add the id-pin, name-filter, web-1-id, reorder, fallback-token and print-leakage rows (Guard 1 rows 4, 5, 6, 11)
- [ ] 1.5 Add the own-dispatch, grace-boundary, ordered-sequence and partial-failure rows (Guard 1 rows 2, 14, 15) and harness rows H1-H3 with the must-PASS non-canonical inputs
- [ ] 1.6 Add the real-`.tf` case with an independent Python derivation and the five mutants; the rendered-filer-body row; the static job-shape rows; the pins (Doppler CLI version and sha256 equal the loader's, `VOLUME_ID_PIN` equals ADR-282 and the postmerge skill, headings and step O5 resolve)
- [ ] 1.7 Add the pin to `token-drift-workflow-causes.test.sh` that this job's steps are in the R1-R5 scanned population
- [ ] 1.8 Run the suite against the tree without the job; confirm every row is RED for the named reason

## Phase 2: GREEN the job

- [ ] 2.1 Insert job `sole-copy-protection-check` after `heartbeat-live-reconcile` and before the rung-2 comment block in `.github/workflows/scheduled-terraform-drift.yml` (no edit anywhere else in the file)
- [ ] 2.2 Steps `checkout` (`persist-credentials: false`), `doppler_cli` (the loader's pinned tarball plus sha256), `tf_commit` (commits API, `GH_TOKEN` here and in the filers only)
- [ ] 2.3 Probe: pinned id constant, awk `.tf` derivation with the name shape check before any URL, `HCLOUD_TOKEN_READONLY` with no fallback and `bc_ok_var` pre-guard, three-attempt request loop, jq container and pagination checks, id pin, verdict `case`, validated single-line outputs
- [ ] 2.4 Finding filer (lifted-outside-terraform, volume-not-found): exact-title dedupe, one comment per run, public-safe body, milestone-less retry
- [ ] 2.5 Could-not-perform filer: the complement set, two titles, one comment per run
- [ ] 2.6 Clear step, notify step (`notify-ops-email`, `continue-on-error`), gate step (`::error::` line, exit 1 on any non-clean or empty verdict)
- [ ] 2.7 `bash -n` each extracted body; YAML parses; R1-R5 stays green

## Phase 3: registries and docs

- [ ] 3.1 `python3 scripts/regenerate-shard-manifest.py --incremental --write` for the suite registration
- [ ] 3.2 Add `AFFECTED_PLUGINS_SOLEUR_TEST_SOLE_COPY_DRIFT_CHECK_TEST_SH_PATHS` in `scripts/lib/test-affected-paths.sh`; quote the consuming line
- [ ] 3.3 Group 3 row (Tier A) in `infra-credential-tiers-8209.md`
- [ ] 3.4 ADR-282 addendum (grace, id pin, residuals, check gap) plus the residual "Detection of lifted protection is generic" edit; status stays accepted
- [ ] 3.5 One sentence in `inngest-luks-cutover-6894.md` "No drift check by log search"; leave the section-5c one-liner block untouched
- [ ] 3.6 Re-read the three `.c4` files; record "no C4 impact" with the enumeration or add one clause
- [ ] 3.7 File three follow-up issues with a roadmap milestone: Sentry check-in for the job, shared pinned Doppler-install step, web-1 `workspaces_luks` check

## Phase 4: verify (targeted only)

- [ ] 4.1 `sole-copy-drift-check`, `token-drift-workflow-causes`, `terraform-drift-step-order`, `terraform-drift-sentry-leg`, `heartbeat-reconcile-issue-step` suites
- [ ] 4.2 `scripts/alarm-issue-filing-guard.test.sh` (highwater must not increase), `tests/scripts/test-argv-bearer-sweep.sh`, `tests/scripts/test-infra-privileged-tier-census.sh`, `.github/actions/infra-credentials/infra-credentials.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`
- [ ] 4.3 `python3 scripts/lint-guard-contract.py`; `bun test plugins/soleur/test/terraform-target-parity.test.ts`; registry and orphan census for the new suite
- [ ] 4.4 No Hetzner, Doppler or production call made at any point

## Phase 5: ship

- [ ] 5.1 PR body `Ref #9927`, assert `closingIssuesReferences` is `[]` after every edit
- [ ] 5.2 Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`
- [ ] 5.3 Parked drafts (#10405, plaintext-volume resolver PR) untouched
- [ ] 5.4 Note the known unrelated red "Tenant integration (dev-Supabase)" on `test/server/action-sends-worm.test.ts`; do not fix
- [ ] 5.5 Comment on #9927: item 9 built, follow-ups filed; issue stays open
