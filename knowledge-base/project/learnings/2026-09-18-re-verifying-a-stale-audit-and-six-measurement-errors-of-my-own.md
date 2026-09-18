---
title: Re-verifying a stale audit — and six measurement errors of my own
date: 2026-09-18
category: workflow-patterns
module: compound, brainstorm, rule-metrics
issue: 8302
pr: 8301
tags: [measurement, audit-verification, subagent-claims, rule-metrics, stale-artifacts]
---

# Learning: Re-verifying a stale audit, and six measurement errors of my own

## Problem

A 36-day-old external audit ("States Without Gates") was handed in as the basis
for a workflow-FSM remediation plan. Its structural findings were sound. Its
numbers and three of its framings were not — and every wrong framing pointed
work at something that was already done, already fixed, or already decided.

Separately, and more usefully: **six of my own measurements during the
re-verification were wrong**, in six distinct ways. That is the reusable part.

## Solution

### Re-derive a stale artifact's numbers — and check whether its defects were FIXED

The generalizable move is not "numbers drift." It is that **a fix lands silently
and the audit never updates**. Three framings inverted:

1. **"The measurement fix is the cheapest high-yield work."** It had been
   designed five months earlier (#2866 / PR #2876) and its hook arm shipped.
   It stalled at 4 of 10 planned skills sourcing `.claude/hooks/lib/incidents.sh`.
   The real question was *why it stalled*, not how to design it. Found by a
   name-keyed sweep of `knowledge-base/project/brainstorms/archive/`.
2. **"Aggregation reads a single per-checkout fragment."** Fixed on 2026-09-11
   by PR #8029 (`65d6a1584`) — a month *after* the audit was written.
3. **"Does the gate block or only record?"** framed as an open operator
   preference. ADR-070's two-tier rule already settles it: deny-by-default is
   permitted only on re-fetching layers, and the `Skill` tool does not re-fetch.

Concrete probes: `git log -S '<the fix string>' -- <file>` dates the fix;
`gh issue view <N> --json state,closedByPullRequestsReferences` shows whether
the cited work closed; an archive sweep finds the prior design.

### A half-fixed bug reads as fixed — measure the residual

PR #8029 collects exactly **two** incident-log roots (repo root + the shared
checkout beside `git rev-parse --git-common-dir`). It does not enumerate sibling
worktrees. Verifying a fix *exists* is not verifying it is *complete*. Measured
live: 23,882 rows readable from a given worktree, **11,346 stranded across 34
sibling roots — 32% of a 35,228-row corpus**.

### A measurement instrument can be mute at layers that each look like the whole problem

Three independent layers here, and fixing any one alone leaves it mute:
**emission** (79 of 98 rules have no call site), **collection** (32% unread),
and **cadence** — `.github/workflows/rule-metrics-aggregate.yml` is
`workflow_dispatch` only; the weekly schedule was *removed* under #6042 because
fresh CI checkouts saw zero incidents. The cadence layer was invisible to the
audit and surfaced only from tracing the pipeline end to end.

## Key Insight

**Every one of my six errors was a case of the measurement's *scope* silently
differing from the claim's scope.** Not arithmetic — scope.

| # | Error | Scope mismatch | Correct method |
|---|---|---|---|
| 1 | `skill_to_phase` membership probed with bare skill names | keys are namespaced `soleur:<skill>` | dump the keys before concluding absence |
| 2 | Phantom duplicate `Phase 4` in `work` | regex stripped the Markdown `#` depth prefix, collapsing `### Phase 4` and `#### Phase 4 Entry-Guard` | preserve depth; it is load-bearing in Markdown |
| 3 | `emit_incident` coverage counted as 82 | matched files that *contained* the string anywhere, not call sites | match the actual emit expression |
| 4 | Sub-phases counted as 53 | pattern matched only `## Phase N`, so `plan` scored 0 | there was no single grammar to count with — that was the real finding |
| 5 | Tier tags undercounted by 1 | `grep -c` counts lines, not occurrences | `grep -o … \| wc -l` |
| 6 | Fragmentation residual reported as 47% | counted live `.jsonl` only, ignoring rotated `.rule-incidents-*.jsonl.gz` archives that hold most of the history | include archives; cross-validate against the consumer's own reported total |

