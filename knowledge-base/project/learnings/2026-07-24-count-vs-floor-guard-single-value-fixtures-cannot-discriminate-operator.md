# Learning: a count-vs-floor guard tested only at floor∈{0,1}/count∈{0,1} cannot distinguish `<` from `!=` (and a new validator branch needs its own fixture)

## Problem

I added a `check_live_coverage_floor` guard to `scripts/lint-encryption-posture.py` (#6902): when the ledger declares `live_coverage_floor >= N`, the sweep asserts `available >= N` where `available` counts stores with `at_rest.live_verification == "available"`. I wrote what looked like a thorough test set:

- AC3: floor=1, 1 available → PASS
- AC2: floor=1, 0 available → FAIL (single-cause)
- MB-13: mutation-delete the fail branch → the AC2 fixture flips FAIL→PASS (non-vacuity)
- floor-absent: field omitted, 0 available → PASS (no-op)

`test-design-reviewer` proved two surviving mutants my suite did not kill:

1. **`if available < floor:` → `if available != floor:` survives the whole suite.** Every fixture evaluated the guard only at `(floor, available) ∈ {(1,1), (1,0), (0,0)}` — and at those three points `available < floor` and `available != floor` are identical. The `!=` form is a plausible real bug: it false-FAILs legitimate over-coverage (floor=1 with 2 available). The docstring advertised a "COUNT floor," but no fixture ever proved it was a floor (`<`) rather than an equality pin.
2. **The new `validate_ledger` branch (`live_coverage_floor must be a non-negative integer`, including the deliberate `isinstance(lcf, bool)` reject) had ZERO fixtures.** Deleting `or isinstance(lcf, bool)` → a JSON `true` is read as floor 1; deleting the whole branch → a negative floor is accepted. Both survived. The bool-reject was important enough that I wrote a defensive code comment for it — but nothing tested it.

## Solution

Add fixtures that move the guard OFF the collinear points:

- **Over-coverage:** floor=1, **2** available → PASS. Under the `!=` mutant this is FAIL, so the fixture kills it.
- **Magnitude:** floor=**2**, 1 available → FAIL. Pins that the guard reads the *declared value*, not a hardcoded 1.
- **Validator branch:** `live_coverage_floor: true` and `: -1` → FAIL (needle `non-negative integer`); explicit `: 0` present → PASS (positive control that the OPTIONAL_TOP allowance is reachable).

Both mutants confirmed killed by running the true SUT vs each mutant against an **empty repo-root** (so the unrelated resource-partition / positive-work checks are inert and the live-coverage floor is the only active gate). Suite went 40→45 green.

## Key Insight

For a guard that compares a **count** to a **threshold**, the fixture set must include a point where the *plausible wrong operator* gives a *different verdict* than the correct one. `<`, `<=`, `==`, `!=`, `>` all agree at the single boundary point `(N, N)` and at `(N, N-1)`; they diverge only at `(N, N+1)` (over-threshold) and at a second magnitude `N≥2`. Testing only at the boundary proves nothing about which operator you wrote. This is the documented "fixture-space cardinality" anti-pattern (`cq`-adjacent; the 2026-07-19 "my own mutation battery was the false confidence" learning) — and it recurred in *my* work despite the AGENTS warnings, which is exactly why it's worth a concrete instance.

Corollary: **every new `validate_*` reject branch is a distinct behavior that needs its own fixture.** A defensive code comment ("bool is an int subclass; reject explicitly") is a signal that the branch is load-bearing and therefore mutation-worthy — write the fixture that fails without it.

## Session Errors

- **Vacuous count-vs-floor fixtures (recurring class)** — Recovery: added over-coverage + magnitude + validator fixtures; verified both mutants killed. Prevention: for any count-vs-threshold guard, fixture at least one over-threshold point AND one threshold≥2 point; cover every new validator reject branch with a fixture. Routed to this learning.
- **Confounded mutant verification (one-off)** — First direct mutant check ran with `--repo-root .` (the real tree), so the real resource-partition/positive-work checks failed the synthetic 2-store ledgers and masked the floor's verdict. Recovery: re-ran with an empty repo-root (matching the test suite's `$REPO_LCF`), which zeroes `tf_store_count` and isolates the floor. Prevention: mutation-verify a synthetic-ledger guard against the SAME empty repo-root the suite uses, never the real tree.

## Tags
category: test-failures
module: encryption-posture-lint
