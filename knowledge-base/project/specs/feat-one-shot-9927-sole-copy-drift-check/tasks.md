# Tasks: sole-copy protection drift check (#9927 item 9)

Plan: knowledge-base/project/plans/2026-10-16-feat-sole-copy-protection-drift-check-plan.md

PR body: `Ref #9927` only (no closing keyword); after every body edit assert `closingIssuesReferences` is `[]`.

## Phase 1: RED first

- [ ] 1.1 Create `plugins/soleur/test/sole-copy-drift-check.test.sh`: extractor (python3 -I + yaml.safe_load) for the probe and filer step bodies of job `sole-copy-protection-check` by job id and step id, with anti-vacuity floors
- [ ] 1.2 Add stub `curl`, `doppler` and `gh` on a synthesized PATH recording argv and stdin; synthesize the `.tf` and Hetzner JSON fixtures
- [ ] 1.3 Add the verdict case table (Guard 1 rows 1, 3, 7, 8, 9) asserting the whole `$GITHUB_OUTPUT` and the exit code per case
- [ ] 1.4 Add the reorder, fallback-token, name-filter, web-1-id and leakage rows (Guard 1 rows 4, 5, 6, 11)
- [ ] 1.5 Add the own-dispatch rows and harness rows (Guard 1 row 2, H1-H3) and the must-PASS non-canonical inputs
- [ ] 1.6 Add the rendered-body classifier row (one injected write-verb line) and the static-shape rows (Guard 1 rows 10, 12 and 13)
- [ ] 1.7 Run the suite against the tree without the job; confirm every row is RED for the named reason

## Phase 2: GREEN the job

- [ ] 2.1 Insert job `sole-copy-protection-check` after `heartbeat-live-reconcile` and before the rung-2 comment block in `.github/workflows/scheduled-terraform-drift.yml` (no edit anywhere else in the file)
- [ ] 2.2 Probe step: derive name and expected flag from the `.tf`, read `HCLOUD_TOKEN_READONLY` with no fallback, mask it, GET by name via `bc_curl`, check pagination, count, name and boolean type, publish single-line outputs
- [ ] 2.3 Finding filer (protection-missing, volume-not-found): idempotent create-or-comment, p1, facts only, no command
- [ ] 2.4 Could-not-perform filer (could-not-read, no-token): create-only, p2
- [ ] 2.5 Gate step: exit 1 on every non-clean verdict after the filers ran
- [ ] 2.6 `bash -n` each extracted body; YAML parses; R1-R5 stays green

## Phase 3: registries and docs

- [ ] 3.1 Register the suite in `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv`
- [ ] 3.2 Add `AFFECTED_PLUGINS_SOLEUR_TEST_SOLE_COPY_DRIFT_CHECK_TEST_SH_PATHS` in `scripts/lib/test-affected-paths.sh`; quote the consuming line
- [ ] 3.3 Add the Group 3 row (Tier A) to `infra-credential-tiers-8209.md`
- [ ] 3.4 ADR-282 addendum plus the residual "Detection of lifted protection is generic" edit (status stays accepted)
- [ ] 3.5 One sentence in `inngest-luks-cutover-6894.md` "No drift check by log search"; leave the section-5c one-liner block untouched
- [ ] 3.6 Re-read the three `.c4` files; record "no C4 impact" with the enumeration or add the one clause

## Phase 4: verify (targeted only)

- [ ] 4.1 `sole-copy-drift-check`, `token-drift-workflow-causes`, `terraform-drift-step-order`, `terraform-drift-sentry-leg`, `heartbeat-reconcile-issue-step` suites
- [ ] 4.2 `tests/scripts/test-argv-bearer-sweep.sh`, `tests/scripts/test-infra-privileged-tier-census.sh`, `plugins/soleur/test/c4-count-parity.test.sh`
- [ ] 4.3 `python3 scripts/lint-guard-contract.py`; `bun test plugins/soleur/test/terraform-target-parity.test.ts`
- [ ] 4.4 No Hetzner, Doppler or production call made at any point

## Phase 5: ship

- [ ] 5.1 PR body `Ref #9927`, assert `closingIssuesReferences` is `[]` after every edit
- [ ] 5.2 Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`
- [ ] 5.3 Parked drafts (#10405, plaintext-volume resolver PR) untouched
- [ ] 5.4 Note the known unrelated red "Tenant integration (dev-Supabase)" on `test/server/action-sends-worm.test.ts`; do not fix
- [ ] 5.5 Comment on #9927: item 9 built, web-1 `workspaces_luks` follow-up; issue stays open
