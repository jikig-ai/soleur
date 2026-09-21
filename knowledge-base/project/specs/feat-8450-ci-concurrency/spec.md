---
feature: 8450-ci-concurrency
lane: cross-domain
brand_survival_threshold: single-user incident
refs: [8450]
brainstorm: knowledge-base/project/brainstorms/2026-09-21-ci-runner-concurrency-brainstorm.md
status: draft
created: 2026-09-21
---

# Spec — GitHub Actions concurrency ceiling relief

## Problem Statement

The org's `free` plan caps concurrent GitHub Actions jobs at 20. A single PR head
dispatches ~18 runs (25 jobs in `CI` alone) and can saturate the entire budget, producing
tail latency on deploy-critical jobs (`migrate` queued 30+ min; merge-commit `CI` queued
40+ min; deploy arm unregistered ~75 min post-merge). Pool throughput is ~250 runs/hr —
the backlog clears, the *tail* is what hurts.

## Goals

- **G1** — Raise the concurrent-job ceiling 20→60 via GitHub Team ($4/user/mo, 1 seat).
  Billing authorization is operator-only; this spec tracks the prerequisite step and the
  recurring-expense record.
- **G2** — Reduce sub-hourly cron cadence where each workflow's documented detection
  window tolerates it (~216 runs/day across 4 files).
- **G3** — Stop non-applicable PR classes from dispatching heavyweight required-check
  producers, without ever leaving a required context unreported.

## Non-Goals

- **NG1** — Self-hosted runner (issue option 3). Deferred: this repo is PUBLIC, so the
  fork-PR execution policy must be settled first. Re-evaluate only if G1 doesn't clear
  the deploy-critical tail.
- **NG2** — Merge-queue adoption. Prior art exists (#5780 learnings); a separate decision.
- **NG3** — Removing checks from the required set. Membership changes to the IaC-managed
  rulesets (ADR-032) are out of scope except where FR3 requires a paired adjustment.
- **NG4** — Touching the `CI` workflow's internal job graph (shard counts, fan-in shape).

## Functional Requirements

- **FR1** — `knowledge-base/operations/expenses.md` gains a recurring-vendor row for
  GitHub Team ($4/user/mo) in the same PR (per `wg-record-recurring-vendor-expense`).
- **FR2** — Each relaxed cron documents, in a comment at the `schedule:` site, which
  detection window the new cadence protects and the worst-case lag introduced.
- **FR3** — A path-filtered required check can never stall a merge: every `paths:` /
  `paths-ignore:` gate keeps a reporting check run (always-run sibling that posts pass),
  or the ruleset's required list is adjusted via Terraform in the same PR.
- **FR4** — The operator upgrade step is written as exact steps (org billing → plan →
  Team), followed by a verification command (`gh api orgs/jikig-ai --jq .plan.name`
  returns `team`).

## Technical Requirements

- **TR1** — Ruleset changes go through `infra/github/` Terraform (ADR-032) — never the UI.
- **TR2** — Cron cadence targets: `scheduled-inngest-health` `*/15`→`*/30`,
  `scheduled-prod-version-drift` `*/30`→hourly, `scheduled-zot-restart-loop` `*/30`→hourly,
  `apply-inngest-rls` hourly→every 4h — each justified against the detection window named
  in its file header; tighten less where the header argues otherwise.
- **TR3** — Post-upgrade verification: sample `actions/runs?status=queued` p50 age before
  and after; record both numbers in the PR body.
- **TR4** — No changes to `concurrency:` group membership except where a consolidated
  cron merges files.

## Acceptance Criteria

- `gh api orgs/jikig-ai --jq .plan.name` returns `team` (operator step, post-PR or in
  parallel).
- Sub-hourly cron count drops from 4 files to ≤2; documented lag per FR2.
- At least one non-applicable PR class (e.g. `knowledge-base/**`-only diffs) skips
  heavyweight producers while all required contexts still report.
- Queue p50 measured after merge is materially below the ~7 min / 30-min-tail baseline.
