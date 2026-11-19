# Tasks: serve gate soak floor and per-instance grader (#12849)

Plan: `knowledge-base/project/plans/2026-11-18-fix-serve-gate-soak-floor-and-per-instance-grader-plan.md`
Decisions: `decision-challenges.md` (D1-D5, F1-F11, G1-G13 Ruled by CTO agent, 2026-11-18, including the
G13 replace-path placement: it ships with #12869).

## Phase 1 — tests first (RED)

- [x] 1.1 Anchor all 7 `sub_condition=` substring checks (2 in `lb-weight-gate.test.sh`, 5 in
      `lb-weight-gate-with-marker.test.sh`) on the whole `gate_fail sub_condition=<id>` line; add the census row.
- [x] 1.2 Source the helper for `SOAK_EV_RE` / `INSTANCE_EV_RE` / `SOAK_FLOOR_S`; add `ev_lines`, `ev_field`,
      `assert_ev`; positive and negative grammar fixtures (G4).
- [x] 1.3 Floor rows for both knobs (1, 2 refuse below_floor; 3, 5, 999 accept; 0, 010, 08, abc, `1 verdict=pass`,
      1000, 200000000000000, 18446744073709551619 refuse invalid; source default/env).
- [x] 1.4 Evidence rows per refusal id in B.2-B.10; pass gives two lines; standby / Condition A / B.1 give zero;
      web-3 row with roster and allowlist fixture additions.
- [x] 1.5 Parity rows: grader `SOAK_DAYS` = gate `SOAK_FLOOR_DAYS`, helper `SOAK_FLOOR_S` = both x 86400; the four
      web-2 literal sites.
- [x] 1.6 Workflow wiring rows (grader step key set, order, `if:`, no tolerance, host parity, EXIT trap, helper
      source lines, grader value, no marker-name mention, knob census) plus committed mutation rows (G5).
- [x] 1.7 Executed rows on `sse_instance_soak` (rc loop 0,1,2,3,78,126,127; ambient `SOLEUR_FT_EARLIEST`; G10
      decoy row; web-3 row; empty-host row; G12 `NOT YET: no GREEN web-2 readiness row` row with the 90-day
      replace next-step; `$GRADE` shape filter row; EXIT/TERM trap row).
- [x] 1.8 Executed rows on `sse_gate_chain_check` (Guard 4 rows, G8 rows, message texts, fenced summary, rc=1
      returns 1); wiring rows for the inline `gate_rc` backstop, the bare (unwrapped) helper call, the guarded
      helper load in both steps, and the step-level `SOLEUR_GATED_HOST: web-2`.
- [x] 1.9 Stub-`gh` rows for `scripts/serve-soak-evidence-last.sh` using the real tab-prefixed `gh run view --log`
      format; the no-match line carries neither token; `headBranch`/`headSha` printed.
- [x] 1.10 Seam row in `lb-weight-gate-with-marker.test.sh` (G6).
- [x] 1.11 Raise `MIN_CASES`; per-section executed-row counters.
- [x] 1.12 `BASELINE_DECLARED_PROBES` 98 -> 99 in `preflight-discoverability-test.test.ts`.
- [x] 1.13 Confirm the new rows are RED.

## Phase 2 — the gate

- [x] 2.1 `lb-weight-gate.sh`: `SOAK_FLOOR_DAYS=3`, `EV_KIND=` initialised above `fail()`, three-digit regex, floor checks, `EV_*` record, emission in
      `fail()` and the two pass emits, header comments.

## Phase 3 — helper, probe and workflow

- [x] 3.1 Create `scripts/lib/serve-soak-evidence.sh` (Part 2).
- [x] 3.2 Create `scripts/serve-soak-evidence-last.sh` (G11).
- [x] 3.3 `cf-lb-overlay.yml`: gate chain capture (redirect after the wrapper path) + EXIT trap + step-level
      `SOLEUR_GATED_HOST` + guarded helper load + bare helper call + inline `gate_rc` backstop; new grader step;
      job header comment. Keep the inner `SOLEUR_GATED_HOST="web-2"` literal and the exact wrapper hand-off
      (`g3_dbin_ok`).
- [x] 3.4 `infra-validation.yml` `pull_request` paths (grader, helper, probe).
- [x] 3.5 Grader comment above `SOAK_DAYS=3` (the line itself untouched).

## Phase 4 — records

- [x] 4.1 ADR-263 addendum (floor, cap, grader, `env -i`, residuals AP-027 / #12938 / #12939, the 6604 reader)
      and supersession blockquote; ADR-068 pointer.
- [x] 4.2 `model.c4` edit; regenerate `model.likec4.json`; C4 tests.
- [x] 4.3 Runbooks: `cf-lb-a-record-gaplessness-verify.md` (new section + refusal table incl. `*_invalid`, id
      `none`, the 90-day `NOT_YET` row), `web-host-replace.md`.

## Phase 5 — verification

- [x] 5.1 Three suites plus `workspaces-luks-verify-workflow.test.sh` green; `python3 scripts/lint-guard-contract.py` on the plan; C4 tests; actionlint;
      shellcheck on the gate, grader, helper and probe.
- [x] 5.2 Run every by-hand mutation once; record each and the row it turned RED for the PR body.
- [x] 5.3 PR body: `Closes #12849`, `Ref #12008`, `Ref #9421`, Operator Holds.
