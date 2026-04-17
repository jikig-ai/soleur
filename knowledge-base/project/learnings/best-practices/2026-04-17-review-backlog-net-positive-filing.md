---
module: "review workflow / scope-out filing pipeline"
date: 2026-04-17
problem_type: workflow_gap
component: pipeline_skills
symptoms:
  - "3-PR window filed 6 scope-outs while closing 3 — net +3 backlog growth"
  - "Pre-existing debt re-surfaced at review-time as new scope-outs instead of triaged inline"
  - "`cross-cutting-refactor` criterion invoked whenever a fix would grow the PR by 2+ files"
  - "No programmatic cadence to drain the existing backlog"
root_cause: four_leaks_upstream_of_the_fix-inline_default
severity: medium
tags:
  - workflow
  - code-review
  - scope-out
  - backlog
  - skill-instruction
synced_to: []
---

# Review backlog grew faster than it drained because four upstream leaks bypassed the fix-inline default

## Problem

Rule `rf-review-finding-default-fix-inline` and `/ship` Phase 5.5's exit gate already forced PR authors to fix findings inline by default, with scope-outs allowed only under four named criteria. Despite that, in the 2026-04-17 three-PR window (#2463, #2477, #2486), the pipeline **filed 6 `deferred-scope-out` issues while closing 3** — a net **+3** on the Phase-3 code-review backlog. Target P1s shipped, but the queue grew faster than it drained.

| PR | Target | Scope-outs filed | Scope-outs closed |
|----|--------|------------------|-------------------|
| #2463 | KB streaming perf | 2 | 0 |
| #2477 | KB binary response (hash TOCTOU fix) | 3 | 2 |
| #2486 | KB workspace helper extraction | 1 | 3 (closed #2467 + #2468 + #2469) |
| **Total** | — | **6** | **3** (net **+3**) |

PR #2486 was the proof-of-concept success: one focused refactor closed three scope-outs at once. But it was hand-chosen. The other two PRs added to the backlog faster than #2486 drained it.

## Investigation / How It Surfaced

Running the 3-PR ledger after #2486 merged showed a net-positive backlog delta. Root-causing produced four distinct leaks, each operating upstream of the Phase 5.5 exit gate:

1. **Plan phase had no overlap check.** Planners wrote change-sets without querying whether any open `code-review` issue named files they were about to touch. Review then re-surfaced pre-existing scope-outs late — too late to fold in cleanly, producing either re-work, duplicate scope-outs, or silent closures.
2. **`cross-cutting-refactor` criterion was too loose.** The original wording ("fix requires touching files materially unrelated to the PR's core change") let any multi-file fix qualify. "Materially unrelated" is subjective and biases toward the author's preferred disposition.
3. **No provenance distinction in review output.** Every finding — whether the PR introduced it or it predated the PR — flowed through the same filter. Pre-existing debt got filed as open-ended scope-outs instead of either fixed inline (small, load-bearing) or closed wontfix (polish, noise).
4. **No drain cadence.** The fix-inline default prevented *new* scope-outs from being filed casually, but there was no equivalent pressure to *drain* the existing queue. The #2486 pattern (one PR closes 3+ scope-outs) worked only when a human manually noticed the opportunity.

All four leaks shared a failure mode: each happened BEFORE the Phase 5.5 exit gate saw the scope-out, so the gate had nothing to catch.

## Solution

Four skill-instruction-level changes, landed together so the effect is measurable:

1. **Plan Phase 1.7.5 — Code-Review Overlap Check.** Planners query open `code-review` issues, grep bodies for the files they will modify, and explicitly choose fold-in / acknowledge / defer for each overlap. Even on zero matches, a `## Open Code-Review Overlap` section with `None` is recorded so the next planner can see the check ran. Edit: `plugins/soleur/skills/plan/SKILL.md`.

2. **Tightened scope-out criteria + second-reviewer gate.** `cross-cutting-refactor` now requires ≥3 concrete files **unrelated** to the PR's core change (defined as files named in the PR's linked issue OR sharing the primary changed file's top-level directory). `contested-design` requires the review agent (not the author) to independently surface ≥2 tradeoff approaches. Every scope-out filing invokes `code-simplicity-reviewer` as a confirmation gate — if the second reviewer disagrees, the disposition flips to fix-inline. Edit: `plugins/soleur/skills/review/SKILL.md` Section 5.

3. **Provenance tagging in review synthesis.** Step 1 Synthesize now tags each finding `pr-introduced` or `pre-existing`. `pr-introduced` findings are fix-inline-only (no scope-out allowed, regardless of criterion). `pre-existing` findings triage into one of three explicit exits: fix inline, scope-out with re-evaluation deadline, or close wontfix. Open-ended scope-outs with no deadline are prohibited. The issue body template gains `Provenance:` and conditional `Re-eval by:` fields. Edits: `plugins/soleur/skills/review/SKILL.md`, `plugins/soleur/skills/review/references/review-todo-structure.md`.

