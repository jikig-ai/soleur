---
title: "fix: stop parking agent-owned pipeline steps on the operator"
date: 2026-11-03
slug: no-invented-operator-go-gates
branch: feat-one-shot-no-invented-operator-go-gates
type: fix
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# fix: stop parking agent-owned pipeline steps on the operator

## Overview

A finished `soleur:work` run closed with `Paused: waiting for your go to ... mark the PR ready`. Marking a PR ready, editing its body, filing a follow-up issue and running review/compound/ship are agent-owned steps. The Stop hook (`plugins/soleur/hooks/unkept-promise-hook.sh`) offered `Paused:` as an exit and its parked-deliverable arm only knew the objects merge, review and ship, so the label parked finished work. The operator's direction: the CTO or a team lead handles these autonomously.

## Premise Validation

The parked arm and its object set exist on main (`PARKED_RE`); its header records that a wider object set (decision, approval, go-ahead) blocked 13 of 15 rule-mandated gates. The fix therefore adds a CLOSED list of agent-owned acts only, and exempts the agent-spawn gate that the existing arm wrongly blocked.

## Property List and Cut List

P1: a `Paused:`/`Blocked:` line waiting on the operator's go for an agent-owned act is blocked. P2: rule-mandated gates (cost, agent spawn, outward sends, production-mutating) stay allowed. P3: the hook's own guidance says what a legitimate stop is. P4: work, ship and one-shot say the pipeline continues without asking. Cut: a rule in AGENTS.rules.md (the behaviour is owned by the hook and the pipeline skills; it does not bind on turns outside them).

## Files to Edit

- `plugins/soleur/hooks/unkept-promise-hook.sh`
- `plugins/soleur/test/unkept-promise-hook.test.sh`
- `plugins/soleur/skills/work/SKILL.md`, `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/one-shot/SKILL.md`

## Acceptance Criteria

- [x] AC1: "Paused: waiting for your go to push through the remaining items and mark the PR ready" and "need your go-ahead to edit the PR body and file the follow-up issue" are BLOCKED; the guidance text names the two legitimate stops.
- [x] AC2: "pending your go before I spawn the review agents" and "waiting on CI run 123; once green I mark the PR ready" stay ALLOWED.
- [x] AC3: mutation record in the suite: dropping the new arm reds two rows, dropping the spawn exemption reds one, a bare `review` widening is equivalent (recorded).
- [x] AC4: work Phase 4, ship Important Rules and the ship PR-body step, and the one-shot Step 8 note state that the pipeline continues without an operator go.
- [x] AC5: no skill `description:` line changed; no rule file touched.
