# Tasks — Widen the anti-vacuity floor hardening

Plan: `knowledge-base/project/plans/2026-08-16-feat-widen-anti-vacuity-floor-plan.md`
Branch: `feat-one-shot-anti-vacuity-floor-widen`
Lane: `procedural`

Phase order is load-bearing. Phase 3 consumes what Phase 1 produces; building the
consumer first leaves it with nothing to run against.

---

## Phase 0 — Preconditions (no edits)

- [ ] 0.1 Re-run each of the 7 target suites; record exact counts. Do **not** trust the
      plan's 2026-08-16 table — a sibling merge can move any count.
  - [ ] 0.1.1 `bash scripts/derive-app-domain-base.test.sh` → record `CASES_RUN`, `passes`
  - [ ] 0.1.2 `bash scripts/marketplace-manifest-validate.test.sh` → record `ASSERTED`
  - [ ] 0.1.3 `bash scripts/verify-marketplace-ruleset.test.sh` → record `ASSERTED`
  - [ ] 0.1.4 `bash scripts/digest-oracle-guard.test.sh` → record `asserts`
  - [ ] 0.1.5 `bash scripts/test-contention.test.sh` → record `pass_n + fails`
  - [ ] 0.1.6 `bash scripts/tmpfs-guard.test.sh` → record `pass_n`
  - [ ] 0.1.7 `bash plugins/soleur/test/preflight-check10-suite-integrity.test.sh` → record
        `PASS+FAIL`, `n_manifest`, `n_pass`, `n_expect`
- [ ] 0.2 `bash scripts/guard-vacuity-floor.test.sh` → must be GREEN as-shipped. A red
      control voids every downstream reading.
- [ ] 0.3 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
      → must be clean **before** any edit. Record `wc -l` of the baseline file.

## Phase 1 — Contract declaration (enabling change)

- [ ] 1.1 Define the `# vacuity-contract: cases=<var> passes=<var> fails=<var> assert_fns=<fn>[,<fn>] anchor=<literal>`
      line format. `anchor` must be a literal unique to that suite's floor block.
- [ ] 1.2 Add the contract line to all 40 floor-bearing suites, immediately above each
      covered floor. For the 33 non-tier-1 suites this is **comment-only** — no behavioural
      change.
- [ ] 1.3 Author `knowledge-base/engineering/architecture/decisions/ADR-191-anti-vacuity-floor-contract.md`
      (ordinal provisional — re-derive before merge).

## Phase 2 — Harden the 7 tier-1 suites

For each suite: **read the file first.** Counter names, helper names, and floor shapes
differ in every one. Do not pattern-substitute.

- [ ] 2.1 Introduce an independent `cases` counter per suite, incremented at assert-helper
      **entry**, before the verdict branch. Never inside `$( )` — a subshell discards it.
  - [ ] 2.1.1 `marketplace-manifest-validate` / `verify-marketplace-ruleset`: move the
        existing `ASSERTED` increment out of `pass()`/`fail()` to the entry point
  - [ ] 2.1.2 `digest-oracle-guard`: move `asserts` out of `ok()`/`bad()` to the entry point
  - [ ] 2.1.3 `derive-app-domain-base`, `test-contention`, `tmpfs-guard`,
        `preflight-check10-suite-integrity`: introduce a new `cases` counter (none exists)
- [ ] 2.2 Re-report every floor directly: replace `fail "…"` / `bad "…"` with
      `printf >&2` + `exit 1`, following `scripts/plugin-legacy-resolver-probe.test.sh`.
      Covers the 9 `fail`/`bad`-routed floors; convert the 2 inline-increment floors too,
      so each suite has one shape.
- [ ] 2.3 Add the accounting-conservation check per suite, reported directly, after the floor.
- [ ] 2.4 **Ratchet last**, from a re-measured green run (2.1–2.3 add assertions):
  - [ ] 2.4.1 `derive-app-domain-base` `CASES_RUN`: 26 → re-measured (28 on 2026-08-16)
  - [ ] 2.4.2 `preflight-check10-suite-integrity` `MIN_CHECKS`: 11 → re-measured (13 on 2026-08-16)
  - [ ] 2.4.3 Record both pre-edit and post-edit numbers for AC12
