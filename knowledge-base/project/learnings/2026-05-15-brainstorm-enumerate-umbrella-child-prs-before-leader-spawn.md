---
title: Brainstorm Phase 1.1 — enumerate umbrella child PRs before spawning leaders
date: 2026-05-15
problem_type: logic_error
component: brainstorm-skill
module: plugins/soleur/skills/brainstorm
severity: high
tags: [brainstorm, multi-stage-umbrella, leader-spawn, premise-verification, stale-context]
synced_to: [brainstorm]
---

# Brainstorm Phase 1.1 — enumerate umbrella child PRs before spawning leaders

## Problem

During a brainstorm to pick the next slice of GitHub umbrella issue #3244
(Command Center server-side agentic runtime), the CTO subagent (spawned at
Phase 0.5) returned a recommendation premised on stale state.

Concrete sequence:

1. Operator invoked `/soleur:go #3244` → routed to `/soleur:brainstorm`.
2. Phase 0.5 spawned CPO + CLO + CTO triad. CTO prompt instructed it to
   "verify the gate-zero premise" and read the umbrella spec at
   `knowledge-base/project/specs/feat-agent-runtime-platform/spec.md` and
   `tasks.md`.
3. CTO read `tasks.md` on main and reported: "Phase 1.1 through 1.4 of PR-B
   are already DONE in this worktree per `tasks.md:54-90` … 1.5.1 migrate the
   9 remaining user-scoped sites is the open frontier." Recommendation:
   "complete PR-B Phase 1.5 (the 9 remaining unchecked items)."
4. The brainstorm parent ran `gh pr list --state all --search
   "feat-agent-runtime-platform"` and surfaced **PR #3395 MERGED 2026-05-06**:
   `feat(pr-b): tenant isolation hardening + BYOK lease (#3244 §1.5–§1.7)`.
5. The CTO's recommendation, if accepted, would have re-implemented work
   already shipped to production. Truth: gate-zero is fully done; the
   actual next slice is PR-C (sibling-query migration in `ws-handler`,
   `conversations-tools`, `session-sync`).

## Root cause

The brainstorm skill's Phase 1.1 sharp-edges cover several adjacent
failure modes but **none cover the "multi-stage umbrella with merged sibling
PRs" case**:

- "Verifying referenced PR/issue state" (line 232 of SKILL.md) fires when
  the user input *names* an adjacent PR (`gh pr view <N>`). It does not
  enumerate child PRs that the user did not name.
- "Verifying cited flag/symbol against main" fires on symbols cited in the
  issue body, not on prior-stage completion.
- "Verifying 'approach 1 vs approach 2' claims" fires on architectural
  options, not on slice-by-slice umbrella progress.
- Phase 0.25 roadmap freshness check updates milestone statuses but does
  not look up which decomposition PRs of a specific umbrella have merged.

The root cause is structural: in a multi-stage decomposition (`PR-A`, `PR-B`,
`PR-C`, … or `Stage 1`, `Stage 2`, …), the **umbrella issue body is written
once at decomposition time and is not updated when sibling PRs merge**. Three
specific staleness traps compound:

1. The umbrella issue stays OPEN until the last sibling merges and someone
   manually closes it. `gh issue view <umbrella>` is uninformative for
   completion status.
2. `tasks.md` is owned by the in-flight PR — once that PR merges, the
   checked boxes are accurate but stale UNCHECKED items can be things
   already shipped under a different branch/PR.
3. The decomposed PRs typically share a common branch slug (e.g.,
   `feat-agent-runtime-platform`, with PR-A on `feat-agent-runtime-platform`,
   PR-B on `feat-agent-runtime-platform-pr-b`, etc.). Searching by that
   shared slug surfaces the entire decomposition history.

## Solution

Add a new sharp-edge bullet in `plugins/soleur/skills/brainstorm/SKILL.md`
Phase 1.1, after the existing "Verifying referenced PR/issue state" bullet,
that prescribes enumeration of umbrella child PRs **before** Phase 0.5
leader spawn:

> **Enumerating umbrella child PRs before spawning leaders.** When the
> feature description references a GitHub umbrella issue (`#N`) AND that
> issue is OPEN AND its body mentions sub-PRs by letter ("PR-A", "PR-B",
> "Stage 1", "Phase 1") OR enumerates increments/slices, run
> `gh pr list --state all --search "<branch-slug-from-issue-body>" --json
> number,state,title,mergedAt --limit 20` BEFORE spawning Phase 0.5
> leaders. The output is the source of truth for "what already shipped" —
> pass the merged-PRs list into every domain-leader prompt's context
> section so leader recommendations are not premised on stale
> decompositions. `tasks.md` / `spec.md` checklist files lag merged work
> (the in-flight PR may have closed boxes that never got back-checked into
> main, and umbrella issue bodies are written-once at decomposition time).
> Distinct from the adjacent `gh pr view <N>` check (single named PR) and
> the cited-flag-symbol check (named architectural mechanism) — this
> targets the multi-stage decomposition pattern specifically.

The bullet also references back to this learning so future readers can
trace the failure mode.

## Prevention

Three layers:

1. **Mechanical (skill instruction):** New Phase 1.1 sharp-edge bullet
   above. The check is `gh pr list --state all --search "<slug>" --limit
   20` — a single command that takes ~1 second and produces a list of
   merged + open PRs sharing the slug.
2. **Leader-prompt enrichment:** When the umbrella's child-PR list is
   surfaced, every Phase 0.5 leader prompt should include a "Sibling PRs
   already merged: #N (title), #M (title)" line in the context section.
   This eliminates the leader-side staleness even if the leader fails to
   run the check themselves.
3. **Reconciliation gate:** If a leader returns a recommendation that
   names work the merged-PR list shows as DONE, the brainstorm parent
   MUST reconcile explicitly (re-prompt the leader, or pivot to "audit
   residual risk" framing) before Phase 2 begins. This already applies
   from the existing "Reconciling fast-returning leader recommendations
   with later-arriving research findings" sharp-edge — the new bullet
   above strengthens its trigger.

## Session Errors

- **CTO subagent leader recommended finishing already-merged PR-B based on
  stale `tasks.md`.** Recovery: ran `gh pr list --state all --search
  "feat-agent-runtime-platform"` independently; surfaced PR #3395 MERGED
  2026-05-06; reframed brainstorm scope to PR-C (the next undone slice
  per the umbrella decomposition). Prevention: new Phase 1.1 sharp-edge
  (above) requires umbrella child PR enumeration before leader spawn, so
  every leader receives the merged-PR list as context.

## Related Learnings

- `2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md`
  — adjacent-PR verification (single named PR). This learning extends to
  multi-stage decompositions where the relevant PR is not named in the
  user input but is a sibling under the umbrella.
- `2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders.md`
  — cited-symbol completion check. This learning extends to umbrella-PR
  completion state, which is harder to grep because the "symbol" is the
  PR-letter, not a code identifier.
- `2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md`
  — leader/research reconciliation when findings contradict. The
  umbrella-PR enumeration check feeds this reconciliation by surfacing
  the contradicting evidence at Phase 1.1, before leaders return.
