---
title: one-shot collision gate must probe MERGED linked PRs, not just OPEN
date: 2026-05-29
category: workflow-patterns
tags: [one-shot, collision-gate, github, dispatch-waste, flagsmith-fallback]
---

# one-shot collision gate must probe MERGED linked PRs, not just OPEN

## Context

`/soleur:go #4232` routed to `/soleur:one-shot` to "implement PR-B for byok_delegations."
The task argument was stale: it described PR-B as unstarted and cited "migration 062 / PR #4290."
In reality PR-B had **already merged** via **PR #4508** (2026-05-26) under branch
`feat-one-shot-4232-byok-delegations-pr-b`. Issue #4232 stayed OPEN only for two
operator-gated residuals (Harry signs the Delegation Consent Side Letter; flip
`byok-delegations` ON for jikigai), which are not codeable.

The one-shot Step 0a.5 collision gate did NOT catch this. It created a worktree + empty
draft PR before the planning subagent's Research Reconciliation gate finally surfaced the
merged state and halted. A full dispatch's setup cost was spent on already-merged work —
the exact failure class the gate exists to prevent (cf. the #3684 → #3699 incident).

## Why the gate missed it

Step 0a.5's OPEN-issue branch only did `gh pr list --search "linked:issue #N" --state open`.
Two blind spots compounded:

1. **State filter.** A MERGED PR linked to a still-OPEN issue is invisible to `--state open`.
   An issue legitimately stays open after its implementing PR merges when residual
   (often operator-only) follow-up remains — so "open issue + merged linked PR" is a COMMON,
   high-signal state, not an edge case.
2. **Branch-name assumption.** The earlier manual `--head feat-byok-delegations-4232` probe
   also missed it because PR-B merged under a *differently named* branch
   (`feat-one-shot-4232-byok-delegations-pr-b`). Squash-merge had already deleted that branch.
   **Never rely on a `--head <branch>` name match to detect collisions** — the merging branch
   is frequently renamed (`feat-one-shot-<id>-*`) or already gone.

## Fix

Step 0a.5 item 3 now runs `--state all` (no state filter) and partitions:
- **MERGED linked PR** → near-certain "already done" signal; interactive mode ABORTS by
  default (operator verifies residual scope before spending a dispatch); headless logs a
  prominent warning.
- **OPEN linked PR** → parallel-session collision; existing continue/abort behavior.

## Bonus finding (flag fallback masking provisioning gap)

While preparing the #4232 flag flip, a `flag-set-role byok-delegations prd on --dry-run`
returned `feature 'byok-delegations' not found in Flagsmith`. The flag was declared in
`RUNTIME_FLAGS` (server.ts) with a Doppler mirror (`FLAG_BYOK_DELEGATIONS=0`) but the
**Flagsmith feature was never created**. The ADR-038 fallback contract (Flagsmith absent →
Doppler env fallback) silently kept the feature OFF and correct, so the missing provisioning
was invisible until a flip was attempted. **Lesson: code-side RUNTIME_FLAGS registration +
Doppler mirror does NOT imply the Flagsmith feature exists.** Verify with a `flag-set-role
--dry-run` before assuming a one-step flip; a brand-new feature needs `soleur:flag-create`
first.

## Takeaway

When checking whether an OPEN issue is already resolved, probe linked PRs with NO state
filter and treat a MERGED match as "stop and verify." Do not trust branch-name matching to
find the resolving PR.
