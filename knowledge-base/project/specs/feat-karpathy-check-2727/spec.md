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

- FR1: Edit existing review-process bullet `4. Challenge Abstractions` in `plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md` to add two sub-bullets covering "unstated invariants the diff silently relies on" and "magic numbers / implicit callsite contracts without inline justification." (Hidden Assumptions is an extension of the existing Challenge Abstractions axis — no separate process bullet needed.)
- FR2: Same file: add one new review-process bullet `7. Verify Stated Goals Against Diff` (matching the format `N. **Name**:` of existing bullets — see line 11). Sub-bullets MUST cover: (a) read acceptance criteria from PR body + linked issue body + any linked `spec.md`; (b) map each criterion to evidence in the diff; (c) flag unmet criteria; (d) flag added behavior not in the criteria as out-of-scope; (e) **fallback for off-diff invocations**: render `### Hidden Assumptions` and `### Goal Verification` as `_N/A — no diff in scope._` when invoked by CONCUR-gate, `/soleur:plan-review`, `atdd-developer`, or `compound`.
- FR3: Same file: append two output-format sections — `### Hidden Assumptions` and `### Goal Verification` — between `### YAGNI Violations` and `### Final Assessment`. Both sections MUST end with the instruction "If no findings, render `_None._`" so reviewers can distinguish audit-ran-no-findings from audit-skipped.
- FR4: Extend `knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md` with a `## Audit Direction (pre-merge check)` section between `## When This Note Becomes Load-Bearing` and `## Related`. The section names the extended `code-simplicity-reviewer` as the implementation and links to this brainstorm, spec, plan, the audit-vs-guidance learning, and issue #2727.

## Technical Requirements

- TR1: No changes to `plugins/soleur/skills/review/SKILL.md`. The agent is already routed by section 4 (line 380-382), CONCUR-gate (line 502-524), `/soleur:plan-review` 3-agent panel, `/soleur:work` final validation, and opportunistic spawns in `atdd-developer` + `compound`. Extending the agent body propagates to every surface.
- TR2: Agent frontmatter unchanged. `description:`, `model: inherit`, and filename remain as-is to satisfy `plugins/soleur/AGENTS.md` agent compliance checklist (no token-budget impact, no example-block additions).
- TR3: No changes to `plugins/soleur/README.md` component counts (no new component).
- TR4: Semver label: `semver:patch` (content addition to an existing agent body).
- TR5: No new dependencies, scripts, env vars, or hooks.

## Acceptance Criteria

- AC1: `code-simplicity-reviewer.md` contains the extended bullet `4. Challenge Abstractions` (FR1), the new bullet `7. Verify Stated Goals Against Diff` matching the canonical `N. **Name**:` format (FR2), and both output-format sections (FR3).
- AC2: The fallback instruction text `N/A — no diff in scope` appears in the agent body bullet 7's sub-bullets (FR2.e). Grep: `grep -c 'N/A — no diff in scope' plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md` returns `1`.
- AC3: The 2026-05-03 prior-art learning has the Audit Direction section (FR4) with working links.
- AC4: `shopt -s globstar; grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` reports the same word count before/after (description unchanged per TR2).
- AC5: PR body includes a `## Changelog` section with `semver:patch`, references issue #2727 via `Closes #2727`, and surfaces the AC1–AC4 grep commands in a manual-verification block.

## Out-of-Scope (parking lot)

- Deterministic complexity scoring / cyclomatic checks (defer; not requested).
- Goal Verification reading from external trackers (Linear, Jira) beyond issue body — wait for evidence of need.
- Pre-commit slash-command shortcut — wait for evidence the PR-time surface is insufficient.
