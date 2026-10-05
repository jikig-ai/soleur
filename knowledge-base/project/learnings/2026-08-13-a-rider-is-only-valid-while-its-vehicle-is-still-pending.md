---
module: registry-observability
date: 2026-08-13
problem_type: integration_issue
component: followthrough_probe
symptoms:
  - "a deferred change sat inert for 45h while its recorded delivery vehicle had already departed"
  - "the probe reported reason=not_delivered accurately the entire time and would have for 90 days"
  - "a correction sweep's own grep false-fired on the retraction quoting what it corrected"
  - "a scope-out was justified by a ForceNew premise that a render-time strip made false"
root_cause: rider_recorded_against_a_vehicle_that_fired_early
severity: medium
tags: [followthrough, rider, delivery, correction-sweep, scope-out, retraction, art-30, review]
issue: 7455
pr: 7514
synced_to: [work, review]
---

# A rider is only valid while its vehicle is still pending

## Problem

ADR-184 shipped a zot container-log shipper into `cloud-init-registry.yml`. The registry host is
cloud-init-only (ADR-096) and every registry resource is an `OPERATOR_APPLIED_EXCLUSION`, so merging
applied nothing. That was known, named, and handled: a **rider** was recorded on #7287 stating that
when its ordered-path **step 6** (`registry-host-replace`) ran, the shipper would be delivered "at no
extra step and no extra downtime."

The rider was correct when written. It was dead by the time the shipper merged.

The ordered path's host replace had already fired — atomically, inside `registry-luks-recut`
(run 31437037877), on **2026-08-10T22:08Z**. The shipper merged **2026-08-12T19:38Z**, roughly
**45 hours later**. So the change was inert on a host born before it existed, and the vehicle it was
booked onto had already left.

**Nothing detected this.** The enrolled follow-through probe reported `reason=not_delivered` on every
sweep, which was *accurate*. It would have kept reporting it for the full 90-day escalation horizon,
because on that channel:

> "not yet delivered" and "the delivery mechanism has already come and gone" are the **same reading**.

## Root cause

A rider is a claim about a *future event*. It has two operands — the change, and the vehicle — and
every gate in the pipeline watched only the first. The probe measured *delivery state*; no artifact
measured *whether the vehicle was still pending*. The 90-day horizon was designed to catch an
indefinitely-undelivered change, and it would have fired eventually — 90 days after the vehicle it
was waiting for had already run.

## Solution