- [ ] 2.5 Preserve `derive-app-domain-base`'s exact `EXPECTED_PASSES` pin and
      `test-contention`'s `# POSITIVE CONTROL` block. Neither is redundant with conservation.

## Phase 3 — Generalize `scripts/guard-vacuity-floor.test.sh`

- [ ] 3.1 Derive the candidate population (set A) by sweeping `scripts/*.test.sh` and
      `plugins/soleur/test/*.test.sh` for the floor-marker family: `anti-vacuity`,
      `vacuity guard`, `cardinality guard`, `assertion floor`, `assertion-count floor`,
      `MIN_ASSERT`, `MIN_CASES`, `MIN_CHECKS`, `EXPECTED_MIN`.
- [ ] 3.2 Read the declared contracts (set B).
- [ ] 3.3 Reconciliation gate: `A \ B` must be empty. A candidate without a parseable
      contract is **FATAL naming the file** — never a skip.
- [ ] 3.4 Generalize `build_mutant`. Remove all four hardcodings: the floor-block grep
      (`^if [[ "$cases" -lt `), the counter declarations, the neutering (stub **every** name
      in `assert_fns`), and the exit trailer. Keep extraction sourced from the real file.
- [ ] 3.5 Add a conservation mutation arm: a mutant with the counter at full value and
      verdicts discarded must exit non-zero.
- [ ] 3.6 Keep and extend the negative control — the pre-fix `fail`-routed shape must still
      exit 0 under neutering.
- [ ] 3.7 Floor the meta-guard itself: an absolute hand-ratcheted `cases` floor **and** a
      hand-ratcheted minimum on the derived population size. Neither derived from a variable
      this file computes.
- [ ] 3.8 Exemption ledger for contract 2: the 30 suites, each with a tracking issue, size
      asserted so it can only shrink.
- [ ] 3.9 File the tracking issue for contract-2 rollout to tiers 2 and 3.

## Phase 4 — Registration and verification

- [ ] 4.1 Register any new `scripts/*.test.sh` in `scripts/test-all.sh` (that dir is NOT
      auto-globbed). Expected no-op — all 7 targets are already registered.
- [ ] 4.2 `bash scripts/lint-orphan-test-suites.sh` → exit 0.
- [ ] 4.3 Verification battery:
  - [ ] 4.3.1 `bash scripts/guard-vacuity-floor.test.sh` → exit 0, population reported = 40
  - [ ] 4.3.2 Each of the 7 suites unmutated → exit 0
  - [ ] 4.3.3 Each of the 7 suites with its own `fail`/`bad` stubbed + a genuine defect →
        exit non-zero **via `[FATAL] accounting:`**, not via the count floor. Record the line.
  - [ ] 4.3.4 Delete a `vacuity-contract:` line → meta-guard exits non-zero naming that file
  - [ ] 4.3.5 `grep -nE '\$\([^)]*(cases|ASSERTED|asserts)[^)]*\+ 1' <each edited file>` → empty
  - [ ] 4.3.6 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
        → clean, and baseline `wc -l` not grown vs 0.3
  - [ ] 4.3.7 `shellcheck -S warning <each changed .sh>` → clean
  - [ ] 4.3.8 `python3 scripts/lint-guard-contract.py <plan>` → exit 0
  - [ ] 4.3.9 `bash scripts/test-all.sh scripts` → exit 0
- [ ] 4.4 Re-derive the ADR ordinal across **all** `origin/*` refs immediately before merge.
      If it moves, sweep the plan, this file, and any AC naming it in the same edit.
- [ ] 4.5 Confirm issue **#7553** is neither referenced as `Closes` nor closed.

---

## Traps (carried from the plan's Risks section)

- A `$(cmd | pipeline)` capture under `set -euo pipefail` dies **at the assignment** on a
  no-match, making any `[[ -n "$x" ]] || { echo FATAL; exit 2; }` guard below it unreachable.
  Use the brace form `{ cmd || true; }`; a trailing `|| true` binds only to the last stage.
- Never set a floor by guessing. Run the suite, count, then set it.
- "Equivalent mutant" is a claim requiring proof — trace both branches to a difference in
  observable output before recording it.
- A conservation check whose case counter moves inside the verdict helper is a **tautology**
  and can never fail. That is the defect class this work exists to end, not a shortcut.
