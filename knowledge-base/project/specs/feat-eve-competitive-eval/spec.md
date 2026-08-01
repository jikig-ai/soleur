---
title: Vercel Eve competitive evaluation (patterns-only posture)
lane: cross-domain
brand_survival_threshold: single-user incident
status: decided
brainstorm: knowledge-base/project/brainstorms/2026-07-17-vercel-eve-competitive-eval-brainstorm.md
draft_pr: 6640
---

# Spec: Eve competitive evaluation — decided posture

## Problem Statement

Operators and the market will encounter Vercel Eve (“Next.js for agents”). Without a recorded posture, Soleur risks (a) accidental substrate shopping, (b) category confusion with frameworks, or (c) under-using useful packaging patterns.

## Goals

1. Record strategic posture: **patterns-only + Tier 4 monitor; no Eve runtime adoption**.
2. Answer harness/Vercel/portability questions with evidence.
3. Name harvestable patterns and real Soleur gaps **without** Eve.
4. Keep legal envelope: no production founder data on Vercel Eve plane without deeper review.

## Non-Goals

- Implementing Eve integration
- Rewriting Soleur harness or Concierge
- Full competitive landscape rescan
- Public Soleur-vs-Eve landing page (unless demand later)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Brainstorm doc captures D1–D8 decisions and Domain Assessments from CPO/CTO/CLO/CMO + research |
| FR2 | Competitive intel action: Eve listed as **Tier 4** on next CI intake (or optional same-branch doc row) |
| FR3 | No product code depends on npm `eve` |
| FR4 | Any future spike must satisfy D5 hard constraints + CLO guardrails + gdpr-gate if regulated surfaces |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Cite existing primitives (`harness.ts`, sandbox, Inngest, eval-harness, `/go`) as substitutes for Eve-class surfaces |
| TR2 | Do not introduce Vercel as Soleur sub-processor without privacy doc + DPA package |
| TR3 | Pattern harvests land as docs/KB or native Soleur primitives — not Eve imports |

## Acceptance Criteria

- [x] Parallel domain leaders + research agents completed
- [x] Brainstorm document committed with User-Brand Impact + Domain Assessments
- [x] Epic #6641 created with gap table + links to product issues (#5862, #5863, #4672, #2004 residual agent-run visibility — not Workstream, #6006, #4674, #4673)
- [ ] Operator confirms CI Tier 4 action (now vs next intake)
- [ ] Child issues under #6641 executed per sequencing (separate work)

## Domain Review (carry-forward)

| Domain | Verdict |
|--------|---------|
| Product | Steal patterns; no substrate |
| Engineering | Patterns-only; rewrite cost if deep integrate |
| Legal | Patterns-only preferred; runtime = deeper review |
| Marketing | Monitor Tier 4; no co-brand |
