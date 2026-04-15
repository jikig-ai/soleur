---
title: Review Workflow Hardening — Fix-Inline Discipline
date: 2026-04-15
topic: review-workflow-hardening
status: brainstorm
---

# Review Workflow Hardening — Fix-Inline Discipline

## Problem

In the past 3 days (2026-04-13 through 2026-04-15), ~70 GitHub issues were filed, with ~53 directly attributable to code review output: 25 `review:`, 10 `compound:`, 6 `Refactor:`, 5 `Code review #2282:`, 4 `arch:`, 3 `follow-through:`. Single PRs spawned 5-8 follow-up issues each (e.g., #2282 → 5 issues; #2213 → 8 issues).

Founder assessment: *"Either we are too verbose or we are building up a lot of technical debt and pushing work that is not of good quality. Most if not all of those items should probably be tackled during the implementation itself and not pushed to later."*

## Root Cause

The `/review` skill's `SKILL.md` has two instructions that, combined, make it a ticket factory rather than a quality gate:

1. `<critical_requirement>`: *"ALL findings MUST be stored as GitHub issues via `gh issue create`. Create issues immediately after synthesis - do NOT present findings for user approval first."* — no severity filter, no fix-inline option.
2. Purpose line: *"Perform **exhaustive** code reviews using multi-agent analysis..."* — agents optimize for find-count, not fix-count.

With 9 review agents × "find everything" × "file everything," each PR review produces a backlog-generator rather than a merge-gate. The findings themselves are largely legitimate (real magic numbers, real duplication, real test gaps); the **disposition** is wrong.

Secondary faucet: `compound`'s route-to-definition mechanism creates GitHub issues to propose skill-file edits that could be direct commits. 10 such issues in 3 days.

## What We're Building

A workflow change that shifts the default disposition of review findings from **file** to **fix**:

1. **`/review` skill** — rewrite the `<critical_requirement>` so agents default to fixing findings inline (committing to the PR branch) for ALL severities (P1/P2/P3). GitHub issues are filed only when a finding meets explicit scope-out criteria.
2. **`/ship` Phase 5.5** — add an exit gate that blocks merge until there are no unresolved P1/P2/P3 findings. A finding is "resolved" if it is either (a) fixed inline on the PR branch, or (b) formally justified as a scope-out with a tracking issue.
3. **Compound route-to-definition** — default to direct skill-file edits when the change is local and mechanical. File issues only when the change is cross-skill, contested, or affects AGENTS.md rule semantics.
4. **Auto-detection** — extend the existing `rule-metrics` telemetry to track issues-filed-per-merged-PR. Emit an email alert when the ratio exceeds a threshold (starting proposal: >3 issues/PR in a 7-day window).
5. **Backlog triage** — one-time triage pass on the ~53 existing `review:`/`Refactor:`/`Code review #:`/`compound:`/`arch:` issues. Classify each as fix-now / valid-defer / invalid. Fix the fix-now subset; close the others with rationale.

## Why This Approach

- **Addresses the root cause**, not symptoms. Caps and human-triage gates treat the flow without changing the fundamental instruction that tells agents to file everything.
- **Preserves review thoroughness.** Agents stay exhaustive in *finding*; what changes is the *action* they take with findings.
- **No new skill or agent needed.** All changes are instruction edits in existing SKILL.md files + one telemetry extension. Low implementation surface.
- **Founder-aligned.** The brief explicitly said *"most if not all of those items should probably be tackled during the implementation itself."* This design makes fix-inline the path of least resistance; filing becomes the exception that requires justification.
- **Detection catches regressions.** Even if a future edit weakens the instructions, the per-PR metric will surface the return of the ticket-factory pattern within a week.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Default disposition for P1 findings | Fix inline on PR branch | Was already required; now enforced at Phase 5.5 exit gate |
| Default disposition for P2/P3 findings | Fix inline on PR branch | Founder directive: include P3 in same categorization to ship high-quality work |
| Default disposition for findings that fail scope-out criteria | Fix inline | File-issue is the exception, not the default |
| Scope-out criteria (when to file instead of fix) | See "Scope-Out Criteria" below | Must be satisfied to justify filing |
| /ship Phase 5.5 exit gate | Block merge on unresolved P1/P2/P3 findings | Forces resolution (fix or formal scope-out) before ship |
| Compound route-to-definition default | Direct skill-file edit | Matches fix-inline principle for skill maintenance |
| Auto-detection mechanism | Per-PR metric + email alert via rule-metrics | Leverages existing telemetry infra; weekly window |
| Initial alert threshold | >3 review-origin issues per merged PR (7-day rolling) | Tunable; starting point based on observed "healthy" PRs |
| Backlog handling | Triage first, then fix the worth-it subset | User choice over batch-fix-all or close-all |
| Scope of hardening | /review, /ship Phase 5.5, compound | Excludes /work Phase 3 (not selected by user) |

## Scope-Out Criteria (when to file instead of fix)

A finding may be filed as a follow-up issue **only if** at least one of these is true:

1. **Cross-cutting refactor** — the fix requires touching files materially unrelated to the PR's core change (would balloon the PR into a different feature).
2. **Contested design decision** — there are multiple valid fix approaches and the choice requires design input that doesn't belong in this PR's scope.
3. **Architectural pivot** — the fix would change a pattern used across the codebase and deserves its own planning cycle.
4. **Pre-existing, unrelated** — the finding existed on `main` before this PR and is not exacerbated by the PR's changes. (Tracked as separate tech-debt issue; does NOT block this PR's merge.)

