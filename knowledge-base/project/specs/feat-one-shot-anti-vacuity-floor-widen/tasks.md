# Tasks — Widen the anti-vacuity floor hardening

Plan: `knowledge-base/project/plans/2026-08-16-feat-widen-anti-vacuity-floor-plan.md`
Branch: `feat-one-shot-anti-vacuity-floor-widen`
Lane: `procedural`

**Revised after three deepen-plan review passes.** The contract-line design (R1) and the
40-suite corpus figure (R2) were both falsified by measurement; see the plan's
`## Deepen-Plan Revisions` table before starting. Phase order is load-bearing.

---

## Phase 0 — Preconditions (no edits)

- [ ] 0.1 Re-run each of the 7 target suites; record exact counts. Do **not** trust the plan's
      2026-08-16 table.
  - [ ] 0.1.1 `bash scripts/derive-app-domain-base.test.sh` → `CASES_RUN`, `passes`
  - [ ] 0.1.2 `bash scripts/marketplace-manifest-validate.test.sh` → `ASSERTED`
  - [ ] 0.1.3 `bash scripts/verify-marketplace-ruleset.test.sh` → `ASSERTED`
  - [ ] 0.1.4 `bash scripts/digest-oracle-guard.test.sh` → `asserts` (note: floor is `-ge`)
  - [ ] 0.1.5 `bash scripts/test-contention.test.sh` → `pass_n + fails`
  - [ ] 0.1.6 `bash scripts/tmpfs-guard.test.sh` → `pass_n`
  - [ ] 0.1.7 `bash plugins/soleur/test/preflight-check10-suite-integrity.test.sh` →
        `PASS+FAIL`, `n_manifest`, `n_pass`, `n_expect`
- [ ] 0.2 `bash scripts/guard-vacuity-floor.test.sh` → must be GREEN as shipped. A red control
      voids every downstream reading.
- [ ] 0.3 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
      → clean **before** any edit. Record the baseline's `wc -l`.
- [ ] 0.4 Re-derive the repo-wide corpus (74 on 2026-08-16) and the covered/deferred split
      (40 / 34). These feed the Phase 3.7 closure identity — do not copy from the plan.

## Phase 1 — Record the invariant

- [ ] 1.1 Author `knowledge-base/engineering/architecture/decisions/ADR-191-*.md` (ordinal
      **provisional**): floors report `printf >&2` + `exit 1` directly, never through the
      suite's assert functions; conservation from call-site increments; population derived
      from floor shape and closed over the repo.
- [ ] 1.2 Add **AP-023** to `knowledge-base/engineering/architecture/principles-register.md`
      referencing ADR-191, enforcement `hook (CI-required suite: scripts/guard-vacuity-floor.test.sh
      via test-all.sh)`. Precedent: AP-021, AP-022.
- [ ] 1.3 **No contract-line rollout** (R1). The 33 comment-only edits are cut.

## Phase 2 — Harden the 7 tier-1 suites

Read each file first. Counter names, helper names, floor polarity, and indentation all differ.

- [ ] 2.1 Introduce an independent `cases` counter incremented at the **CALL SITE** (R4), the
      `plugin-legacy-resolver-probe` shape. `pass()`/`fail()` touch only verdict counters.
      Never inside `$( )`.
  - [ ] 2.1.1 `marketplace-manifest-validate` (~22 sites): move `ASSERTED` out of both helpers
  - [ ] 2.1.2 `verify-marketplace-ruleset` (~27 sites): move `ASSERTED` out of both helpers
  - [ ] 2.1.3 `digest-oracle-guard` (~26 sites): move `asserts` out of `ok()`/`bad()`
  - [ ] 2.1.4 `derive-app-domain-base`, `test-contention`, `tmpfs-guard`,
        `preflight-check10`: introduce a new `cases` counter (none exists)
  - [ ] 2.1.5 Enumerate every bare call site **and** every wrapper (`expect_rc`, `expect_mut`,
        `assert_jq`) per suite — do not sample. A missed site makes conservation permanently
        unequal and the suite permanently red.
