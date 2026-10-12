# Tasks: cla-evidence R2 SigV4 pair off curl argv (#9756)

Plan: `knowledge-base/project/plans/2026-10-11-fix-cla-evidence-r2-sigv4-pair-off-curl-argv-plan.md`

## Phase 0 - RED first

- 0.1 Write `apps/cla-evidence/scripts/_r2-sigv4-curl.test.sh`: judge rows (single-byte swaps of a valid pair, exact rc 2, `::error::` once, marker once, `declare -F`), must-PASS rows, chokepoint wire with a stub that drains stdin unconditionally and exits 99 on a missing `user = "` line, argument-allowlist must-REFUSE and must-PASS rows, environment row, destination-pin rows, real-curl wire row with a serve-forever listener (port file, PID trap, record count, scope, no secret on the wire, control run); watch it fail.
- 0.2 Extend `upload-evidence.test.sh` and `upload-bypass.test.sh` stubs (record argv and drained stdin, exit 99 without the `user` line; distinct synthesized fixtures replacing the all-zero literals); malformed-credential and `bash -x` rows in the evidence suite only.
- 0.3 Write `apps/cla-evidence/scripts/bootstrap-r2-probe.test.sh`: scripted URLs only (exit 99 otherwise), exact recorded URL lists, valid-pair positive control, no Doppler write after the 500, malformed pair, `bash -x`, temp file cleanup.

## Phase 1 - helper and probe

- 1.1 Create `apps/cla-evidence/scripts/_r2-sigv4-curl.sh`: `_r2_cred_ok`, `r2_sigv4_judge` (safe `script=` field, `::error::` line, marker), `r2_sigv4_curl` (`[[ $# -ge 4 ]]`, in-file `=~` URL pin, argument allowlist, judge, `env -u` scrub, `--globoff --proto '=https'`, `--config -` via process substitution).
- 1.2 Create `apps/cla-evidence/scripts/r2-sigv4-refusal-probe.sh` (offline refusal probe printing the marker on stdout).
- 1.3 Lint the helper on its explicit path before building on it (Rule D pin form); run the helper suite GREEN.

## Phase 2 - r2-conditional-put.sh

- 2.1 xtrace refusal first after `set`; source the helper; pre-loop judge `|| exit 2`; `put_once` via `r2_sigv4_curl` (no trailing `2>/dev/null`); update stale comments.

## Phase 3 - bootstrap.sh

- 3.1 Unconditional xtrace refusal; source the helper; probe via `r2_sigv4_curl` (no separate pre-probe judge); `mktemp` body file with trap replacing `/tmp/r2-probe-body`; update the probe comment.

## Phase 4 - lint fallout

- 4.1 Delete both rows from baseline E and the census ceiling; reword the OWNERS header in the lint writer and both committed headers.
- 4.2 Delete both rows from the A/B/C baseline and the D baseline (leave `inspect-evidence.sh`); verify `--write-baseline` and `--write-baseline-d` show only those deletions.
- 4.3 `scripts/lint-shell-trace-credential-refusal.test.sh`: census-ceiling rows over a synthesized pair (`CC_BASE`/`CC_CEIL`); floor `CC_LISTED >= 2`; live-pair-reads-clean row; seed-mutation row.
- 4.4 `tests/scripts/test-argv-bearer-sweep.sh` S5 Guard 1: empty-baseline set identity, reworded header pin, carve-out deletion with its owner-line control.
- 4.5 Trim the two false docstring paragraphs in `scripts/lint-shell-trace-credential-refusal.py`; ADR-280 addendum (at most 10 lines, incl. the direct-egress requirement).

## Phase 5 - verify and ship prerequisites

- 5.1 Run every acceptance-criterion command in the plan (lint explicit/repo-wide/`--changed`, suites, shellcheck, CI lint steps, telemetry drift test, probe command).
- 5.2 Confirm the diff touches no `apps/web-platform/infra/` or `infra/github/` path (no production apply).
- 5.3 Confirm the PR's own CI run of the helper suite (hosted runner, curl 8.5) is green before merge (AC 12).
- 5.4 File one `deferred-scope-out` issue for the pair on the `doppler` CLI argument list at bootstrap Step 2 (not curl).
- 5.5 PR body: `Closes #9756`, `Ref #9597`, `## Changelog`, curl version line, decision-challenges render, post-merge verification command (`gh run list --workflow cla-evidence.yml`).
