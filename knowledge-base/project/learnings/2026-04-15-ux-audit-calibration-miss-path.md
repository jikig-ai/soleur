---
title: "ux-audit calibration MISS path: ship dry_run=true permanently is a real escape hatch, not a fallback"
date: 2026-04-15
category: agent-loop-calibration
tags: [ux-audit, agent-loop, calibration, dry-run, escape-hatch]
related_issues: [2341, 2342, 2378, 2379]
---

# Learning: ux-audit calibration MISS path ships dry_run=true permanently

## Problem

Plan #2341 Phase 3 introduced a calibration signal for the `soleur:ux-audit` agent loop: the first dry-run must surface "sidebars take too much space / no collapse control" in its top-5 findings. If the signal does not appear, the plan allows exactly one rubric tune, then either:

- **PASS** (signal appears in re-run) → flip `dry_run=false`, trust the agent to file issues.
- **MISS** (signal still absent after one tune) → ship with `dry_run=true` permanently, unblock the dependent feature (#2342) on founder judgment.

The plan treats these outcomes symmetrically, but the MISS path had never actually been exercised. The temptation during implementation was to interpret MISS as "tune more" or "investigate root cause" (see #2379's auth/storage-state investigation) rather than accept the plan's escape hatch at face value.

## Solution

Run the ONE tune permitted, run one re-run dry-run, then accept the outcome:

1. **Apply all three rubric tunes from #2378 in a single commit** (route-list.yaml reorder, CAP_PER_ROUTE=2, strengthened real-estate rubric). Do not split into separate commits or A/B individual tunes — the plan grants one tune budget, not three.
2. **Trigger the scheduled workflow on the feature branch** via `gh workflow run scheduled-ux-audit.yml --ref <branch> --field dry_run=true`. The workflow uses `actions/checkout` and reads the skill from the checked-out ref, so the feature branch's tunes take effect without merging to main.
3. **Evaluate against the calibration signal exactly.** In this session the re-run produced 3 of 5 findings on bot-authenticated `/dashboard*` routes (up from 1 of 5 pre-tune) — CAP_PER_ROUTE and route reorder worked as designed. But the specific "collapsible sidebar" finding did not surface. Partial success on the category is not the signal; the plan's calibration check is exact.
4. **Ship the MISS path without rationalization.** Hardcode `UX_AUDIT_DRY_RUN: 'true'` in the scheduled workflow, remove the `workflow_dispatch.inputs.dry_run` toggle, update the workflow header comment to document the MISS outcome and the explicit manual step required to re-enable file mode. Post closing comments on #2378 (tune exhausted) and #2342 (unblocked on founder judgment).

## Key Insight

**Agent-loop plans with an escape hatch are stronger than plans without one, but only if the escape hatch is actually used.** The instinct under a MISS is to widen the rubric further, add more calibration runs, or dig into sibling investigations (#2379 has 3 separate root-cause hypotheses for why bot routes underperformed). All of that is work the plan did not budget. The MISS path exists precisely because agent outputs on subjective categories (UX judgment) will occasionally diverge from the founder's prior even when the rubric is well-tuned — at some point, manual review of findings is the cheaper contract than further automation.

The friction lever that makes MISS work is in the workflow file, not the skill:

- Hardcode the env var (`UX_AUDIT_DRY_RUN: 'true'`) rather than defaulting it, so re-enabling file mode requires a commit rather than a UI toggle.
- Remove the `workflow_dispatch.inputs.dry_run` input entirely, so there is no one-click way to flip the state.
- Document the MISS outcome in the workflow's header comment with links to the specific dry-run IDs, so future maintainers understand why the state is permanent rather than "temporarily paused."

The audit loop still runs on every push and monthly cron. Findings still land in the artifact. The founder reads the artifact and files issues manually. This is not the audit failing — it is the audit operating in the mode the plan explicitly designed for.

## Session Errors

**Edit attempt on route-list.yaml without prior Read** — Recovery: ran Read tool first, then retried Edit. Prevention: already hook-enforced by the Edit tool's built-in read-before-write guard (rule `hr-always-read-a-file-before-editing-it`). No workflow change needed.

**First Monitor script emitted one event per poll cycle instead of only on state change** — Recovery: TaskStop and relaunch with a `prev != result` guard around `echo`. Prevention: skill-level — noted in work-parallel docs via this learning. When using the Monitor tool for CI polling, the filter must both cover all terminal states AND deduplicate identical consecutive outputs; otherwise a 45-minute job generates 45 notifications.

**GitHub Actions PreToolUse security reminder hook fired on workflow edit** — Recovery: re-issued the identical Edit, which succeeded on the second attempt. Not a real failure — the hook output looked like an error but the edit was non-blocking advisory. No workflow change needed.

## Tags

category: agent-loop-calibration
module: soleur:ux-audit
