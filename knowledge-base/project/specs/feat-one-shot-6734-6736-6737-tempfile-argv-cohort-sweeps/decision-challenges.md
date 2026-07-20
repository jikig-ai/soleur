# Decision Challenges — feat-one-shot-6734-6736-6737

Persisted from `plan` Step 4.5 + `plan-review` consolidation. Headless run: these are **not**
auto-applied. `ship` Phase 6 renders this into the PR body and files an `action-required` issue.

---

## OPERATOR RESOLUTIONS — 2026-07-20 (interactive, binding on `/work`)

The run was interactive, so UC-1, UC-3 and E1 were put to the operator directly rather than
deferred into the `action-required` queue. Resolutions:

- **UC-1 — REJECTED (no split).** Ship #6734 + #6736 + #6737 as **one PR**, as originally scoped.
  The panel's split recommendation is recorded above and not acted on.
- **UC-2 — moot for scope,** since UC-1 keeps one PR. Still restate `## User-Brand Impact` in
  **realized** rather than conditional voice — "if this lands broken" is the wrong tense for
  something that already happened. Do not flip `requires_cpo_signoff`.
- **UC-3 — ACCEPTED (measure, don't report).** Phase 3.0 becomes measurement + reconciliation.
  Fire all 8 `MIGRATED_PROMPT` crons via the `soleur:trigger-cron` skill (no SSH), record what
  each actually produces, and fold the evidence into **#4375**. Do **not** open a 29th
  `action-required` issue. **AC16 changes** from "an issue exists" to "artifact evidence exists
  per handler." Operator has given explicit assent for triggering these production crons.
- **E1 — ACCEPTED, separate PR immediately after this one merges.** Do NOT touch the published
  comparison pages on this branch. After this PR merges, grep-sweep the stale Polsia figure across
  all 8 files and ship a standalone correction PR.
- **E2 — unchanged.** Systemic `action-required` queue failure; worth its own issue, not this
  plan's problem to solve. It is the reason UC-3 was accepted.

---

## UC-1 — Split Phase 3 (#6737) into its own PR (User-Challenge)

**Operator's stated direction (the default):** the one-shot pipeline scoped #6734, #6736 and #6737
into a single PR on this branch.

**What the panel found:** 4 of 5 reviewers (DHH, code-simplicity, CTO, CPO) independently
recommended splitting at the Phase 3 seam. Their arguments do not overlap by accident:

- Phases 1+2 genuinely belong together — they share **4 files** (`learning-retrieval-bench.sh`,
  `skill-freshness-aggregate.sh`, `test-all.sh`, `ci.yml`), one ADR, and one CI job. Splitting
  *those* would be two PRs racing on one file.
- Phase 3 shares no code, no test surface, no ADR (it executes ADR-126, not the new one), and no
  language with Phases 1-2. It is a fourth review mode.
- **The decisive argument is urgency mismatch, not size.** Phase 3 carries a live finding that is
  already 41-110 days old. A P2-chore PR gets reviewed, merged and post-merged at chore cadence.
  CPO's framing: the outage's priority is *capped by the PR's aggregate label*.

**Why this is not auto-applied:** dropping or re-cutting operator-requested scope is a
never-Mechanical class per ADR-084 / decision-principles.md. The operator asked for one PR.

**Recommendation if accepted:** PR A = Phases 1+2 (P2 chore). PR B = Phase 3, at raised priority.
The plan is already written so this split is a clean cut at one heading.

---

## UC-2 — Phase 3 is not a P2 chore (User-Challenge)

**CPO finding:** the plan's own Operations review says the operator "has been consuming stale
artifacts for 41-110 days while every monitor reported healthy," and its Marketing review calls
this "a business-visible consequence, not just a monitoring defect." A plan that says
*business-visible consequence* while carrying `requires_cpo_signoff: false` is internally
inconsistent.

**Roadmap-fit:** Phase 4 is *Validate + Scale* — recruit 10 founders. The eight dark crons are the
top-of-funnel machinery for exactly that phase, and the Marketing Gate was cleared 2026-06-08 into
an engine that had been inert since 2026-04-01.

**Proposed:** flip `requires_cpo_signoff: true` for the Phase 3 work and restate
`## User-Brand Impact` in **realized** rather than conditional voice ("If this lands broken…" is
the wrong tense for something that already happened).

**Why not auto-applied:** changes the plan's declared threshold and sign-off requirement — a
scope/priority judgment reserved for the operator.

---

## UC-3 — Do not file a 29th `action-required` issue (User-Challenge, highest confidence)

**CPO finding, verified during planning:**

- **#4375** — *"ops: competitive-analysis Cloud scheduled task has not fired in 36 days
  (watchdog)"*, opened **2026-05-24**, labelled `action-required`, **still OPEN 57 days later**.
- The `action-required` queue holds **28 open issues**; the oldest content escalations (#553,
  #555) date to **2026-03-12** — 130 days.

So the cohort outage was **already detected and already escalated through precisely the channel
Phase 3.0 proposes**, and it broadened from one cron to eight during the 57 days that issue sat
open. Phase 3.0's route has a measured 0% success rate *on this exact finding*.

**Proposed instead:** Phase 3.0 becomes a **measurement + reconciliation** action, not a report —
fire the 8 crons via the existing `soleur:trigger-cron` skill (no SSH), record what each actually
produces, then fold the result into **#4375** rather than opening a duplicate. AC16 changes from
"an issue exists" to "artifact evidence exists per handler."

**Why not auto-applied:** it re-scopes the operator's escalation route, and triggering production
crons is a live-system action requiring operator assent.

---

## E1 — a live published accuracy defect (needs its own PR; plan phase is write-restricted)

Two published, indexed comparison pages
(`plugins/soleur/docs/blog/2026-03-26-soleur-vs-polsia.md`,
`.../2026-03-31-soleur-vs-paperclip.md`) assert **Polsia at $1.5M ARR / 2,000+ managed companies**.
`knowledge-base/product/competitive-intelligence.md` (`last_updated: 2026-07-04`) carries **~$10M and
7,600** — a **~6.7× understatement of a competitor**, inside **JSON-LD** (a `FAQPage`
`acceptedAnswer`), on pages whose entire purpose is that comparison.

Four aggravating factors: it is machine-ingested structured data (an AEO trust defect, not just a
content one); it is the **load-bearing rebuttal** in the FAQ; it errs in the direction that
**flatters Soleur**; and the correction has been available internally for **16 days**. The stale
figure appears in **8 files** — sweep by grep, not file-by-file.

**Not fixable here** — this planning phase may only write under `knowledge-base/project/{plans,specs}/`,
and this is copy work on published pages. It should not wait on cron restoration.

## E2 — the `action-required` queue is a systemic routing failure

28 open items; the oldest content escalations (#553, #555) date to **2026-03-12** — 130 days. #4375
has sat 57 days on the very finding this plan re-discovered. Every future escalation inherits this.
Worth its own issue; it is not this plan's problem to solve, but it is this plan's reason for UC-3.

## Recorded disagreement — the panel vs. the plan on `retryEligible`

Both simplification reviewers called the `retryEligible: false` sweep "the one cheap cohort win"
and "behaviour-preserving by construction." **That is wrong, and it was verified during planning.**

Per `_cron-shared.ts` (`const failed = threw && !heartbeatOk && retryEligible !== false;`):
*omitting* the field is inert, but *passing `false`* flips `failed` to false and **suppresses the
Inngest retry** for 7 crons that retry today. Kieran independently reached the same conclusion.

The ADR-126 premise does hold uniformly — all 7 handlers tear down their workspace in `finally`
(measured) — so the change is *correct*. But it is a deliberate behaviour change to 7 production
crons, not a one-line no-op, and a `grep -c` presence AC cannot gate it. Plan v2 therefore
**defers** it rather than shipping it as boilerplate.
