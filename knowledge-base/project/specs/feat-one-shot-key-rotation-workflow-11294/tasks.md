# Tasks: key-rotate workflow (Ref #11294, Ref #10205)

Plan: `knowledge-base/project/plans/2026-11-02-feat-key-rotation-workflow-plan.md`. Decisions: `decision-challenges.md` (F1-F9, G1-G7, H1-H3). Tracking issues: #11920, #11922, #11923, #11927, #11928.
Hard constraints for every task: no `rotate` dispatch by an agent, no production write, never read or print a secret value, no Claude Code memory writes, run test suites ONE AT A TIME (CI is the authority), `Ref #11294` and `Ref #10205` only (no `Closes`), never arm or merge any of the three PRs.

## Phase 0 - prerequisite PRs

- [ ] 0.1 PR-F: new branch and worktree off `main` for the redaction-filter fix
  - [ ] 0.1.1 RED first: labelled synthesized rows in `tests/scripts/test-tf-redact-random-ids.sh` (tainted-must-be-replaced, deposed-will-be-destroyed, drift-has-changed, replaced-as-requested, destroyed, created), regression rows, live detector row, stuck-state rows (unterminated block, end of input mid-block, later diagnostic stays readable)
  - [ ] 0.1.2 Widen the block-start in `tests/scripts/lib/tf-redact-random-ids.sh` to any plan comment line naming a `random_*` address
  - [ ] 0.1.3 Run that suite, then the shard holding `terraform-target-parity.test.ts` (one at a time)
  - [ ] 0.1.4 Read-only audit of existing public apply-run logs for tainted or deposed blocks (count only); report any hit
- [ ] 0.2 PR-0 (after 3.x): derive the key list with `bash tests/scripts/test-trio-baseline-census.sh --emit-baseline` on the finished branch; `@allow` lines in `tests/scripts/trio-baseline.tsv` and ADR-241 `Allow:` lines only (max-expiry 2026-11-30); then spend them in this PR once PR-0 has merged and `main` is synced

## Phase 1 - RED: `apps/web-platform/infra/key-rotate-workflow.test.sh`

- [ ] 1.1 Harness: instrument self-test, fixture dir guards, symlinked mutation-tree helper with landing checks (exactly-once anchor, `bash -n`, inside the function range), `scenario(script, workflow)` runner (real = stops, mutated copy = proceeds), literal oracles, single clock via `kr_now`, YAML parsed once to JSON, stubs built once
- [ ] 1.2 Layer A static workflow rows (dispatch-only, groups, scoped terraform check with positive `setup-terraform` row, trio only in the redeploy step env, timeouts as literals)
- [ ] 1.3 Layer B static script rows (type-checked symbols, top-level source, pre-source `^K[RK]_` refusal, no `set -e`, no `trap`, single `kr_tf` call site, 35-token set equality plus coverage table, no `inngest-key-rotate`/`converge` text in any stream/argv/issue, sha256 pin of sourced source text incl. callees, `kr_out` allowlist, credential-free `--print-contract` under `env -i`)
- [ ] 1.4 Layer C behaviour rows (ref/actor/owner/approval rungs, ladder, all seven keys in plan, six in rotate, egress refusal, kb_drift boundary table, gate refusals with literal row counts, H1 absent paths and projection, post-state verdict precedence and the retry, redeploy failure after apply, `owner_step_pending`, notify decision table with `write_started`, `issue_unfiled`, temp dir removed) against faithful stubs (argv-derived plan actions, real doppler table format, `pending` statuses, issue body capture)
- [ ] 1.5 No-stream test with control run and stream-count floor
- [ ] 1.6 Layer D mutation rows for Guards 1-4 and harness rows

## Phase 2 - GREEN: `scripts/key-rotate.sh`

