---
title: "fix: soak probe for #9323 cannot converge — runs API drops pull_requests on merge; paginate and resolve via head_branch"
type: fix
date: 2026-10-25
slug: fix-9323-battery-path-gate
branch: feat-one-shot-9323-battery-path-gate
issue: 9323
closes:
lane: engineering
brand_survival_threshold: single-user incident
---

# fix: #9323 battery path-gate — implementation already merged; the soak probe that gates closure could never converge

## Overview

The issue's build work **already shipped**: PR #9324 (merge commit `65cb8c97e1`, merged 2026-10-01)
landed the ADR-262 mechanism — `_diff_touches --pr-gated`, the five `*_BATTERY_PATHS` declarations in
`scripts/lib/test-relevance-paths.sh`, counted `skip_suite` verdicts, the in-runner canary, Guard 1
(`scripts/test-all-pr-battery-gate.test.sh`) and Guard 2 (the `lint-orphan-test-suites.sh` closure
check). This branch's scaffold commit was empty; there was nothing to re-implement.

What remains open on the issue is exactly one acceptance box: *"Re-measure after merge."* That is the
job of the follow-through probe `scripts/followthroughs/pr-battery-gate-saving-9323.sh`, which the
scheduled sweeper runs nightly. **Measured across the 2026-10-09..2026-10-24 sweeps it reported
`NOT YET: 0–12 qualifying run(s) (need >= 20)` and could never converge:**

1. **Window starvation.** The runs query fetched one page — the ~100 most recent completed
   `pull_request` runs, ~24 h at this repo's volume — and a qualifying run is only ~5-15% of a page
   (48% cancelled, 34% failure at last count; bot PRs and machinery-touching PRs are excluded by
   design). `MIN_RUNS=20` inside one page needs a >20% qualifying day.
2. **The deeper defect — a structural deadlock.** The runs API only populates `pull_requests` while
   the PR is *open* (measured 2026-10-25: **2 of 13** successful human runs on the latest page carried
   one). A merged PR's run — the exact set the escape check (arm b) needs — reports the field empty and
   was dropped by the `pr` filter; an open-PR candidate that did get through reaches the escape arm
   with no merge commit and lands in `pending` → NOT YET. At **any** page count the probe could only
   see candidates that could never satisfy arm (b).

**This change fixes the probe, not the gate.** The runs list is paginated (`PAGE_CAP=6`), the
detail scan is bounded (`EXAMINE_CAP=220`), and a run whose `pull_requests` is empty is resolved
through `pulls?head=<owner>:<head_branch>&state=all` before the machinery filter. Neither cap loosens
the bar: `MIN_RUNS` qualifying runs are still required, and a capped scan reports NOT YET, never a
fail. Live verification on 2026-10-25: `qualifying_runs=40 (MAX_RUNS) in 69 candidates across 6 pages`
— versus `3 qualifying` under the old code on the same day.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Issue acceptance: "Batteries declare subject paths; skip counted and printed" | Shipped in #9324: `REGISTRY/CF_TUNNEL/LINT_ORPHAN/TAG_AUTHORSHIP/TEST_ALL_AFFECTED_BATTERY_PATHS` in `scripts/lib/test-relevance-paths.sh`; decline prints `[skip] <label> (relevance)` via `skip_suite` and increments `_relevance_declined`; a PR-context epilogue explains the declines | No work; verified by reading and by Guard 1 green (90 assertions, 34/34 mutants caught) |
| Issue acceptance: "ADR recording the PR-vs-main split and its residual" | `knowledge-base/engineering/architecture/decisions/ADR-262-*.md` (plus ADR-276 amendment): PR arm keys on `GITHUB_EVENT_NAME == pull_request`; `push`, `merge_group`, `workflow_dispatch`, `schedule`, unset, `--full`, `SOLEUR_TEST_FORCE_ALL=1`, undeterminable diff all run; residuals R1-R4 named | No work |
| Issue acceptance: "fail closed when declaration missing" | Missing `test-relevance-paths.sh` → runner `exit 2`; unset/empty/below-floor array → `lint-orphan-test-suites.sh` ERROR (vacuity guard + per-array `MIN` floors + self-inclusion + Guard-2 closure floor of 5 derived `--pr-gated` sites); predicate regression → in-runner canary `PR_GATE_CANARY_FAILED` forces run-all | No work |
| Issue acceptance: "Re-measure after merge" | Probe exists and sweeps nightly, but could never converge (deadlock above) | Phase 1: probe pagination + head-branch resolution + test pins |

## Implementation Phases

### Phase 1: `scripts/followthroughs/pr-battery-gate-saving-9323.sh`

