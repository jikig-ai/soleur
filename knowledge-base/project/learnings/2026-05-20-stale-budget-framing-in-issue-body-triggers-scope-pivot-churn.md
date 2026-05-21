---
title: Stale Budget Framing in Issue Body Triggers Scope-Pivot Churn
date: 2026-05-20
category: engineering
tags: [stale, budget, framing, issue, body, triggers, scope, pivot, churn]
domain: planning
related: [cq-write-failing-tests-before, wg-when-an-audit-identifies-pre-existing]
trigger_pr: 4118
trigger_session_artifacts: [knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md, https://github.com/jikig-ai/soleur/pull/4127 (closed — first attempt, framing was correct at file time), https://github.com/jikig-ai/soleur/pull/4143 (closed — second attempt, framing collapsed mid-planning), https://github.com/jikig-ai/soleur/issues/4142 (closed — PR-1 split that became unnecessary)]
type: workflow-pattern
---

# Stale Budget Framing in Issue Body Triggers Scope-Pivot Churn

## Problem

Issue #4118 (Inngest cloud-init IaC) shipped with a precise budget claim in its body:

> `B_ALWAYS at branch tip = 24499 B (4960 AGENTS.md + 19539 AGENTS.core.md). Cap = 22000. Pre-existing overflow = 2499 B.`

That measurement was correct at issue-file time. By the time `/soleur:one-shot` ran the planning subagent ~2 hours later, parallel sessions had merged AGENTS trims (PRs in the #4097 / #4120 / #4122 / #4123 family touched AGENTS files). The actual B_ALWAYS on `main` had dropped to 21849 (under the 22000 cap, in WARN tier).

The first deepen-pass measured against the bare-root HEAD (which was already lagging), reported 24499, and prescribed a 6-rule budget-recovery PR-1 as a prerequisite. The operator agreed to the PR-1/PR-2 split. PR #4127 (the PR-2 draft) was closed; PR #4142 (the PR-1 umbrella) was filed; PR #4143 (the PR-1 draft) was opened.

The SECOND deepen-pass (against the PR-1 worktree, branched from fresh `origin/main`) returned the actual measurement of 21849. The PR-1 rationale collapsed. PR #4143 was closed; #4142 was closed; the work collapsed back to a single PR for #4118 with a much smaller Phase 0 (2 rule trims, not 6).

Net cost: ~3 plan+deepen subagent invocations (~600k tokens), 2 closed PRs, 1 closed umbrella issue, and ~30 minutes of operator decision time.

## Root Cause

A budget claim in an issue body is **a measurement at a point in time**, not an invariant. When the half-life of the measurement is shorter than the planning cycle (the AGENTS budget changes whenever any PR touching AGENTS files merges), the issue body's number is stale on arrival.

The deeper failure: **/soleur:one-shot did not re-measure the operator-cited budget BEFORE spawning the planning subagent.** The first deepen-pass DID re-measure (per `cq-write-failing-tests-before`'s plan-quoted-numbers rule), but by then the planning context was already shaped by the stale claim from the issue body — the deepen-pass's measurement was treated as confirmation of the operator's framing rather than as a freshness probe that could invalidate the framing.

## Solution applied (this session)

1. Filed the budget-recovery PR-1 (#4142 / PR #4143).
2. Second deepen-pass exposed the staleness.
3. Operator chose to collapse the split.
4. Closed PR #4127, PR #4143, issue #4142.
5. Filed #4126 (Tier 2 weekly DR test, originally planned).
6. Restarted /soleur:one-shot for #4118 with slimmed Phase 0 (2 rules, not 6).

## Pattern: "Stale Anchor + Long Planning Cycle" failure mode

This is one instance of a broader failure pattern:

| Anchor type                     | Half-life      | Risk                                                       |
|---------------------------------|----------------|------------------------------------------------------------|
| AGENTS budget (B_ALWAYS)        | hours          | Pivots scope, files unnecessary PRs                        |
| Open-issue counts (`gh issue list \| wc -l`) | hours-days     | Wrong baseline for "how much backlog is this"              |
| Inventory counts cited in body  | hours-weeks    | Sweep-class fixes underspecify the work-list               |
| Lock/lease/queue depth          | minutes        | "There's already a job for X" can be wrong by the time you plan |
| Library version pins            | days-weeks     | "Latest is X.Y" rots fast in active SDKs                   |

For any of these, the operator's framing is **scope direction**, not authoritative measurement. The planning skill must re-measure before pivoting.

## Prevention

**Pre-spawn budget probe in /soleur:one-shot.** Before spawning the planning subagent, the orchestrator should re-measure any operator-cited numerical claim:

```bash
# If the input args reference a B_ALWAYS budget number,
# re-measure and inject the current value into the subagent prompt.
if [[ "$ARGS" == *"B_ALWAYS"* ]] || [[ "$ARGS" == *"AGENTS budget"* ]]; then
  CURRENT_B_ALWAYS=$(python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1 | grep -oE 'B_ALWAYS=[0-9]+' | head -1)
  ARGS="$ARGS [orchestrator-measured at $(date -u +%Y-%m-%dT%H:%M:%SZ): $CURRENT_B_ALWAYS]"
fi
```

Same shape for `inventory_count`, `open_issue_count`, `lib_version`.

**Treat scope pivots as a re-measurement trigger.** When an operator decides "split this PR into PR-1 + PR-2" or "abort and refile" based on a measurement claim, the FIRST action should be `re-measure`, not `re-plan`. The cost of the measurement is seconds; the cost of re-planning is ~$X in agent tokens.

**Plan-time AC's pointing at "≤ baseline" budgets should account for path-name overhead.** This session's AC0 said `B_ALWAYS_after ≤ 21849` (baseline). The trim achieved net +144 B because the pointer paths in the trimmed rule bodies (`knowledge-base/project/learnings/best-practices/2026-05-20-...-why-and-how.md`) consumed ~100 B/rule of the trim budget. Plan-time math should subtract pointer-path cost BEFORE claiming achievable per-rule byte targets.

## Session Errors

- **PR-1/PR-2 split decision was based on a measurement that had drifted ~30 min before being read** — Recovery: the second deepen-pass caught the drift; operator collapsed the split. — Prevention: pre-spawn budget probe (above).
- **AC0's `≤ baseline` was infeasible given path-name overhead** — Recovery: documented the +144 B miss in the Phase 0 commit; landed under the hard 22000 B cap. — Prevention: plan skill should subtract path-string cost from rule-trim budget math before claiming a target.
- **3 plan+deepen subagent cycles for 1 final PR** — Recovery: third cycle landed clean. — Prevention: when operator pivots, the orchestrator should re-measure before re-planning.
- **GHCR digest-pin recommended by security-sentinel but session has no docker auth** — Recovery: documented as known limitation in PR body; the digest-pin is a real improvement deferred to a session with docker auth. — Prevention: plan's "Vendor-tier reality check" section should note whether the current session has access to the registry the PR depends on.
- **`git mv` failed on untracked learning file** — Recovery: used plain `mv`. — Prevention: minor, n/a.

## How to apply

When `/soleur:plan` or `/soleur:one-shot` is invoked with input args containing a numerical claim that names a specific subsystem's state (budget byte counts, queue depth, inventory size, file count, lib version), re-measure that subsystem at the orchestrator level BEFORE spawning the planning subagent. Pass both the operator-cited value AND the orchestrator-measured-now value to the subagent. The subagent's first job is to reconcile them; a stale operator claim becomes an early signal that scope decisions premised on the number need re-validation.

When deciding to split a PR into N stages based on a measurement, **always re-measure first**. The cost of re-measurement is ≤30 seconds and ≤1 bash call.

## Re-evaluation

This learning retires when `/soleur:one-shot` and `/soleur:plan` carry an explicit "operator-cited number freshness probe" gate (analog to `cq-write-failing-tests-before`'s plan-quoted-numbers rule, but at orchestrator level). Until then, the human pattern-match on "operator gave me a number; is it still fresh?" is the load-bearing prevention.