Everything else (magic numbers, duplicated helpers, small refactors, missing tests for PR-introduced code, polish, naming, a11y on PR-introduced surfaces, performance issues introduced by the PR) must be fixed inline.

Filing a follow-up issue requires the review agent to state which criterion applies in the issue body. Issues without this justification fail the Phase 5.5 exit gate.

## Auto-Detection Design

**Signal:** Count of GitHub issues filed that reference a merged PR via `(#NNNN)` in the title or `Ref #NNNN` in the body, filtered to issues created within 48 hours of merge, with titles matching review-origin prefixes (`review:`, `Code review #`, `Refactor:`, `arch:`, `compound:`, `follow-through:`).

**Location:** Extend `plugins/soleur/skills/rule-utility/` or the existing weekly aggregator workflow (`.github/workflows/scheduled-rule-metrics.yml` or equivalent) — reuse the pattern that produced #2277 "chore(rule-metrics): weekly aggregate."

**Threshold:** Alert when the rolling 7-day average exceeds **3 review-origin issues per merged PR**. Rationale: many healthy PRs produce zero follow-ups; a handful with 1-2 is expected; sustained >3 indicates the ticket-factory pattern has returned.

**Alert channel:** Email via `.github/actions/notify-ops-email` (per `hr-github-actions-workflow-notifications`). Body: a small HTML table of offending PRs and their issue counts. No Discord.

## Backlog Triage (one-time)

Scope: all open issues created 2026-04-13 through 2026-04-15 with titles matching the review-origin prefixes above. Approximate count: 53.

Process:

1. One triage agent (or small set of parallel agents) reads each issue and classifies:
   - **Fix-now**: genuine defect/debt, still load-bearing, fix inline in a targeted PR.
   - **Valid-defer**: matches the new scope-out criteria; keep the issue, tag with `deferred-scope-out`.
   - **Invalid**: polish-only, wasn't worth filing under the new rules; close with "closed per new fix-inline workflow" rationale.
2. Batch the fix-now subset into logical grouped PRs (by feature area) so we don't create 30 micro-PRs.
3. Close the invalid subset with rationale linking to this brainstorm.
4. Report final counts as telemetry baseline for the alert threshold.

## Open Questions

- **Threshold tuning.** Is "3 issues/PR in 7-day window" the right alert level, or should we start stricter (>2) and relax if too noisy?
- **Enforcement strength for /ship exit gate.** Hard block (cannot merge without resolving all findings) vs. warning (requires explicit `--accept-findings` flag with justification)? Current design assumes hard block.
- **Compound retroactivity.** Should the 10 existing `compound: route-to-definition proposal` issues be triaged the same way, or auto-applied as direct edits now that the pattern is identified?
- **Back-pressure on review agents.** If review agents can't file an issue (because no scope-out criterion applies), how do they surface disagreement? Proposed: agent proposes fix, implementer-reviewer pair must accept or reject inline; no silent "filed and forgot" escape valve.
- **Agent capability for inline fix.** Do current review agents have write permissions and the instruction clarity to apply fixes and commit? The `pr-comment-resolver` agent pattern exists; review agents may need a similar toolkit.

## Non-Goals

- **Not** changing `/work` Phase 3. User explicitly excluded this from scope; review moves earlier only if we later find Phase 5.5 at /ship time is too late.
- **Not** reducing review agent thoroughness. Agents still look at everything; they just act differently on findings.
- **Not** adding new review agents. Working with the existing multi-agent set in `plugins/soleur/skills/review/`.
- **Not** changing how `/ship` handles correctness (tests, migrations, security) — those gates stay as-is.

## Success Criteria

- Weekly review-origin issue count drops by ≥70% within 2 weeks of rollout (from ~25/week to ≤8/week).
- Average review-origin issues per merged PR drops to ≤1.
- Phase 5.5 exit gate catches at least one attempted ship with unresolved findings in the first 2 weeks (proves the gate works).
- Auto-detection alert fires on the first day a threshold breach occurs in a synthetic test; doesn't produce false positives for 2 weeks of normal shipping.
- No regression in ship velocity (merged PRs per week) beyond +20% (one-time cost of applying inline fixes).
