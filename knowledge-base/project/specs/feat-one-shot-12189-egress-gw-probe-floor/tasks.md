# Tasks: egress-gw soak probe floor (Ref #12189, #12180)

Plan: `knowledge-base/project/plans/2026-11-06-fix-egress-gw-probe-apply-floor-and-informational-resolver-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-12189-egress-gw-probe-floor/decision-challenges.md`

## Phase 1: Suite (RED first)

- 1.1 Harness: add `EGRESS_GW_SILENT_FLOOR_EPOCH` to `run_case`; `FLOOR_AGE` default in `reset_defaults`; default `ROSTER_BQ` with both roster hosts non-zero; add a 1048111600-shaped decoy to `build_fixtures`.
- 1.2 Rewrite the rows that encode the old contract
  - 1.2.1 age-boundary rows -> floor-age boundaries on non-collinear points
  - 1.2.2 open-anchor staleness and `SOLEUR_FT_EARLIEST` rows -> `quiet_since` rows and "EARLIEST ignored" rows
  - 1.2.3 `actor -> 5` and key-missing `-> 3` rows -> informational (pass, field printed)
  - 1.2.4 "no warehouse read when resolved" row flips (pass now reads rows)
- 1.3 New rows
  - 1.3.1 pre-floor resolved decoy ignored; slack boundary pair (floor-300 counts, floor-301 does not); second post-floor incident after a compliant pre-floor one
  - 1.3.2 pre-floor open incident: exit 2 inside `quiet_since + 15300`, exit 5 past it; pre-floor incident resolved after the floor moves `quiet_since`
  - 1.3.3 pass-path rows: rc non-zero / credentials unbound / non-row answer / empty roster -> 3; roster host at zero -> 5; extra host does not cover a roster host
  - 1.3.4 floor and canary checks -> 3: floor after now, floor before anchor start, canary `created_at` missing / unparseable / too early, duplicate canary alerts, canary incident too early, anchor open-state disagreement
  - 1.3.5 retired canary -> distinct exit 5; declared variant keeps old text
- 1.4 Pins: 12-field order regex; `APPLY_FLOOR_EPOCH=` once at column 0 digits; SUT does not read `SOLEUR_FT_EARLIEST` or `updated_at`; RETIREMENT block lists the pin; negative controls for new helpers
- 1.5 Confirm the suite is RED against the unmodified probe; re-pin `MIN_ASSERTIONS` only after Phase 2 is green

## Phase 2: Probe (GREEN)

- 2.1 Add `APPLY_FLOOR_EPOCH=1793967363`, `FLOOR` seam, `SLACK_S=300`, `QUIET_STALE_S=15300`; delete the `SOLEUR_FT_EARLIEST` block
- 2.2 Setup checks -> exit 3 (floor sanity, canary alert count and `created_at`, canary incident bound, anchor state agreement)
- 2.3 Recurrence set (`epoch >= FLOOR - SLACK_S`, id != anchor), `quiet_since`, pre-floor open set
- 2.4 Verdict ladder in the CTO order; delete the actor gates, the `V_AGE` gate and the canary-age gate
- 2.5 `read_rows` function in the main shell (no `$( )` verdict), `ROWS_OK` from the same jq; rows verdict-bearing before the declared-or-live step
- 2.6 `emit_line` +2 fields; update header (contract, EARLIEST, blind spot, pin, RETIREMENT sites)
- 2.7 Suite green; re-pin `MIN_ASSERTIONS`; `bash -n`; no `exit 1` in code

## Phase 3: Documents

- 3.1 Runbook `cron-egress-blocked.md`: field list, OBSERVED/NOT measured wording, new decision-table rows
- 3.2 ADR-218: append "Amendment 2026-11-06 (#12189, Ref #12180)"; earlier text untouched
- 3.3 Repo grep for stale ASSUMED / "resolved by the alert" wording

## Phase 4: Verify

- 4.1 Probe suite, `egress-gw-alert.test.sh`, `c4-count-parity.test.sh`, `test-argv-bearer-sweep.sh`, `lint-guard-contract.py` on the plan
- 4.2 One read-only live run (readonly token, no writes); record the verdict line in the PR

## Phase 5: Ship notes

- 5.1 PR body: `Ref #12189`, `Ref #12180`, no `Closes`
- 5.2 Corrective comment on #12189 (criterion 2)
