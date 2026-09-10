# Decision Challenges — feat-one-shot-7849-7853-7854-fixture-env-ledger-ancestry

Recorded per ADR-084 / `decision-principles.md`. This run is headless, so these are persisted for
`ship` to render into the PR body and file as an `action-required` issue rather than being asked
interactively.

## DC-1 — split the aggregator reconciliation into its own PR — **RESOLVED, not deferred**

**Class:** originally logged as user-challenge; **reclassified as a technical fork and resolved.**
**Raised by:** the engineering domain leader (CTO) and, independently, the DHH reviewer.

**The challenge.** Plan Phases 4–5 (as first drafted) were the only arms that mutated a committed
artifact (`knowledge-base/project/rule-metrics.json`) and changed a CI gate's failure semantics,
while the rest were test-isolation fixes. One reviewer and one revert unit for two different risk
profiles.

**Why it is not an operator question.** `hr-technical-fork-is-not-an-operator-question` is explicit:
the operator is asked for authorization, cost and scope — not for which path to take. The operator
named the *work* ("address the aggregator orphan gate over `scripts/rule-metrics-aggregate.sh`"),
and issue #7853's own comment consolidated that work into #7853. A PR boundary is a revert-unit
decision that belongs to the engineer. The first draft cited operator direction as cover for a fork
it should have resolved itself; that is corrected here.

**Resolution: one PR.** The split was argued on blast radius proportional to the size of the
mechanism, and the review panel cut that mechanism. What was a hand-maintained 23-entry registry
file, a ~130-line drift lint, a guard contract and two acceptance criteria is now **one jq
predicate**, one `_valid_rule()` simplification, and a regenerated artifact. At that size the
blast-radius argument no longer holds, and splitting would prevent the PR from carrying
`Closes #7853`.

**The seam is preserved anyway.** The dependency that would have forced an ordering is measured
absent: 787 of `post-dispatch-watch-gate`'s 896 ledger rows are genuine, so the orphan count survives
the Phase 3.5 cleanup and there is no ordering constraint. If review still prefers the split, Phase 4
lifts out cleanly and the PR then carries `Closes #7849`, `Closes #7854` and `Ref #7853`.

## DC-2 — whether this work warrants an ADR — **RESOLVED by scoping down**

**Class:** taste.
**Raised by:** the CTO consult ("no architecture decision record needed — none of this crosses a
service, data-model, or technology boundary") and the DHH reviewer ("two header comments are not an
architecture decision record"); the code-simplicity reviewer said "scope down" rather than "cut".

**Resolution.** ADR-205 is kept with **one** decision instead of two. The surviving invariant — that
an incident-ledger rule id declares its namespace by prefix, and that hook telemetry must therefore
not carry an AGENTS.md section prefix — is genuinely cross-cutting, is a contract every future hook
author must honour, and today exists only as a comment inside a jq program. The second decision
(a declared telemetry registry) evaporated with the mechanism it described. Plan Phase 2.10's
criterion (*a new cross-cutting invariant every consumer must honor*) is met by what remains; the
reviewers' narrower criterion is not. The disagreement is recorded rather than silently resolved.

## DC-3 — the mechanisms the panel cut

Not challenges to operator direction, recorded here because they materially changed what ships and a
reader of the PR should be able to see the reasoning without re-reading the plan:

- a `SOLEUR_IN_TEST_RUN` marker plus a refusal branch inside `emit_incident` — **cut**; the
  chokepoints that would set the marker set the redirect instead;
- a hand-maintained hook-telemetry-id registry and its drift lint — **cut**; one predicate over an
  invariant that holds for all 105 AGENTS ids replaces both;
- a committed quarantine script and its own test suite — **cut**; a one-time cleanup of a gitignored,
  self-expiring, operator-local file does not get permanent machinery;
- a new declared entry-point list file — **cut**; the parity test's existing scrub loop is the list;
- a `git_fixture` shell wrapper — **cut**; the builder's config globals already make its only
  setting unreachable.

Two suites were **added** for the opposite reason: review found an acceptance criterion and a guard
row with no producer, and Phase 2's ~13 conversions with no verification at all.
