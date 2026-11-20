# Tasks — feat-one-shot-12941-bastion-runcmd-rehearsal

Plan: `knowledge-base/project/plans/2026-11-20-feat-bastion-runcmd-rehearsal-plan.md`.
Rulings: `decision-challenges.md` (Q1-Q18). Prototype: `prototype/`.
Issue #12941 (Closes), Ref #12866, Ref #9421. Draft PR #12995.

## 1. Setup

- 1.1 Re-read the plan's `## Proposed Solution`, `## Guard Contract` and `## Plan Review Revisions`.
- 1.2 Render the template once with terraform 1.10.5 (CI's `TERRAFORM_VERSION`) and diff against a 1.17.2 render.
- 1.3 Record the noble cloud-image manifest serial and date for the `CLOUD_IMAGE_PKGS` comment.
- 1.4 Grep the joined runcmd for an existing `W=` before using it in `_egress_why`.

## 2. Core implementation — RED first

- 2.1 Write `apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh`:
  - 2.1.1 Header: property, limits, divergence table, `IMAGE_ASSUMED`, `CLOUD_IMAGE_PKGS`.
  - 2.1.2 Preconditions (`BRH_TOOL_ABSENT:<tool>` under CI), pin read from the git-data suite, privileged notice.
  - 2.1.3 Fixtures (host key, CA, server cert, DSN), work dir, single EXIT trap, evidence kept on failure / `BRH_KEEP_TMP`.
  - 2.1.4 `render`, `mutate` with `BRH_ANCHOR_MISS`.
  - 2.1.5 Offline predicate self-tests (must-PASS and must-RED, incl. the real FAULT-A boilerplate string).
  - 2.1.6 S0 (`cloud-init schema`) and S1 (`dash -n` with its must-RED control); `BRH_STATIC_ONLY`.
  - 2.1.7 Fixture images via `gd_apt_install_bounded --no-install-recommends` (debs through the helper), shims, content+week tag; `BRH_BASELINE_NOT_MINIMAL` check.
  - 2.1.8 Per-row topology (198.18.k.0/24, stub, decoy on B1 only), `--add-host` pins, priv0, boot wait (150 s cap), archive probe.
  - 2.1.9 Rows B1 (+B1-E, B1-P), B2, M1, M2, F1, F1-M, FA, B1-C in waves [B1,B2,M1] [M2,F1,F1-M] [FA,B1-C].
  - 2.1.10 Derived deadline (180 + 300 + 150 + 150), `BRH_DEADLINE`, ADR-188 classification, CI skip ceiling (`BRH_SKIP_CEILING`), `BRH_ROWS`/`PARTIAL`, refusals under CI.
  - 2.1.11 Verdict: `FAILURES`, ADR-193 floor and identity, `ROWS_BOOTED`, terminal lines.
- 2.2 Run on main's template; record B1 RED (`egress_load`, `User does not exist`) and F1 detail RED (AC2).

## 3. Core implementation — template fixes

- 3.1 `bastion-cloud-init.yml`: add `systemd-timesyncd` to apt_install (FAULT-A).
- 3.2 `bastion-cloud-init.yml`: `_egress_why` (`--sync`, `-b`, content selection, `why=no_reason_line` Result branch), capture on both unit lines, rewrite the comment, header pointer to the suite (FAULT-B).
- 3.3 `bastion.test.sh`: SETTLE row 5 anchor; run `bash apps/web-platform/infra/bastion.test.sh` to `PASS`.
- 3.4 Re-run the pin census for the rewritten lines; re-run the suite to `PASS` (two local runs, cold and warm).

## 4. Registration and CI

- 4.1 `run-registered-suites.sh`: `DEDICATED_JOB_WHY`, shard exclusion, `--enumerate` exclusion, `SOLEUR_INFRA_SKIP_DEDICATED` marker with its loud line, `_SUITE_BOUNDS` 900, TOOLING line.
- 4.2 `run-registered-suites.test.sh`: shard / unsharded / marker arm via `--list`.
- 4.3 `test-infra-suite-registration.sh`: scoped PRIVILEGED parse, generalized job arm, manifest/durations treatment, Arm 4 `need` loop, monitor-marker assertion; run Guard 2 mutations 1-8.
- 4.4 `infra-validation.yml`: job `bastion-boot-rehearsal` (18 min with derivation comment, failure artifact, no credentials); aggregator `needs`, `entries`, env, `cancelled)` rewrite.
- 4.5 `deploy-script-tests-aggregator-diagnosis.test.sh`: third result, cancelled rows, wiring row.
- 4.6 `main-health-monitor.yml`: `SOLEUR_INFRA_SKIP_DEDICATED=1` on `test-infra`.
- 4.7 `apt-bounded.test.sh` SPECS line (counts derived); `guard-vacuity-floor.test.sh` PROMOTED entry.
- 4.8 `git add` the suite, then run: registration test + its mutations, `test-main-duplicate-skip.sh`, `apt-bounded.test.sh`, `guard-vacuity-floor.test.sh`, `lint-orphan-test-suites.sh`, `lint-shell-capture-exit`, `fixture-relative-assert`, `fixture-dir-operand-assert`, `regenerate-shard-manifest.py --group infra --incremental` (dry run, no change).

## 5. Records and verification

- 5.1 ADR-327 addendum (rehearsal requirement, user-install invariant, IMAGE_ASSUMED, two baselines, QEMU alternative and trigger, #12942 gate).
- 5.2 `bastion-host.md` paragraph.
- 5.3 Read `model.c4`, `views.c4`, `spec.c4` in full; run `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 5.4 Comment on #12942 (gate requires `bastion-boot-rehearsal` green on the birth SHA).
- 5.5 Record wall times (local cold/warm, first CI run) and the discoverability probe output (`1`) in the PR body; PR body first line states merging mutates no production resource.
