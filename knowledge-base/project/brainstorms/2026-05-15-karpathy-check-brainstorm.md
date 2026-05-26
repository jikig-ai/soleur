---
title: karpathy-check (pre-merge simplicity review)
date: 2026-05-15
issue: 2727
parent_issue: 2718
branch: feat-karpathy-check-2727
pr: 3784
lane: single-domain
brand_survival_threshold: review-friction-only
status: decided
---

# karpathy-check — Brainstorm

## What We're Building

Extend `plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md` with two new review sections covering the angles of Karpathy's 4 principles that are NOT already in the agent body:

1. **Hidden Assumptions** — surface unstated invariants, magic numbers without justification, callers/contexts the change silently relies on.
2. **Goal Verification** — check the diff against the spec/issue's stated acceptance criteria; flag unmet goals and out-of-scope additions.

No new skill, agent, command, or script. Integration with `/soleur:review` is automatic: `code-simplicity-reviewer` is already a member of the 8-agent code-class path.

## Why This Approach

**Prior-art constraint.** `knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md` documented that the 4 Karpathy rules overlap heavily with the Claude Code system prompt (Simplicity First, Surgical Changes) and AGENTS.md `cm-challenge-reasoning-instead-of` (Think Before Coding / surface tradeoffs). Adding them verbatim was rejected as a byte-budget loss with no behavior change.

**The audit direction is narrower than the guidance direction.** That learning addressed "should the LLM be told to follow these rules?" (already answered yes by system prompt). This issue asks the orthogonal question: "should the LLM also CHECK code against these rules pre-merge?" The current `code-simplicity-reviewer` covers complexity (Principle #2) and noise/redundancy (Principle #3 most cases). The genuinely missing angles are #1 (hidden assumptions) and #4 (goal verification).

**YAGNI tier sizing.** Issue is `priority/p3-low`. A single-file edit that adds two sections to an existing agent is the proportionate response. A new skill, slash-command, or script bundle would burn discoverability budget and component count for two checklist items.

**Reference (`alirezarezvani/claude-skills/commands/karpathy-check.md`) is not directly portable.** Their implementation is a 4-script + 1-agent system under `engineering/karpathy-coder/` with separate Python checkers per principle. That fits a portable skill library; Soleur's plugin already routes simplicity-class review through one agent invoked by one orchestrator skill. Mirroring the upstream structure would duplicate infrastructure, not capability.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Integration shape | Extend existing agent | Smallest YAGNI delta; inherits `/soleur:review` 8-agent routing for free |
| New skill / slash command | **No** | Discoverability budget per `plugins/soleur/AGENTS.md` skill compliance; entry point is already `/soleur:review` |
| New scripts (complexity / diff / goal verifier) | **No** | LLM judgment via the agent body is the right tier for p3-low scope; scripts add maintenance debt |
| Where the goal-verification check reads from | The PR body, linked issue body, and (if present) `knowledge-base/project/specs/feat-<name>/spec.md` Acceptance Criteria | These are the existing acceptance-criteria sources in the Soleur workflow; no new metadata required |
| Audit-direction rationale lives in | Existing prior-art learning, extended with an "audit direction" section | One learning file, one source of truth; closes the loop on both directions |
| Output format | Two new sections appended to `code-simplicity-reviewer`'s existing markdown output (`### Hidden Assumptions`, `### Goal Verification`) | Reviewers already parse this format; no consumer changes |

## Open Questions

None blocking. Resolution will surface in implementation.

## Non-Goals

- Standalone `karpathy-check` skill, slash command, or `/karpathy-check` entry point.
- Deterministic Python complexity / diff / assumption / goal scripts.
- New `karpathy-reviewer` agent file.
- Adding the 4 Karpathy rules to AGENTS.md (covered by 2026-05-03 prior-art learning).
- Pre-commit hook integration (out of scope; review surfaces at PR time, not pre-commit).
- Renaming `code-simplicity-reviewer` to `karpathy-reviewer` (rename would orphan `/soleur:review`'s class=code agent list and the docs/_data inventory; not worth the churn for a content addition).

## Domain Assessments

**Assessed:** Engineering (single-domain lane per Phase 0.4 inference).

### Engineering

**Summary:** Single-file edit to an existing review agent. No new components, no new routing, no plugin loader changes. Aligns with `plugins/soleur/AGENTS.md` agent compliance checklist (description stays unchanged; model remains `inherit`; no token-budget impact). Inherits `/soleur:review` 8-agent code-class routing for free.

## Implementation Sketch (for plan skill)

1. Edit `plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md`:
   - Add review-process bullet "Surface Hidden Assumptions" (parallel to existing "Challenge Abstractions").
   - Add review-process bullet "Verify Goals" (parallel to existing "Apply YAGNI Rigorously").
   - Add two output-format sections: `### Hidden Assumptions` and `### Goal Verification` (each with bullet structure mirroring `### YAGNI Violations`).
2. Extend `knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md` with a `## Audit Direction (pre-merge check)` section pointing to the extended `code-simplicity-reviewer` as the implementation, citing this brainstorm and issue.
3. No changes to `/soleur:review` (the agent is already in its class=code list).
4. No changes to `plugins/soleur/README.md` counts (no new component).
5. No semver bump label needed (content-only change to an existing agent body — `semver:patch`).

## References

- Parent issue: #2718 (Claude-skills competitive audit — action plan)
- This issue: #2727
- Source pattern (MIT): `alirezarezvani/claude-skills/commands/karpathy-check.md`
- Existing prior-art learning: `knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md`
- Target agent: `plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md`
- Orchestrator (already routes this agent): `plugins/soleur/skills/review/SKILL.md`
- AGENTS.md backdrop: `cm-challenge-reasoning-instead-of`, `cq-write-failing-tests-before`, `cq-agents-md-tier-gate`