Delivery required a **separate, dedicated** `registry_host_replace` job
([run 31639782781](https://github.com/jikig-ai/soleur/actions/runs/31639782781)), completing
**2026-08-12T20:54:12Z**. First warehouse readback 21:03:51Z: 37 envelope rows against a floor of 7,
which flipped ADR-184 `adopting → accepted`.

**Prevention:** when recording a rider against a pending event, the rider is only as live as its
vehicle. Before treating "the probe says not-delivered" as "still waiting", re-check that the vehicle
is still pending — `gh issue view <N> --json state` plus its closing comment, since a closed ordered
path is the signal that the rider is stale rather than the change. Better: state the rider's
falsification condition (*"if #7287 closes without this delivering, the rider is spent"*) so the
condition is checkable rather than implicit.

## Supporting findings from the same session

Each of these is measured, not hypothesised. Several are cases where a gate caught me.

### A correction sweep's own grep false-FIRES on the retraction quoting what it corrected

An acceptance criterion predicted the claim-class sweep would leave exactly one survivor. It left
six. A **file-level** grep cannot distinguish a live claim from prose *quoting* the claim it
retracts — and a retraction quotes it by design.

This is the documented "grep assertion false-matches its own comments" class
([2026-06-17](test-failures/2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md)),
**inverted**: there a guard false-*passes* on its own comment; here a correction sweep
false-*fires* on its own retraction.

**Prevention:** an AC over a correction sweep must be a line-level inspection with a disposition per
survivor, never a survivor **count**. Amend the AC explicitly when the count is wrong — never
quietly satisfy a looser check.

### A literal-bounded sweep proves the absence of STRINGS, not of the CLAIM

Three literals (`step-6 registry-host-replace`, `merged inert`, `INERT UNTIL A PROVISIONING`)
returned **0** hits across `knowledge-base/legal/`, and that zero was read as "legal is not
relevant." Widening to the claim as the legal corpus actually phrases it —
`Ships INERT|delivery rides|no additional data flows` — returned **4**.

The same bound missed the **origin** text in `cloud-init-registry.yml` on punctuation alone: that
file writes ``step-6 `registry-host-replace` `` with backticks, and `INERT UNTIL PROVISIONED`, not
`INERT UNTIL A PROVISIONING`.

**Prevention:** index a correction sweep by **claim**, then grep each paraphrase independently. A
corpus that never uses your phrasing is invisible to a literal bound. Extends
[2026-07-20](2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md).

### Correcting every paraphrase while leaving the ORIGIN standing is exacerbation

Two artifacts were deferred as "pre-existing". Both failed that criterion's second conjunct, because
correcting the paraphrases while leaving the source made the repo **self-contradictory** where it had
been uniformly stale — strictly worse. In `model.c4` the edge said DELIVERED while the element still
said "will until the apply fires", and the stale sentence fanned out **12×** in the generated JSON.

**Prevention:** `pre-existing-unrelated` requires "not exacerbated by this PR". A half-landed sweep is
exacerbation by definition. If your PR corrects a paraphrase, the origin is in scope.

### A technical-sounding scope-out premise is still a claim to MEASURE

The `cloud-init-registry.yml` deferral was justified on: `user_data` is ForceNew on
`hcloud_server.registry`, with no `ignore_changes`. Both true — and irrelevant. The CONCUR gate found
`registry_rationale_strip` (`zot-registry.tf:405,563`), a render-time regex that deletes every comment
line **before** `base64gzip`. Measured: stripped render **byte-identical, delta 0**, budget headroom
unchanged at 19,632 B.

The gate also found the criterion unmet on its face regardless — `contested-design` requires the
review agent to name **≥2** approaches and recommend a design cycle; the finding named one fix and no
cycle.

**Prevention:** "any edit to a `templatefile` source is an infra change" is false wherever a
render-time strip exists. Grep for a strip/filter between the template and the consumer before
claiming an edit reaches the artifact — and run the CONCUR gate *before* filing, not after.

### Retract AT the claim, not only in a remote amendment

The retraction was placed in an appended amendment ~110 lines and five headings below the superseded
sections, citing the ADR-044 precedent. That over-read the precedent: ADR-044's amendment sat at line
449 with its superseded prose at 448 — **adjacent**. It is silent on remote placement because it had
none. Five other retractions in ADR-184 itself are all co-located.

**Prevention:** a reader entering mid-file via a cross-reference never sees a remote amendment. Put an
inline marker at the claim; the appended section carries the reasoning.

### A green test can pin a now-false operator instruction

The probe's `not_delivered` arm advised *"nothing to do here"*, and a passing `C2` assertion required
that exact string. Post-delivery that arm is reachable only through a **regression** — and the sweeper
republishes the probe's stdout verbatim as a comment on a **public** issue every tick.

**Prevention:** when a delivery inverts what a signal means, the script and its fixture must move
together. A green suite is not evidence the advice is still true.

### An attestation acquires a shelf life at the moment of delivery

The CLO's framing, recorded in `2026-08-counsel-review-7440.md` §11.4. The Art. 30 register asserted
"Ships INERT" in the present tense; that became false at 20:54:12Z, and the currency duty arose from
the **delivery event**, not from the PR that documented it. A topology-dependent legal conclusion
reasoned against an inert channel is a **prediction**, not an attestation.

**Prevention:** a compliance record must never assert deployment state in a tense that silently
becomes false — state it as dated fact about the merge. Re-attest, and visibly re-date, any
topology-dependent conclusion on the day the channel starts carrying traffic.

### The evidence for the flip existed nowhere checkable

#7455 — the tracker whose entire purpose is *"observe an envelope-stamped row"* — had **zero
comments**. The probe output and the new boot id appeared only in artifacts this branch authored: a
citation loop, not a source. The probe's own header names the designed evidence path (the sweeper
posts its stdout as a comment).

**Prevention:** before citing an observation in a durable artifact, post it where it can be checked
independently of the change that cites it.

## Session Errors

1. **Plan's `Legal: not relevant` verdict was wrong.** — Recovery: amended the plan and routed the
   substance to the CLO. — **Prevention:** sweep the legal corpus with its own phrasings.
2. **Claim-class AC predicted 1 survivor, got 6.** — Recovery: amended to line-level inspection. —
   **Prevention:** never assert a survivor count over a correction sweep.
3. **Sweep bound missed the origin text on punctuation.** — Recovery: semantic re-grep. —
   **Prevention:** index by claim, not literal.
4. **Deferred the C4 pin fix that my own PR made contradictory.** — Recovery: folded in. —
   **Prevention:** PR-introduced findings admit no scope-out.
5. **Scope-out on a false ForceNew premise.** — Recovery: CONCUR dissent; measured delta 0; fixed
   inline. — **Prevention:** measure the premise.
6. **`§4 predicted` misattribution.** — Recovery: corrected. — **Prevention:** grep the cited section.
7. **Called a provenance token "the positive control".** — Recovery: corrected; §3 warns that anchor
   matches only the echo. — **Prevention:** read what the probe calls each field.
8. **Compared `dropped_rows` against a floor gating a different counter.** — Recovery: removed the
   comparison. — **Prevention:** read the guard's operand before citing it.
9. **Post-replace claim sourced from pre-replace readings.** — Recovery: cited the actual readback. —
   **Prevention:** check the timestamp of any reading used as evidence.
10. **Inverted the runbook box, left the decision bullet below it saying "Expected; wait".** —
    Recovery: corrected. — **Prevention:** when inverting a warning, sweep the whole section.
11. **Listed a `reason=` enum unreachable on zero rows.** — Recovery: rewrote the list. —
    **Prevention:** check each enum's gating condition.
12. **Remote retraction + heading implying only two stale sites.** — Recovery: inline markers and a
    third site named. — **Prevention:** enumerate, do not imply completeness.
13. **Evidence existed nowhere checkable.** — Recovery: posted to #7455. — **Prevention:** anchor
    evidence outside the citing change.
14. **`grep -c` on one-line generated JSON counted lines, not occurrences** — under-reported a 12×
    fan-out as 1. — **Prevention:** `grep -o … | wc -l` on single-line files.
15. **Process (not defects):** all 4 review agents died on a session limit and were **resumed from
    transcript** rather than respawned, preserving partial findings; the full-suite gate was
    deliberately skipped for a prose diff in favour of the 5 suites that gate the changed files,
    citing `5b5cc7873` as the commit the last green full run covered.

## Cross-references

- [I swept by file when the unit of truth was the claim](2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md)
- [I marked one block and not its twin](2026-07-21-i-marked-one-block-and-not-its-twin-in-the-file-whose-purpose-was-removing-that-defect.md)
- [grep assertion over script body false-matches own comments](test-failures/2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md)
- ADR-184 `## Amendment 2026-08-12`; `2026-08-counsel-review-7440.md` §11
