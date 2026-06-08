---
name: plan-review
description: "This skill should be used when having multiple specialized agents review a plan in parallel. It spawns DHH, Kieran, and code simplicity reviewers to provide diverse feedback on implementation plans."
---

> **Dynamic-workflow alternative (opt-in).** A [`Workflow`-tool](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code) port of this skill lives at [`workflows/plan-review.workflow.js`](./workflows/plan-review.workflow.js) — deterministic fan-out, journaled resume, schema-validated output. Run it with `Workflow({ scriptPath: "plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js", args: ... })`. The prose skill below stays the default; the two coexist during calibration. See [`knowledge-base/project/specs/feat-review-workflow-prototype/spec.md`](../../../../knowledge-base/project/specs/feat-review-workflow-prototype/spec.md).

# Plan Review

Have @agent-dhh-rails-reviewer @agent-kieran-rails-reviewer @agent-code-simplicity-reviewer review this plan in parallel.

When the plan declares `Brand-survival threshold: single-user incident` in its `## User-Brand Impact` section, also include @agent-soleur:engineering:review:architecture-strategist and @agent-soleur:product:spec-flow-analyzer in the parallel batch — the 3-agent baseline catches overengineering and convention drift; the 5-agent panel catches blast-radius and flow gaps.

When consolidating a 5-agent panel's findings, treat the simplification panel (DHH + code-simplicity) and the correctness panel (Kieran + architecture-strategist + spec-flow) as orthogonal axes. **When BOTH panels fire on the same scope, prefer delete over fix** — a feature that simultaneously triggers "too complex, remove" and "has 4 specific bugs" is over-architected; cutting it dissolves the bugs. Many "paper-resolution" findings (FRs added without implementation) vanish when the cuts land. **Why:** 2026-05-11 #2720 plan v1→v2 — 953→829 lines, 4 P0 issues dissolved when the matrix-split cut landed; see `knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`.
