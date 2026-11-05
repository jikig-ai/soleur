# Tasks — ci: oracle-only fast lane (#12156)

Plan: `knowledge-base/project/plans/2026-11-05-ci-oracle-only-fast-lane-plan.md`
Lane: cross-domain (fail-closed default; no spec.md). Threshold: single-user incident — CPO sign-off item O1 pending.

## Phase 1 — Classifier driver + sentinel scaffold (RED first)

- [ ] 1.1 Write `scripts/ci-oracle-lane.test.sh` FIRST (RED): fixture-diff battery driving the real driver — surface members, every exclusion, hunk-extent arms, output grammar, lock, fail-closed defaults, manifest parity. Mirror `scripts/ci-pr-selection.test.sh` harness shape.
- [ ] 1.2 Write `scripts/ci-oracle-lane.sh`: defaults-first output block; merge-ref two-parent validation (pull_request) and `merge_group.{head,base}_sha` diff (merge_group); same-repo/attempt-1/≤500-file/M-A-D/mode/ASCII/`::`/`,` guards; per-path surface check (2 literal TSVs + doc allowlist identical to `is_doc_path`); `git diff -U0` hunk-extent check vs `^AFFECTED_[A-Z0-9_]+_PATHS=(`…`^)` in base AND head images; `readonly ORACLE_LANE_LOCKED=1`; grammar-checked final output block; `SOLEUR_ORACLE_LANE` notice; EXIT-trap exit-0.
- [ ] 1.3 Write `scripts/ci-oracle-lane-suites.txt` (label + argv per line; membership per decision T3): enumerate-EXACT labels (`plugins/soleur/test/ci-pr-affected-preactivation.test.sh` carries the `.test.sh` — SUITE_GLOB registration, no `run_suite` line) + committed commented exclusion list naming the eight evaluated non-members per T3.

## Phase 2 — ci.yml wiring

- [ ] 2.1 Add `oracle-selection` job to `.github/workflows/ci.yml`: `if: (pull_request || merge_group) && vars.CI_ORACLE_LANE != ''`, `continue-on-error: true`, `contents: read`, `fetch-depth: 0`, no `needs:`, `timeout-minutes` alone on its line, outputs `oracle_only/active/skip_legs/head_sha/base_sha`, env-only inputs.
- [ ] 2.2 Add the oracle `if:` conjunct to the five heavy legs (`test-webplat`, `test-bun`, `test-scripts`, `test-scripts-heavy`, `web-platform-build`) + `needs: oracle-selection`; head-bound via `github.event.pull_request.head.sha || github.event.merge_group.head_sha`.
- [ ] 2.3 Add `needs.oracle-selection.outputs.oracle_only != 'true'` conjunct to `shard-totality-mutations` + `needs: oracle-selection`.
- [ ] 2.4 Add `oracle-index-check` job (`if: ${{ always() && !cancelled() && (github.event_name == 'pull_request' || github.event_name == 'merge_group') }}`, `needs: [oracle-selection]` — `always()` defeats needs-skip propagation from the var-gated `oracle-selection`, CPO O1 condition 1): runs the manifest serially when `oracle_only == 'true'` (exit codes propagate), else prints `not-oracle-only` and exits 0.
- [ ] 2.5 `test` aggregator: `needs:` += `oracle-selection, oracle-index-check`; `entries[]` += `oracle-index-check`; env `ORACLE_*` outputs; ORACLE-ONLY-SKIP arm (event ∈ {pull_request, merge_group}, active, head-bound, attempt 1, five-name regex). Extend `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`.

## Phase 3 — push-dedupe + consumers

- [ ] 3.1 Tighten the `push-dedupe` proof: all SIX skippable legs `success` required for elide — five heavy legs + `shard-totality-mutations` (skipped/absent/malformed → `elide=false`, per CTO T4); sentinel pins the leg-name set bi-directionally; extend `scripts/ci-push-dedupe.test.sh`.
- [ ] 3.2 Verify consumers read a reduced `test` correctly: `plugins/soleur/skills/ship/scripts/battery-owed.sh`, `plugins/soleur/scripts/admin-merge-ready.sh`, `plugins/soleur/scripts/monitor-pr-checks.sh`, `.github/workflows/post-merge-monitor.yml`. Record a verdict line per consumer; edit only on a misread.

## Phase 4 — Registration + docs

- [ ] 4.1 `run_suite "scripts/ci-oracle-lane" bash scripts/ci-oracle-lane.test.sh` in `scripts/test-all.sh`; `AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS` = {driver, suite, manifest, `.github/workflows/ci.yml`, `scripts/lib/test-affected-paths.sh` (THIS FILE)} in `scripts/lib/test-affected-paths.sh`.
- [ ] 4.2 Dated `## Amendment` on `ADR-276-*` (lever, `CI_ORACLE_LANE`, lock, BLOCKING `would_skip`-audit exit criterion, push-dedupe tightening, census link, `[full]`-marker caveat) naming BOTH Decision 5's proposed boundary AND Decision 2's adopting invariant (per CTO T1), the oracle-data-only scope bound, and the consumer record (admin-merge-ready.sh/ci-head-verdict.sh residual recorded, never taught the reduced-run read); conditional ADR-262 pointer line.
- [ ] 4.3 Runbook `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` (dark phase, observation, activation procedure `gh variable set CI_ORACLE_LANE=on` → observe → lock-removal PR, rollback = unset).
- [ ] 4.4 File/attach activation tracking on the #10865 observation window.

## Phase 5 — Verify

- [ ] 5.1 `bash scripts/ci-oracle-lane.test.sh`, `bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, `bash scripts/ci-push-dedupe.test.sh`, `bash scripts/probe-merge-group-coverage.sh` all exit 0.
- [ ] 5.2 `actionlint` clean on ci.yml; `grep -c 'oracle' scripts/required-checks.txt` == 0.
- [ ] 5.3 Every Guard Contract mutation row demonstrated RED when applied.