- [ ] 2.1 Source `scripts/inngest-key-rotate.sh` at top level; type-checked symbol check (exit 78); wholesale `KR_GATE_TABLE`, `KR_INFLIGHT_WORKFLOWS`, `KR_VERDICT_TOKENS`; same-name redefinitions
- [ ] 2.2 Gate table, `kk_gate`/`kk_gate_plan` (unioned want, `absent_all` flag), copy-state function (`present|absent|unknown`)
- [ ] 2.3 `guard` and `precondition` subcommands (ref rung, redaction sanity step with `redaction_ok`, refusal ladder, owner allowlist, `approval_environment_missing`, kb_drift window, owner_step_open, lower-run-id rung)
- [ ] 2.4 `apply` subcommand (re-checks, authorization_stale, pre-state, plan, five-field projection, gate, re-checks again, `write_started`, apply, post-state with retries, precedence)
- [ ] 2.5 `redeploy` (three steps: re-checks, `track.sh`, verdict; `owner_step_pending`) and `notify` (the only issue filer; re-list check; close-on-`rotate_ok`)
- [ ] 2.6 `--print-contract`; `shellcheck`

## Phase 3 - `.github/workflows/key-rotate.yml`

- [ ] 3.1 Jobs guard / apply / redeploy / notify, groups (`inngest-key-rotate` dispatch, distinct push group, rotate-only Terraform group, `web-1-swap`), redaction sanity step in the guard job gating `apply` on `redaction_ok`, trio only in the `track.sh` step env with no `GH_TOKEN`, `issues: write` on notify only, timeouts from the budget table
- [ ] 3.2 Header comment (dispatch-only, production act, confirm is a fat-finger guard, public repository)

## Phase 4 - parity and registrations

- [ ] 4.1 `plugins/soleur/test/terraform-target-parity.test.ts`: Guard 5 describe, `TEST_FLOOR`, ledger line
- [ ] 4.2 `.github/workflows/infra-validation.yml` paths; `scripts/lib/test-affected-paths.sh` entries plus the reverse edge
- [ ] 4.3 `apps/web-platform/infra/web-hosts-fanout-parity.test.sh` operand 8
- [ ] 4.4 `knowledge-base/engineering/architecture/diagrams/model.c4` edge sentence; run the C4 tests
- [ ] 4.5 Weight row for the new suite in `scripts/suite-durations.tsv`; run and register per output: tier census, trio census (red until PR-0), orphan-suite lint, guard-vacuity floor, grep-q pipe guard, fixture-relative baseline, pr-affected audit accept, shard tables, `infra-credential-tiers-8209.md`

## Phase 5 - documentation and tracking

- [ ] 5.1 `knowledge-base/engineering/operations/runbooks/key-rotation.md` (no SSH; Better Stack read-only probes for the gap windows; preconditions per key; no reminder arming or cohort tagging during a prd manual-trigger rotation); pointer line in `inngest-server.md`
  - [ ] 5.1.1 Re-verify and, if stale, correct the owner-step command block of `github-app-provisioning.md` Step 4 against the current Doppler layout (`soleur-github-app` project) in this PR
- [ ] 5.2 New ADR via `soleur:architecture create` (reserve the ordinal against a freshly fetched `origin/main`; provisional 314; sweep plan and tasks for the old number on any renumber) covering F1, F2, F9, G6/H2 and the F3 rationale; one pointer line and `related:` entry in ADR-307 (body unchanged)
- [ ] 5.3 Create the `owner_step_pending` label; comment on #9294 (trio-consumer migration list)

## Phase 6 - verification and PR

- [ ] 6.1 Run, one at a time: redaction suite; `key-rotate-workflow.test.sh`; `inngest-key-rotate-workflow.test.sh` (unchanged); `web-hosts-fanout-parity.test.sh`; `terraform-target-parity.test.ts`; `c4-count-parity.test.sh`; plan guard-contract lint
- [ ] 6.2 Review, QA, compound
- [ ] 6.3 PR body: prerequisite PRs and merge order, red-until-sync checks, "nothing was dispatched", "every rotate needs the owner's own typed go", redaction coverage report, authorization residual, `Ref #11294`, `Ref #10205`; leave all three PRs unarmed
