---
date: 2026-05-15
category: best-practices
issue: "#3833"
pr: "#3837"
tags: [agents-md, rule-retirement, cross-reference-sweep, byte-budget, workflow]
---

# Learning: AGENTS.md rule retirement requires `/work`-time cross-reference sweep (not just plan-time)

## Problem

Issue #3833 (shrink B_ALWAYS below 22,000) went through three plan iterations before landing:

1. **Plan v1 — demote + 5 Why-trims.** Rejected at 5-agent plan review: simplification panel (DHH + code-simplicity) said "prefer retirement"; correctness panel (Kieran + spec-flow) flagged byte-math drift + missing atomic-commit AC.
2. **Plan v2 — retire `hr-no-dashboard-eyeball-pull-data-yourself`.** Adopted at the operator's gate based on simplification panel recommendation. **Abandoned at /work time** when the cross-reference sweep discovered the rule was canonically anchored in 5 operator-facing surfaces:
    - `plugins/soleur/skills/ship/SKILL.md:1143, 1169`
    - `plugins/soleur/skills/plan/SKILL.md:726`
    - `plugins/soleur/agents/engineering/review/deployment-verification-agent.md:97`
    - `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md:160`
    - `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md:101`

   Retirement would have left 5 dangling references (rule body absent from sidecars; references resolve to a retired ID via `retired-rule-ids.txt` → learning file). The brainstorm 2026-04-23 retirement protocol allows this, but operator-facing skill bodies reading `Per hr-no-dashboard-eyeball...` would point at nothing in-context.
3. **Plan v3 — pivot back to demote + 6 Why-trims.** Architecture-strategist had ACCEPTED this approach at plan review; the simplification panel had argued for retirement without accounting for cross-reference anchoring cost.

The /work-time discovery cost ~20 minutes of pivot churn (rewriting plan, rewriting tasks, separate commits). Plan-time discovery would have cost ~30 seconds (one `grep -rln`).

## Solution

**Plan-time gate for retirement candidates.** Before proposing the retirement of any AGENTS.md rule ID, grep the entire repo for cross-references:

```bash
grep -rln "<rule-id>" --include='*.md' --include='*.sh' --include='*.py' --include='*.ts' . \
  | grep -v knowledge-base/project/{learnings,brainstorms,plans,specs}
```

The exclusions strip out the natural retirement breadcrumbs (the retired-rule-ids.txt entry, the linked learning file, the brainstorm that decided to retire) so only the OPERATIVE references show. If >2 matches, prefer demotion over retirement — the cross-reference cleanup cost exceeds the simplicity win.

This sweep should run at plan time (in the `## Files to Edit` section), not at /work time. Add to plan/SKILL.md Sharp Edges: when retiring an AGENTS.md rule ID via `scripts/retired-rule-ids.txt`, the plan's "Files to Edit" enumeration MUST include the grep output. If retired-rule-ids.txt entry is the only edit needed, mark approach as "clean retirement"; otherwise list every cross-reference site as a co-edit OR justify why dangling references are acceptable.

## Key Insight

**The simplification panel's "retire one rule, ship in 20 minutes" framing was correct in spirit but missed the cross-reference cost.** The architecture-strategist's ACCEPT on the demote+trim approach turned out to be the right call once the cross-reference anchoring was surfaced. Plan-review by multiple agents catches different defect classes; deferring the cross-reference sweep until /work time means the wrong panel's recommendation can win at the operator gate.

Two complementary practices:
1. **Plan-time grep for any rule-ID retirement** (this learning's solution).
2. **The brainstorm's discoverability litmus** stays in place for *systemic* retirement (~25-rule sweep against the 32k target); for single-PR shrink work, the cross-reference cost dominates the heuristic.

## Session Errors

- **Cross-reference sweep ran at /work time, not plan time.** Recovery: pivot from v2 (retire) back to v3 (demote+trim) — architecture-strategist had already ACCEPTED v3. Prevention: add the `grep -rln <rule-id>` step to plan/SKILL.md's retirement-candidate analysis (this learning is the workflow proposal).
- **Plan byte-math drifted by ~12 B across both v1 (348→352 demotion bytes) and v3 (21,954→21,966 final).** Recovery: post-commit `wc -c` measurement replaced the projection; commit message and PR body carry the actual number. Prevention: plan-time estimates should explicitly note "±15 B drift envelope" and the AC should target the lefthook reject threshold (≤22,000) rather than an arbitrary tighter number that could miss by single-digit drift.
- **Plan v2 referenced wrong AGENTS.md line for the retirement target (line 25 vs actual line 36).** Recovery: caught at /work time by `grep -n` before any edit. Prevention: at plan time, run `grep -n "<rule-id>" AGENTS.md` and copy the actual line number into the plan rather than reading by index.
- **Workflow stop after Review Phase Complete** (wrap-up sentence instead of immediate next-skill invocation). Recovery: user-flagged; continued the pipeline. Prevention: Stop hook to be added in a separate PR — detects `## (Work|Review|QA|Compound) Phase Complete` markers in the just-ended turn without an accompanying Skill tool call, re-injects the next-step directive as a SystemReminder.
- **Pattern-recognition reviewer P3-6 false positive** ("diff deletes feat-one-shot-3818, feat-one-shot-3827 spec folders"). Recovery: verified my diff is adds-only via `git diff origin/main...HEAD --numstat`. Prevention: confirm reviewer agents use three-dot diff syntax; flag two-dot misuse in the review skill's Sharp Edges (already documented under "branch-vs-main diffs" entry).
- **Initial planning subagent (a560d31374dd861ad) hit Claude usage limit at 29 tool uses.** Recovery: fell back to inline plan + deepen-plan path per the one-shot fallback contract. Prevention: this is budget-shaped, not workflow-shaped; no rule change proposed. Existing fallback path worked.

## Related

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-23-agents-md-budget-revisit-brainstorm.md` (discoverability litmus + retirement protocol)
- Plan: `knowledge-base/project/plans/2026-05-15-chore-agents-shrink-b-always-below-22000-plan.md` (this PR's plan with three-iteration history visible)
- PR #3837 (this PR)
- Issue #3834 (per-rule cap audit — follow-up shrink work)
- Brainstorm 2026-04-23 (~25-rule retirement pass for the 32k target)
