# Decision Challenges — feat-one-shot-6436-infra-observability-batch

Persisted by `plan` + `plan-review` running **headless** (one-shot pipeline, no TTY).
Per ADR-084 / `decision-principles.md`, these are **not** auto-applied: they argue the
operator's *stated direction* should change, or they are **Taste** findings from a
named panel. `/ship` Phase 6 renders this file into the PR body and files an
`action-required` issue.

---

## UC-1 — [User-Challenge] Split Phase 4 (`ci-deploy.sh`) into its own PR

**Operator's stated direction (the default):** *"Fix #6436, #6437, #6429, #6446, #6447
as one batch."*

**What the challenge is:** two independent reviewers — **CPO (blocking condition)** and
**DHH** — argue Phase 4 must ship as a separate PR from Phases 1/2/3/5.

**Why they argue it:**

1. **Phase 4 is the only phase that can cause an incident.** `ci-deploy.sh` is the live
   deploy path. Verified: `docker stop` (`:1884`) → `docker rm` (`:1885`) → `docker run -d`
   (`:1907`) leaves a ~22-line window with **no prod container**. A fatal error there is
   an `app.soleur.ai` **outage**, not a stale image. Phases 1/2/3/5 are comment edits, a
   C4 element, an alert-comment sweep, and a CI-step deletion — jointly inert.
2. **The plan's safety for Phase 4 rests on a human reading advisory greens.**
   `deploy-script-tests` is not a required check, so the ACs that exercise Phase 4 do
   not block merge. Burying those two checkboxes in an 18-AC, 5-issue PR is the
   condition under which nobody reads them.
3. **Self-inconsistency (the sharpest form of the argument).** The plan invokes
   review-dilution three times to defer D-1, D-3, and D-4 — *"burying a new name in a
   5-issue PR is the review-dilution that gate exists to prevent"* — then declines to
   apply the same reasoning to the riskiest edit in its own batch.
4. **Revert granularity.** `git revert` of the batch takes the C4 model, the citation
   sweep, and the alert audit with it — under incident pressure, with deploys down.

**Proposed shape:** PR-A = Phases 1/2/3/5 (`no user impact`); PR-B = Phase 4
(`single-user incident`, `user-impact-reviewer`, mandatory human read of the deploy ACs).
Cost: Phase 3 and Phase 4 both touch `issue-alerts.tf`, so PR-A lands first and PR-B
rebases. A sequencing dependency, not a blocker.

**Counter-argument for keeping one batch:** the operator asked for one batch; all five
issues still close either way; two PRs is two review cycles and two merges for a solo
operator; the shared `issue-alerts.tf` edits create a rebase.

**Status:** **APPLIED** — operator decision, 2026-07-15, after escalation.

The "operator's stated direction" quoted above (*"as one batch"*) did **not** originate
with the operator: it entered as `/soleur:go` args, synthesised from a semicolon-grouped
issue list (`#6436, #6437, #6429, #6446, #6447; #6427; #6445`). The plan then overrode a
**CPO blocking** finding on the strength of a mandate the operator never gave. When the
provenance was surfaced, the operator chose the split.

Resulting shape (as proposed above):
- **PR-A** = Phases 1/2/3/5 → #6436, #6429, #6446, #6447. `no user impact`. Lands first.
- **PR-B** = Phase 4 → #6437. `single-user incident`, `user-impact-reviewer`, mandatory
  human read of the deploy ACs. Rebases onto PR-A (shared `issue-alerts.tf`).

**Process learning (feeds `/compound`):** a headless planner cannot distinguish an
operator's stated direction from pipeline-synthesised args, so "the operator asked for X"
is load-bearing on provenance the planner cannot see. Overriding a *blocking* review
finding should require confirming that provenance, not assuming it.

---

## T-1 — [Taste] Fold D-5 (schema-check the 3 sibling cloud-init templates) into the batch?

**Disagreement between reviewers:**

- **CTO + code-simplicity: defer.** "Unbounded discovery" — each of
  `cloud-init-git-data.yml`, `cloud-init-inngest.yml`, `cloud-init-registry.yml` needs
  its own var map (three render harnesses, not three lines), and any one could red
  immediately on a real defect, turning a 5-line fix into open-ended debugging.
- **DHH: fold in.** *"You are deferring the check **because it might work**. Three
  templates that have never been schema-checked might be broken, and that's the reason
  not to look? If one reds, you found a boot-time defect on a fresh host, which is the
  entire reason the check exists."*

**Status:** NOT applied — deferred as D-5, per the CTO's ruling and the majority. DHH's
objection is recorded because it is a genuine argument about risk appetite, not a
technical error: the deferral's stated rationale ("it might red") is indeed weak, and the
honest rationale is the var-map cost, which the D-5 issue now carries.

---

## T-2 — [Taste] Re-milestone #6437 and #6446; refresh the roadmap's Current State

**CPO finding (non-blocking):**

- **#6437** (Sentry-dark deploy paths) is filed `Post-MVP / Later`, p2. But the roadmap's
  **Phase 4 milestone explicitly lists "Error tracking (Sentry or equivalent)"**, and
  Phase 4 recruits 10 founders and tracks 2 weeks of unassisted usage. Telemetry that
  silently goes dark during that window means the validation motion runs blind. It reads
  as a **prerequisite**, not a nice-to-have.
- **#6446** (infra gate red on every infra PR) is a friction tax on all remaining Phase 4
  infra work.
- **Roadmap drift:** `knowledge-base/product/roadmap.md` `Current State` says
  "Phase 4: 43 open, 160 closed" (dated 2026-05-25); the milestone API says **51 open,
  165 closed**. Frontmatter claims `last_updated: 2026-07-06`, `review_cadence: weekly`;
  today is 2026-07-15.

**Status:** NOT applied — re-milestoning issues and editing the roadmap is a product
call outside this batch's scope, and doing it silently inside an infra PR is the same
review-dilution the plan objects to elsewhere.

---

## T-3 — [Taste] Does Phase 1.4 (the stale `merge_queue` narrative) belong in this batch?

**code-simplicity:** it closes none of the five issues; it is a *stale narrative*, not a
rotted line citation — folded in on a "same rot family" analogy.

**Counter (adopted):** the stale comment **demonstrably caused harm inside this very
planning session** — it made the plan's first draft assert a false blocker (RR-14) and
mis-size the D-1 decision. It is ~4 line edits.

**Status:** APPLIED (kept in Phase 1.4), rationale recorded. code-simplicity's narrower
objection to **AC3** (asserting prose non-contradiction is not grep-able) was accepted
and AC3 was cut.