1. Paginate `actions/workflows/ci.yml/runs?event=pull_request&status=completed&per_page=100&created=>MERGED_AT&page=N`
   for `N=1..PAGE_CAP` (6 pages ≈ 6 days at current volume); stop early when a page returns `<100` raw
   runs. Raw page length — not the filtered count — decides whether a next page exists.
2. Emit `branch: (.head_branch // "-")` and `pr: (.pull_requests[0].number // "-")` per candidate;
   `-` placeholders keep the `read` fields aligned (an empty field would shift columns).
3. In the detail loop, a `pr == "-"` candidate resolves via
   `pulls?head=${REPO%%/*}:$branch&state=all&per_page=1` → `.[0].number`; an unresolvable branch is
   skipped (costs one call, never aborts). `state=all` because the merged set is what the escape arm
   needs.
4. `EXAMINE_CAP=220` bounds the detail scan: ≤3 calls per candidate (head lookup when needed, files
   read always, jobs read when it clears the machinery filter) stays inside the sweeper's
   ~1000-requests/hour budget alongside the ≤80-call escape check and ≤6 list calls.
5. The escape arm handles the third PR state head-branch resolution newly admits: a **closed-unmerged**
   PR (`state: closed`, `merged_at` null) is *dropped* — no merge commit will ever exist, so pending it
   would re-create the deadlock — while an open PR still pends (it may merge) and a merged PR gets its
   push run checked. The drop count is printed. (`merge_commit_sha` cannot be the discriminator: the API
   reports the test-merge sha there for open and closed-unmerged PRs alike — verified on #11038.)
6. Print `candidates_examined=$examined pages=$pages` on the `qualifying_runs=` line and in the
   `NOT YET` message, so a starved sweep is diagnosable from the sweeper comment alone.
7. Header comments document the starvation measurement, the `pull_requests`-empty-on-merge quirk, and
   the branch-reuse residual (`.[0]` picks the newest PR on a reused branch — over-inclusion drops the
   candidate conservatively; under-inclusion is a priced rare miss; the alternative is the deadlock).

### Phase 2: `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh`

1. Fake `gh` gains a `pulls?head=*` arm (fixture `head-<branch>.json`, `/`→`_`; absent fixture =
   materialised empty list — it must flow through the `--jq` tail like a real response, not print raw)
   and a `*page=*` arm (`page=1` → `runs.json`; `page=N≥2` → `runs-p$N.json` or a materialised
   `{"workflow_runs":[]}`).
2. New rows: `pg1` (page 1 = 90 bots + 10 head-resolvable humans; page 2 = 15 direct-association runs
   → `qualifying_runs=25` PASS, `page=2` fetched, `pulls?head=` issued); `h1` (a machinery-touching PR
   found via `head_branch` is still excluded; a branch with no PR is looked up then skipped); `d1` (a
   closed-unmerged qualifying PR drops out of the escape check instead of pending forever); a negative
   pin that a `<100`-run page 1 does **not** fetch page 2.
3. Existing rows unchanged: every prior assertion still passes verbatim (30/30 green).

## Guard Contract

### Guard 1 — soak probe exit-code contract (PASS/FAIL/NOT YET/CANNOT ESTABLISH), `pr-battery-gate-saving-9323.test.sh`

**Property.** The probe's verdict is a function only of its four documented conditions — mean saving
≥ 20 runner-min over ≥20 qualifying runs, no red merge-commit push run — and every indeterminate
state (too few runs, unmerged gate PR, pending push run, API failure, xtrace with a credential)
exits non-PASS with its own code. The fix must not loosen the bar: pagination and head resolution
only widen the *candidate pool*; they change nothing about what qualifies or what passes.

**Assembly.** Every verdict flows through four exit sites in the probe: (1) the `n < MIN_RUNS`
NOT-YET arm after the detail loop, (2) the `escapes`/`pending` arms of the push-run check, (3) the
final `awk` comparison against `BASELINE_RUNNER_MIN - REQUIRED_SAVING_MIN`, (4) `fail_api`/`exit 3`/`exit 78`
preconditions. The candidate pool feeds all of them via the accumulated `runs` array, built solely by
the paginated fetch and the per-candidate machinery/jobs filters.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Feed the probe only page 1 of a 2-page fixture (delete `runs-p2.json`; page 1 still full at 100) | The probe fetches page 2, gets `{"workflow_runs":[]}` (`raw_n=0 <100` → break) and grades the 10 head-resolved candidates alone → `NOT YET: 10`, never a pass |
| 2 | Make a head-resolvable PR machinery-touching (`files-555.json` = `scripts/test-all.sh`, `h1` row) | Excluded post-resolution → `qualifying_runs=20` on a 20-qualifying fixture, i.e. the exclusion still applies to resolved PRs |
| 3 | Omit `&page=N` pagination entirely (revert to the single-fetch form) | The `pg1` row goes `NOT YET: 10` instead of `qualifying_runs=25` PASS, and the `page=2` request-log assertion goes RED |
| 4 | Drop the head-branch resolution block (revert to skipping `pr=="-"`) | The `pg1` row reports `NOT YET: 15` (page-2 candidates only), and the `pulls?head=` request-log assertion goes RED |
| 5 | Treat a closed-unmerged qualifying PR as pending instead of dropped (`d1` row) | RED — the `d1` fixture's `NOT YET`/`PASS` split flips: without the drop, `pending` stays >0 and the suite never sees the `"closed unmerged"` note or exit 0 |

**Anchor.** `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` (30 assertions) runs in the
`test-scripts` shard leg 4 (`scripts/suite-shard-legs.tsv`); `PBGS_MIN_ASSERTIONS=22` floors the
suite itself.

## Observability

- The `NOT YET` line now reads `N qualifying run(s) in M candidate(s) across P page(s)` — the sweeper
  comment alone shows whether starvation persists (small M across P=6 pages) or the scan is healthy.
- The `qualifying_runs=` line carries `candidates_examined=` and `pages=` for the same reason.
- `requests.log` assertions pin that `page=2` is fetched iff page 1 was full, and that `pulls?head=`
  lookups are issued for association-less runs.

## Acceptance Criteria

- [x] Probe test suite green: 30/30 assertions (`bash scripts/followthroughs/pr-battery-gate-saving-9323.test.sh`).
- [x] Live probe converges to a verdict-capable pool: `qualifying_runs=40 in 69 candidates across 6 pages` (was: 3), ending at `NOT YET: 5 qualifying PR(s) have no completed push run` — the only remaining gate is the real pending state the arm exists for.
- [ ] Sweeper reports a real verdict (PASS or FAIL) on the next nightly runs; issue #9323 then closes
      on evidence, or stays open on a FAIL — either is a correct outcome. **Note: `mean_runner_min`
      measured 192 vs the pinned 76 baseline** — `test-scripts` has grown to 8 shards × ~12-23 min
      (~143 runner-min) since the 2026-09-30 measurement, so a FAIL on the absolute baseline is the
      likely mechanical verdict; whether that is a gate regression or suite growth is a human
      adjudication the probe was designed to force, and it supersedes this change.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | Issue: "Re-measure after merge: runner-minutes per PR CI run, and `test-scripts` queue wait" | Phase 1 + Phase 2: make the measuring probe convergent | mapped — the only unmet acceptance box |
| 2 | Issue: other acceptance boxes (ADR, declarations, counted skip, main/nightly coverage, fail-closed) | Verified already shipped by #9324; no re-implementation | verified, no diff |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| `pr-battery-gate-saving-9323.sh` (pagination, EXAMINE_CAP, head_branch resolution) | "no escape on the merge-commit push runs", "at least 20 qualifying PR runs" | inferred — the issue requires the measurement; the shipped probe cannot produce it (measured deadlock); the fix preserves every stated threshold |
| `pr-battery-gate-saving-9323.test.sh` (fake-gh arms + rows) | — | inferred — `cq-write-failing-tests-before`; an exit-code contract nothing drives is a comment (the suite's own header) |
| this plan file | — | inferred — one-shot pipeline artifact |

### Split Assessment

- Subsystems touched: 1 — `scripts/followthroughs`
- Planned files: 2 edit + 1 create | Estimated changed lines: ~120
- Recommendation: single PR. **Caveat for ship:** the draft PR body says `Closes #9323`; it should
  say `Refs #9323` — merging must not close the issue ahead of the soak verdict the sweeper issues.

## Risks / Residuals

- **Branch reuse misresolution** — `pulls?head=` `.[0]` picks the newest PR on a reused branch; a
  machinery touch present only in the older PR's diff would be missed. Priced rare; documented in the
  probe header.
- **API budget** — worst case ≈ 6 list + ~3×220 detail + ~80 escape calls; `EXAMINE_CAP` keeps the
  typical case ≪ that, and the probe degrades to CANNOT ESTABLISH (retried) on a 403, never a verdict.
- **Likely FAIL verdict** — see Acceptance Criteria: the pinned 76-runner-min baseline predates ~2.5×
  of suite growth; the probe converging now means the *verdict* lands, which is the point of the soak.
