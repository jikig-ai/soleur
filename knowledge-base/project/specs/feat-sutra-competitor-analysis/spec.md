---
title: Sutra competitor entry and Soleur improvement backlog
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-06-sutra-competitor-analysis-brainstorm.md
---

# Spec: Sutra competitor entry and improvement backlog

## Problem Statement

Sutra (`sankalpasawa/sutra`) overlaps Soleur's "AI departments from one brief" thesis and is absent from the competitor list. Its product and site also show UX and mechanics Soleur lacks.

## Goals

- Record Sutra as a Tier 3 internal-only watch entry with sourced, tagged claims.
- Turn the comparison into a ranked improvement backlog and file one issue per top item.

## Non-Goals

- No public comparison page and no change to soleur.ai in this PR.
- No copying of Sutra text, code or structure; no `NOTICE` entry.
- No refresh of `business-validation.md`.
- No adoption of the subscription-billing pattern.

## Functional Requirements

- FR1: `competitive-intelligence.md` has a Tier 3 row, a New Entrants entry and a targeted-addition note for Sutra (done).
- FR2: Every Sutra claim is tagged observed or inferred and carries the retrieval date and repo HEAD SHA.
- FR3: One GitHub issue per top backlog item (demo, acceptance check, "runs on your Claude plan" copy, visible privacy line) plus one to verify live Anthropic terms.

## Technical Requirements

- TR1: `last_reviewed` stays unchanged so the full-scan clock is not reset.
- TR2: Issues satisfy the issue-filing gate and use the roadmap milestone where one applies.
