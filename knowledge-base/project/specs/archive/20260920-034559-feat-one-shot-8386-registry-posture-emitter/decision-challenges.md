# Decision Challenges — feat-one-shot-8386-registry-posture-emitter

Persisted by `plan` (headless arm, ADR-084). `ship` Phase 6 renders these into the PR body and
files an `action-required` issue. Nothing here was silently applied.

## UC-1 — The ledger flip is deferred, against the issue's literal wording

**Class:** User-Challenge (the issue states a direction; this plan does not take it).

**What #8386 asks for (step 3):** "Flip the ledger row to `live_verification: available` backed by the
runner-reachable Better Stack read … and add the row to the Layer A `live_coverage_floor`."

**What this plan does instead:** rewrites the row's `unavailable:` reason to name the merged emitter,
the probe and the delivery dependency, and leaves the flip — plus `live_coverage_floor: 2` — to a
one-line follow-up PR that the probe's V6 verdict asks for the day a real boot is observed.

**Why the direction was challenged.** `available` is not prose: it is the exact string
`check_live_coverage_floor` counts in `scripts/lint-encryption-posture.py`, and ADR-141 §Context 2
defines it as "available *because a HOST probe exists*". At merge the host does not run the emitter —
delivery needs a `registry-host-replace`, which is dead while #8361 holds `apply-web-platform-infra.yml`
over GitHub's 512,000-byte limit, and #8361 has no ETA. Flipping now would make the Layer A floor count
a probe that has never run, for an unbounded window. The ledger's own sibling row
`hcloud_volume.inngest_redis_luks` records the same discipline: the mechanism flips "in the follow-up
commit that records an OBSERVED cutover boot, never before".

**Cost of the challenge:** one extra one-line PR. It cannot rot — #8386 cannot close until the ledger
reads `available`, because the probe's V6 verdict blocks on exactly that and the sweeper posts the
instruction daily.

**Signals:** the session model and the CTO domain leader agreed independently; `architecture-strategist`
at plan review confirmed the lagging record is the right structure against ADR-140/ADR-141.

**If the operator disagrees:** flip the row in this PR and raise `live_coverage_floor` to 2, accepting
that Layer A then asserts live coverage for a store no probe has measured until #8361 clears.
