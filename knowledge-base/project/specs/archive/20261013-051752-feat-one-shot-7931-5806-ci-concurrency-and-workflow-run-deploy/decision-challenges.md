# Decision Challenges — feat-one-shot-7931-5806-ci-concurrency-and-workflow-run-deploy

Headless routing per ADR-084. Findings below were classified **Taste** or **User-Challenge** by
`plan-review` consolidation and are surfaced rather than silently applied. `ship` Phase 6 renders
this file into the PR body and files it as an `action-required` issue.

Plan: `knowledge-base/project/plans/2026-09-09-chore-ci-concurrency-and-workflow-run-deploy-plan.md`

---

## DC-1 — #5806's milestone says this work is deferred, but the plan executes it now

**Class:** Taste (tracking accuracy) · **Source:** `cpo` plan-review, condition 1

`gh issue view` shows #7931 in **Phase 4: Validate + Scale** (the active roadmap milestone) and
**#5806 in "Post-MVP / Later"** — a milestone whose own description is *"valid issues that don't
fit in any current roadmap phase … reviewed periodically for promotion when user demand or
strategic direction changes."*

This plan promotes #5806 into active work on a **technical-coupling** argument (§Overview: Phase D
changes what the gate measures, Phase E changes whether the gate exists; the wrong order leaves a
ceiling sized over a term that no longer exists). That argument is sound and is engineering's call.
What is missing is the *record*: no milestone move accompanies the promotion, so roadmap tracking
silently drifts.

**Proposed:** move #5806 to #7931's milestone, or state the promotion explicitly in the PR body.
**Not auto-applied** because changing an issue's roadmap milestone is a scope/prioritization
decision, not a technical one.

---

## DC-2 — the deferred item 4 is the direct mitigator for this plan's own declared incident class

**Class:** User-Challenge · **Source:** `cpo` plan-review, condition 2 (the finding it pushed back on)

The plan defers #5806's item 4 (gate the "v0.X.Y released!" Slack/email announcement on
deploy-success). The mechanism-level reason is sound: after Phase E the announcement and the deploy
live in **different workflow runs**, so it stops being a `needs:` edge and becomes a cross-run
notification — a different design than #5806 sketched — and `reusable-release.yml`'s second
consumer (`version-bump-and-release.yml`, component `plugin`) has no deploy phase to gate against.

The challenge is that the *risk* moves the wrong way. After Phase E the two are **less** coupled
than today, so the precise scenario this plan's own `## User-Brand Impact` names — green PR,
published Release, "released!" in Slack, production still on the old build — becomes **easier** to
hit silently, and its only remaining detector is the drift check at
`DRIFT_SUSTAINED_THRESHOLD_MIN = 207 min` (~3.5 h of operator-visible wrongness). A plan declaring
`brand_survival_threshold: single-user incident` should not carry a re-evaluation criterion of
"wait until a misleading message is observed".

**Applied in the plan (mechanical half):** the deferral is now filed at **P2** with a **fixed
re-evaluation date** tied to this plan's own AC-P1..AC-P3 soak (merge + 3 days), replacing the
"when observed" trigger; the residual is named as R11.

**Still open for the operator (the User-Challenge half):** whether item 4 should be pulled *into*
this PR rather than deferred at all, accepting the shared-workflow blast radius. The operator's
stated direction — #5806's own body says treat item 4 as in-scope only if it does not destabilise
other consumers of `reusable-release.yml` — is the default, and this plan follows it. CPO's view is
that the deferral is defensible on mechanism grounds but that the risk framing needed correcting,
which has been done. No redesign of the announcement mechanism is being requested.

---

## DC-3 — the detection lag between a silent no-deploy and any alert is ~3.5 hours

**Class:** Taste (operator-experience trade-off) · **Source:** `cpo` plan-review, finding 5(a)

Consequence of DC-2 rather than an independent finding, recorded separately because it is the
operator-visible number. Between a `workflow_run` trigger that never fires and the drift check's
alert, the operator has already seen a "released!" message against a stale site with no earlier
signal.

The plan accepts this and names it (R2, R11, and the `## Observability` row
*"the workflow_run trigger does not fire"*), routing it to the pre-existing drift check rather than
building a new detector — because a run that never starts emits nothing, so no in-run probe can
cover it. Closing the lag is what DC-2's item 4 would do.

CPO's finding 5(b) — the double-deploy transition window — was assessed as **acceptable, no
operator action needed** (idempotent and serialised by the existing cross-pipeline `web-1-swap`
concurrency group; R8 / AC-P8) and is not carried here as a challenge.

---

## DC-4 — three reviewers independently recommend splitting this into separate PRs

**Class:** User-Challenge · **Source:** DHH (P1), Kieran (structural note), code-simplicity (ship order)

**The operator's stated direction is one PR** — the brief says both issues "share a worktree and one
PR" — and that direction is the default. This plan follows it. Three of six reviewers independently
argued against it, so it is recorded rather than silently kept or silently changed.

**The argument for splitting.** The sequencing case in `## Overview` is only about D↔E, and A, B and
C have no ordering relationship with either. D.4 explicitly refuses to re-derive any ceiling and E
deletes `CEILING_S` outright, so the hazard the bundling protects against is a number nobody changes
in either order, on a gate one of the two phases removes.

**The strongest form of it — and this one is a real defect, not taste.** AC-P2 makes a
`time-to-test` median regression >20% the rollback trigger for Phase D, and R1 promises Phase D can
be "reverted alone — it is a one-line change in a separate commit." If D and E merge together, that
attribution is not available: E changes the deploy topology on the same merge, so a regression cannot
be assigned to D, and reverting D alone means reverting one commit out of a PR that also rewrote
B8/B9, the invariants suite, and six consumer files. **The measurement plan and the bundling are in
tension, and the plan currently asserts both.**

**Proposed split (DHH's, endorsed in substance by Kieran):**
1. **PR1 = D + A** — one line of YAML, its comment, Guard 1, the ADR-212 correction. Merge, let 15
   main pushes land, run AC-P1..AC-P3 for real.
2. **PR2 = B** — the aggregator discriminator. Independent.
3. **PR3 = C** — the `TEST_TIMING_LOG` binding.
4. **PR4 = E** — the topology, opened with PR1's post-merge baseline in hand rather than promised.

Kieran's framing: *"A–D is a coherent, independently-revertible unit that closes #7931 completely. E
is a deploy-topology rewrite that turns out to need a release-artifact resolver, a doppler-gate
rehoming, a B9 rewrite and a founder-email decision."*

**What was applied without the split:** the plan already sequences the phases as independently
revertible commits in that exact order, and R9 records the fallback (E splits out after D, never
before). What cannot be applied without the operator's call is the split itself.

**If the answer is "keep one PR":** AC-P2's rollback trigger needs re-scoping, because attributing a
`time-to-test` regression to Phase D across a merge that also changed the deploy topology is not
something the measurement can do. Either accept the attribution gap explicitly, or land D's commit
on `main` ahead of E's within the same PR and measure between them.

---

## DC-5 — ADR-214 decides two unrelated things

**Class:** Taste · **Source:** DHH (P1, within the split finding)

As drafted, ADR-214 records both a semantic correction to a concurrency key and a deploy-trigger
topology change. Those are two decisions with different blast radii, different reversal costs and
different audiences. If DC-4 resolves toward splitting, they should be two ADRs; if it resolves
toward one PR, one ADR with two clearly separated Decision blocks is acceptable but weaker.

Not auto-applied because ADR granularity follows the PR decision in DC-4.
