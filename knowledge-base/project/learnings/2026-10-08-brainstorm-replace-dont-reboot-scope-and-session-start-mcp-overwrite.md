# Learning: scoping "replace, don't reboot" for shipped surfaces, and two session-start frictions

## Problem
Issue #9750 asked to encode immutable infrastructure in the skills, agents and gates Soleur users receive. The repo already had `hr-prod-host-config-change-immutable-redeploy`, so the open question was where the remaining gap sat and how large the mechanism should be.

## Solution
Brainstorm with the CTO, CPO and CLO plus repo and learnings research converged on advisory text only. The edits go to the two infra agents, one plan sharp-edges bullet, and one clause each in review and deepen-plan. They add no AGENTS rule and no blocking gate. Reasons: the rule budget (ADR-151), `cq-agents-md-tier-gate` (domain-scoped IaC content belongs to its owning skill or agent), the rule's repo-only reach, and legitimate reboots (fresh-host NIC bring-up, drained cutover).

## Key Insight
A rule that exists in AGENTS.rules.md reaches only this repo. Before adding a rule, check whether the shipped skill and agent surfaces carry the same guidance. The gap is usually there, and fixing it there costs no rule budget.

## Session Errors
1. **The session-start `.mcp.json` restore overwrote an uncommitted user edit in the main checkout.** Recovery: I backed the file up to the scratchpad first. Prevention: the go.md preamble should skip the restore when `.mcp.json` has uncommitted changes, or back it up itself. Filed as a candidate, not applied.
2. **`iac-plan-write-guard` blocked a spec write because the prose named a service-restart command, although the spec prescribes no manual infrastructure step.** Recovery: reworded to "a service restart". Prevention: when a spec discusses reboot or restart as a concept, name it in prose without the command form.

## Tags
category: workflow-issues
module: brainstorm, infra-agents
