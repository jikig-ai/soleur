# Decision Challenges — feat-one-shot-7291-t5-mutation-network-flake

Persisted by `plan-review` (headless arm) per ADR-084. `ship` Phase 6 renders these into the PR body
and files an `action-required` issue. Not auto-applied — each contradicts the operator's stated
direction and needs an explicit operator decision.

---

## UC-1 — Drop the SKIP verdict entirely; make it a loud, correctly-attributed FAIL

**Class:** User-Challenge (contradicts operator-stated direction in #7291)
**Raised by:** CTO review (devex lens), plan review 2026-08-12
**Status:** surfaced, not applied — the plan proceeds with SKIP as #7291 directs

### The operator's stated direction (the default)

Issue #7291: *"On a download failure the honest verdict is SKIP-with-reason (or a retry), not FAIL"*,
and *"assert the precondition explicitly, emitting `SKIP: T5 mutation needs the real tarball;
download failed` while keeping the cardinality floor honest."*

### What the challenge proposes instead

A two-branch verdict with no new vocabulary: execution marker present and `CHMOD_RAN` absent ⇒ FAIL;
execution marker absent ⇒ **FAIL, with a message that names non-execution and prints the docker rc**.

### The argument for the challenge

1. The check is **not merge-blocking** — verified against all four live repo rulesets; the
   `deploy-script-tests` context appears in none of them. A red check on a non-blocking job costs a
   triage cycle, and so does a SKIP that a human must still read and interpret. The two cost the
   same.
2. It buys **zero new vocabulary**: no `SKIPPED` counter, no ceiling constant, no floor arithmetic
   change, no amended B5 doctrine block, and — decisively — **no ADR**, since nothing in that slice
   changes the verdict taxonomy. That removes roughly two thirds of the plan's diff.
3. The diagnostic improvement that actually matters (rc + stdout captured, non-execution named
   rather than mislabelled "vacuous") is delivered in full by the FAIL branch. The current bug is
   that the message *lies about what happened*, not that the run is red.

### The argument for keeping SKIP (why the plan proceeds as-is)

1. It is what the operator asked for, and operator direction is the default absent a
   security/feasibility regression.
2. **AP-021 / ADR-166**, a registered principle with a blocking CI lint, independently supports it:
   *"a verdict must never collapse 'could not check' into 'bad' (the DEAD/UNVERIFIABLE/UNMEASURED
   distinction calls for different, sometimes opposite, operator actions)."*
3. **ADR-177** already established that a non-executing run rendering identically to a failing one
   *"trains the reader to treat `[FAIL]` on that suite as noise, so the next genuine failure is
   pre-discounted"* — the exact harm a permanent FAIL-on-non-execution would cause here.

### What would settle it

The challenge is strongest if the flake proves rare after the pre-bake (Deferred Scope) lands, since
a verdict class that fires once a quarter earns less machinery than one firing weekly. It is weakest
if the arm skips regularly, because then ADR-177's noise-training argument dominates.

**Decision needed from the operator:** proceed with the counted SKIP verdict (plan as written), or
re-scope to the two-branch FAIL and drop the counter, ceiling, floor change and ADR-186.
