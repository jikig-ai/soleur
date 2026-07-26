# Decision challenges — feat-one-shot-6178-verify-window-decouple

Decisions taken during the pipeline that diverge from a skill default, or that the operator
should see. Rendered into the PR body by `/ship` Phase 6.

---

## 1. Compound consolidation: plan + tasks.md deliberately NOT archived

**Skill default:** `/soleur:compound` auto-archives `knowledge-base/project/{plans,specs}/*<slug>*`
to `archive/` on feature branches, and auto-confirms in headless mode.

**Decision:** skipped archival for
`knowledge-base/project/plans/2026-07-24-fix-inngest-verify-window-decouple-plan.md` and
`knowledge-base/project/specs/feat-one-shot-6178-verify-window-decouple/tasks.md`.

**Why:** both are the operative runbook for work that has **not happened yet**. The plan's
`### Post-merge` block and `tasks.md`'s `## Exit` block define the AC-V1 → AC-V4 sequence, which
runs *after* this merge:

- AC-V1 — `apply-deploy-pipeline-fix` delivers the probe; sha256 must match `main`.
- AC-V2 — `op=verify` dispatched only after AC-V1 passes (different concurrency groups; a
  premature dispatch lets the OLD probe answer).
- AC-V3/V4 — the verdict, which decides whether #6178 may close and whether Hetzner image
  `411798619` may be deleted.

Archiving at merge time would bury the checklist for the phase that is still pending, and the
operator explicitly instructed that #6178 stays open and the image is retained pending AC-V4.

**Re-eval trigger:** archive both artifacts once AC-V4 is satisfied (or an incident is opened on a
detected double-fire) — i.e. at the same moment #6178 becomes eligible to close.

---

## 2. One review recommendation declined on its reasoning

**Recommendation (security-sentinel, P2-6):** restrict the flip-FSM anchor reason set to the
`start_server`-bearing reasons, dropping `dbsize-nonzero` / `flushall-failed` /
`refuse-rearm-after-done` because those fire on flips where the scheduler never started.

**Decision:** declined the fix; adopted the underlying observation.

**Why:** the anchor takes the EARLIEST matching row, and `earliest(A ∪ B) ≤ earliest(A)` — so a
larger reason set can only move the anchor earlier, i.e. widen the window, which is the safe
direction. Restricting the set trades safety for width on a gate whose false-clean outcome is
data-destruction-class. The real defect the agent surfaced was the **deadlock** it described
downstream: extra width trips the page-1 feasibility gate, whose remediation was inert, leaving
`CUTOVER_DOUBLEFIRE_FUNCTION_IDS` (the vacuous-clean lever) as the operator's only working exit.
That is fixed directly — `CUTOVER_ANCHOR_FROM` now outranks the derived anchor — so the pressure
gradient from fail-closed into false-clean is removed without narrowing the anchor set.

**Re-eval trigger:** if a future cutover shows the abort-reason rows materially inflating the
window in practice, revisit — but only alongside a coverage assertion, never as a bare narrowing.
