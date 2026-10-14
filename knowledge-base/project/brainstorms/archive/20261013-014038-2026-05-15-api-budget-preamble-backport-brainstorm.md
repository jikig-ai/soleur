---
title: "API-budget operator preamble backport to autonomous-loop skills"
date: 2026-05-15
status: brainstorm
brand_survival_threshold: single-user incident
lane: cross-domain
related_issues: [3819]
parent_pr: 3809
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-15-goal-primitive-operator-escape-hatch-brainstorm.md
parent_plan: knowledge-base/project/plans/2026-05-15-feat-goal-primitive-operator-escape-hatch-plan.md
---

# API-budget operator preamble backport — Brainstorm

## What We're Building

A uniform API-budget operator preamble, expressed as a fenced `<decision_gate>` block, backported to the six autonomous-loop skills that don't currently carry one:

- `plugins/soleur/skills/test-fix-loop/SKILL.md`
- `plugins/soleur/skills/drain-labeled-backlog/SKILL.md`
- `plugins/soleur/skills/resolve-todo-parallel/SKILL.md`
- `plugins/soleur/skills/resolve-pr-parallel/SKILL.md`
- `plugins/soleur/skills/work/SKILL.md`
- `plugins/soleur/skills/one-shot/SKILL.md`

The preamble has three load-bearing parts adapted from `plugins/soleur/docs/pages/goal-primitive.md` §"What it consumes":

1. **Per-iteration cost model**, tailored to the skill (bounded iterations vs. parallel agent fan-out vs. wall-clock pipeline).
2. **Runaway risk**, naming the specific failure mode (a poorly-bounded loop or oversized cluster can produce a surprise invoice).
3. **Soleur / Anthropic billing split** + BSL 1.1 warranty disclaimer (canonical wording reused verbatim).

A companion AGENTS.md hard rule (`hr-autonomous-loop-skill-must-disclose-api-budget` or similar slug) + a CI assertion in `plugins/soleur/test/components.test.ts` close the back door for the next autonomous-loop skill.

## Why This Approach

The parent docs PR #3809 (merged 2026-05-15) shipped the API-budget disclosure on the new `/goal` docs page only. The six pre-existing autonomous-loop skills consume operator API budget under the same cost model but never tell the operator. That asymmetry would, on its first runaway invocation, look like Soleur hid the cost surface on its own primitives while disclosing it on Claude Code's. The risk is **trust breach via inconsistent framing**, not a missing technical capability — exactly the surface the user-impact framing question flagged.

The fenced `<decision_gate>` block (surface choice A) is the right surface because:

- It already exists in `test-fix-loop/SKILL.md:42-46` as the pre-flight confirmation pattern. Choosing the same shape across all six skills produces one auditable grep target rather than two competing patterns.
- LLMs running the skill recognize `<decision_gate>` as a "surface this to operator before proceeding" marker, so even skills that don't have an interactive prompt today gain the surfacing behavior at zero additional logic cost.
- A single CI assertion (`grep -l '<decision_gate>' plugins/soleur/skills/{test-fix-loop,drain-labeled-backlog,resolve-todo-parallel,resolve-pr-parallel,work,one-shot}/SKILL.md` must match all six) is a one-line gate.

The single bundled PR (6 files) wins over per-skill PRs once the surface is locked: the prose is structurally similar across files, and reviewers see the consistency itself as evidence of correctness. The issue body's preference for per-skill PRs assumed the design question (fenced vs. inline) was still open; with the surface decided here, the bundled diff is shorter to review than six sequential ones.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Disclosure surface | Fenced `<decision_gate>` block (Approach A) | Matches `test-fix-loop` precedent; one auditable pattern; LLM-recognized surfacing semantics. |
| Uniformity | Same shape across all 6 skills | Auditable via single grep; uniform shape across cost-model variants. |
| Per-skill tailoring | Body of the block adapts to the skill's cost model | `test-fix-loop`: iteration cap; `drain-labeled-backlog`: cluster × one-shot multiplier; `resolve-*-parallel`: N agents in parallel; `work`: tier-cost framing (already partial); `one-shot`: 30-90 min wall-clock pipeline. |
| Soleur / Anthropic split + BSL 1.1 disclaimer | Reused verbatim from `/goal` docs | Canonical wording lives in `goal-primitive.md`; backport copies, doesn't paraphrase, to avoid drift. |
| PR shape | Single bundled PR | Shape is decided; review consistency is the win. Issue body's split-PR preference assumed surface was open. |
| Rule binding | New `hr-*` AGENTS.md rule + CI test | Same plan; closes the door for the next autonomous-loop skill. |
| Description-budget impact | None | Edit is to body text; `description:` frontmatter unchanged; 1800-word cumulative cap unaffected. |
| Placement | After intro paragraph, before "When to use" / Phase 0 | Operator reads it before substantive content; matches `test-fix-loop`'s position of its existing `<decision_gate>`. |

## Open Questions

1. **Rule slug.** Tentative: `hr-autonomous-loop-skill-must-disclose-api-budget`. Plan-phase decision.
2. **CI test placement.** `plugins/soleur/test/components.test.ts` already runs description-budget assertions; adding a sibling "every autonomous-loop skill includes `<decision_gate>`" test is natural. Alternative: standalone test file. Plan-phase decision.
3. **Per-skill cost numbers.** The preamble for `drain-labeled-backlog` and `one-shot` should ideally cite a concrete order-of-magnitude (e.g., "a single one-shot run typically consumes ~$X-$Y of Anthropic credit at default parameters"). Need at least rough empirics. Plan/work-phase to decide whether to ship numbers or defer to follow-up PR.

## User-Brand Impact

- **Artifact:** the six autonomous-loop skill SKILL.md files (operator-facing routing surface).
- **Vector:** an operator runs one of the six skills against an unfamiliar dataset (a 50-issue label backlog, a 30-comment PR, a long test-fix iteration tree) without realizing the per-iteration / per-agent token cost. Anthropic invoices the operator's key; Soleur does not proxy and currently does not warn.
- **Threshold:** single-user incident. One operator surprise invoice in the hundreds-to-thousands of dollars range is a brand-survival event for a tool whose value proposition is autonomous operator-trust.

Carry-forward: the brand-survival threshold is inherited from parent plan #3809; this brainstorm does not re-derive it.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support (carry-forward from parent plan #3809; no leaders re-spawned per Phase 0.5 in-flight feature refresh option).

### Carry-forward summary

CPO, CLO, and CTO already signed off on the user-brand framing for `/goal` itself in the parent brainstorm + plan; the load-bearing user-impact-reviewer gate runs at PR review and is the active enforcement layer for this PR. The backport scope is strictly narrower (no new mechanism, no new surface — just propagating the parent's disclosure pattern to siblings that share the same cost model).

## Non-goals

- Adding a runtime check that the operator has set a billing cap (Anthropic dashboard concern, not Soleur's surface).
- Removing or rewording the existing `test-fix-loop` `<decision_gate>` at lines 42-46 — it remains the *pre-flight confirmation* gate. The new API-budget block is a sibling block, not a replacement. (Plan-phase to confirm whether to stack two `<decision_gate>` blocks or extend the existing one.)
- Retrofitting `/goal` into any of the six skills (AGENTS.md plugin-level guidance explicitly forbids this).
- Per-skill cost-number telemetry collection (deferred; the disclosure prose itself is the PR's deliverable).
