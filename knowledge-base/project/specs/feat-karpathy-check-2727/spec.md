---
title: karpathy-check (pre-merge simplicity review)
date: 2026-05-15
issue: 2727
parent_issue: 2718
branch: feat-karpathy-check-2727
pr: 3784
lane: single-domain
brand_survival_threshold: review-friction-only
status: spec-ready
---

# Spec — karpathy-check (pre-merge simplicity review)

## Problem Statement

Karpathy's 4 coding principles (Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution) translate cleanly into an audit checklist for LLM-authored PRs. Soleur's `code-simplicity-reviewer` already covers the simplicity + noise/redundancy half (Principles #2 and most of #3). Two angles remain uncovered as explicit pre-merge audits:

- **Hidden Assumptions** (Principle #1): unstated invariants, magic numbers without justification, silent reliance on callers/contexts not named in the diff.
- **Goal Verification** (Principle #4): does the diff actually satisfy the stated acceptance criteria in the PR body / linked issue / spec, and does it stop there?

Without these audits, over-engineering or partial implementations can ship under a passed-review banner, eroding trust in the review skill and forcing rework after merge.

## Goals

- G1: `code-simplicity-reviewer` produces a `### Hidden Assumptions` section listing each unstated invariant the diff relies on, with file:line evidence.
- G2: `code-simplicity-reviewer` produces a `### Goal Verification` section listing each acceptance-criterion sourced from the PR body, linked issue body, or `knowledge-base/project/specs/.../spec.md`, with a met / unmet / out-of-scope verdict per item.
- G3: The two new sections appear in the agent's output whenever it is invoked by `/soleur:review` on a class=code PR. No additional routing wiring required.
- G4: The 2026-05-03 prior-art learning is extended with an Audit Direction section so future contributors find one source of truth covering both the guidance-direction (no AGENTS.md rule) and the audit-direction (extended `code-simplicity-reviewer`) decisions.

## Non-Goals

- NG1: Standalone `karpathy-check` skill, slash command, or `/karpathy-check` entry point. Discoverability budget per `plugins/soleur/AGENTS.md` skill compliance — `/soleur:review` is the existing entry point.
- NG2: Deterministic Python complexity / diff / assumption / goal scripts (the `alirezarezvani/claude-skills` shape). LLM judgment is the right tier for p3-low scope.
- NG3: New `karpathy-reviewer` agent file. Renaming `code-simplicity-reviewer` is also out of scope (would orphan the orchestrator's class=code agent list and docs inventory).
- NG4: Adding the 4 Karpathy rules to AGENTS.md (already rejected by 2026-05-03 prior-art learning).
- NG5: Pre-commit hook integration. Review surfaces at PR time.

## Functional Requirements

- FR1: Edit `plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md` review-process list to include a "Surface Hidden Assumptions" bullet (parallel to existing "Challenge Abstractions"), with sub-bullets enumerating: unstated invariants, magic numbers without justification, implicit callsite contracts, hidden ordering / timing dependencies.
- FR2: Same file: add a "Verify Goals" bullet (parallel to existing "Apply YAGNI Rigorously"), with sub-bullets enumerating: read acceptance criteria from the PR body and any linked spec/issue; map each criterion to evidence in the diff; flag unmet criteria; flag added behavior not in the criteria as out-of-scope.
- FR3: Same file: append two output-format sections — `### Hidden Assumptions` and `### Goal Verification` — each structured with bullet items mirroring `### YAGNI Violations` (item / why it matters / suggested fix or verdict).
- FR4: Extend `knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md` with a `## Audit Direction (pre-merge check)` section that names the extended `code-simplicity-reviewer` as the implementation and links to this brainstorm + spec + issue #2727.

## Technical Requirements

- TR1: No changes to `plugins/soleur/skills/review/SKILL.md`. `code-simplicity-reviewer` is already on the class=code agent list.
- TR2: Agent frontmatter unchanged. `description:`, `model: inherit`, and filename remain as-is to satisfy `plugins/soleur/AGENTS.md` agent compliance checklist (no token-budget impact, no example-block additions).
- TR3: No changes to `plugins/soleur/README.md` component counts (no new component).
- TR4: Semver label: `semver:patch` (content addition to an existing agent body).
- TR5: No new dependencies, scripts, env vars, or hooks.

## Acceptance Criteria

- AC1: `code-simplicity-reviewer.md` contains the two new review-process bullets and the two new output-format sections (FR1, FR2, FR3).
- AC2: A representative invocation of `/soleur:review` against a synthetic PR with one unstated invariant and one unmet acceptance criterion surfaces both findings in the agent's output (manual smoke test recorded in PR body).
- AC3: The 2026-05-03 prior-art learning has the Audit Direction section (FR4) with working links.
- AC4: `grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` reports the same word count before/after (description unchanged per TR2).
- AC5: PR body includes a `## Changelog` section with `semver:patch`, references issue #2727 via `Closes #2727`.

## Out-of-Scope (parking lot)

- Deterministic complexity scoring / cyclomatic checks (defer; not requested).
- Goal Verification reading from external trackers (Linear, Jira) beyond issue body — wait for evidence of need.
- Pre-commit slash-command shortcut — wait for evidence the PR-time surface is insufficient.
