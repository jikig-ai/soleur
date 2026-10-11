# Tasks: cla-evidence R2 SigV4 pair off curl argv (#9756)

Plan: `knowledge-base/project/plans/2026-10-11-fix-cla-evidence-r2-sigv4-pair-off-curl-argv-plan.md`

## Phase 0 - RED first

- 0.1 Write `apps/cla-evidence/scripts/_r2-sigv4-curl.test.sh` (judge, must-PASS, chokepoint wire, helper contract, destination pin, real-curl wire row, negative canary); watch it fail.
- 0.2 Extend the stubs and rows in `apps/cla-evidence/scripts/upload-evidence.test.sh` and `upload-bypass.test.sh` (record argv and drained stdin; distinct synthesized fixtures; malformed-credential and `bash -x` rows in the evidence suite only).
- 0.3 Write `apps/cla-evidence/scripts/bootstrap-r2-probe.test.sh` (probe argv/stdin, malformed pair, `bash -x`, temp file cleanup).

## Phase 1 - helper

- 1.1 Create `apps/cla-evidence/scripts/_r2-sigv4-curl.sh` (`_r2_cred_ok`, `r2_sigv4_judge`, `r2_sigv4_curl` with in-file `=~` URL pin and caller-argument refusal).
- 1.2 Lint the helper on its explicit path before building on it (Rule D pin form); run the helper suite GREEN.

## Phase 2 - r2-conditional-put.sh

- 2.1 xtrace refusal first after `set`; source the helper; pre-loop judge `|| exit 2`; `put_once` via `r2_sigv4_curl`; update stale comments.

## Phase 3 - bootstrap.sh

- 3.1 Unconditional xtrace refusal; source the helper; probe via `r2_sigv4_curl`; `mktemp` body file with trap (replaces `/tmp/r2-probe-body`); update the probe comment.

## Phase 4 - lint fallout

- 4.1 Delete both rows from baseline E and the census ceiling; reword the OWNERS header in the lint writer and both committed headers.
- 4.2 Delete both rows from the A/B/C baseline and the D baseline (leave `inspect-evidence.sh`); verify `--write-baseline` and `--write-baseline-d` show only those deletions.
- 4.3 `scripts/lint-shell-trace-credential-refusal.test.sh`: census-ceiling rows over a synthesized pair; floor `CC_LISTED >= 2`; live-pair-reads-clean row.
- 4.4 `tests/scripts/test-argv-bearer-sweep.sh` S5 Guard 1: empty-baseline set identity, reworded header pin, carve-out deletion.
- 4.5 Trim the two false docstring paragraphs in `scripts/lint-shell-trace-credential-refusal.py`; ADR-280 addendum (at most 10 lines).

## Phase 5 - verify and ship prerequisites

- 5.1 Run every acceptance-criterion command in the plan (lint explicit/repo-wide/`--changed`, suites, shellcheck, CI lint steps, telemetry drift test, `curl` 8.5 wire row).
- 5.2 Confirm the diff touches no `apps/web-platform/infra/` or `infra/github/` path (no production apply).
- 5.3 File one `deferred-scope-out` issue for the pair on the `doppler` CLI argument list at bootstrap Step 2 (not curl).
- 5.4 PR body: `Closes #9756`, `Ref #9597`, `## Changelog`, curl version line, decision-challenges render.
