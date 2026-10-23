---
title: "ADR-296: Persist the rehearsal-skip monitor streak in a workflow artifact, not the Actions cache"
status: Accepted
date: 2026-10-23
supersedes: []
amends:
  - ADR-188
tags: [ci, monitoring, fail-closed, github-actions, persistence]
---

# ADR-296: Persist the rehearsal-skip monitor streak in a workflow artifact, not the Actions cache

## Status

Accepted — 2026-10-23. The decision is accepted; its delivery is verified by the post-merge
dispatch pair recorded in the plan (a `bootstrap=true` run, then a `bootstrap=false` run whose
`Assert the streak state round-trips` step concludes `success` with `restored=true`). If that pair
fails, this ADR is amended rather than left standing.

## Context

`.github/workflows/scheduled-rehearsal-skip-monitor.yml` carries a consecutive-TRANSIENT counter
across daily runs (ADR-188's carrier). It persisted that counter in the GitHub Actions cache, and its
round-trip assertion exits non-zero when no prior generation is restored. Counted on 2026-10-23 from
the per-run step conclusions of `Assert the streak state round-trips` (`gh run view <id> --json jobs`),
the step was red on 24 of the last 30 daily runs.

Measured 2026-10-23 (read-only `gh api repos/jikig-ai/soleur/actions/cache/usage` and
`gh api --paginate 'repos/jikig-ai/soleur/actions/caches?per_page=100'`; the figures are a snapshot and
drift upward within a day, a later re-count read 206 entries and 11.83 GB, same direction): the repository
held 10.23 GB across 178 entries, every one on `refs/heads/main`.
160 entries (9.6 GB) are `buildkit-blob-1-sha256:*`, written by the release workflow's
`cache-to: type=gha,mode=min` (`reusable-release.yml`); seven release exports on that day wrote about
1.17 GB each. GitHub evicts least-recently-accessed first, so a 192-byte entry read once per 24 hours
is always the eviction candidate. The monitor's own per-run keys do not accumulate (2 entries, 391
bytes) and no pull-request refs participate. Deleting caches by hand would be refilled by the next
release within hours.

## Decision

A correctness-critical cross-run counter lives in a store its own neighbours cannot evict. The streak
is a single decimal integer stored in a workflow **artifact** (`rehearsal-skip-monitor-streak`,
`retention-days: 90`, above the 60-day scheduled-workflow auto-disable). The decision logic is one
script, `scripts/monitor-streak-state.sh` (`fetch`, `seal`, `assert`), so it is testable without a
hosted runner, and its suite also parses the workflow's wiring.

- An **unreadable** store (a failed or malformed listing) exits 1 under every setting; an **empty**
  store is `matched=false`, and the assert step turns that into a red run. The three states (unreadable,
  empty, poisoned) are never conflated.
- Selection is fail-closed: unexpired, at most 4096 bytes, from branch `main`, from this repository's
  own runs (artifacts are repository-scoped, so a fork pull-request run is listed here with a
  fork-controlled `head_branch`; the head repository must equal this repository), from a run strictly
  before the current one, newest by run id, exact archive member `streak`, value 1 to 6 digits.
- An explicit `workflow_dispatch` input `bootstrap` (default `false`, unreachable from a scheduled run)
  replaces the old `RUN_NUMBER > 1` test, which would have fired a guaranteed false red on the first
  scheduled run after merge. It is the explicit reseed: a BOOTSTRAP run discards a corrupt newest
  artifact so a poisoned artifact cannot wedge the monitor (a red run on an empty store also self-heals,
  because the upload still publishes that run's value).
- `seal` is verdict-aware and compares against the value `fetch` restored (`prior=` in its output): a
  TRANSIENT verdict must have moved the streak to exactly `restored + 1`, because the probe's own write
  is `2>/dev/null || true` and a lost increment would otherwise be sealed silently; a PASS forces `0`; a
  FAIL keeps what an escalation left (absent means `0`); a `broken` probe keeps the restored value.
- The artifact is read through a bounded pipe (the 4096-byte limit is on the compressed archive), and a
  failed listing, a hung listing or a failed download is fatal even under `bootstrap`; only corrupt
  CONTENT is discarded by a bootstrap run.
- A failed state step (`fetch`, `seal`, `assert`, `upload`) also files an alert issue, because a red
  scheduled run has no watcher: the old assertion was red on 24 of 30 days without anyone acting. A pure
  store failure has its own title; when the probe also failed the probe title wins and the issue body
  lists the state-step outcomes.

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| A. Cache hygiene (prune workflow, hand deletion, smaller release export) | Rejected for the monitor | Leaves a correctness-critical counter on an evictable store. The release export is production-affecting and its reuse profile is unmeasured; tracked separately. |
| C. State issue (body or comment marker) | Rejected | Issue state is mutable and closable by triage, and adds tracker noise. |
| D. Repository Actions variable | Rejected | `GITHUB_TOKEN` cannot write variables; it needs an App token through Doppler for one integer. |
| E. Derive the streak from run history | Rejected | The counter lives inside the probe; run conclusions do not encode `transient` versus `pass`. |
| Keep the cache and stop asserting | Rejected | It restores the original fail-open: escalation could never fire and nothing would say so. |
| Legacy-cache fallback during migration | Rejected | It re-introduces the evictable store as a silent second source of truth. |

## Consequences

- The monitor's assertion step is green on a healthy day. The job as a whole can still be red because
  of a legitimate probe `fail` (alert issue open at the time of writing); that is a true positive and
  outside this decision.
- The release cache export churn that caused the eviction remains until its own tracking issue lands, so
  the other caches (npm, CodeQL) continue to be evicted daily.
- Listing and downloading artifacts with the default token and `actions: read` is already done in this
  repository (`web-platform-release.yml` lists a run's artifacts and downloads the zip; the cross-run
  download in `fix-constraints-stage-b.yml` documents the `actions: read` need), both under
  `workflow_run`. This monitor runs under `schedule`, the same token class, but that exact trigger is
  unproven until the post-merge dispatch pair; the fallback inside this design is the repository's
  App-token mint for the two read calls, never the cache.
- Accepted residuals (also in the workflow header): a cancelled run can under-count by one; a stale value
  after a day on which the upload was skipped or failed; no age bound; selection by run id rather than
  execution order; `overwrite` is delete-then-upload; and any actor with write access can plant a same-named artifact from a run on
  `main`, the same trust level as editing the workflow. A scheduled run that fires before the first
  `bootstrap` dispatch after merge goes red once, by design, and files one alert issue.
