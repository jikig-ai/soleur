---
title: A filter that runs after the single decision cannot protect the decision
date: 2026-10-28
category: logic-errors
tags: [compound-promote, create-arm, ledger, single-call, reachability]
---

# Learning: a filter that runs after the single decision cannot protect the decision

## Problem

The compound-promote create arm makes ONE model call over the offered patterns, then `checkCreate` applies the ledger (gate 5, `isHashSuppressed`). The model is never told which hashes the ledger owns, so it can pick an owned pattern: the gate refuses it, the run ends `no_action` / `other`, and the other eligible patterns were never evaluated. Live-fire 2026-10-28 (run `01M60XZRYG9ADVEWAY07HEQ5JK`, marker `create_arm=ran`, `create_outcome=no_action`, `create_no_action_reason=other`, `ledger_suppressed=1`, `patterns_open=7`): one owned pattern among seven ended the run with `create_pr=null`.

Same shape as the create-arm slot starvation fixed on 2026-10-27 (a cap reservation) ([a shared cap let the mandatory loop starve the gated arm](2026-10-27-a-shared-cap-let-the-mandatory-loop-starve-the-gated-arm.md)): the gate was correct, and the arm still could not reach its goal.

## Solution

Apply every known "owned" fact before the single decision, not after it. `proposeInner` now drops same-run hashes, then ledger-suppressed hashes (same `decideSuppression`, same memoized clock), before any read, request or model call. The post-call gate stays as the backstop for a model that names an unoffered pattern.

## Key Insight

A gate placed after a one-shot decision rejects, it does not redirect. When the decision is not repeatable, any fact known beforehand (ownership, suppression, caps) belongs in the input to the decision; the later gate is then a backstop, and the test for the filter must show a different candidate reaching the outcome, not only the owned one being refused.

## Session Errors

- Plan subagent's `decision-challenges.md` rows failed `technical-ruling-gate.sh` (bad Ruling shape). **Prevention:** write rulings as `Ruled by CTO agent, <date>: ...` or class `taste`.
- First handler tests assumed `page-two` was offerable; the edit loop owns it in the default fixture. **Prevention:** when asserting what is offered, derive it from the fixture's same-run hashes first.
