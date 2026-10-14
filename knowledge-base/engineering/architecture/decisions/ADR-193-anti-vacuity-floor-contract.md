# ADR-193: A suite's anti-vacuity floor reports directly, and its case counter moves at the call site

- **Status:** Accepted. True the moment the code merges — no soak window, no time-gated criterion.
- **Date:** 2026-08-16
- **Predecessor:** the four guard-vacuity gaps closed in `f84e508` (merged 2026-08-16), which
  established the shape on two delivery-path suites. This ADR generalises that shape into an
  obligation on the corpus and replaces the hardcoded two-suite population with a derived one.
- **Relationship to ADR-183:** **independent.** ADR-183 moved the full battery from
  implementation-exit to ship. This ADR is about whether a suite's *own* result can be trusted at
  all, which is orthogonal to when the battery runs.

## Context

A bash suite in this repo typically ends with an anti-vacuity floor whose job is to notice "no
assertions ran" — a harness that silently asserts nothing would otherwise report a clean `0/0`.
The near-universal way to write that floor was to call the suite's own `fail`:

```bash
if [[ "$cases" -lt 75 ]]; then fail "vacuity guard: only $cases assertions ran"; fi
...
[[ "$fails" -eq 0 ]]
```

`fail` increments `fails`, and the exit status reads `fails`. **The detector therefore ran
through the thing it detects.** Neuter `fail` — redefine it, break its arithmetic, lose its body
to an editing slip — and every assertion row goes quiet *and so does the floor that exists to
notice the quiet*. The suite prints a total and exits 0.

There is a second half, and it is the one that actually bites in practice. The floor only catches
*"no assertions RAN"*. It cannot catch *"assertions ran and their verdicts were DISCARDED"*,
because the case counter is incremented by the assert HELPERS and never by `fail`. Stub `fail` to
a no-op in a real suite and the counter stays at full value, the floor is satisfied, and the run
exits 0 with real failures hidden. Measured on the probe suite before its fix:
`45 passed, 0 failed (48 assertions)`, RC=0, with a genuine defect present.

A third failure mode was found while generalising, and it is the reason this ADR exists rather
than a learning file. A case counter incremented **inside both verdict helpers** makes the
conservation identity a **tautology**: the counter moves *with* the verdict, so stubbing `fail`
drops the row and its count together and `passes + fails == cases` still holds under the exact
fault it was written to catch. Measured on the `ok`/`bad` shape: `conservation GREEN — defect
hidden`, RC=0. Three of the ten suites hardened here had precisely that shape, and it reads as
correct at every call site.

## Decision

**1. A floor reports with `printf >&2` + `exit 1` directly, never through the suite's own verdict
helpers.** A floor enforced through the suspect cannot witness the suspect. This applies to every
floor a suite carries, including floors that measure a *system under test* rather than the suite
itself — those route through the same `fail` and are silenced by the same fault.

**2. The case counter is incremented at the CALL SITE, and the verdict helpers touch only the
verdict counters.** This is what makes conservation non-tautological, and it is not a stylistic
preference: it is the entire difference between a check that catches a discarded verdict and one
that cannot. The increment must never sit inside a command substitution `$( … )` — a subshell
discards it, and the code reads as correct.

**3. A suite carrying a floor also carries an accounting-conservation check** (an obligation on
new suites; enforced today over the suites that carry one, with a shrink-only ratchet, rather
than over every floor-bearing suite in the corpus) — `passes + fails
== cases` — reported directly, for the same reason as the floor. It diagnoses **both**
directions: fewer verdicts than counted means a discarded verdict (a neutered helper); more means
a call site with no increment (a harness bug). Naming both keeps a genuine harness slip from
reading as a product failure.

**4. Where a suite's floor and its conservation check can both fire on the same fault, the
conservation check runs FIRST.** A neutered `fail()` deflates the pass count, so a floor or exact
pin reading passes *also* trips — and whichever runs first exits and names the fault. Ordering
conservation first makes the run say "a verdict was discarded" instead of the misleading
"assertions were added or removed". Where the floor reads an independent `cases` counter the
conflict does not arise, which is the preferred shape.

**5. The population is DERIVED, never listed.** `scripts/guard-vacuity-floor.test.sh` enumerates
tracked `*.test.sh` recursively and classifies by SHAPE — a `-lt`/`-ge`/`-le` comparison against a
counter the file itself increments. A hand-maintained list is the snapshot that goes stale, which
is the same failure class one level up. A suite whose floor the guard cannot construct a runnable
mutant for is **named and counted**, never silently skipped.

## Why the mutation oracle asserts the REASON, not the exit code

This is the single highest-value constraint in the ADR, and it was found by measurement rather
than argument.

The guard builds a mutant by slicing the floor block out of the real file, neutering every helper
(`command_not_found_handle() { return 0; }`, which beats a declared helper list because a declared
list can be under-declared), zeroing the counters, and running it. The obvious oracle is
`rc != 0`.

