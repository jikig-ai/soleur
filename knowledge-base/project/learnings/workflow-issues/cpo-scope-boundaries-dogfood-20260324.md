---
module: System
date: 2026-03-24
problem_type: workflow_issue
component: tooling
symptoms:
  - "CPO agent flagged git-backed KB as local-only data loss risk without checking architecture"
  - "CPO asked implementation-choice questions (persistSession vs history injection) that belong to CTO"
  - "CPO flagged onboarding flow details as roadmap-level gaps when they are planning-level details"
  - "CPO dropped billing features from second review after overcorrected scope boundary rule"
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: medium
tags: [cpo, domain-leader, scope-boundaries, dogfooding, product-roadmap]
synced_to: [product-roadmap, cpo]
---

# Learning: CPO Agent Scope Boundaries for Roadmapping

## Problem

During the first dogfood of the `/soleur:product-roadmap` skill with domain leader review, the CPO agent made four categories of mistakes:

1. **False technical claims.** Flagged KB artifacts as "local-only data loss risk" without checking that workspaces are git-backed repos. Server death = `git clone`, not data loss.

2. **Implementation-choice questions.** Asked "persistSession vs history injection?" for multi-turn — a CTO decision during spec, not a CPO question during roadmapping.

3. **Planning details as roadmap gaps.** Flagged "onboarding should have N screens" and "onboarding flow specification missing" — these are planning-level details, not roadmap-level gaps.

4. **Overcorrected scope boundary.** After correction #1-3 were encoded as rules, the second CPO review dropped billing features entirely because the rule said "pre-beta product doesn't need subscription management." But the roadmap explicitly plans Stripe live mode in P4 — billing is a prerequisite, not premature scope.

## Solution

Three iterations of CPO agent (`agents/product/cpo.md`) and skill (`skills/product-roadmap/SKILL.md`) updates:

### Iteration 1: Scope boundaries added

- Distinguish roadmap gaps (missing phases/features) from planning details (UX flows, screen designs)
- Verify technical claims by checking actual codebase before asserting
- Flag the NEED, not the HOW — route implementation questions to CTO

### Iteration 2: Overcorrection fixed

- Distinguish **premature** features (no phase plans for them) from **prerequisite** features (a planned phase requires them)
- "If Phase N activates payments, billing infrastructure is a prerequisite in a prior phase"

### Iteration 3: Validated via re-run

Second CPO review correctly:

- Did not flag git-backed KB as data loss risk
- Did not ask implementation questions
- Did not flag planning-level details
- BUT still missed billing (overcorrection) — caught by founder, leading to iteration 2

## Key Insight

Agent scope boundaries need both positive constraints ("do X") and negative constraints ("don't do X"), but negative constraints must include exceptions for legitimate cases. A blanket "don't propose premature features" rule without a "unless the roadmap depends on them" exception causes the agent to drop valid requirements. The fix is to make the rule conditional: check whether later phases create dependencies on the proposed capability.

Dogfooding in iterative cycles (run agent → challenge mistakes → encode fix → re-run → verify) is the fastest path to reliable agent behavior. Three iterations in one session produced a dramatically better CPO.

## Session Errors

1. **Markdown lint failure (MD032) on first commit.** Lists not surrounded by blank lines in roadmap.md. **Recovery:** Added blank lines before lists. **Prevention:** Always add blank line before bullet lists in markdown files.

2. **Markdown lint failure (MD032) on second commit.** Same issue in SKILL.md scope boundaries section. **Recovery:** Same fix. **Prevention:** Same — this pattern recurred because the first fix wasn't generalized.

3. **AskUserQuestion schema error.** Passed `preview` field on a `multiSelect` question. The tool requires single-select for previews. **Recovery:** Retried without preview parameter. **Prevention:** Only use `preview` field when `multiSelect: false`.

4. **Milestone null assignment syntax.** `-f milestone=""` doesn't work with `gh api`. Needed `--input -` with JSON body `{"milestone": null}`. **Recovery:** Used JSON input. **Prevention:** Use `--input -` with JSON body for null/empty values in gh api PATCH calls.

## Tags

category: workflow-issues
module: System
