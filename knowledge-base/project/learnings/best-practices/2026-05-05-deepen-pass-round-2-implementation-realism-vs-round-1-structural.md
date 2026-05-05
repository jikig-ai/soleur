---
date: 2026-05-05
category: best-practices
tags: [planning, deepen-plan, security, plan-vs-code-drift, internal-consistency]
module: soleur:plan, soleur:deepen-plan
symptom: "Plan body asserts a security boundary or atomic primitive; the actual code path or downstream SQL grammar contradicts the plan claim; only a second deepen-pass catches it"
root_cause: "Round-1 deepen agents (security-sentinel, architecture-strategist) operate on plan TEXT; they validate the plan's internal logic against external best practices but rarely grep the implementation file the plan is supposedly hardening. Round-1 also doesn't self-audit later sections of the plan after earlier sections drop the infrastructure those later sections reference."
---

# Deepen-pass round 2 surfaces plan-vs-code drift that round 1 cannot

## Problem

During `/soleur:deepen-plan` for `feat-agent-runtime-platform` (PR #3240), two distinct round-1 misses surfaced only in round 2:

1. **Plan-vs-code security-boundary drift.** Plan §1.2 asserted "BYOK delivered NEVER via `process.env`" as a load-bearing CWE-526 mitigation. Round-1 security-sentinel reviewed the plan TEXT, validated the AsyncLocalStorage scope shape, and approved. Round 2 ran a targeted grep on `apps/web-platform/server/agent-env.ts:46-49` and found `buildAgentEnv()` actively writes `env: { ANTHROPIC_API_KEY: apiKey, ... }` into the spawned subprocess's environment block — the Anthropic Claude Agent SDK's CLI subprocess REQUIRES the key in env. The plan's negative claim was false at the code level. Mitigation had to be rewritten from "remove from env" to "kernel-harden the env block via `prctl(PR_SET_DUMPABLE, 0)` + bubblewrap `--proc /proc`".

2. **Plan internal-consistency drift after deepen-pass infrastructure drop.** Plan §3.5 prescribed `INSERT … ON CONFLICT (founder_id, window_start) DO UPDATE` against a `tenant_cost_window` table. Earlier in the same deepen pass, DHH-style review-cut #4 dropped that table (cumulative spend was made derivable from `audit_byok_use` SUM). The §3.5 grammar was now syntactically un-implementable — no conflict target exists — but no agent re-read §3.5 after the table drop. Round 2 (data-integrity-guardian re-running over the post-drop plan) caught it; primitive was rewritten as a single-statement WITH-CTE on `users`.

## Solution

Both classes of miss share the same fix: the deepen-plan skill's round-2 fan-out MUST include two specific agent prompts that round 1 does not:

1. **Verify-the-negative agent prompt.** For every negative security claim in the plan ("NEVER X", "MUST NOT Y", "key never reaches Z"), spawn a targeted `Read` + `grep` against the implementation file the plan claims is constrained. The agent's task is not "is this a good plan" but "does the code TODAY contradict this plan claim — yes/no, with a file:line citation". Round 1's structural reviewers don't do this because their job is plan-quality, not plan-vs-code reconciliation.

2. **Post-edit self-audit agent prompt.** After round-1 edits drop or rename infrastructure (tables, columns, modules), spawn a re-read pass that greps the rest of the plan body for references to the dropped infrastructure (`grep -n "tenant_cost_window\|<dropped-symbol>" plan.md`). Every hit is a candidate for a downstream rewrite that round 1 missed.

In this session both passes were run inline in round 2 because the user explicitly invoked deepen-plan a second time. The lesson is that they should be **structural** to the deepen-plan skill, not contingent on a second invocation.

## Key Insight

Round-1 deepen agents review the plan as a document. Round-2 catches drift because it reviews the plan as code-against-code: "does the plan's claim survive a grep against the actual implementation, and does the plan's later half survive a grep against its own earlier half?"

Both checks are cheap (one grep per claim, one grep per dropped symbol). The cost-benefit ratio for adding them to round 1 is overwhelmingly positive. The barrier is that round-1 prompts are tuned for "find new issues from external best practices" rather than "find drift between this plan and existing code or earlier sections of itself."

## Prevention

- For plans that contain negative security claims (`NEVER`, `MUST NOT`, `does not reach`, `cannot leak`): deepen-plan adds a "verify-the-negative" agent that greps the named-or-implied implementation file for the constrained behavior.
- For plans where deepen-pass round 1 drops a table, column, RPC, or module: deepen-plan adds a "post-drop self-audit" pass that greps the rest of the plan body for references to the dropped symbol.
- This learning is in scope for a future skill edit to `plugins/soleur/skills/deepen-plan/SKILL.md`. Not folded into AGENTS.md (byte-budget pressure; existing `cq-plan-ac-external-state-must-be-api-verified` covers the spirit; adding another rule would be net-negative per `cq-agents-md-why-single-line`).

## Tags

category: best-practices
module: soleur:plan, soleur:deepen-plan
related-prs: "#3240"
related-learnings:
  - 2026-04-23-plan-quality-class-deepen-pass-catches.md
  - 2026-04-15-plan-skill-reconcile-spec-vs-codebase.md
  - 2026-05-04-verify-third-party-action-behavior-claims-against-codebase-precedent.md