- [ ] 2.2 Add the **call-site coverage lint**: per covered suite, assert no verdict-function
      call site is reachable without a preceding `cases` increment.
- [ ] 2.3 Re-report every floor directly (`printf >&2` + `exit 1`). Two need more than a call swap:
  - [ ] 2.3.1 `digest-oracle-guard`: predicate is **inverted** (`-ge`) with the success arm
        calling `ok`. Invert to `-lt`, drop the `else`, delete the `ok` row.
  - [ ] 2.3.2 `derive-app-domain-base`: floor's `else` calls `pass(…)`, counted by the exact
        `EXPECTED_PASSES` pin. Same deletion effect.
  - [ ] 2.3.3 Convert the two inline-increment floors too, so each suite has one shape.
- [ ] 2.4 Add the accounting-conservation check per suite, reported directly, after the floor.
- [ ] 2.5 Fix `test-contention`'s positive control (R5): its rollback of `pass_n`/`fails` must
      also cover `cases`, or conservation is permanently false by 2 and the suite is red on
      every run. Restoring `cases` does not defeat the probe — the probe asserts the counters
      *moved*, checked before the rollback.
- [ ] 2.6 Move `tmpfs-guard`'s floor onto `cases` (it currently reads `pass_n`, so real
      failures trip a *cardinality* message for a non-cardinality problem — the class
      `test-contention` already fixed).
- [ ] 2.7 **Ratchet last**, from a re-measured green run (2.1–2.6 change the counts):
  - [ ] 2.7.1 `derive-app-domain-base` `CASES_RUN` 26 → re-measured (28 on 2026-08-16)
  - [ ] 2.7.2 `preflight-check10` `MIN_CHECKS` 11 → re-measured (13 on 2026-08-16)
  - [ ] 2.7.3 `derive-app-domain-base` `EXPECTED_PASSES` 34 → post-conversion measured (R7)
  - [ ] 2.7.4 `digest-oracle-guard` `MIN_ASSERTS` 26 → post-conversion measured (R7)
  - [ ] 2.7.5 Record pre- and post-edit numbers for each (AC14)
- [ ] 2.8 Preserve (re-ratcheted, not removed) `derive-app-domain-base`'s exact
      `EXPECTED_PASSES` pin — it survives a neutered `fail()` and is property 2 by another route.

## Phase 3 — Rebuild `scripts/guard-vacuity-floor.test.sh`

- [ ] 3.1 Derive the population from floor **SHAPE** unioned with marker prose. Enumerate
      tracked `*.test.sh` **recursively** under `scripts/` and `plugins/soleur/test/` —
      **never a shell glob** (`scripts/*.test.sh` is non-recursive: 59 vs 78).
  - [ ] 3.1.1 Signal 1 (structural, primary): a `-lt`/`-ge` comparison against the suite's
        assertion counters. **Must match indented floors** — the `^if [[` anchor misses
        `preflight-check10:196`.
  - [ ] 3.1.2 Signal 2 (prose, secondary): the marker family.
  - [ ] 3.1.3 Regression pins: `terraform-drift-step-order.test.sh` enters via signal 1 only;
        `preflight-check10:196` enters only if indentation is handled.
- [ ] 3.2 Build a runnable mutant with **no declarations** (R1):
  - [ ] 3.2.1 `command_not_found_handle() { return 0; }` — neuters every helper at once
  - [ ] 3.2.2 **Widen the slice backward** over contiguous assignment lines so thresholds bind
  - [ ] 3.2.3 Zero only **counter** variables; preserve thresholds (zeroing one inverts a
        `-ge` floor and destroys discrimination)
  - [ ] 3.2.4 Append `exit 0` rather than reconstructing each suite's trailer
- [ ] 3.3 **Assert the REASON, not the exit code** (R3 — highest-value change). Capture stderr,
      require the floor's own sentinel, and classify `unbound variable` / `command not found` /
      rc=2 as a distinct loud **construction failure**.
