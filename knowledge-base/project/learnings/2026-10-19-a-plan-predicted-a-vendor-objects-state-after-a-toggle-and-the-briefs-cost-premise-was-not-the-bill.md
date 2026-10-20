---
module: CI
date: 2026-10-19
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "The brief's cost premise ($10 per active committer per month) did not appear anywhere in the billing usage API; the real charge was a metered AI-credits line of $254.96 over 28 days"
  - "A ticked plan criterion said the Code Quality workflow would stop reading `active` after the toggle; it still reads `active` and the plan's own gate called that a fail"
  - "Review found 21 written-not-measured claims in a 7-file documentation PR (ratchet coverage, why the meter accrued, when billing began, ticked boxes)"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [vendor-settings, billing, plan-acceptance-criteria, measured-vs-asserted, code-quality, review]
---

# Learning: a settings toggle leaves the vendor object's state unchanged, and the brief's cost premise was not the bill

## Problem

Slice 4 of the code-quality arc had to decide whether GitHub Code Quality stays on, then record the decision. Two premises were taken from upstream text and turned out not to match the system:

1. The brief and the audit said the cost was "$10 per active committer per month plus AI credits and Action minutes". Reading `GET orgs/jikig-ai/settings/billing/usage` (read-only) showed one line, product `code_quality`, SKU "Code Quality AI Credits": $94.31 in September and $160.65 in October. No per-committer line exists. The first CTO ruling (keep, re-evaluate) rested on the $10 figure; the second (off) rested on the measured meter.
2. The plan said the disable would be proven by `GET .../actions/workflows/343194280` no longer reading `active`. After the toggle the workflow object still reads `active` (updated_at unchanged). The behaviour that changed was that new pushes stopped getting a `Code Quality: PR #N` run, and the settings page offered "Enable code quality".

## Solution

- Read the billing usage API before ruling on any cost lever; it is one call and it replaced the whole premise.
- Prove a settings-toggle disable by the behaviour the toggle controls: the runs that stop appearing on pushes made after the change (check at least two heads, and one before the change as a control), plus the settings page reading off after a reload. Record the vendor object's unchanged state as a caveat instead of ticking a criterion that predicted otherwise.
- Take every sentence a ruling or a brief supplies and either measure it or mark it as inherited: "ratchets cover the high-volume rules" was true only for what ruff and eslint scan (ruff excludes `knowledge-base`, eslint covers test directories), and "the AI scans toggle was off so the meter came from the standard analysis" was an inference the SKU name argues against.

## Key Insight

A plan acceptance criterion that predicts a vendor object's state after a settings change is a prediction, not a check, and it is the kind a verifier ticks from memory of intent. Word it as the observable behaviour (runs, API reads taken before and after) and run it. Cost and scope premises in a brief are the same: they were true somewhere once (the 2026-10-14 confirm dialog), and the usage API is the arbiter.

## Session Errors

1. **Plan AC predicted `workflow state != active` after the disable** — Recovery: reworded to the run-evidence and recorded the caveat in the audit — Prevention: plan ACs about vendor object state name the behaviour to observe and the control read taken before the change.
2. **Bulk-ticked every plan checkbox with one `sed`** — the work skill already forbids it; it ticked a PR-body criterion that could only be true at ship and a criterion that was false. Recovery: unticked the ship-time item and rewrote the false one — Prevention: tick an AC only by running the command it names (existing work-skill rule; no new rule).
3. **Unmeasured causal and universal claims in the ADR amendment** (AI-scan cause, ratchet coverage, "queue pressure", billing start date) — Recovery: seats flagged them, all qualified or sourced — Prevention: before writing a causal sentence, name the command that would falsify it.
4. **Inherited the "billing began 2026-09-22" and "whole billing life" framing from the plan** into the ledger and ADR; the meter has earlier small items (2026-09-10, August $0.41) — Recovery: reworded to "September and October, daily charges from 2026-09-22" — Prevention: list the meter's items before naming a start date.
5. **Guessed a settings URL** (`settings/code_quality`, 404) — Recovery: read the real link from the page (`settings/code-quality`) — Prevention: take navigation targets from the page's own links.
6. **Run watcher filtered on an event field the branch listing does not expose** and timed out — Recovery: read the run list directly — Prevention: test a poll filter against a known-present row first.
7. **A multi-replacement Python edit silently skipped one replacement** (anchor case mismatch, guarded by an `if … else print`) — Recovery: re-ran with exact text — Prevention: assert every replacement landed and read the failing key, not the batch's closing "ok".
8. **A commit was blocked as a commit on main** because a later `cd` to the bare repo root sat in the same command — Recovery: split the commit and the issue comments into separate calls — Prevention: keep a commit in a call with no other `cd`.
9. **Technical-ruling gate rejected `Ruled by CTO agent, <date> (revised):`** — Recovery: moved the qualifier after the colon — Prevention: the shape is `Ruled by CTO agent, <date>: <decision> - <rationale>` with nothing between the date and the colon.
10. **Secret-scan hook logged `.gitleaks.toml absent` for a worktree commit** — the scan did not run; a full-range gitleaks run found no leaks — Recovery: filed #10609 as its own issue — Prevention: tracked there.

## Related

- #10331 (arc tracker), #9730 (S5 tracker), #10381 (verification), #10609 (secret-scan hook gap).
- ADR-276 amendment of 2026-10-19; audit `2026-10-14-github-code-quality-baseline.md`.
