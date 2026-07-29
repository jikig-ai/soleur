# Decision Challenges — feat-one-shot-6750-cron-handler-local-liveness

Recorded headless (one-shot pipeline, no TTY). Each entry challenges the operator's **stated
direction** in issue #6750. The operator's direction is the default; these are surfaced, not
silently applied — `/ship` renders them into the PR body and files them as an `action-required`
issue.

Plan: `knowledge-base/project/plans/2026-07-28-chore-cron-handler-local-liveness-cohort-plan.md`
(v2, after a 6-reviewer panel + a strong-model consult).

---

## DC-1 — The C4 edge element: `inngest -> kb` vs `api -> kb`

**Class:** user-challenge (diverges from the issue's explicit wording)

**Your stated direction.** Issue #6750 Item 4: *"The correct missing edge is `inngest -> kb`."*

**What the evidence says.** Two independent objections, and the second also overturned the plan's
own first answer:

1. **Not `inngest`.** `model.c4` already records this exact attribution question and answers it the
   other way, deliberately: *"Deliberately NO `inngest -> sentry` edge… The Inngest-FIRED crons'
   check-ins are posted by the code `api` serves."* The Inngest Server is a Go queue/scheduler on a
   dedicated host (ADR-100) and never opens a git workspace. `inngest -> kb` would assert an
   authorship path that does not exist — the same defect class Item 4 exists to fix.
2. **Not `webapp` either** (the plan's v1 answer, now withdrawn). `webapp = system "Web Application"`,
   while **all nine** existing inbound `kb` edges are container/component level. `webapp -> sentry`
   earns system altitude because it spans the dashboard *and* server configs; the cron→kb path is
   single-container and server-only. Copying that precedent "verbatim" would have imported an
   altitude it does not earn, and drawn a different-altitude parallel edge beside the existing
   `api -> kb`.

**Counter-evidence, stated fairly.** `inngest -> github` and `inngest -> doppler` (ADR-088,
`cron-ghcr-token-minter`) *do* attribute an Inngest-fired cron's writes to `inngest`. The model is
internally inconsistent, and `inngest -> kb` would match those two. The plan treats them as the same
mis-attribution, annotates them inline, and files a tracking issue rather than leaving the
inconsistency silent — because without the annotation the new convention would be in the minority
with its rationale attached only to the new edge.

Also noted honestly in the ADR: the cited note's *headline* reason is network topology (the Inngest
host has no Sentry path at all); the attribution sentence is secondary.

**What the plan does.** Implements **`api -> kb`** as a second relationship on that pair (duplicate
pairs are already legal and present in this model), and records the attribution reasoning plus both
precedents in the ADR-126 amendment.

**Your override.** Change one line in `model.c4`, re-run `bash scripts/regenerate-c4-model.sh`, and
amend the ADR's attribution section. Nothing else in the plan depends on the choice.

---

## DC-2 — `cron-content-generator`'s class: the audit's table is wrong, and your issue was right

**Class:** user-challenge (corrects a *derived artifact*, not your direction)

> **This entry inverted between plan v1 and v2.** v1 challenged your Item 2 enumeration as an
> omission. That was wrong, and the correction is recorded here rather than quietly dropped.

**Your stated direction.** Issue #6750 Item 2: *"Class A ports only — `cron-growth-audit` and
`cron-campaign-calendar`… The four Class B (change-conditional) producers would be FALSE-REDed."*

**What v1 claimed.** That 2 + 4 = 6 ≠ 7, so `cron-content-generator` had been omitted — and it
proposed giving it the Class A rule on the strength of the audit's classification table.

**What the evidence actually says.** Reading `CONTENT_GENERATOR_PROMPT` directly, it carries **two
prompt-mandated no-artifact exits**:

- STEP 1b — *"If no usable topic, create issue … and stop."*
- STEP 2 — *"If content-writer aborts due to FAIL citations, create issue and stop."*

Both are *designed healthy outcomes*: they file the audit issue (so `heartbeatOk` stays true) and
commit nothing. Under a Class A must-commit rule they would **false-RED**. `cron-content-generator`
is therefore **Class B**, your enumeration was correct, and the mis-classification lives in the
**audit's table** — which `scripts/cron-artifact-age.sh` then inherited into its `class` column.

**What the plan does.** Corrects `cron-content-generator` from `A` to `B` in
`scripts/cron-artifact-age.sh` (now the single source of truth for the class table), records the
prompt evidence in the ADR amendment, and adds a parity test so the shell table and the handlers'
compiled class arms cannot drift apart.

**Your override.** If `cron-content-generator` should stay Class A, the two prompt stop-paths need a
signal the handler can read (e.g. a "topic selected" marker) so the rule can distinguish them from a
genuine failure. That work is not in this plan.

---

## DC-3 — Should the class parameterisation exist at all?

**Class:** user-challenge (a simplify-cut of operator-requested scope — never auto-applied)

**Your stated direction.** Issue #6750 Item 2 asks for must-commit-every-run assertions on two named
deterministic producers, explicitly distinguishing them from the change-conditional four.

**The challenge.** The simplification panel argued for collapsing to a **single uniform rule** —
`failed → RED`, `committed + undetermined-without-resumed → RED`, everything else GREEN — applied
identically to all seven, with artifact-presence left entirely to the already-shipped
`origin/main` detector. Their case: the Class A assertion buys a detection window of one cron period
versus the detector's 15–22 days for a weekly producer, and it costs a non-zero, unbounded, unmeasured
false-RED rate paid in the one currency that matters — operator trust in a red monitor.

**Why the plan keeps the classes anyway.** The uniform rule would drop an assertion you explicitly
asked for on two producers whose determinism is now *prompt-evidenced* rather than assumed (see
DC-2's method). And the plan removed the parts of the Class A machinery that were genuinely
unjustified: the production-prompt edit that manufactured a diff so an assertion could hold is gone,
and the two ~509-line harness ports collapsed into the existing cohort table.

**Your override.** Say the word and Class A collapses into Class B; the plan loses Phase 3's class
arms, the `{{RUN_DATE}}` pin, and roughly half the test scenarios. The dedup hardening, the
`retryEligible` sweep, the liveness markers, and the C4 edge are unaffected — those are where the
measured defect actually lives.

---

## Not challenges — factual corrections recorded for the record

- **The fixture hazard in Item 1 is stale.** All three suites already return union-valid
  `SafeCommitResult`; the `{ok: true}` mocks were removed under #6714. The predicted REDs still
  occur, via `paths` being *omitted* in the shared cohort fixture.
- **The plan chose the ADR-126 *amendment*** over a new ADR ordinal. Your issue sanctions either
  (*"its OWN ADR (or an ADR-126 amendment)"*), and the amendment removes the ordinal-collision and
  renumber-sweep failure modes entirely.
- **The issue's Item 1–3 scope was incomplete in one respect nobody flagged**: the ADR-126 remedy has
  **two** halves, and the dedup short-circuit hardening was in neither the issue nor plan v1. Without
  it all seven handlers keep a GREEN-with-no-artifact path — the exact dated 2026-07-14→07-19 shape —
  while every acceptance criterion passes. It is now in scope.