- [ ] 3.4 Declare `preflight-check10`'s three nested SUT floors **out of the mutation arm** by
      name and reason, counted (R6). They still get the 2.3 conversion.
- [ ] 3.5 **Loop the conservation arm over the population** (R8): per suite, stub the verdict
      helpers, assert non-zero exit **and** that the message is the conservation sentinel, not
      the floor sentinel.
- [ ] 3.6 Keep and extend the negative control.
- [ ] 3.7 Floor the guard itself, mirroring `scripts/lint-orphan-test-suites.sh`: an absolute
      hand-ratcheted `cases` floor, a population-size minimum, and the **closure identity**
      `covered + deferred == repo-wide total`.
- [ ] 3.8 Add a **synthesized out-of-population must-PASS control** with third counter names.
      (The first draft's two "controls" were population members and asserted nothing.)
- [ ] 3.9 File the tracking issue for the 34 deferred floor-bearing suites.

## Phase 4 — Registration and verification

- [ ] 4.1 Register any new `scripts/*.test.sh` in `scripts/test-all.sh` (not auto-globbed).
      Expected no-op.
- [ ] 4.2 `bash scripts/lint-orphan-test-suites.sh` → exit 0.
- [ ] 4.3 Verification battery (mirrors Acceptance Criteria):
  - [ ] 4.3.1 Guard exits 0; population ≥ ratcheted minimum; closure identity holds
  - [ ] 4.3.2 Per suite: stub `fail`/`bad` + real defect → non-zero **via conservation sentinel**
  - [ ] 4.3.3 Revert a floor to `fail`-routed → RED naming *floor did not fire*
  - [ ] 4.3.4 Remove slice-widening → **construction failure**, never a pass
  - [ ] 4.3.5 `terraform-drift-step-order` and `preflight-check10:196` both in the population
  - [ ] 4.3.6 Floor-bearing suite in an unlisted directory → closure identity RED
  - [ ] 4.3.7 `grep -nE '\$\([^)]*(cases|ASSERTED|asserts)[^)]*\+ 1' <edited files>` → empty
  - [ ] 4.3.8 Call-site lint passes; deleting one increment drives it red
  - [ ] 4.3.9 `test-contention` green with conservation enabled
  - [ ] 4.3.10 `lint-shell-capture-exit.py` clean; baseline not grown
  - [ ] 4.3.11 `shellcheck -S warning` clean on every changed `.sh`
  - [ ] 4.3.12 `bash scripts/test-all.sh scripts` → exit 0
- [ ] 4.4 Re-derive the ADR ordinal across **all** `origin/*` refs immediately before merge. If
      it moves, sweep the plan, this file, and any AC naming it in the same edit.
- [ ] 4.5 Confirm issue **#7553** is neither referenced as `Closes` nor closed.

---

## Traps

- **A non-zero exit is not evidence a floor fired.** Under `set -u` a mutant missing a binding
  dies before the floor with the same exit code. 8 of 11 target floors behave this way today.
  Always assert the reason.
- **Conservation whose case counter moves inside the verdict helper is a tautology** and can
  never fail. Measured: neutered `bad()` printed `conservation GREEN — defect hidden`, RC=0.
- A `$(cmd | pipeline)` capture under `set -euo pipefail` dies **at the assignment** on a
  no-match, making a `[[ -n "$x" ]] || { echo FATAL; exit 2; }` guard below it unreachable.
  Use `{ cmd || true; }`; a trailing `|| true` binds only to the last stage.
- A `cases` increment inside `$( )` is discarded to a subshell.
- Never set a floor by guessing. Run the suite, count, then set it — and ratchet **after** the
  conversions, which delete assertions in two self-counting suites.
- "Equivalent mutant" is a claim requiring proof — trace both branches to a difference in
  observable output before recording it.
- Never specify the sweep as a shell glob; `scripts/*.test.sh` is non-recursive.
