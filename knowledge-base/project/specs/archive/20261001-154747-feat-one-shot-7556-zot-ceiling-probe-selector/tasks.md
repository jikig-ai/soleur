# Tasks: fix zot upload-ceiling probe selector (#7556)

Plan: `knowledge-base/project/plans/2026-10-01-fix-zot-upload-ceiling-probe-selector-plan.md`
Ref #7556 (never Closes). Targeted tests only; CI runs the full battery.

## Phase 1 - RED tests first

- 1.1 Create `scripts/followthroughs/zot-upload-ceiling-7556.test.sh`: stub query (`ZOT_CEILING_QUERY`) replaying the real
  tool contract (newest-N truncation, OR-LIKE over double-encoded raw, `--until` as `dt <=`, rc 3), production-shaped
  double-encoded fixtures with fabricated values.
- 1.2 Cases: live-state regression (44 PATCH + heartbeat echoes -> PASS patch_rows=44); heartbeats-only; echo with `i/o timeout`;
  n1 error row; n1 text in non-SOLEUR_ZOT_LOG row; n2 latency table (30m0s, 28m31s, 1h0m0s cut; 5m55s, 3m31s, 28m29s not; PUT);
  unparseable latency; FAIL before floor/truncation/unparse; floor 11/12; truncation 4999/5000 and 19999/20000; drop reasons;
  anchor present/absent/contaminated/at-slack/only-outside; webhook row quoting "syntax error" still graded; header and path
  forgery; classifier-failed; every `reason=` in the plan's table; stdout sentinel (no row excerpts).
- 1.3 Direct floor + conservation reporting per ADR-193 (`printf >&2` + `exit 1`, `cases` at call site).
- 1.4 Run against the UNCHANGED probe; record the red count.

## Phase 2 - probe

- 2.1 Add `fetch NAME LIMIT ARGS...` (rc, structural error payload, truncation) and route all four reads through it.
- 2.2 Add the python3 classifier (prefix pin, head cut, anchored regex, n1/n2/other5xx/unparse/upload_any) with a validated
  fixed-shape output line; `classifier-failed` otherwise.
- 2.3 Reorder verdicts: FAIL (n1+n2) -> unparse -> truncated -> floor -> dropped guard -> anchor -> PASS.
- 2.4 Add the dropped-read guard (allow-list of `rate_cap`, limit 20000) and the anchor read (`--since $WINDOW --until start+6h`,
  python3 date arithmetic, `SOLEUR_ZOT_DISK` (plus a trailing space) offset-0 pin); delete the span guard and old `is_error_payload`.
- 2.5 Update header comment (exit contract, anchor arithmetic, D7 crash note, lib-extraction trigger) and PASS text caveats D5.

## Phase 3 - registration and gates

- 3.1 `run_suite "scripts/zot-upload-ceiling-7556" ...` in `scripts/test-all.sh` beside the zot followthrough suites.
- 3.2 Run: harness; `lint-orphan-test-suites.sh`; `lint-followthrough-varq-ban.sh`; `lint-guard-contract.py` on the plan;
  `lint-infra-no-human-steps.py --changed --base origin/main`; `shellcheck`; `SCRIPTS_SHARD=i/7 bash scripts/test-all.sh --enumerate scripts` for i=1..7.

## Phase 4 - mutation battery

- 4.1 Run Guard 1 (8 rows) and Guard 2 (8 rows) plus harness rows H1/H2 against the finished probe; each must redden the harness.
  Record a table for the PR body.

## Phase 5 - issue and PR

- 5.1 File the follow-up issue (shipper `is_cap_exempt` vs real error line; runbook correction; 7440 `n_patch`).
- 5.2 One read-only local run of the probe against the warehouse; record only the verdict line.
- 5.3 PR body: `Ref #7556`, expected PASS and auto-close with holding options, D2 power statement, four defects, red/green and
  mutation evidence, follow-up issue number.