4. **New `/soleur:cleanup-scope-outs` skill.** Queries open `deferred-scope-out` issues (default milestone `Post-MVP / Later`, where 15+ of 22 open issues lived at rollout time), groups by top-level directory via `scripts/group-by-area.sh`, picks a cluster meeting `min-cluster-size` (default 3), and delegates to `/soleur:one-shot` to produce one cleanup PR that closes all N issues. Exits cleanly with a "No cleanup cluster available" message when no area meets the floor. Reference implementation: PR #2486. New files: `plugins/soleur/skills/cleanup-scope-outs/SKILL.md`, `scripts/group-by-area.sh`, `plugins/soleur/test/cleanup-scope-outs.test.sh`.

Deliberately NOT changed:

- AGENTS.md rule `rf-review-finding-default-fix-inline` (immutable by `cq-rule-ids-are-immutable`; these improvements reinforce it via execution-level tightening).
- `/ship` Phase 5.5 exit gate (it already blocks merge on un-justified scope-outs; the improvements tighten the *filter feeding into it*, not the gate).
- Rolling cap / throttle (brainstorm proposal #4 — deferred per user direction until the four improvements above are measured in a 2-week window).

## Regression Signal — What to Watch

**Metric:** net `deferred-scope-out` filings per 3-PR window (filings minus closures). Target: ≤ 0.

**Collection command:**

```bash
# For a given window of PR numbers PR_START..PR_END:
for N in $(seq $PR_START $PR_END); do
  gh issue list --label deferred-scope-out --state all \
    --search "Ref #$N in:body" --json number,state \
    --jq 'length as $total | map(select(.state=="OPEN")) | length as $open |
          "\($total - ($total - $open)) opened"'
done
```

If net filings stay ≥ 0 across a 2-week measurement window after these improvements land, escalate to the deferred rolling-cap proposal (#4).

## Session Errors

Errors encountered during implementation that informed the final shape:

1. **Skill-description word-budget exceeded** — adding the new skill pushed cumulative `description:` word count from 1798 to 1831 (limit: 1800). **Recovery:** trimmed cleanup-scope-outs, ship, and social-distribute descriptions to land at 1791. **Prevention:** already covered by `plugins/soleur/AGENTS.md` Skill Compliance Checklist — run `bun test plugins/soleur/test/components.test.ts` before first commit when adding a skill.

2. **Helper over-engineered with multi-language serialization pipeline** — initial `group-by-area.sh` round-tripped TSV → awk → tr → python3 → JSON when a single pure-jq pipeline did the same job. **Recovery:** rewrote as one jq expression; dropped python3 dependency, ~110 LOC removed. **Prevention:** for data-reshape shell scripts, default to "one jq pipeline" and justify any second language. Added as Sharp Edge in `cleanup-scope-outs/SKILL.md`.

3. **jq `scan` with capturing-group regex returned only the capture** — `scan("[A-Za-z0-9_./\\-]+\\.(ts|tsx|...)\\b")` returned the extension, not the full path. jq's `scan` returns the captured group when one exists, the full match otherwise. **Recovery:** switched to non-capturing `(?:ts|tsx|...)`. **Prevention:** alternation inside `jq scan` regexes must always be non-capturing. Sharp Edge added.

4. **jq `as` binding with streaming source ran downstream once per stream item** — `(.[] | select(...)) as $above | [$above] as $meets | { ... }` emitted multiple top-level JSON values (one per matching cluster), which then broke `$(jq 'length' <<<"$PARTITIONED")` under `[[ -eq 0 ]]` with `[[: 1\n1: syntax error`. **Recovery:** collect first — `[ .[] | select(...) ] as $meets`. **Prevention:** when binding `as` against a multi-value source, wrap in `[ ... ]` to collect into an array before the downstream expression. Sharp Edge added.

5. **Second-reviewer gate lacked a mechanical output contract** — the first wording said "if code-simplicity-reviewer disagrees, flip to fix-inline" without specifying how the caller parses agree vs. disagree. Caught by the code-simplicity-reviewer itself reviewing its own gate. **Recovery:** added a `CONCUR` / `DISSENT: <reason>` first-line contract with fail-safe toward fix-inline on any other content. **Prevention:** confirmation gates that invoke sub-agents require a string-matchable first-line output contract, not free-form prose interpretation. Applied directly to `review/SKILL.md`.

## References

- **Parent brainstorm:** `knowledge-base/project/brainstorms/2026-04-15-review-workflow-hardening-brainstorm.md`
- **Plan:** `knowledge-base/project/plans/2026-04-17-feat-review-backlog-workflow-improvements-plan.md`
- **AGENTS.md rule preserved:** `rf-review-finding-default-fix-inline`
- **Related learning:** `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — justifies the second-reviewer confirmation gate.
- **Related rule:** `cq-rule-ids-are-immutable` — why the fix is execution-level, not a new AGENTS.md rule.
- **Reference PR (pattern):** #2486 — one PR closed #2467 + #2468 + #2469.
- **Related PRs (the leak window):** #2463, #2477, #2486.
