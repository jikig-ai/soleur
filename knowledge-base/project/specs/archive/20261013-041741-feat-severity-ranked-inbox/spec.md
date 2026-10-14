---
feature: severity-ranked-inbox
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: 6007
epic: 6006
plan: knowledge-base/project/plans/2026-07-04-feat-severity-ranked-inbox-plan.md
brainstorm: knowledge-base/project/brainstorms/2026-07-04-multica-primitives-adaptation-brainstorm.md
wireframe: knowledge-base/product/design/inbox/severity-ranked-inbox.pen
---

# Spec — Severity-ranked inbox (#6007)

Attention spine for the non-technical founder: one inbox that ranks everything needing them into **NEEDS YOU** (`action_required`) over **GOOD TO KNOW** (`attention`/`info`), pushes on completion, and never buries a running statutory clock. Child 1 of the Multica-adaptation Epic #6006. Full detail + all review revisions in the plan.

## Load-bearing invariants
- **I1:** a non-archived statutory item is always pinned in NEEDS YOU, uncapped, never swept (deadline is a cosmetic chip only).
- **I2:** an un-acted `action_required` item can never be silently lost (archive-guard + retention carve-out).
- **I3:** no `createServiceClient` in the inbox read path; targeted rows private to their recipient.

## Non-goals (deferred)
Per-Owner recipient-state join (→ #4672), `approval_required`/`autopilot_run` emit (→ #4672/#4674), snooze/filters/state machine, severity calibration loop, deep pagination.
