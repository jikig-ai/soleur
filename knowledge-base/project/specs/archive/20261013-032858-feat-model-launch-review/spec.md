---
name: model-launch-review
title: model-launch-review skill — recurring per-model-release audit + auto-fix
date: 2026-06-11
issue: 5100
parent_issue: 3791
brainstorm: knowledge-base/project/brainstorms/2026-06-11-model-launch-review-brainstorm.md
branch: feat-model-launch-review
draft_pr: 5157
lane: single-domain
brand_survival_threshold: not-applicable
user_brand_critical: false
domains_assessed: [Engineering]
---

# Spec: `model-launch-review` skill

## Problem Statement

Every Anthropic model release (Opus 4.6 → 4.7 → 4.8 → Fable 5) recurs an identical
manual checklist: model-ID swaps, claude-code-action pin sync, thinking-API shape
changes, pricing-table refresh, and tier-map re-evaluation. The checklist was executed
by hand for the #3791 tiering work. Two compounding gaps:

1. **No reusable artifact** — the procedure lives only in learnings, re-derived each release.
2. **Dormant trigger** — #3791's "pricing change" re-eval criteria never fired when
   Fable 5 shipped; the work surfaced only by accident during an unrelated brainstorm
   (`2026-06-10-model-economics-brainstorm-dormant-triggers-and-pricing-source.md`).

## Goals

- G1: A `/soleur:model-launch-review` skill that audits the five-item checklist and
  **auto-fixes mechanical drift**, opening a CI-gated PR.
- G2: Detection wired into an **existing scheduled cron** that files an issue on drift
  or a newly-released model — closing the dormancy gap.
- G3: Auto-fix never breaks CI: the `(model-ID, pin, thinking-API shape)` triple is
  bumped as one unit and validated by a pre-PR compatibility probe.

## Non-Goals

- NG1: No new standalone scheduled workflow / Inngest cron (reuse existing per operator choice).
- NG2: No auto-apply of the tier-map re-evaluation (judgment call — flag for human sign-off only).
- NG3: No direct-to-main writes — all fixes go through a PR.
- NG4: Not a general "any vendor" model watcher — Anthropic/claude-code-action scope only in v1.

## Functional Requirements

- FR1: **Audit** — detect drift across all five checklist items, reporting each with
  evidence (file path, current vs. expected value). No silent green: an all-clear result
  must still enumerate what was checked.
- FR2: **Inventory by grep, not by list** — discover affected files via independent
  `grep`/`gh api`, never trust a hardcoded file list (learning `2026-02-22`: inventories undercount).
- FR3: **Auto-fix (mechanical)** — apply model-ID swaps, claude-code-action pin bumps,
  thinking-API shape rewrites, and pricing-table refresh; open a PR with the diff.
- FR4: **Coupled-triple invariant** — when bumping a model ID in any `.github/workflows/*.yml`,
  bump the matching claude-code-action pin AND reconcile the thinking-API shape in the
  same change (rule `cq-claude-code-action-pin-freshness`, learning `2026-04-18`).
- FR5: **Flag-for-review (judgment)** — surface tier-map re-evaluation findings against
  the Model Selection Policy in the PR body for human sign-off; do not auto-apply.
- FR6: **Pre-PR compatibility probe** — before opening the PR, dry-run a minimal API call
  with the new model + the target pin's SDK thinking shape; abort with a clear error if it 400s.
- FR7: **Cron-hosted detection** — append a model-drift check to an existing scheduled
  workflow (candidate: `kb-drift-walker.yml`) that opens an issue when a new model ships
  or drift is found, referencing this skill as the remediation.

## Technical Requirements

- TR1: Pricing/model facts sourced from the `claude-api` skill's cached model table,
  never model memory (learning `2026-06-10`).
- TR2: Pin freshness resolved via `gh api repos/anthropics/claude-code-action/releases`
  and per-pin commit dates (learning `2026-04-18` audit commands).
- TR3: Skill description stays within the cumulative word budget (`cq-skill-description-budget-headroom`).
- TR4: New skill must satisfy plugin compliance checklist + `hr-new-skills-agents-or-user-facing`
  user-facing-capability rule; release-docs counts updated at ship.
- TR5: Pre-PR probe requires an API key available to the host cron's secret scope (verify
  at plan time).

## Open Questions (carried from brainstorm)

1. Which existing cron hosts detection — `kb-drift-walker.yml` (daily), `rule-audit.yml`
   (1st/15th), or `scheduled-terraform-drift.yml`?
2. New-model detection source — Anthropic models endpoint, claude-code-action releases, or both?
3. Is thinking-API-shape rewrite mechanical enough to auto-fix in v1, or flag-only?

## Acceptance Criteria

- AC1: Running the skill against a synthetic stale fixture produces an accurate drift
  report and a correct auto-fix PR (mechanical items) + flagged tier-map note.
- AC2: A deliberately mismatched model/pin pair is caught by the pre-PR probe and blocks PR creation.
- AC3: The cron check files an issue on a simulated new-model / drift condition.
- AC4: All-clear runs still enumerate every checked item (no silent green).
