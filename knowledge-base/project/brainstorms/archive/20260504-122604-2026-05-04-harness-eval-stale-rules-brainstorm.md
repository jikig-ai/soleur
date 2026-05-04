---
title: Harness eval suite + stale-rule reporter (scoped to C2)
date: 2026-05-04
issue: 3120
status: brainstormed
related_brainstorms:
  - knowledge-base/project/brainstorms/2026-04-14-rule-utility-scoring-brainstorm.md
  - knowledge-base/project/brainstorms/2026-05-04-harness-engineering-review-brainstorm.md
related_prs:
  - 3119
related_issues:
  - 2210
---

# Harness eval suite + stale-rule reporter

## What We're Building

A quarterly retirement-proposal pipeline that surfaces AGENTS.md rules with zero firings over 180 days as a single **pull request** appending them to `scripts/retired-rule-ids.txt`. The PR itself is the tracking artifact.

Concrete deltas over the existing rule-utility-scoring infra (#2210, shipped):

1. **New flag `--propose-retirement`** on `scripts/rule-prune.sh`. When set, the script does NOT file per-rule issues. Instead, it opens a single PR that appends each candidate to `retired-rule-ids.txt` with the canonical `<id> | <date> | PR #<N> | scheduled by rule-prune` format (PR # backfilled by the same script via `gh pr view --json number` after creation).
2. **New scheduled workflow** `.github/workflows/scheduled-rule-prune.yml`. Cron `0 9 1 1,4,7,10 *` (09:00 UTC, 1st of Jan/Apr/Jul/Oct) → `rule-prune.sh --weeks=26 --propose-retirement`. Manual `workflow_dispatch` available.
3. **Skip-list** in the same flag path: rules already listed in `retired-rule-ids.txt` are skipped (idempotent across quarters). Rules with `[hook-enforced]` or `[skill-enforced]` annotations are surfaced with a per-rule warning in the PR body — reviewer must explicitly acknowledge them as untestable-but-load-bearing rather than blanket-approve.

Out of scope for this brainstorm (deferred):

- **Theme D1: regression eval suite for new rules.** Replaying new rules against historical `Closes #N` diffs to compute would-have-caught rates. Deferred to a separate issue gated on real evidence (≥2 incidents where a shipped rule provably failed to catch what it claimed). Goodhart and corpus-contamination problems make this a speculative metric today.
- **60-day flag tier.** Re-add as Approach B if quarterly retirement proves too aggressive or if early-warning signal proves valuable. Per-rule issue spam at 60d is the primary concern.
- **External announcement.** CMO recommends blog-eligible content **after** acceptance criteria fire (first eval-driven retirement merges). No README/docs claim at ship.

## Why This Approach

**The C2 substance is mostly already built.** `incidents.sh emit_incident` records `deny`/`bypass`/`applied`/`warn` events. `rule-metrics-aggregate.yml` rolls up to `rule-metrics.json` weekly. `rule-prune.sh` already surfaces zero-hit rules at a configurable threshold and files idempotent per-rule issues. The two genuine gaps in C2-as-written:

- The script isn't scheduled (only invoked via `/soleur:sync rule-prune`), so the loop never closes without operator action.
- The "propose retirement" automation step (commit ID to `retired-rule-ids.txt`) doesn't exist — humans must hand-edit `retired-rule-ids.txt` after reading each issue.

Approach A closes both gaps in the smallest reviewable diff: one new flag, one workflow file, ~30 lines of PR-creation logic. PR-as-tracking-artifact (rather than a separate consolidated tracking issue) keeps the diff and the deliberation in the same place a reviewer is already going to look.

**D1 was deferred for three reasons:**

1. **No incident evidence.** No PR cited where a shipped rule failed to catch a regression it claimed to prevent. The motivation in the parent brainstorm (PR #3119) is meta-quality framing from Fowler/Schmid essays, not founder pain.
2. **Goodhart drift.** Rule authors gravitate toward grep-friendly triggers (`useRef`, `package.json`) because those score on the corpus. Rules guarding rare-but-catastrophic events (`hr-never-git-stash-in-worktrees`, `hr-dev-prd-distinct-supabase-projects`) score zero by construction — these are the highest-value rules. The metric pressures the wrong direction.
3. **Corpus contamination.** Many `Closes #N` PRs *added* the rule that catches them. Replaying any rule against its originating diff produces a false positive automatically. Excluding the introducing PR requires NLP that is exactly what D1 was meant to make tractable.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Scope** | C2-finish only; defer D1 | CPO evidence gate: ≥2 incidents needed before D1 is justified |
| **Tracking artifact** | Single PR per quarter (no separate tracking issue) | Reviewer already inspects the diff; one artifact, not two |
| **Cadence** | Quarterly (1st of Jan/Apr/Jul/Oct, 09:00 UTC) | Matches CPO; balances signal with review fatigue; aligns to release-quarter cadence |
| **Threshold** | `--weeks=26` (≈182 days) | Matches issue #3120's 180-day retirement spec; well past 60d flag tier |
| **`--propose-retirement` semantics** | Opens ONE PR appending all candidates to `retired-rule-ids.txt` | Avoids N tiny PRs that race against each other and clobber the same file |
| **`hook-enforced` / `skill-enforced` rules** | Surface in PR body with per-rule warning, do NOT auto-skip | Reviewer must affirm these explicitly — `fire_count=0` is expected for some hook-only rules |
| **PR semver label** | `semver:patch` | Rule retirements aren't user-facing; they affect agent guardrails, which are dev-tooling |
| **PR auto-merge** | NO. Human review required, no `--auto` queue | CPO: retirement is a one-way door for `hr-*` (per `cq-rule-ids-are-immutable`). Hands stay on. |
| **Idempotency** | Skip ids already present in `retired-rule-ids.txt` | Quarterly cron must be safe to re-run; no duplicate-line PRs |
| **Existing 8-week manual path** | Unchanged. `/soleur:sync rule-prune` (and ad-hoc `--weeks=8`) keeps filing per-rule issues | Useful for operator-driven inspection between quarters |
| **D1 deferral** | New issue, blocked on ≥2 incidents where a shipped rule failed | Evidence gate keeps speculative metrics out of the harness |

## Non-Goals

- Auto-edit AGENTS.md to remove the rule body. The PR only appends to `retired-rule-ids.txt`; rule-text removal is a separate human PR (per existing `cq-rule-ids-are-immutable` retirement protocol).
- 60d "flag" tier (Approach B). Reconsider after 1-2 quarters of retirement-PR data.
- D1 corpus-replay metric, ground-truth labeling, trigger-pattern NLP. All deferred.
- Slack/Discord notifications. The PR is the notification.
- Retirement of `hr-*` rules. Already hard-blocked by `lint-rule-ids.py` (per the hr-rule-retirement-guard brainstorm, 2026-04-24). The flag must respect that block — `hr-*` candidates surface in the PR body as "blocked-from-automation: edit linter to retire" but are NOT appended to `retired-rule-ids.txt` by the script.

## Open Questions

1. **What if zero candidates exist for a quarter?** Skip PR creation entirely (no-op log line). The workflow file should not fail.
2. **What if the PR has merge conflicts (a human edited `retired-rule-ids.txt` mid-quarter)?** The cron runs once a quarter — conflicts are extremely rare. The script's append-only pattern means rebase-on-main resolves trivially. If conflict resolution becomes a recurring failure, add a workflow step that rebases before push.
3. **What if a hook-enforced rule with `fire_count=0` is genuinely retire-eligible?** Reviewer judgment. The PR body's per-rule warning gives them the trigger-source pointer; they can either remove that line from the PR and let it carry the rest, or close the PR and edit-the-linter for that rule manually.

## Acceptance Criteria

- A quarterly cron `scheduled-rule-prune.yml` exists and runs `rule-prune.sh --weeks=26 --propose-retirement`.
- The first quarterly run produces either (a) one PR appending ≥1 rule to `retired-rule-ids.txt` OR (b) a no-op log line if no candidates exist.
- The PR body lists each candidate with: rule id, section, first-seen date, fire_count, rule-text-prefix, and an explicit warning for hook-/skill-enforced rules.
- Idempotency: re-running the workflow does not append already-listed ids.
- The existing 8-week manual `/soleur:sync rule-prune` path still works unchanged.
- One follow-up issue exists for D1, milestoned to "Post-MVP / Later", body documenting the evidence-gate (≥2 incidents) before the issue is actionable.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO — current task topic, self-assessed)

**Summary:** Small, contained delta on shipped `rule-utility-scoring` infra. Architectural risk is low: one new flag on an existing script, one new workflow following the established `rule-metrics-aggregate.yml` pattern. Drift guards: the new PR-creation path must respect `_RULE_ID_RE` (already in script) and the `lint-rule-ids.py` hr-* block (must NOT auto-append `hr-*` ids). Schema contract on `rule-metrics.json` already gated by `SCHEMA_VERSION`.

### Product (CPO)

**Summary:** Real pain with a small, evidence-grounded delta. D1 is deferred on Goodhart + corpus-contamination grounds; a separate issue with an explicit evidence gate (≥2 incidents) keeps the speculative metric out of the harness without losing it. Recommend retitling #3120 to "Schedule + consolidate stale-rule reporter (C2 only)."

### Marketing (CMO)

**Summary:** Internal harness tooling. **Blog-eligible** post-ship — Fowler/Schmid/Liu thread audience overlaps Soleur's agent-tooling positioning. Trigger external content **after** the first eval-driven retirement merges (acceptance criterion). No README/docs change at ship; no pre-announcement.

## User-Brand Impact

`USER_BRAND_CRITICAL=false`. The phase 0.1 framing answer ("False retirement of load-bearing rule") flagged a real internal failure mode but did not match the trigger keywords for credentials/data/auth/payment. Failure mode is contained to harness quality (operator must spot bad retirements at PR review). Mitigations baked into the design: human-only review (no auto-merge), `hr-*` ids blocked from automation by `lint-rule-ids.py`, hook-/skill-enforced rules flagged in PR body.
