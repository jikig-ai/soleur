---
name: plan-review
description: "This skill should be used when having multiple specialized agents review a plan in parallel. It spawns DHH, Kieran, and code simplicity reviewers to provide diverse feedback on implementation plans."
---

> **Dynamic-workflow alternative (opt-in).** A [`Workflow`-tool](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code) port of this skill lives at [`workflows/plan-review.workflow.js`](./workflows/plan-review.workflow.js) — deterministic fan-out, journaled resume, schema-validated output. Run it with `Workflow({ scriptPath: "plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js", args: ... })`. The prose skill below stays the default; the two coexist during calibration. See [`knowledge-base/project/specs/feat-review-workflow-prototype/spec.md`](../../../../knowledge-base/project/specs/feat-review-workflow-prototype/spec.md).

# Plan Review

Have @agent-dhh-rails-reviewer @agent-kieran-rails-reviewer @agent-code-simplicity-reviewer review this plan in parallel.

When the plan declares `Brand-survival threshold: single-user incident` in its `## User-Brand Impact` section, also include @agent-soleur:engineering:review:architecture-strategist and @agent-soleur:product:spec-flow-analyzer in the parallel batch — the 3-agent baseline catches overengineering and convention drift; the 5-agent panel catches blast-radius and flow gaps.

When consolidating a 5-agent panel's findings, treat the simplification panel (DHH + code-simplicity) and the correctness panel (Kieran + architecture-strategist + spec-flow) as orthogonal axes. **When BOTH panels fire on the same scope, prefer delete over fix** — a feature that simultaneously triggers "too complex, remove" and "has 4 specific bugs" is over-architected; cutting it dissolves the bugs. Many "paper-resolution" findings (FRs added without implementation) vanish when the cuts land. **Why:** 2026-05-11 #2720 plan v1→v2 — 953→829 lines, 4 P0 issues dissolved when the matrix-split cut landed; see `knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`.

## Named CEO/design/devex panel (relevance-gated)

The eng panel above reviews for engineering quality (simplicity, convention, correctness, blast-radius, flow). A plan can be engineering-immaculate and still be a **product / market / design / developer-experience** mistake. Alongside (never replacing) the eng panel, include a **named panel** of the existing domain leaders — spawned only when the plan is *relevant* to their lens:

| Panel axis | Agent(s) | Lens (reviews the finished plan for) |
|---|---|---|
| **CEO / business** | `@agent-soleur:product:cpo` + `@agent-soleur:marketing:cmo` | cpo: product strategy, positioning, scope-vs-roadmap fit. cmo: market/GTM implications, brand-voice, messaging risk. |
| **design** | `@agent-soleur:product:design:ux-design-lead` | user-flow completeness, UX decay, design-taste risk in user-facing surfaces. |
| **devex / eng-strategy** | `@agent-soleur:engineering:cto` | developer/operator experience, maintenance/DX cost, build-vs-buy, ongoing engineering strategy — **distinct** from `architecture-strategist`'s blast-radius/structural lens. Give `cto` a devex lens string, not a structural one, so the two do not duplicate. |

**Relevance gate — INDEPENDENT of the plan's own `## Domain Review` verdict.** The named panel exists to catch what plan Phase 2.5 got wrong, so it MUST NOT trust that phase's verdict as its trigger (a UI plan mis-judged `Product: NONE` would inherit the exact miss). Compute activation from an **independent** read of the plan's actual content; use the `## Domain Review` + Product/UX Gate tier only as a *hint*, never as the sole gate:

1. **Mechanical UI-surface scan (independent):** scan the plan's `## Files to Create` + `## Files to Edit` against the UI-surface glob superset (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, plus the shared UI-term list). Any hit → force `ux-design-lead` + `cpo` active regardless of the Domain Review verdict.
2. **Fresh relevance read (independent):** judge relevance from the plan *body* (Overview, Files, User-Brand Impact), not by parsing a "Domains relevant: none" line — product/scope language → `cpo`; market/GTM/brand/user-copy language → `cmo`; user-facing/flow/visual language → `ux-design-lead`; code/infra/tooling Files-to-Edit → `cto`.
3. **Threshold bias:** when the plan declares `Brand-survival threshold: single-user incident`, bias toward activating (stakes are high — the eng panel already escalated).
4. If **none** activate (trivial non-engineering docs plan), only the eng panel runs — today's behavior is preserved.

**Every named-panel reviewer is prompted for structured advisory only — NO `AskUserQuestion`.** cpo/cmo default to orchestrator mode and will otherwise emit `AskUserQuestion`, which hangs a headless `one-shot` (a Task subagent cannot answer it, and the agent `.md` body does not reach anonymous Task spawns). The prohibition MUST live in the prompt text, mirroring the plan Phase 2.5 Product/UX gate's "Output a structured advisory — do not use AskUserQuestion."

## Classifier routing (taste findings are surfaced, never silently applied)

Consolidation tags **each** consolidated decision with `decisionClass ∈ {mechanical, taste, user-challenge}` per **[decision-principles.md](../brainstorm-techniques/references/decision-principles.md)** (ADR-084), routing through that doc's **four never-Mechanical classes** (dropping operator-requested scope; a new sub-processor/paid dep; a new recurring cost; an irreversible data op) — not a fresh classification path:

- **Eng-panel** correctness/simplification findings (bug, convention-drift, flow-gap, blast-radius) → **Mechanical** (one right answer / purely-technical), **auto-appliable**. Exception: a `simplify-cut` of **operator-requested scope** is never-Mechanical → Taste / User-Challenge.
- **Named-panel findings default to Taste** (fail-safe): a cpo/cmo/ux/cto finding touching **user-visible / money / scope** is Taste unless it is *clearly* Mechanical (a factual/typo/broken-link fix). Product/market/design findings are almost never Mechanical — bias them to **surface**, never silently auto-apply. This is the single safety point of the panel; on ambiguity it fails toward surfacing.
- Any finding arguing the operator's **stated scope/direction** should change (drop/merge/split/add) → **User-Challenge** — never auto-decide.
- **Security/feasibility regression** → the ADR-084 sanctioned exception: attached → urgent `AskUserQuestion`; headless → terminal halt before merge + an `action-required`+`security` issue.

**Single-signal context.** `plan-review` is NOT one of ADR-084's two "both-signals" consult gates (`plan` Step 4.5, `ship` Phase 5.5); it classifies with a **single** signal (the consolidator's judgment). Per decision-principles.md, ambiguity biases to the more-surfaced class (unsure Taste-vs-User-Challenge → treat as User-Challenge). Do NOT add a per-review strong-model consult here (cost/latency creep — the both-signals adjudication stays owned by `plan` Step 4.5, which writes the *same* `decision-challenges.md` artifact). **The consumer applies the routing** (`plan` "Plan Review (Always Runs)"): Mechanical → auto-apply; Taste / User-Challenge → attached present at the "Apply these changes?" gate (5-line frame for User-Challenge), headless persist to `knowledge-base/project/specs/<branch>/decision-challenges.md` (append; `ship` Phase 6 renders it + files the `action-required` issue). `plan-review` only classifies + appends — it never authors the PR body.
