# Spec: Expand Plan Phase 2.5 Domain Detection

**Issue:** #753
**Branch:** feat-plan-domain-gates-753
**Brainstorm:** knowledge-base/project/brainstorms/2026-03-19-plan-domain-gates-brainstorm.md

## Problem Statement

The plan skill's Phase 2.5 only detects product/UX signals, missing legal and operations implications when engineering adds third-party services. Two failure modes: (1) users bypassing brainstorm by running `/plan` or `/one-shot` directly get no domain assessment at all, and (2) even when brainstorm runs domain assessments, findings aren't persisted and evaporate before plan Phase 2.5.

**Incident:** Web platform MVP (PR #637) added Resend and Supabase without updating legal documents or recording expenses, despite brainstorm having run domain assessments.

## Goals

- G1: Detect cross-domain implications (all 8 business domains) during plan generation
- G2: Persist brainstorm domain findings so they survive into plan execution
- G3: Block plan progression until relevant domain leaders complete their review
- G4: Reuse existing brainstorm-domain-config.md as single source of truth
- G5: Preserve the existing product/UX BLOCKING tier with specialized agent invocations

## Non-Goals

- New domain leaders or specialist agents (all 8 already exist)
- Keyword-based detection (LLM semantic assessment is mandatory per project convention)
- Changes to brainstorm Phase 0.5 routing logic (it already works)
- Automated remediation (domain leaders advise; implementation is separate)

## Functional Requirements

- **FR1:** Plan Phase 2.5 reads brainstorm-domain-config.md and assesses all 8 domains against plan content using each domain's Assessment Question
- **FR2:** For each relevant domain, spawn the domain leader as a blocking Task using the Task Prompt from brainstorm-domain-config.md
- **FR3:** If a brainstorm document exists with a structured `## Domain Assessments` section, carry forward those findings instead of re-running detection
- **FR4:** Product/UX domain retains its specialized BLOCKING/ADVISORY/NONE tier with spec-flow-analyzer, CPO, and ux-design-lead pipeline
- **FR5:** Output a `## Domain Review` section (replacing `## UX Review`) with per-domain subsections
- **FR6:** Brainstorm Phase 3.5 writes domain assessment results in a structured, parseable `## Domain Assessments` section

## Technical Requirements

- **TR1:** All changes are to SKILL.md files only — no new scripts, hooks, or code files (follows existing pattern)
- **TR2:** Detection uses LLM semantic assessment, not keyword matching
- **TR3:** `## UX Review` heading references in downstream consumers (work skill, plan-review agents, compound skill) must be migrated to `## Domain Review`
- **TR4:** Token budget impact must be measured — spawning up to 8 domain leader agents in one-shot pipelines (where plan runs inside a subagent) must not exceed context limits
- **TR5:** Cross-domain disambiguation must be updated bidirectionally per project convention

## Acceptance Criteria

- [ ] Plan Phase 2.5 detects legal implications when a plan introduces a new third-party service
- [ ] Plan Phase 2.5 detects operations implications when a plan introduces a new paid service
- [ ] Domain findings from brainstorm carry forward into plan without re-running
- [ ] Product/UX BLOCKING tier still triggers spec-flow-analyzer and ux-design-lead
- [ ] `## Domain Review` section appears in all generated plans
- [ ] No references to `## UX Review` remain in active skill files
- [ ] Plan proceeds only after all relevant domain leaders complete their review
