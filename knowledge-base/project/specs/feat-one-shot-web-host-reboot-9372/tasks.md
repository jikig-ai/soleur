# Tasks: web-host-reboot workflow (#9372, Ref only)

Plan: `knowledge-base/project/plans/2026-10-07-feat-web-host-reboot-workflow-plan.md`. Branch: `feat-one-shot-web-host-reboot-9372`. No dispatch, no Doppler write, no token mint, no Terraform apply, no `.tf` change, no ledger or posture edit in this work.

## Phase 0: read before write

- 0.1 Read all three C4 files in full (`model.c4`, `views.c4`, `spec.c4`) and record the actor, system, store and relationship enumeration.
- 0.2 Re-read live state: `gh run view 37508997529` and `gh run view 37516716515`; workflow states for the rebirth workflow and both push-apply workflows; `gh issue view 9372 6931 9669 9572 --json state`; the marker name membership (exact name count only); a read-only Hetzner GET for the live server.
- 0.3 Re-run the `actions/reboot` census and record the expected file set.
- 0.4 Confirm the loader still exports `AWS_*` from the Tier-B pair and that `web-platform-infra-apply` still has a required reviewer and a `main`-only branch policy.
- 0.5 Verify GitHub's concurrency-versus-environment-approval behaviour from its documentation; record the verified sentence or an explicit "unverified" for the runbook.
- 0.6 Re-measure the readiness rows, probe rows and the journald boot list through the rows helper; keep the real JSON shapes as fixture templates.

## Phase 1: RED (tests first)

- 1.1 `scripts/web-host-reboot.test.sh`: fake world (curl shim for Hetzner and Better Stack replaying real object shapes, terraform shim, gh shim); refusal scenarios, one-write assertion, anchor-before-POST, evidence verdict scenarios, footer and denylist scans, deadline with a fake clock, parity and tombstone rows, mutation battery on COPIES with a mutant-count floor.
- 1.2 `apps/web-platform/infra/web-host-reboot-workflow.test.sh`: YAML-parsing structural rows S1 to S12, step classification, validate-step behaviour under `bash -e`, `observe` least-privilege rows, exit-2-is-green mapping, `TERRAFORM_VERSION` equality, allow-list agreement, mutation battery.
- 1.3 Run both suites and record the RED row counts (every row red because the subjects are absent).

## Phase 2: scripts

- 2.1 `scripts/web-host-reboot.sh`: helpers copied from `scripts/web2-rebirth.sh`; `reboot` with refusals 1 to 10 and the anchor written before the POST; `summary` with no Hetzner call.
- 2.2 `scripts/web-host-reboot-evidence.sh`: credential and `declare -F` loading checks; `snapshot`; `grade` with the pure verdict function, the three reads per iteration (clock read first), the `next:` line, the fixed footer, exit codes 0, 1, 2, 3 and 78.
- 2.3 Add the evidence script to `READERS` in `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`.

## Phase 3: workflow

- 3.1 `.github/workflows/web-host-reboot.yml` per the plan's contract table (inputs, `run-name`, two jobs, step order, `env -i` snapshot subshell, exit mapping, no forbidden text).
- 3.2 `bash scripts/lint-workflows.sh` and the `lint-workflow-*` linters over the new file.

## Phase 4: registration and censuses

- 4.1 `scripts/test-all.sh` registration line; regenerate the four shard and duration TSV files incrementally.
- 4.2 `scripts/guard-vacuity-floor.test.sh`: per-file promotion for the infra suite if it carries a floor of the measured shape.
- 4.3 `apps/web-platform/infra/run-registered-suites.sh` timeout pin only if the measured runtime exceeds 360 s.
- 4.4 `scripts/lib/test-affected-paths.sh` and `plugins/soleur/test/fixture-relative-assert.baseline.txt` only if their censuses ask.
- 4.5 `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` bump with the dated PLACEMENT, TRUTH and NO SUBSTITUTE comment.

## Phase 5: documentation and records

- 5.1 New runbook `knowledge-base/engineering/operations/runbooks/web-host-reboot.md`.
- 5.2 `web2-luks-rebirth-9372.md`: dated status correction, pointer section, row 5 as a literal deletion list sequenced after the graded #6931 PASS, retire-versus-keep stated.
- 5.3 `infra-credential-tiers-8209.md`: two inventory rows and a dated note.
- 5.4 ADR-263 short dated addendum; ADR-241 one-line dated entry.
- 5.5 `model.c4` edge prose (two edges, cited by text); `bash scripts/regenerate-c4-model.sh`; C4 tests.

## Phase 6: verification (local only)

- 6.1 Both new suites green; mutation batteries print their mutant counts.
- 6.2 `c4-count-parity`, `terraform-target-parity`, `nic-wait-gate`, `workspaces-luks-verify-workflow`, `guard-vacuity-floor`, `test-infra-privileged-tier-census`, `lint-orphan-test-suites`.
- 6.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; `python3 scripts/lint-guard-contract.py`; `npx markdownlint-cli2` over the plan, this file and the new runbook.
- 6.4 Run the `discoverability_test` command once against live read-only data and paste its output (ids and ages only).

## Phase 7: PR

- 7.1 First line of the PR body: merging this alone mutates nothing (dispatch-only, no `.tf`, nothing dispatched). Body carries `Ref #9372`, never `Closes`.
- 7.2 Record the dispatch as the owner's separate go-ahead, tracked on #9372.
