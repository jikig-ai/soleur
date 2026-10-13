---
title: "Plan-phase cost controls: cut unasked-for mechanisms before they are researched"
date: 2026-08-11
slug: plan-phase-cost-controls
branch: feat-one-shot-plan-phase-cost-controls
type: prose-only
domain: engineering
---

## Overview

The plan-checkpoint work merged 2026-08-10 as `c1145dc4d` (ADR-176) cost ~1.8M tokens and
surfaced twelve blocking defects behind a 285/285 green suite. Nine of the twelve did not
survive the CTO-ruled redesign: they were defects in machinery the originating issue never
asked for, and they vanished with the machinery. Nothing in the plan → review path asks
"which requirement does this mechanism satisfy, and does something already satisfy it?"
until post-implementation review, at roughly ten times the cost to act on.

This plan adds that question at the two cheapest points (plan time, plan-review time), stages
the review panel so design validity is settled before the full implementation panel runs, and
closes two measurement gaps the same session exposed.

Six bounded prose edits across four files. No new agents, no new required checks, no runtime
code.

## Files to Edit

| File | Change | Surface |
|---|---|---|
| `plugins/soleur/skills/plan/SKILL.md` | New `### 0.6b. Mechanism Minimality Gate` | short subsection |
| `plugins/soleur/skills/plan/SKILL.md` | New `### 0.6c. Value-Proposition Measurement` | short subsection |
| `plugins/soleur/skills/plan-review/SKILL.md` | Re-aim the simplicity reviewer's question | ≤3-line clarification |
| `plugins/soleur/skills/review/SKILL.md` | `design-risk` signal on the Change Classification Gate | one bullet + tree arm |
| `plugins/soleur/agents/engineering/review/test-design-reviewer.md` | Mutation-axis checklist | one new section |
| `plugins/soleur/skills/review/SKILL.md` | Instrument-check: extend the existing axes bullet | ≤3-line clarification |

## Placement decisions (the minimality gate, applied to this plan itself)

Two of the six items were checked against what the repo already has before being written —
which is the discipline item 1 exists to install:

- **Item 5 (mutation axes) — the task brief's premise was WRONG, and the item was cut down.** The
  brief asserted the corpus "already says 'audit the axes, not the count' but never enumerates
  them". It does enumerate them. `review/SKILL.md` on `origin/main` (the bullet beginning
  "Escalating a shape-matching guard to an EXECUTING one") names five of the seven inline —
  *dispatch, fixture shape, fixture direction, extractor uniqueness, harness `.trim()`* — carries
  **the same two measured survivors** (`TOKENS = []` → 26/0; deleting the executing `describe` →
  17/0, exit 0), cites the same learning file, and states the same meta-rule ("enumerate the AXES a
  battery edits, not the count it reports"); `set's cardinality` is named in a sibling bullet.
  A seven-row table in the agent file would therefore have been a second copy of live prose,
  numbers included — the restatement anti-pattern (`one-shot` token discipline #1) that item 1
  exists to prevent, i.e. the change failing its own gate. What survives is a **pointer**: the
  agent gets the axis vocabulary and the instrument rule, and is sent to `review/SKILL.md` for the
  substance. Verified real gap that justifies even the pointer: the agent file carried no standing
  mutation guidance at all (`grep -in 'mutat\|axes\|batter\|instrument'` on `origin/main` exits 1),
  and it is spawned by callers other than `review/SKILL.md`, which is the only thing that injects
  the axes at spawn time.
- **Item 6 (instrument check) → extend the existing bullet, do not add a new one.**
  `review/SKILL.md` already says "verify the INSTRUMENT before reading any verdict" and lists
  instrument rules. The three new failures from the cited session are new *instances* of that
  rule, not a new rule. They append to the bullet that owns it.

## Acceptance Criteria

- [ ] `### 0.6b.` and `### 0.6c.` exist in `plan/SKILL.md` between `### 0.6.` and `### 0.7.`
- [ ] `plan-skeleton-checkpoint.test.ts` stays 18/0 (the 0.6/0.7/1 ordering assertion still holds —
      `### 0.6b.` does not match `/^### 0\.6\./`)
- [ ] `plan-review/SKILL.md` asks the per-mechanism requirement question, not "is this plan good?"
- [ ] `review/SKILL.md` classification gate carries a `design-risk` signal that **orders** the
      panel and does not reduce it
- [ ] `test-design-reviewer.md` enumerates the seven mutation axes
- [ ] Every added claim is either measured in-session or cites the ADR-176-session evidence
- [ ] `components` 1297/0, `workflow-fidelity` 27/0, `plan-skeleton-checkpoint` 18/0, and the five
      other listed suites stay green; `lint-agents-rule-budget.py` does not regress past `[WARN]`
- [ ] Net issue flow ≤ 0 — no follow-ups filed for items 1–6

## Non-goals

- No `AGENTS.rules.md` edit. The corpus is at `[WARN] B_ALWAYS=44478 >= 44000` against a 46000
  ratchet, and under the `cq-agents-md-tier-gate` placement gate these insights are domain-scoped
  to the owning skills.
- No ADR. These are skill-prose changes, not architecture decisions.
- No edits to `one-shot/SKILL.md` or `deepen-plan/SKILL.md` (rewritten by the cited PR).
