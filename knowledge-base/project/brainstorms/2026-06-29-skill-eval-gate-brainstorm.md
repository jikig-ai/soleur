---
date: 2026-06-29
topic: skill-eval-gate
status: brainstorm-complete
brand_survival_threshold: single-user incident
lane: single-domain
origin: article review — SkillOpt (MS Research, 2605.23904) / GEPA / EvoSkill (2603.02766)
---

# Brainstorm: Validation-Gated Skill-Edit Acceptance Loop

## What We're Building

A verification gate wired into `compound`'s "Route Learning to Definition" step. When compound
proposes an edit to a **verifiable-signal classifier skill** (today: `soleur:go` routing,
`ticket-triage` P-levels), it runs the `eval-harness` arms **before and after** the proposed edit
and only applies the edit if it clears the accept rule. Rejected edits are logged so the same
dead-end is not re-proposed across sessions.

This borrows the one idea from the source article that attacks a real gap for us — a
**validation-gated acceptance loop** (SkillOpt's core discipline) — while deliberately skipping the
parts that don't fit our scale (genetic/Pareto multi-candidate evolution, autonomous unattended
optimizer, "skill as trainable parameter" framing, formal train/test split).

## Why This Approach

Our bottleneck is **edit verification, not edit generation.** `compound` already generates good,
well-placed edits (session-error inventory, deviation analysis, placement gate, enforcement
hierarchy). What we have ~zero of: any measurement of whether a skill/rule edit actually improved
behavior afterward. We own both halves of the gate — `eval-harness` (promptfoo, 2-arm
baseline-vs-skill, +19pts go-routing measured 2026-06-15) and `compound` (the proposer) — but they
are disconnected. This wires them together. Lowest-cost high-leverage borrow: it is integration of
existing pieces, not new infrastructure.

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Trigger model | **Wired into `compound`** route-learning step | Catches edits at the generation source, in-session. |
| 2 | Accept rule | **No-regression + target improvement** | Held-out corpus must not regress AND the targeted miss the edit fixes must now pass. Robust to small-N variance (strict-improve flips on noise at N=7). |
| 3 | Corpus model | **Single append-only synthesized golden set per gated skill** | Each compound fix appends a task encoding the miss → corpus becomes a living regression suite. No fragile train/test split at N=7. Honors "synthesized fixtures only." |
| 4 | Scope | **Classifier skills only** (go-routing, ticket-triage) | The only skills with a verifiable signal + golden set. Article itself says these methods can't work on subjective/open-ended tasks (brainstorm, plan, legal, marketing). Extensible: any skill that gains a golden set can opt in. |
| 5 | Rejected-edit log | **Adopt** (SkillOpt's rejected-edit buffer) | Append rejected edits to a buffer (fits `.claude/.rule-incidents.jsonl` JSONL pattern) so dead-ends aren't re-litigated. |
| 6 | Enforcement-hierarchy guard | Gate applies to **prose edits of gated skills only** | Must NOT crowd out compound's hook-first fix hierarchy (PreToolUse hook > skill instruction > prose). A text-space gate can structurally only judge prose; if over-applied it would bias us back toward prose-only fixes — a regression. |

## Open Questions

- **Headless/in-session API cost.** A before/after eval on go-routing is ~126 calls × 2 arms. Acceptable in-session? Or gate only fires when compound runs in interactive mode and defers to an async run otherwise? (Lean: run it; it's a deliberate quality spend, disclosed.)
- **Fixture-sync drift.** eval-harness golden tasks are a hand-copy of production classifier prose (SKILL.md fixture-sync caveat). The gate is only as honest as the synced fixtures. Does this feature also tighten the sync step, or assume it?
- **What counts as "the target case"** when an edit is cross-cutting (touches AGENTS.md, not a single classifier)? v1 scopes to single-classifier edits; cross-cutting rule edits are out of scope.

## Deferred (follow-up issues)

- **CI backstop for manual edits.** Decision 1 only covers compound-authored edits; a manual edit to `go/SKILL.md` bypasses the gate. A required CI check re-running eval-harness on PRs touching gated skills closes this — deferred to keep v1 proportional.
- **Broader gated-skill catalog.** Adding golden sets for other classifier-like skills (e.g. domain routing in `pdr-*` rules) to bring them under the gate.

## Domain Assessments

**Assessed:** Engineering (self-assessed by orchestrator — internal agent-infrastructure, no user data / no production surface / no UI; full CPO/CLO/CTO triad spawn judged disproportionate for an internal eval-loop tool per the "no process theater" principle).

### Engineering

**Summary:** Pure integration of two existing skills (`compound` + `eval-harness`) plus a small JSONL rejected-edit buffer. No new infra. Main engineering risk is in-session API cost and fixture-sync honesty, both captured as open questions. The enforcement-hierarchy guard (Decision 6) is the load-bearing correctness constraint — the gate must remain prose-only and never displace hook-first fixes.

## User-Brand Impact

- **Artifact:** the `compound` route-learning edit path for classifier skills (`soleur:go`, `ticket-triage`).
- **Vector:** a skill edit silently regresses routing/triage, mis-routing a real user request with no error surfaced. (Reflexively, this feature is the guard against exactly that vector.)
- **Threshold:** single-user incident.
