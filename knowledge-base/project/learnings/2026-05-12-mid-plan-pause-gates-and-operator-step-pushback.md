---
title: Mid-plan pause-gates and operator-step pushback both violate "execute, don't list"
date: 2026-05-12
category: workflow
tags: [work-skill, plan-skill, ship-skill, automation, operator-burden, mcp]
---

# Mid-plan pause-gates and operator-step pushback both violate "execute, don't list"

## Problem

During a 13-phase /work execution of a GDPR-critical feature
(`feat-dsar-art15-export-endpoint` #3637), the agent:

1. Inserted "Pause for review or continue?" prompts after each
   committed phase, even though `tasks.md` defined Phase 0 → Phase 13
   as a single execution unit and the run was in pipeline mode (file
   path arg in Phase 1).
2. At Phase 13 ("Pre-merge verification") and the post-merge section,
   listed the steps back to the operator as a manual checklist:
   "Apply migrations 041 + 042 to dev Supabase via supabase db push
   or MCP", "select * from cron.job where jobname like 'dsar-export-%'
   returns 2 rows", "gh pr ready 3634", etc. — instead of executing
   them via the loaded Supabase MCP server (apply_migration,
   execute_sql) and `gh` CLI.

Both behaviors share the same root cause: the agent treated the
multi-phase plan as a sequence of opt-in handoffs rather than a
single pipeline, and treated "operator-driven" as a do-not-execute
label rather than a routing label that should be re-checked against
available automation.

The user explicitly called this out:

> we need to improve the workflow so you stop providing steps for
> operator/me and do those automatically. Soleur Users won't
> understand those things. they need to run automatically as part
> of the workflow

## Root causes

**Cause 1 (mid-plan pausing):** The work skill's Phase 4 handoff
section says "Continue through the post-implementation pipeline
automatically. Do NOT stop and wait" — but only at the END of work,
not BETWEEN sub-phases of a long Phase 2. There was no explicit rule
covering "tasks.md has 13 phases; do them all without pausing." The
agent filled the silence with caution, asking "continue or pause?"
after each commit. A 13-phase plan triggered 7 "pause or continue?"
prompts.

**Cause 2 (operator-step pushback):** The plan template
(`plan/SKILL.md`) prescribes a `### Post-merge (operator)` subsection
for actions that happen post-merge — but does not require the plan
author to first ASK whether each step is automatable. The plan rev-2
authored AC-PM-1 through AC-PM-4 as operator steps; three of four
were Supabase MCP one-liners. The /work agent inherited the labels
verbatim and re-listed them.

**Compounding factor:** The principle "every 'please run this
manually' is a context switch — execute, don't list" is documented
in ship/SKILL.md:1027 and ship/SKILL.md:1177 (with PR #1375 as the
canonical past failure), but it lives in the SHIP skill, not in /work
or /plan. Agents executing /work and /plan don't read /ship and so
don't internalize the rule until they invoke /ship.

## Fix

Three concrete edits committed in the same fix:

1. **work/SKILL.md** — added "No mid-plan pause gates (HARD GATE)"
   and "Operator-step automation gate (HARD GATE)" inside Phase 2's
   task execution loop. The first forbids inserting "continue or
   pause?" between sub-phases; the second enumerates the loaded MCP
   servers + CLIs (Supabase, gh, Playwright, Cloudflare, Stripe) that
   make most "operator" steps automatable, and instructs the agent to
   execute inline rather than list.

2. **plan/SKILL.md** — added an "automation-feasibility gate" as a
   prerequisite for authoring `### Post-merge (operator)` steps.
   Genuinely-not-feasible steps (CAPTCHA, interactive OAuth consent,
   judgment calls) are still allowed but require an inline
   `Automation: not feasible because <X>` justification.

3. This learning file (you're reading it).

## Prevention

For agents executing /work in pipeline mode:

- Treat `tasks.md` Phase 0 → Phase N as ONE execution unit. The only
  sanctioned stopping point is the Phase 4 handoff to /review →
  /resolve-todo-parallel → /compound → /ship.
- Before any text that says "Pause for review?" or "Continue to
  Phase N+1 next turn?" — STOP and re-read the work skill Phase 2
  hard-gate. The pipeline is the contract.
- For any step a phase calls "operator-driven", check the loaded MCP
  tools list first. If `mcp__plugin_supabase_supabase__apply_migration`
  is loaded and the step is "apply migration X", the step is
  automatable.

For plan authors using /plan:

- Before adding a row to `### Post-merge (operator)`, run the
  automation-feasibility gate. If the step is automatable, place it
  inline in a /work phase or in /ship instead.

## Session errors

The pause-gate violation surfaced 7+ times in a single session before
the user pushed back. The operator-step listing violation came at
Phase 13 with text starting `## Phase 13 (operator) — next steps for
you:`. Both were caught by the operator, not by self-audit; the fixes
above move the audit upstream into the skill files themselves.
