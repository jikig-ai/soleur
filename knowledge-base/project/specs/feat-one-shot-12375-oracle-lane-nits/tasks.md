# Tasks — feat-one-shot-12375-oracle-lane-nits (#12375)

Derived from `knowledge-base/project/plans/2026-11-09-chore-oracle-lane-post-unlock-nits-plan.md`.
All edits are comment-or-test-assertion only; no driver (`scripts/ci-oracle-lane.sh`) changes.

## Phase 1 — Stale-comment rewrites (4 sites)

Scope discipline (deepen-pass): rewrite ONLY the stale lock sentences; the surrounding accurate text (the `if:` non-empty compare explanation, ORACLE_HEAD_OK event-agnostic binding, S4 input descriptions) stays.

- [x] 1.1 `.github/workflows/ci.yml` oracle-selection job header comment (~L432-444): replace the "SWITCHED OFF, THEN DARK AND LOCKED" staging line and the "While `ORACLE_LANE_LOCKED=1` stands in the driver, `active` never becomes `true` … (dark launch; activation is a separate authorized step …)" sentences with post-activation semantics — compile-time lock removed by #12300 (2026-11-08); `ORACLE_LANE_LOCKED=1` in env is the unwired dark-mode revert path; `active` becomes `true` on an oracle-only diff with `SWITCH=on`.
- [x] 1.2 `.github/workflows/ci.yml` aggregator env comment (~L2437): replace "While `ORACLE_LANE_LOCKED=1` stands in the driver, `active` is always `false` and nothing is tolerated" with the env re-lock / armed semantics.
- [x] 1.3 Do NOT touch the pr-selection S4 comment (~L2430 "While the activation lock holds") — `PR_AFFECTED_LOCKED=1` still stands at `scripts/ci-pr-selection.sh:90`. [AC-2]
- [x] 1.4 `apps/web-platform/test/c4-likec4-version-pin.test.ts` ~L262-264: replace "while `ORACLE_LANE_LOCKED=1` stands in the driver" with env re-lock phrasing (the committed literal was removed by #12300).
- [x] 1.5 `scripts/ci-draft-light.test.sh` ~L99: rephrase "(active, not oracle_only: oracle_only is true during the locked dark phase while active stays false)" to name the live distinction — a non-`on` switch or an `ORACLE_LANE_LOCKED=1` env re-lock can leave `oracle_only` true while `active` stays false.

## Phase 2 — Mutation-battery label + surgical mutant (`scripts/ci-oracle-lane.test.sh`)

- [x] 2.1 Retitle `mutate "O-LOCK the arm ignores the lock" "$UNLOCKED" "$(kill_guard O-ARM)" row_switch` to name what it proves (arm-presence, e.g. `O-ARM the whole arm line is deleted (arm-presence, not lock-conjunct)`). [AC-4]
- [x] 2.2 Add `mutate "O-LOCK the arm's lock conjunct is dropped" "$PRISTINE" 's| && \[ "\$locked" = false \]||' row_lock` — port of `scripts/ci-pr-selection.test.sh:1455`; sed verified lands on driver:384 and `bash -n` clean. [AC-4]

## Phase 3 — `ORACLE_LANE_LOCKED` negative-value sweep in `row_lock()`

- [x] 3.1 After the existing `ORACLE_LANE_LOCKED=1` assertions in `row_lock`, add `for v in 0 true on; do drive accept "$d" "SWITCH=on" "ORACLE_LANE_LOCKED=$v";` with `check_eq` rows asserting `active=true`, `skip_legs=$ORACLE_FIVE`, notice `locked=false`. [AC-5]
- [x] 3.2 Add `mutate "O-LOCK the lock-read is loosened to non-empty" "$PRISTINE" 's|\[ "\${ORACLE_LANE_LOCKED:-}" = 1 \]|[ -n "${ORACLE_LANE_LOCKED:-}" ]|' row_lock` — the probe that proves the sweep discriminates (sed verified lands on driver:137). [AC-6]

## Phase 4 — `cmp -s` intent annotation

- [x] 4.1 Add one comment line at the `cmp -s "$PRISTINE" "$UNLOCKED"` pin (~L1060) naming the residual property: bounds the recipe's blast radius; `$UNLOCKED` is the file `row_switch` + two mutants are measured against. [AC-6]
- [x] 4.2 (optional) Re-derive `MIN_ROWS` via `bash scripts/ci-oracle-lane.test.sh | tail -1` and bump the floor in the same commit.

## Phase 5 — Verification

- [x] 5.1 `bash scripts/ci-oracle-lane.test.sh` → exit 0, `mutation battery: K/K killed`, zero `surviving mutants`. [AC-7]
- [x] 5.2 `bash -n scripts/ci-oracle-lane.test.sh` clean; `git diff` shows only comment-syntax lines changed in `ci.yml`, `c4-likec4-version-pin.test.ts`, `ci-draft-light.test.sh`. [AC-8]
- [x] 5.3 `grep -c 'stands in the driver' .github/workflows/ci.yml` → 0 in oracle-lane contexts; pr-selection lock comment unchanged. [AC-1..3]