That oracle is wrong, and it was scoring crashes as passes. A slice that starts at the floor's
`if` leaves a threshold assigned on the *preceding* line unbound; under `set -u` the mutant dies
**before reaching the floor**, exiting non-zero for both the pre-fix and post-fix forms.
The effect is reproducible in the shipped tree: disabling the backward slice-widening moves
suites out of FIRES and into the construction bucket wholesale, and the failure mode is
`MIN_ASSERTS: unbound variable` — the mutant dying before the comparison it exists to test.
(An earlier draft of this ADR put the ratio at "8 of 11". That figure came from an intermediate
builder and does not reproduce against anything in the tree; the directional finding is what is
load-bearing, so the numerals are dropped rather than restated.)

So the oracle requires a floor-shaped sentinel on stderr, and classifies shell-error signatures as
a distinct **construction failure** — its own loud class, neither pass nor fail. The slice is
widened backward over contiguous assignments so thresholds are bound, and only *counter* variables
are zeroed: zeroing a threshold inverts a `-ge` floor's polarity and destroys discrimination.

## Consequences

- Every floor-bearing suite under `scripts/` and `plugins/soleur/test/` **for which a runnable
  mutant can be constructed** is mutation-tested on every PR via the CI-required `test` context.
  A suite that regresses to a `fail`-routed floor is caught by derivation, with no author action
  and no list to update. Suites whose floor block is not independently runnable are counted
  separately and named — see the next bullet; the guard does not claim to have tested them.
- Suites whose floor block is not independently runnable (it reads state computed by surrounding
  code) are counted against a **shrink-only** ratchet. They are visible debt, not silence.
- **Closure is enforced by two DECLARED directory scopes plus an UNCLASSIFIED bucket that must
  be empty** — not by the arithmetic identity `covered + deferred == total`. That identity was
  drafted, shipped, and then falsified by mutation: deriving `deferred` as "everything not
  covered" makes the two sets a partition of one list, so the sum always equals the total and
  the arm can never fail. A floor-bearing suite added under a directory in neither scope left
  the guard GREEN. With both scopes declared, that suite lands in UNCLASSIFIED and the guard
  reddens naming the file. The deferral ledger additionally carries a shrink-only ratchet, so
  the deferred set cannot silently accrete.
- The corpus outside those two directories (notably `apps/web-platform/infra/`, which has its own
  runner) is deferred and counted, not forgotten.

> **Amended 2026-08-19 (#7580).** The bullet above was accurate and insufficient, and the gap was
> exactly the distance between its two verbs. *Counted* is what the deferred corpus was; *counted*
> is what failed to notice that **eleven** of its suites carried floors exiting 0 under a neutered
> assertion machinery. Because the mutation loop read `$COVERED` only, every arm of
> `guard-vacuity-floor.test.sh` returned an identical verdict before and after those eleven were
> fixed — a repair the guard could not observe.
>
> The deferred scope is now **mutation-classified in place**, not merely counted (ARM 2b). It
> carries its own shrink-only NO_FIRE ratchet, pinned at **0**: a set invariant ("every member
> fires") has no tolerance, and slack in a floor is narrowing budget. Alongside it sits an exact
> bucket identity — `fires + nofire + construct == n_deferred` — which is strictly stronger than a
> floor on the classified count, because it catches an arm that classifies an *empty* list. That
> arm would report `0 NO_FIRE` and pass while classifying nothing, which is this ADR's own defect
> one level up.
>
> A second shrink-only ratchet, `MAX_DEFERRED_CONSTRUCTION`, closes an escape path the amendment
> itself opens: a floor **rewrite** can move a suite from NO_FIRE into CONSTRUCTION rather than
> into FIRES, driving the NO_FIRE count to 0 while the property still fails.
> `MAX_CONSTRUCTION_FAILURES` cannot see that — it is global and derived from `$COVERED`.
>
> This is deliberately **not** promotion into `COVERED_DIRS`. `COVERED_DIRS`,
> `MAX_CONSTRUCTION_FAILURES` (15) and `MAX_DEFERRED` (47) are unchanged. Promotion remains blocked
> on arithmetic: the deferred scope carries **18** mutant-construction failures against a global cap
> of 15 with zero headroom, so it would push that cap to ~33 and stop ARM 2 discriminating. Tracked
> as the precondition on #7585.
>
> `CONSERVING` now spans both scopes, so ARM 10/10b/10c/10d cover the deferred suites' conservation
> checks; `MIN_CONSERVING` was raised 18 → 32, its measured post-amendment value.

## Alternatives considered

| Alternative | Why not |
|---|---|
| A declared `# vacuity-contract:` line on every suite | **Falsified by construction.** A generic mutant builder with zero declarations discriminated 8/8, including the `ok`/`bad` case the proposal was built on. It also replaced a hardcoded list of 2 with a hand-maintained obligation on 40 — the same failure class at larger scale. |
| Keep the hardcoded suite list, extend it to 7 | The snapshot that goes stale is the defect being fixed. |
| Restate each floor inside the meta-guard | A restated copy is a second pin, and the copy that drifts is the one that runs. |
| Run every covered suite to completion for the conservation arm | Would make the meta-guard as slow and flaky as the batteries it guards. Conservation is checked structurally (no increment inside a verdict helper; no increment inside `$( )`; the check reports directly) and proven per-suite by mutation at authoring time. |
| A shrink-only exemption ledger of individual suite names | A ratchet on a list of things deliberately not done: adding a legitimate new suite fails CI on bookkeeping, and the predictable response is to edit the assertion. Replaced by the directory split plus the closure identity. |