Error 6 is the sharpest, because it was caught only by **cross-validating against
the tool that consumes the data**: the aggregator reported 23,805 kept + 77
dropped = 23,882, which matched a per-root recount exactly and exposed the
original denominator as wrong. *When a consumer of the data reports its own
total, reconcile against it.*

### Adopt a subagent's correction only after re-deriving it

The "counts are claims" rule fired in **both directions in one session**. A CTO
agent disputed four of my counts. Three were right and I adopted them. The
fourth — "12 emit sites, not 19" — was itself wrong; re-derivation confirmed 19,
because the 11 SKILL.md-body emitters turned out to be a strict *subset* of the
19 executable ones rather than additive. A correction is a claim with the same
evidentiary status as the thing it corrects.

### A premise handed to a subagent can be wrong in the safe-looking direction

I told the CLO the rule-fire event was "a bare rule-id + counter." It is not:
`emit_incident()` writes `command_snippet` — the triggering Bash command
verbatim, 1024 chars — which ADR-091 notes stores absolute paths, git/gh
identity and PR-body text. The CLO caught it. Had it accepted my framing, it
would have cleared a 5× multiplication of that content without noticing the
category. **Verify the premises you hand down, not just the answers you get back.**

## Prevention

- **`wg-every-session-error-must-produce-either`:** before any count bounds a
  decision, state the population it is over, and re-derive two ways where a
  consumer publishes its own total.
- Re-derive a stale artifact's numbers **and** probe whether each cited defect
  was fixed in the interval (`git log -S`, `gh pr view --json mergedAt`).
- Treat a subagent's *correction* with the same scrutiny as its original claim.
- When comparing Markdown heading identifiers, never strip the `#` depth.
- When counting log rows, include rotated/compressed archives.

## Session Errors

1. **Namespaced-key false negative.** Probed `.claude/phase-surface-map.json`
   with bare skill names; keys are `soleur:<skill>`, so every lookup reported
   "NO PHASE". — *Recovery:* dumped the keys. — *Prevention:* enumerate keys
   before asserting absence.
2. **Phantom duplicate heading.** Depth-stripping regex invented a duplicate
   `Phase 4` in `work`. — *Recovery:* refuted by the CTO agent, verified by
   `grep -oE '^#+ Phase [0-9.]+' | sort | uniq -d` returning empty. —
   *Prevention:* preserve heading depth.
3. **Co-occurrence mistaken for a call site.** `emit_incident` coverage read as
   82 instead of 19. — *Recovery:* matched the emit expression itself. —
   *Prevention:* a call site is a syntax match, not a file-contains match.
4. **Single-grammar assumption.** Sub-phase count of 53 from a pattern matching
   one of 4+ grammars. — *Recovery:* enumerated grammars per skill. —
   *Prevention:* confirm a uniform convention exists before counting instances.
5. **`grep -c` vs `grep -o | wc -l`.** Tier tags undercounted where one line
   carried two. — *Prevention:* count occurrences, not lines.
6. **Wrong denominator on the fragmentation residual.** Reported 47% from live
   `.jsonl` only; the true figure is 32% once rotated `.gz` archives are
   included. — *Recovery:* cross-validated against the aggregator's own reported
   total. — *Prevention:* include archives; reconcile against the consumer.
7. **Unverified premise handed to a domain leader.** Described the rule-fire
   event to the CLO as a bare id + counter; it carries `command_snippet`. —
   *Recovery:* the CLO read the source and corrected it. — *Prevention:* read
   the emitter before characterising its output in a subagent prompt.

## Related

- `knowledge-base/project/learnings/2026-07-22-rule-metrics-denominator-investigation.md` (#6794) — do not prune on `rules_unused_over_8w`
- `knowledge-base/project/learnings/2026-09-10-three-measurement-instruments-and-two-were-wrong-before-they-were-right.md`
- `knowledge-base/project/learnings/2026-07-27-instrument-misreports-own-coverage-and-subagent-counts-are-claims.md`
- ADR-070 (two-tier fail-open), ADR-086 (PostToolUse mandate), ADR-116 (advisory→blocking never promoted), ADR-131 (gate moratorium), ADR-151 (unconditional rule corpus), ADR-091 (local-producer rule metrics)
- Brainstorm: `knowledge-base/project/brainstorms/2026-09-18-workflow-fsm-remediation-brainstorm.md`
