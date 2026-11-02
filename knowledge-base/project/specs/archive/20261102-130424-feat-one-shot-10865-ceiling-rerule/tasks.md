# Tasks: re-rule the observation-window wall ceilings and settle the s4-drain floor (Ref #10865, Ref #10861, Ref #10448)

Plan: knowledge-base/project/plans/2026-11-02-ci-rerule-observation-window-wall-ceilings-plan.md
Rules: `Ref` only, never `Closes`. No baseline edit, no live probe run, no post to #10865, no flip, no `CI_PR_AFFECTED`, no lock removal.

## Phase 0: Preflight (read-only)

- 0.1 Run `bash plugins/soleur/scripts/collision-precheck.sh 10865` (PR #11847 is this branch's own draft PR).
- 0.2 Record `git grep -n -E 'SOAK_BUDGET_S:-270|TIMEOUT_WALL=290|budget_s=270'` (3 sites) and `wc -l` + `git hash-object` of `scripts/ci-pr-affected-audit.baseline.tsv`.

## Phase 1: The probe (`scripts/followthroughs/ratchet-observation-window-10865.sh`)

- 1.1 `P95_MAX=210` to `240`, `MAX_MAX=270` to `285` (anchor `^P95_MAX=` / `^MAX_MAX=`, keep the trailing comment); touch nothing else numeric.
- 1.2 Header criterion (d): 240/285, keep the phrase `ceilings are PROVISIONAL`, cite the 2026-11-02 re-rule; failure strings and PASS echo byte-identical.
- 1.3 Add `DRAIN_SENTINEL=11226` and the fail-closed sentinel as function `drain_sentinel_check`, called once between the `drain_at` validation and the floor application (exit 3 with the one fixed `CANNOT ESTABLISH:` line).
- 1.4 Header RESTART FLOOR clause: floor needs the token to see pull requests; guarded by the sentinel.

## Phase 2: Replay suite (`plugins/soleur/test/ci-pr-affected-replay.test.sh`)

- 2.1 `row_ow_slow`: 250 / over 240; `ow_u_slow` 220 to 250.
- 2.2 `row_ow_max`: 288 / over 285; `ow_u_bigmax` 280 to 288.
- 2.3 `row_ow_timeout`: `over 270` to `over 285` (the consumer the brief omits).
- 2.4 `row_ow_static`: `^P95_MAX=240 ` and `^MAX_MAX=285 `.
- 2.5 Titles of the two `chk` lines (240 s / 285 s).
- 2.6 `ow_case`/`ow_write`: stub `pulls/11226` (default `merged_at` null; `OW_SENTINEL` modes; without a default every existing OW row hits STUB-MISS).
- 2.7 New rows: sentinel trips, older list, applied, unmerged, errors; register with `chk`.
- 2.8 New mutants: sentinel-disarmed, -read-removed, -after-listing (call line becomes `trap 'drain_sentinel_check' EXIT`), -error-ignored, -timestamp-unvalidated; ceiling-p95-raised, ceiling-max-raised. Grep every `^ow_mutate` old string against the probe to prove each lands once.
- 2.9 Confirm no text naming the sweeper workflow was added to this suite (would add a ratchet pair).

## Phase 3: Runbook (`knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`)

- 3.1 Ceilings line, Criteria bullet, "Ceilings are PROVISIONAL" bullet (dated re-rule, recheck trigger).
- 3.2 One sentence: floor depends on the sweeper token's pull-requests scope; sentinel; first post-merge sweeper output must print `floor=s4-drain`.
- 3.3 Dated 2026-11-02 observation-log row with the measured series (372 jobs; p95 218/225; merge_group 212, pull_request 225; max 284; 2 of 372 over 270; daily p95 206, 207, 201, 206, 215, 222, 237; vs oldest-260 203-205) plus the floor finding.

## Phase 4: ADR-276

- 4.1 Append `## Amendment 2026-11-02 (observation-window wall ceilings re-ruled, Ref #10865; Ref #10448)`; item 6 and all earlier text unedited.

## Phase 5: Sweeper workflow and pin

- 5.1 `.github/workflows/scheduled-followthrough-sweeper.yml`: add `pull-requests: read` with a comment.
- 5.2 `scripts/sweep-followthroughs.test.sh`: pin (comment-stripped, top-level present, no job-level override) plus harness rows.

## Phase 6: Verify and ship

- 6.1 `bash scripts/sweep-followthroughs.test.sh`; replay suite OW rows then one full run; `python3 -I scripts/ci-pr-affected-replay.py ratchet` (live == baseline); `bash plugins/soleur/test/c4-count-parity.test.sh`; `technical-ruling-gate.sh --branch`.
- 6.2 PR body: Ref-only; floor evidence (unproven under a GITHUB_TOKEN); exit-code table 0/2/3; oracle-input note (excluded from counts, window not restarted); ratchet-on-main green-or-explained; post-merge `floor=s4-drain` check; rendered decision-challenges rows.
- 6.3 Post nothing to #10865.
