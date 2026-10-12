---
title: Review Workflow Hardening — Fix-Inline Discipline
status: draft
owner: engineering
brainstorm: knowledge-base/project/brainstorms/2026-04-15-review-workflow-hardening-brainstorm.md
created: 2026-04-15
---

# Spec: Review Workflow Hardening

## Problem Statement

The `/review` skill, `/ship` Phase 5.5, and `compound` route-to-definition produce ~25-30 follow-up GitHub issues per week, driven by instructions that default every review finding (regardless of severity) to "file as issue" rather than "fix inline." This is generating technical debt instead of preventing it. One PR produced 5 issues (#2282); another produced 8 (#2213).

## Goals

- **G1.** Default disposition of review findings is "fix inline on the PR branch" for ALL severities (P1/P2/P3).
- **G2.** GitHub issues are filed only when a finding meets explicit scope-out criteria (cross-cutting, contested, architectural, pre-existing-unrelated).
- **G3.** `/ship` Phase 5.5 blocks merge on any unresolved P1/P2/P3 finding.
- **G4.** Compound route-to-definition defaults to direct skill-file edits.
- **G5.** An auto-detection signal alerts when the ticket-factory pattern regresses (>3 review-origin issues per merged PR over a 7-day window).
- **G6.** The existing ~53 review-origin issues are triaged once: fix-now subset addressed, invalid subset closed, valid-defer subset tagged.

## Non-Goals

- **NG1.** No changes to `/work` Phase 3 quality check (deferred unless Phase 5.5 proves too late).
- **NG2.** No reduction in review agent thoroughness — agents still find everything; disposition changes, not discovery.
- **NG3.** No new review agents or skills created.
- **NG4.** No changes to correctness gates (tests, migrations, security) in `/ship` beyond Phase 5.5 review-findings gate.
- **NG5.** No changes to how `/review` is invoked or which agents it spawns.

## Functional Requirements

- **FR1.** `/review` SKILL.md's `<critical_requirement>` is rewritten: default action is to fix the finding inline on the PR branch (commit + push). Filing a GitHub issue is allowed only when one of the four scope-out criteria is met; the criterion name MUST appear in the issue body under `## Scope-Out Justification`.
- **FR2.** Scope-out criteria are defined and documented in `plugins/soleur/skills/review/references/` as `review-scope-out-criteria.md`. The four criteria: cross-cutting-refactor, contested-design, architectural-pivot, pre-existing-unrelated.
- **FR3.** `/ship` Phase 5.5 gains an exit-gate check: query GitHub for open issues referencing the current PR (via `#<number>` in title or body) with review-origin prefixes (`review:`, `Code review #`, `Refactor:`, `arch:`, `compound:`, `follow-through:`) that lack a `deferred-scope-out` label. If any exist, block ship with a message listing the unresolved findings and the remediation paths (fix inline or add scope-out justification + label).
- **FR4.** Compound's route-to-definition proposal path is rewritten: default action is a direct skill-file edit (committed to the current branch). Issue-filing path is retained only for cross-skill changes, contested changes, or AGENTS.md rule semantic changes; gated by the same scope-out criteria.
- **FR5.** A `deferred-scope-out` label is created in the repo (one-time setup) and applied by review agents when a filed issue meets a scope-out criterion.
- **FR6.** A per-PR metric is added to the rule-metrics weekly aggregator: count of review-origin issues created within 48h of merge, per merged PR, rolling 7-day average. Metric is emitted in the weekly aggregate output.
- **FR7.** A GitHub Actions workflow (new or extending an existing rule-metrics workflow) checks the metric on each aggregator run. If the 7-day average exceeds 3 review-origin issues per merged PR, the workflow sends an email via `.github/actions/notify-ops-email` with an HTML body listing the offending PRs and their issue counts.
- **FR8.** A one-time triage artifact (`knowledge-base/project/specs/review-workflow-hardening/backlog-triage.md`) classifies each of the ~53 existing review-origin issues (created 2026-04-13 through 2026-04-15) as fix-now / valid-defer / invalid, with rationale. Fix-now issues are grouped into logical batched PRs; valid-defer issues are labeled `deferred-scope-out`; invalid issues are closed with a rationale comment.

## Technical Requirements

- **TR1.** No secrets or Doppler config changes required — alert email uses existing `notify-ops-email` composite action.
- **TR2.** Metric storage: extend the existing rule-metrics JSONL or aggregate output (do NOT introduce a new storage layer). If the current aggregator writes to `knowledge-base/engineering/rule-metrics/` or similar, append the new metric there.
- **TR3.** Threshold (3 issues/PR) is parameterized in the workflow env or the aggregator script (single constant, easy to tune without a code change).
- **TR4.** All SKILL.md edits use the immutable rule-ID convention (`[id: <prefix>-<slug>]`) where new rules are added to AGENTS.md, and preserve existing rule IDs when editing.
- **TR5.** Changes must pass `npx markdownlint-cli2 --fix` on all touched `.md` files.
- **TR6.** `/ship` Phase 5.5 gate must use `gh issue list` with a filter query that runs in under 5s on a repo with <1000 open issues (no full-repo scans).
- **TR7.** The auto-detection workflow follows `hr-in-github-actions-run-blocks-never-use` — no heredocs below the YAML base indent; use `{ echo ...; } > file` for multi-line HTML bodies.
- **TR8.** The triage artifact is a committed markdown file (not an ephemeral script output), so the classification decisions are auditable and the new-workflow baseline is preserved.

## Out of Scope (Future Work)

- Moving review earlier into `/work` Phase 3 (deferred; may be revisited if Phase 5.5 proves too late to force fixes).
- Automated scope-out criterion detection (currently agent-assessed + human-verified; could be made deterministic later).
- Extending fix-inline discipline to UX audit, SEO audit, and security-sentinel outputs (separate audit skills with different disposition semantics; evaluate if the same pattern emerges).

## Success Criteria

- **SC1.** Weekly review-origin issue creation drops ≥70% within 2 weeks of rollout (from ~25/week to ≤8/week).
- **SC2.** Average review-origin issues per merged PR drops to ≤1.
- **SC3.** Phase 5.5 exit gate catches at least one ship attempt with unresolved findings in the first 2 weeks.
- **SC4.** Auto-detection alert fires within 24h of a synthetic threshold breach and produces zero false positives over 2 weeks of normal shipping.
- **SC5.** Backlog triage closes ≥50% of the ~53 existing review-origin issues (either fixed or closed-as-invalid); remainder labeled `deferred-scope-out` with justification.
- **SC6.** No regression in ship velocity (merged PRs/week) beyond +20% overhead.
