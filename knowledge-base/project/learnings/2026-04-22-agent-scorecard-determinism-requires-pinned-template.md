---
date: 2026-04-22
category: integration-issues
tags: [agents, scheduled-audits, determinism, prompt-engineering, aeo, growth-strategist]
issue: 2679
related_issues: [2615, 2596]
module: growth-strategist
---

# Learning: Agent-produced scorecards drift when the template isn't pinned

## Problem

Three consecutive runs of `scheduled-growth-audit.yml` (2026-04-18, 04-19, 04-21) produced three different AEO scorecard shapes:

- **04-18:** SAP framework (Structure/Authority/Presence), weights 40/35/25, Presence row present (40/F).
- **04-19:** 8-component AEO rubric (FAQ structure, answer density, statistics, source citations, conversational readiness, entity clarity, authority, citation-friendly structure). No Presence row.
- **04-21:** Back to SAP, Presence 20/25 (80%).

The 04-19 drift broke #2615's exit criteria (Presence lift from 40/F → ≥55/D) because the Presence row was gone. Triage landed in #2679.

## Root Cause

Neither the workflow prompt nor the agent doc prescribed a deterministic scorecard template:

- `.github/workflows/scheduled-growth-audit.yml` Step 2 prompt: *"Produce a structured scoring table and detailed analysis."* — no format specified.
- `plugins/soleur/agents/marketing/growth-strategist.md` GEO/AEO Content Audit section: describes SAP dimensions qualitatively, lists sub-signals under each, but does not pin weights, grading scale, or the table column structure.

With qualitative guidance and no pinned template, the agent freelanced a new table shape each run based on which signals felt most diagnostic at the moment.

## Solution (Planned)

Pin a **dual-rubric template** in BOTH the workflow prompt and the agent doc:

1. **SAP headline scorecard** (weights Structure=40, Authority=35, Presence=25; grading A≥90, B 80-89, B+ 75-79, C 60-74, D <60). This preserves cross-audit Presence comparability that #2615 depends on.
2. **8-component AEO diagnostic** (weights FAQ=20, Answer density=15, Statistics=15, Source citations=15, Conversational=10, Entity clarity=10, Authority/E-E-A-T=10, Citation-friendly=5). This surfaces richer diagnostic detail without replacing the headline.

Pinning in both surfaces (workflow inline + agent doc) is belt-and-suspenders: cron runs and ad-hoc `/soleur:growth aeo` invocations both get the deterministic template.

## Key Insight

**Agents with qualitative scoring instructions produce non-deterministic scorecards.** When the output is a comparison artifact (something consumed across multiple runs for trend analysis or threshold verification), the prompt MUST pin:

1. **Exact dimensions** (named rows).
2. **Weights** (numeric, summing to 100 or 1.0).
3. **Grading scale** (numeric thresholds → letter grades).
4. **Column structure** (Dimension, Weight, Score, Weighted, Notes).

Qualitative "score each category" plus a list of sub-signals is not enough. If you want comparable outputs across runs, prescribe the table verbatim.

## Prevention

- For any agent that produces a scorecard consumed by workflows or threshold gates, audit the prompt for the four pinning requirements above.
- When creating a follow-through issue with score-based exit criteria (e.g., "Presence ≥ 55/D"), verify the producing agent's template is pinned BEFORE the issue is filed. An exit criterion against a free-form agent output is a latent rubric-drift bug.
- When drift is detected (scorecard shape differs from prior runs), check the workflow prompt and agent doc in the same diagnostic pass — drift usually lives in one of those two surfaces, not in the agent's reasoning.

## Session Errors

1. **Spec directory created at bare-repo path, invisible from worktree** — `worktree-manager.sh feature <name>` echoed `Created spec directory: <bare-repo-path>/knowledge-base/project/specs/<feat>/` but that directory was not accessible from the worktree working tree. `ls` from inside the worktree returned exit code 2. Recovery: `mkdir -p` inside the worktree before `Write` could save `spec.md`. **Prevention:** The brainstorm skill already prescribes writing inside the worktree, so this is a UX papercut in the worktree script's echo rather than a workflow violation. Worth tracking but not blocking.

## References

- Source PR: #2596 (on-site Presence surface)
- Follow-through: #2615
- Triage: #2679
- Audits: `knowledge-base/marketing/audits/soleur-ai/{2026-04-18-seo-audit.md, 2026-04-19-aeo-audit.md, 2026-04-21-aeo-audit.md}`
- Agent doc: `plugins/soleur/agents/marketing/growth-strategist.md`
- Workflow: `.github/workflows/scheduled-growth-audit.yml`
