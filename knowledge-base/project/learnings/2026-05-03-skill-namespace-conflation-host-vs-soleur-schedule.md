---
title: Skill-namespace conflation — host `schedule` vs `soleur:schedule`
date: 2026-05-03
category: integration-issues
tags: [skills, namespace, schedule, harness, agent-routing]
related_issues: [3094, 3067, 3093]
related_prs: [3067]
related_brainstorms: [knowledge-base/project/brainstorms/2026-05-03-schedule-one-time-runs-brainstorm.md]
---

# Skill-namespace conflation — host `schedule` vs `soleur:schedule`

## Problem

Two distinct skills exist with the same short name `schedule`:

- **Host `schedule`** (Anthropic-managed) — registers a routine via `CronCreate`/`CronList` deferred tools; agent fires in Anthropic's sandbox; supports recurring AND one-time ("open a cleanup PR for X in 2 weeks"); cannot access user's repo, secrets, or CI.
- **`soleur:schedule`** (this plugin) — generates `.github/workflows/scheduled-<name>.yml` committed to the user's repo; agent fires in user's GitHub Actions runner with their secrets; supports recurring only (until #3094); CAN push commits, open PRs, invoke Soleur skills.

A parallel session needed to schedule a one-time follow-up investigation in 2 weeks. The agent declined `/schedule`, citing "the skill generates recurring cron workflows, not one-time agents" and "the skill template invokes a single skill name without arguments." Both statements are true of `soleur:schedule` but **false of host `schedule`**, which the agent never considered. The follow-up was instead posted as an issue comment with no resurfacing mechanism.

## Root cause

Skill descriptions in the available-skills manifest list the host skill as bare `schedule` and the plugin skill as `soleur:schedule`. When an agent thinks "the schedule skill", it tends to resolve to whichever skill it most recently discussed or is most familiar with — without disambiguating. Neither skill's description explicitly tells the agent "if you need X, prefer the other one."

The agent's reasoning chain failed at the first step: "is there a skill that fits this need?" → resolved to `soleur:schedule` → found `soleur:schedule` insufficient → concluded "no skill fits" → fell back to a comment. The correct reasoning chain would have been: "is there a skill that fits?" → resolve to **all** skills with `schedule` semantics → host `schedule` fits → use it.

## Solution

Two layers of fix:

1. **Disambiguation in `soleur:schedule` SKILL.md.** Add a "When to use this skill vs harness `schedule`" section that explicitly tells the agent: act-on-repo cases (push commits, open PRs, run Soleur skills, modify branches, use repo secrets) → `soleur:schedule`; think-and-report cases (analysis, summaries, posting somewhere, no repo writes) → harness `schedule`. Tracked as part of #3094 / FR6.
2. **AGENTS.md cross-reference.** Add a one-line pointer in the Communication or Workflow section so future agents see this distinction without having to read the SKILL.md. Sized to fit byte budget (≤120 chars).

The deeper structural fix is to verify-existence-of-alternatives whenever a skill is judged insufficient. If `/foo:bar` doesn't fit, check `/bar` (bare) and any other namespaces before falling back to manual.

## Secondary insight: different abstractions ≠ merge

In the same brainstorm, the user proposed merging `--once` with `feat-follow-through` to reduce code paths. Analysis showed the two are different abstractions (date-driven vs condition-driven). Forcing condition-driven work through a date-driven primitive would either (a) require users to pre-guess when conditions complete, or (b) re-implement polling logic inside one-shot agents. "Less code paths" became "more total complexity."

The lesson: when two systems look similar at the API surface, check the underlying abstraction before merging. Two cleanly-separated systems with clear "use X for Y" docs are often simpler than one system that handles both with conditional logic. Applies broadly: skills, agents, workflow stages, even types.

## Session Errors

**Compound skipped before commit** — Phase 3.6 of brainstorm committed brainstorm + spec before compound ran (compound was structurally placed in Phase 4). Violates `wg-before-every-commit-run-compound-skill`. Recovery: ran compound after commit (this file). Prevention: brainstorm skill Phase 3.6 should run compound before its commit step, OR the workflow gate should be relaxed for brainstorm-doc-only commits. Proposed enforcement: skill instruction edit on brainstorm Phase 3.6.

**AskUserQuestion 5-option validation error** — minor tool-validation error, recovered in 1 retry. No rule needed; tool schema enforces the cap.

## Prevention

**For skill-namespace conflation:**
- When asked to run a recurring or scheduled task, list ALL skills matching the pattern before judging any of them insufficient.
- When proposing fallback ("post a comment instead"), verify no alternative namespace covers the original ask.
- Plugin skills with names that overlap harness skills MUST include explicit disambiguation in SKILL.md.

**For "should we merge these?" questions:**
- Identify each system's primary axis (date vs condition, sync vs async, push vs pull).
- If axes differ, default to coexistence with documentation. Merge only if the merge collapses the axes cleanly (without conditional branches).

## Tags

- category: integration-issues
- module: skills/schedule
- impact: agent-routing
