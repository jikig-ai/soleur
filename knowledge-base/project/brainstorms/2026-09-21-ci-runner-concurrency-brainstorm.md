---
title: "GitHub Actions concurrency ceiling — one PR saturates the org's 20-job budget"
date: 2026-09-21
status: decided
lane: cross-domain
brand_survival_threshold: single-user incident
tags: [ci, github-actions, concurrency, infra-cost]
related_issues: [8450]
related_adrs: [ADR-030, ADR-032, ADR-033]
---

# CI runner concurrency — brainstorm (issue #8450)

## The question

Issue #8450: GitHub Actions runs queue behind the free org plan's 20-concurrent-job
ceiling; a single PR head dispatches 18 runs and the `CI` workflow alone is 25 jobs, so
one PR can saturate the org's entire budget. Which of the four options do we take?

## Measured floor (verified this session, not quoted from the issue)

- Org plan `free`, 1 seat; **0 self-hosted runners** (`gh api orgs/jikig-ai`,
  `repos/.../actions/runners`).
- **79** workflow files on `main`; 26 fire on `pull_request`; **20** carry real `schedule:`
  triggers (the issue body's "80 / 27" was loose counting — comment mentions of the word
  inflated the cron figure).
- Throughput is **~250 runs/hr** (the issue's own addendum corrected the body's 29/hr) —
  this is a **tail-latency** problem: p50 queue age ~7 min, but deploy-critical jobs
  (`migrate`, deploy arms) waited 30–75 min behind the ceiling.
- **Cron fleet ≈ 216 runs/day (~4% of load)**: `scheduled-inngest-health` `*/15` (~96/day),
  `scheduled-prod-version-drift` `*/30` (~48/day), `scheduled-zot-restart-loop` `*/30`
  (~48/day), `apply-inngest-rls` hourly (~24/day); ~11 more are daily/weekly/monthly.
- **Required checks: 26 contexts** — "CI Required" ruleset (24) + "CLA Required" ruleset
  (`cla-check`, `cla-evidence`). Nearly all of the 18 runs per PR head produce required
  contexts; the advisory surface option 4 could trim is thin.
- **61/79 workflows already carry `concurrency:` groups** — per-workflow dedup exists; it
  does not bound the org-wide ceiling.
- Prior art: merge-queue wiring precedent (#5780 learnings), self-hosted substrate
  precedent (self-hosted Inngest on Hetzner, ADR-030/ADR-033), rulesets are IaC (ADR-032).

## Decision

**Option 1 + code trims** — operator-chosen 2026-09-21. GitHub Team upgrade (20→60
concurrent jobs, $4/user/mo at 1 seat) is the primary lever; code trims (sub-hourly cron
consolidation, path filters for non-applicable PR classes) ship in parallel.
Domain-leader fan-out was declined — the operator picked the concrete path over a full
triad brainstorm.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | GitHub Team upgrade is the primary fix | Only lever that directly raises the ceiling; smallest diff, largest measured effect. Billing authorization is operator-only (payment surface). |
| 2 | Thin the three sub-hourly crons | ~216 runs/day concentrated in 4 files; each cron comment names the detection window its cadence protects, so relaxation must be argued per-cron. |
| 3 | Path filters only where ruleset permits | Required checks that never report leave a PR pending-forever; filtering must keep a reporting path or adjust the IaC-managed ruleset in the same PR. |
| 4 | Self-hosted runner deferred | Public-repo fork-PR execution policy is unsettled; re-evaluate if the ceiling raise doesn't clear the deploy-critical tail. |

## Open Questions

- Per-cron cadence floor: how much detection lag does each of `inngest-health`,
  `prod-version-drift`, `zot-restart-loop`, `apply-inngest-rls` tolerate?
- Which required-check producers are safe to path-filter (docs-only/chore diffs)?
- Does the Team upgrade alone dissolve the tail, making option 3 permanently moot?

## User-Brand Impact

- **Artifact:** the deploy-verification pipeline for this repo — the named surface is the
  queued `migrate`/deploy jobs whose tail latency delays post-merge verification.
- **Vector:** worst case, a merge lands while its deploy arm is queued ~75 min and a
  broken deploy goes unverified; the user-facing blast radius is the production app.
- **Threshold:** `single-user incident`.

## Lane

`cross-domain` (auto per #5175 — `USER_BRAND_CRITICAL=true` set unconditionally).
