---
title: Path-aware CI gating (S4 affected-only PR runs + e2e fix + shard-totality gate)
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 9729
branch: feat-ci-path-filtering
brainstorm: knowledge-base/project/brainstorms/2026-10-12-ci-path-aware-gating-brainstorm.md
---

# Spec: path-aware CI gating

## Problem Statement

Doc-only PRs (PR 10097: one `knowledge-base/**/*.md` file) run most of the CI battery on hosted runners capped at
60 concurrent jobs, starving the rest of the pipeline. About 14% of the last 300 merged PRs were
`knowledge-base/**/*.md`-only. `knowledge-base/**` cannot be skipped by path alone (240 baseline rows of real
readers), so the gate must be selector-driven.

## Goals

- PR `CI` job-minutes per run down at least 20% (S4 target: about 20 of 99.8), measured by the committed census.
- `merge_group`, push to main, `workflow_dispatch`, schedule, undeterminable diffs and runner edits keep the full battery.
- No required context renamed, removed, left pending or posted skipped-green (ADR-276 3(a)).
- Fix the e2e classifier fallback seen on PR 10097; gate `shard-totality-mutations`.

## Non-Goals

- CodeQL / Code Quality on md-only PRs (S5, #9730) and `claude-code-review.yml` gating (follow-up issue).
- Raising runner supply; any change to merge_group or push authority.
- A hand-written `knowledge-base/**` skip list.

## Functional Requirements

- FR1: On `pull_request` only, with a kill-switch variable exactly `on`, run the `--affected` suite set plus the always-on ratchets; the affected pre-pass runs once per run, not per shard leg.
- FR2: The `test` aggregator tolerates skips only for named reasons (PR event, switch on, gated legs only); `encryption-posture` stays required; any unknown means full battery.
- FR3: Full-battery runs carry a `[full]` `run-name` suffix; `admin-merge-ready.sh` demands a completed successful full-battery run on the head SHA (runs API: head SHA, event, display_title, conclusion; not check name).
- FR4: Detective post-merge probe flags any merge whose head SHA lacks a `[full]` full-battery run; residual counted in the escape metric.
- FR5: Diagnose and fix the `e2e` `enum-failed` fallback on KB-only diffs.
- FR6: Path-gate `shard-totality-mutations` (ADR-262 style, no aggregator change).
- FR7: ADR-276 amendment (S4, kill-switch, exit criterion, census link) plus pointer amendments to ADR-262 and ADR-183 and `amends:` frontmatter, appended in the stage PR before the switch is flipped.

## Technical Requirements

- TR1: Replay evidence: `--print-selection` over the last 300 first-parent commits against suite failures, escape rate under 2% (break-even about 12 to 16%).
- TR2: "Runner changed means full battery" detector and the affected-selection index are read from a trusted base-ref copy, not the PR tree; registration-only carve-out stays out of PR mode.
- TR3: Consumers `battery-owed.sh`, the deploy `workflow_run` arm and `post-merge-monitor.yml` never read a reduced run as full.
- TR4: Dark launch behind the kill-switch; rollback = unset the variable (the `[full]` marker is still emitted on full PR runs, so the admin route does not stall).
- TR5: Own Guard Contract in the plan; `scripts/ci-push-dedupe.test.sh` and `scripts/ci-draft-light.test.sh` gated-set pins extended for any new heavy job.

## Decision record

S4's re-decide gate (S2 #9818 and S3 censuses first) was waived by the operator on 2026-10-12; see the brainstorm Key Decisions.
