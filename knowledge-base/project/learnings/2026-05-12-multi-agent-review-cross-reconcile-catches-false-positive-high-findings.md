---
title: Multi-agent review cross-reconcile catches false-positive HIGH findings
category: review-workflow
date: 2026-05-12
pr: "#3670"
issues: ["#3639", "#3640", "#3641", "#3642"]
tags: [review, multi-agent, refactor-only, false-positive, cross-reconcile]
related:
  - 2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
  - 2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md
  - 2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md
  - 2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md
---

# Multi-agent review cross-reconcile catches false-positive HIGH findings

## Problem

A 10-agent review of PR #3670 (cc-dispatcher cluster drain — refactor-only,
closing #3639/3640/3641/3642) produced 14 findings across 8 always-on agents +
2 conditional agents. One agent (`code-quality-analyst`) rated a finding HIGH:

> "`mirrorWithDebounce` sweep cutoff changed from `2 * MIRROR_DEBOUNCE_MS` to
> `> ttlMs`. **This can double Sentry event count for slow-recurring fallbacks**
> (every 6-9 min). Refactor-only invariant violated. Recommend: parameterize
> per-instance with a separate `staleTtlMs` constructor arg."

If accepted at face value, the proposed fix would have added a per-instance
`staleTtlMs` parameter to `TtlDedupMap` — re-introducing the asymmetry the
class extraction was designed to eliminate (the plan's #3639 F3 had
explicitly unified the two cache shapes).

## Solution

**Cross-reconcile against the other agents that touched the same code path
before applying any HIGH finding.** Three independent signals contradicted
the HIGH rating:

1. **`performance-oracle`** traced the dedup flow precisely:

   > "An entry older than `ttlMs` can no longer suppress anything (the TTL
   > window has closed). Keeping it for another `ttlMs` was conservative
   > slack with no protective effect."

   The sweep is a **memory-reclamation optimization**, not a correctness
   primitive. Dedup correctness lives in `tryClaim`'s `now - last < ttlMs`
   check, which fires identically regardless of whether the key was swept —
   if the key is absent (swept), `tryClaim` returns `true` (new claim);
   if the key is present (not swept) but `last < ttlMs` ago, `tryClaim`
   also returns `true`. Same outcome either way.

2. **`git-history-analyzer`** read the Phase 3 commit diff and confirmed the
   change was a **documented intentional unification**:

   > "Pre-refactor `mirrorWithDebounce` swept at `2 * MIRROR_DEBOUNCE_MS`;
   > `mirrorP0Deduped` swept at `> ttlMs`. The new class collapses both to
   > the tighter cutoff. The drift note in the commit body acknowledges this."

3. **Direct dedup-logic analysis** confirmed the operator-visible Sentry
   stream is unchanged: a 7-min-recurring key dedupes within the 5-min TTL
   window for the first 5 min, then re-claims at minute 5 regardless of
   whether the sweep ran at minute 5 or minute 10.

The HIGH finding was a false positive. The single inline fix the session
**did** apply (a 5-LoC comment correction to remove a stale `staleTtlMs`
reference) had already been applied by `git-history-analyzer` during its
own pass — no per-instance parameter needed.

## Key Insight

**A single review agent's HIGH severity is a hypothesis, not a verdict.**
The cost-of-filing gate (`≤30 LoC ≤2 files = fix inline`) and the
provenance-default-fix-inline rule push toward action, which means a
false-positive HIGH carries real cost: it can trigger a "fix" that
re-introduces the complexity the PR was designed to eliminate.

**Reconcile triad before applying any HIGH or P1:**

1. **Find at least one orthogonal agent** that touched the same code path.
   In this case: code-quality (semantic), performance-oracle (runtime
   profile), git-history-analyzer (commit-history context).
2. **Trace the claimed harm to a concrete user-visible or operator-visible
   outcome.** "Could double Sentry event count" is a hypothesis;
   "operator at 7-min recurring fallback sees N events instead of N/2 in
   the last hour" is a falsifiable claim. The latter is what the dedup
   trace falsifies.
3. **If two-of-three agree the finding is structurally wrong, downgrade
   to advisory or skip.** Single-agent HIGH against two-of-three concur
   is the most common false-positive pattern in multi-agent review.

This generalizes the existing learning `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`
(multi-agent review catches bugs single tests miss) with the inverse:
**multi-agent review also catches false positives that single agents emit
with high confidence.** The same multiplicity that surfaces the truth
about correctness surfaces the truth about non-issues.

## Where this matters most

- **Performance and memory analyses.** Sweep/eviction/cache-policy
  changes are particularly prone to false-positive HIGH from
  semantic-quality agents that don't trace the time-based math.
  `performance-oracle` is the orthogonal check.
- **Type-widening cross-consumer impact.** A code-quality agent may flag
  the widening as P1 risk; `data-integrity-guardian` + `tsc --noEmit` are
  the orthogonal checks.
- **Sentry / log-volume claims.** Always trace the dedup or sampling
  logic before accepting "this will N-x event count" claims. The
  orthogonal check is the actual rate-limit / dedup primitive's input
  contract.

## Session Errors

**Initial grep CWD slip — Bash tool ran from bare repo root.** During
Phase 1 baseline verification, `grep -nE "setTimeout|expect.poll|await
new Promise" apps/web-platform/test/cc-dispatcher.test.ts` returned `No
such file or directory` because the Bash tool doesn't persist CWD across
calls; the prior worktree `cd` from a different tool call had been
discarded. Recovery: prefix the next grep with explicit `cd
/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-drain-pr-a2-review-3639-3642
&& ...`. Prevention: this is already covered by the Bash-CWD-non-persistent
constraint documented in AGENTS.md and the work skill's CWD-discipline
guidance. The parent orchestrator should follow the same `cd && cmd`
pattern subagent prompts already enforce. The work subagent's prompt
included this rule explicitly — the slip was in the parent context, not
the delegated work. No workflow change needed; the rule is in force.

## Workflow proposal

Add a one-line bullet to `plugins/soleur/skills/review/SKILL.md`'s
"Sharp Edges: Review Agent Limitations" section:

> When a single agent rates a finding P1/HIGH but no orthogonal agent
> independently surfaces the same harm, downgrade to advisory or skip.
> Single-agent HIGH against two-or-more silent or contradicting agents
> is the modal false-positive pattern. Cross-reconcile triad: a
> semantic-quality agent (code-quality, pattern-recognition), an orthogonal
> runtime agent (performance-oracle for cache/sweep/eviction;
> data-integrity-guardian for type widening), and `git-history-analyzer`
> for documented-intent context. Two-of-three concur on "non-issue" =
> skip with one-line disposition.
