---
title: "ci: S4 replay no-run cause receipt, ci_runs corroboration, criterion-a re-run"
date: 2026-11-08
slug: ci-s4-replay-norun-cause-hardening
branch: feat-one-shot-10862-norun-investigation
issue: 10862
type: chore
lane: single-domain
closes: 10862
priority: p3-low
domain: engineering
---

## Overview

Issue #10862 asks why 90 of 300 recent main commits routed `no-run` in the S4 affected-index
replay. The read-only investigation already established the cause on 2026-11-07 and posted it as
an issue comment: **the runs existed; GitHub's `?head_sha=` filtered run listing (search-backed)
dropped ~30% of existing runs at collect time** — hypothesis H4, with the locus one level
upstream of the script's client-side `FULL_EVENTS` filter. The budget owner's go-ahead (issue
comment 2026-11-07) authorizes the discriminating `gh api` reads, the cause receipt under the
investigation spec directory, and the criterion-a evidence re-run
(`collect`/`ejections`/`aggregate`/`verdict`) that the source plan gates on it.

Per the plan's decision rule (H3/H4 arm — re-read through the true run, keep the window), this PR:

1. Commits the cause receipt with command output under
   `knowledge-base/project/specs/feat-one-shot-10862-norun-investigation/receipts/`.
2. Hardens `ci_runs` in `scripts/ci-pr-affected-replay.py` so a well-formed empty `?head_sha=`
   answer is no longer authoritative: the listing is retried once, then corroborated through the
   commit-keyed check-runs read (not search-indexed) before any `no-run` verdict is recorded.
3. Re-runs the criterion-a evidence on a fresh window (runbook §4: last 300 first-parent commits
   of `origin/main`, `collect` + `ejections` + `aggregate --expect-commits 300` + `verdict`) and
   commits the receipts. The verdict command is run with the measured criterion-a status and the
   other criteria `unmeasured` — the full go/no-go re-ruling stays where the plan put it: with the
   budget owner, out of this issue's scope.
4. Updates runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
   §4 so the next re-run knows an empty head-sha listing is corroborated, never taken at face
   value.

## Research Insights

**Premise validation (Phase 0.6).** #10862 OPEN, `closedByPullRequestsReferences: []`; no
linked/body-probe PR collision (merged #10851 cites it in prose but `closingIssuesReferences` is
empty — scope is the PR3a ratchet job, different work). Cited issues verified: #10448 CLOSED,
#9729 OPEN (parked parent), #10859 CLOSED (PR3b merged via #12329). Plan authority file exists at
`knowledge-base/project/plans/archive/20261023-144502-2026-10-22-feat-s4-affected-index-pr3-required-ratchet-plan.md`,
section "Parallel track - why 90 of 300 recent main commits route `no-run`". `collision-precheck.sh 10862`
names only this run's own draft PR #12377. No open code-review issue names any planned file
(`gh issue list --label code-review`, jq `contains($path)` per file, 2026-11-08).

**Property list (Phase 0.6b).** P1 the cause is recorded with command output as a receipt under
the spec directory. P2 a `no-run` verdict is never produced from an empty `?head_sha=` answer
alone — a corroborating non-search read must also find no ci.yml push/merge_group run. P3 a unit
whose run the index dropped resolves through the corroborated true run (the H3/H4 decision arm:
re-read through the true run, keep the window). P4 criterion-a arithmetic is re-derived by a fresh
evidence re-run with committed receipts. P5 a failed corroborating read is `runs-read:`
not-evaluable — a failed read is never "no failure", the script's standing invariant.

**Cut list (Phase 0.6b).** (a) Choosing a new replay window — the decision rule already resolved:
"the read was wrong, not the window"; no mechanism buys anything. (b) `ci_runs` lookup by PR
number + time window (the plan's H3 arm) — H3 is refuted by the receipts (runs sit under
`head_sha` = the first-parent commit itself); not built. (c) A bounded `no-evidence` class (the
plan's H5 arm) — H5 refuted (every commit is its own push head_sha); not built.

**Key files.** `scripts/ci-pr-affected-replay.py` — `ci_runs` at `:420`, the sole producer of the
runs list `cmd_collect` classes on (`:623`); the `no-run` reason assignment at `:636`; `gh_text`
/`gh_pages` retry-and-fail-closed read primitives at `:271`/`:285`. Test suite
`plugins/soleur/test/ci-pr-affected-replay.test.sh` — PATH-seamed `gh` stub keyed by request path
(`fx`/`fx_err`/`keyof` at `:196`-`:202`), `DECLARED_TOTAL` mutate-site pin at `:77`, `mutate`/
`mutant_outcome` driver at `:3393`. Runbook §4 commands at
`knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md:104-117`.

**Prior art verified live (2026-11-08).** `GET repos/{r}/commits/{sha}/check-runs` is
commit-keyed, not search-indexed: `check_runs[].details_url` carries
`https://github.com/{r}/actions/runs/{run_id}/job/{job_id}` (verified on `f0c3bb8656`), and
`total_count` can exceed `per_page=100` (152 observed) — corroboration must paginate (`gh_pages`).
`GET repos/{r}/actions/runs/{id}` carries `path` (e.g. `.github/workflows/ci.yml`), `event`,
`head_sha`, `conclusion`, `run_attempt`, `check_suite_id` (verified on run 42452613187).
`scripts/watch-wallclock-p90-11774.sh` already treats an unreadable check-runs response as a
failed read, never an empty answer — the same discipline this fix ports into `ci_runs`.

**Related issues/PRs.** #8770 (the retry/corroborate precedent the cause comment names),
`knowledge-base/engineering/operations/post-mortems/2026-09-24-release-deploy-arm-false-skip-on-lagging-runs-search-postmortem.md`
(same failure class: `event`/`head_sha` are search parameters; the index lagged). PR3b #12329 made
`affected-index-ratchet` and `oracle-review-required` required contexts — `scripts/ci-pr-affected-replay.py`
is an oracle-surface file, so this PR's diff triggers `oracle-review-required`; it passes on
`author == deruelle` (this session's PR author), which is the authored arm, not the review arm.

**Relevant learnings.** A failed READ is never "no failure" — the script's own docstring
(`not-evaluable` class) and `watch-wallclock-p90-11774.sh`'s `::error::every per-run check-runs
read failed` arm both encode it; the fix extends it from failed reads to *wrongly-empty* reads.
Guard-contract gate: the mutation matrix below is derived from the design (a `no-run` needs two
independent empty answers), not from the implementation.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-visible. `ci-pr-affected-replay.py`
  is an evidence/measuring tool and the advisory ratchet job; a wrong change makes a replay
  measurement lie or the advisory job red — no serving surface, no user data.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no vector — the change
  reads public Actions run metadata of this repo and writes receipts under knowledge-base.
- **Brand-survival threshold:** none — machinery-only change to a CI measurement script; the
  canonical sensitive-path regex matches none of the touched files.

## Implementation Phases

### Phase 1 — Cause receipt (spec directory)

`knowledge-base/project/specs/feat-one-shot-10862-norun-investigation/receipts/cause.md`:
the H4 verdict, the per-hypothesis dispositions, and the discriminating command outputs —
re-derived in this session, not pasted blind from the issue comment (the comment is quoted as the
prior finding; each command is re-run and its output embedded).

### Phase 2 — `ci_runs` corroboration + tests

`scripts/ci-pr-affected-replay.py`:

- Split the listing fetch out of `ci_runs` into `head_sha_runs(repo, sha)` (same query, same
  `total_count != len` truncation refusal).
- New `corroborating_runs(repo, sha)`: paginate `commits/{sha}/check-runs` (all pages; the summed
  `check_runs` count must equal `total_count` or the read is refused as truncated), collect
  distinct `/actions/runs/<id>` ids from `details_url` values scoped to
  `github.com/<repo>/actions/runs/` (an external app's check-run links elsewhere — an id taken
  from one could collide with a real run id of THIS repo), fetch each run once, keep runs whose
  `head_sha == sha`, `event in FULL_EVENTS` and `path == ".github/workflows/ci.yml"`.
- `ci_runs(repo, sha)` becomes `(runs, via)`: filtered non-empty on first read →
  `via="head-sha"`; empty → retry once → `via="head-sha-retry"`; still empty → corroborate →
  `via="check-runs"` (runs found) or `via="corroborated-no-run"` (`[]`). Any failed read raises
  `ReadError` — the unit is `runs-read:` not-evaluable, never `no-run`.
- `cmd_collect` records `u["runs_via"]` so the receipt can histogram how units resolved.
- Docstring: the `not-evaluable` description gains that an empty head-sha listing is corroborated
  through check-runs before `no-run` stands.

`plugins/soleur/test/ci-pr-affected-replay.test.sh`:

- Stub: add `fx_once`/`ONCE_<key>` (first call returns the body then deletes it) for the
  retry-heals case.
- Fixture rows: (a) index-dropped listing twice + check-runs → ci.yml run → unit resolves,
  `runs_via=check-runs`; (b) empty listing + empty check-runs → `no-run`,
  `runs_via=corroborated-no-run`; (c) check-runs naming only other-workflow/wrong-sha runs →
  `no-run`; (d) `fx_err` on check-runs → `runs-read:` not-evaluable; (e) `ONCE_` empty then
  non-empty listing → `runs_via=head-sha-retry`, zero check-runs requests; (f) non-empty first
  read → zero check-runs requests (common path costs nothing).
- `mutate` rows: drop-corroboration (empty → `[]`), accept-wrong-sha-run, swallow-check-runs-error;
  `DECLARED_TOTAL` updated by the suite's own count.

### Phase 3 — Runbook §4 update

Name the corroborated `no-run` semantics and the `runs_via` field; point at the cause receipt.

### Phase 4 — Evidence re-run (authorized by the 2026-11-07 go-ahead)

Runbook §4 commands, fresh window, run inside this worktree (the selector files are untouched by
this diff, so the measurement is origin/main-equivalent while exercising the patched collector):

```bash
OUT=/var/tmp/s4-rerun-10862
python3 -I scripts/ci-pr-affected-replay.py collect   --out "$OUT" --commits 300 --chunk I/4 --base origin/main   # I=1..4, parallel
python3 -I scripts/ci-pr-affected-replay.py ejections --out "$OUT" --commits 300 --base origin/main
python3 -I scripts/ci-pr-affected-replay.py aggregate "$OUT" --expect-commits 300 --out "$OUT/replay-summary.txt"
python3 -I scripts/ci-pr-affected-replay.py verdict --a <status> --b unmeasured --c unmeasured --d unmeasured
```

Criterion-a status from the aggregate: `point` ≤ 2% and `cp95_upper_on_worst_case` < 12% → pass,
else the failing arm named. Receipts committed under `receipts/rerun/`: the summary text, the
ejections window meta, the `runs_via`/`reason` histograms (jq over the units files), the four
command invocations with rc.

## Files to Edit

- `scripts/ci-pr-affected-replay.py` (`ci_runs`, `cmd_collect`, docstring `not-evaluable` line)
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` (stub `ONCE_` arm, fixtures, rows, mutations, `DECLARED_TOTAL`)
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (§4 note only)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10862-norun-investigation/tasks.md` (pipeline artifact)
- `knowledge-base/project/specs/feat-one-shot-10862-norun-investigation/decision-challenges.md` (pipeline artifact)
- `knowledge-base/project/specs/feat-one-shot-10862-norun-investigation/session-state.md` (pipeline artifact)
- `knowledge-base/project/specs/feat-one-shot-10862-norun-investigation/receipts/cause.md`
- `knowledge-base/project/specs/feat-one-shot-10862-norun-investigation/receipts/rerun/` (replay outputs)

Explicitly NOT edited: `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` (selector
inputs are the runbook's declared limits), `.github/workflows/ci.yml` (the corroboration lives in
the collector, not the workflow), any ruleset file. The spec-directory convention holds: the
cause receipt lands under THIS branch's spec dir, which is the investigation's.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200) was searched with `jq --arg path`
for `scripts/ci-pr-affected-replay.py`, its suite and the runbook on 2026-11-08: no open issue
names any of them.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change inside `scripts/` and one
test suite. Product tier: NONE (no user-facing surface in Files to Edit/Create).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Find the cause before choosing a window or changing how collect reads commits." [issue #10862] | Phase 1 (receipt lands the already-established H4 cause) | mapped |
| 2 | "Record the cause with command output as a receipt" [issue #10862] | Phase 1, `receipts/cause.md` | mapped |
| 3 | "the criterion-a arithmetic is re-run only by the evidence re-run, which waits for the budget owner's go-ahead" [issue #10862] | Phase 4 (go-ahead recorded 2026-11-07) | mapped |
| 4 | "a merged PR recording the cause ... plus whatever code/doc fix the cause implies" [dispatch brief] | Phases 2-3 (`ci_runs` corroboration, runbook) | mapped |
| 5 | "the criterion-a arithmetic re-run per the plan's decision rule" [dispatch brief] | Phase 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `receipts/cause.md` | "Record the cause with command output as a receipt" | asked |
| `ci_runs` corroboration | "whatever code/doc fix the cause implies" | asked — shape set by the cause comment's H3/H4 recommendation ("treat an empty `?head_sha=` result as non-authoritative: retry and corroborate with a non-search read") |
| `runs_via` unit field | — | inferred — justification: without it the re-run receipt cannot show how each unit resolved (the evidence the fix exists to produce) |
| Runbook §4 note | "whatever code/doc fix the cause implies" | asked |
| Evidence re-run receipts | "the criterion-a arithmetic is re-run only by the evidence re-run" | asked |
| spec-dir artifacts (tasks/session-state/decision-challenges) | — | inferred — justification: the one-shot pipeline's own artifact contract requires them |
| ONCE_ stub arm | — | inferred — justification: the retry-heals case cannot be fixed-shaped without a first-call-only fixture; the stub's keyed-file mechanism is the existing seam |

### Split Assessment

- Subsystems touched: 3 — `scripts`, `plugins/soleur`, `knowledge-base`
- Planned files: 3 edits, ~6 creates | Estimated changed lines: ~350 (SUT ~70, suite ~180, docs ~20, receipts ~80 prose)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — one cohesive investigation+fix unit; receipts are generated data.

## Guard Contract

### Guard 1 — `ci_runs` empty-listing corroboration

**Property.** A `no-run` verdict on a commit unit requires a corroborating commit-keyed read that
finds no ci.yml push/merge_group run for the sha; an empty `?head_sha=` listing — alone or after
one retry — never produces `no-run`, and a failed corroborating read produces `runs-read:`.

**Assembly.** `ci_runs()` is the chokepoint: it is the sole producer of the runs list
`cmd_collect` classes on, and the only path to a `no-run` reason. The corroborating read is
`commits/{sha}/check-runs` (commit-keyed) resolved through `actions/runs/{id}` — never another
search-parameter listing of the same index class.

**Mutation matrix.**

| Edit (design-level) | Expected | Suite driver |
|---|---|---|
| Empty listing accepted as authoritative (no retry, no corroboration) | index-dropped fixture unit → `no-run` instead of clean via the corroborated run | row (a) |
| Corroborate but skip the `head_sha`/`path`/`event` filter | check-runs naming only an other-workflow or other-sha run still resolves the unit | row (c) |
| A failed check-runs read treated as "no runs" | `fx_err` check-runs fixture → `no-run` instead of `runs-read:` not-evaluable | row (d) |
| Guard never fires on the common path (corroboration wired wrong — e.g. corroborating on every read, doubling cost and silently depending on check-runs) | non-empty listing must make zero check-runs requests | row (f) REQ-count assertion |

Harness rows: the `ONCE_` arm is the suite-side mechanism the retry-heals case (e) needs — deleting
it makes (e) unfixable and is a suite-edit red; the must-PASS non-canonical input is (c):
check-runs present but pointing at no ci.yml run is a *correct* `no-run`, not an error.

**Anchor.** Not a stored-value comparison — the property is read-time corroboration, no hash or
manifest to anchor against.

## Acceptance Criteria

- AC1: `receipts/cause.md` under the spec dir names the H4 cause, the per-hypothesis dispositions
  and the discriminating command outputs, re-derived this session.
- AC2: `ci_runs` returns `(runs, via)`; an empty filtered listing is retried once then
  corroborated via `check-runs` + `actions/runs/{id}`; corroboration-filter requires
  `head_sha == sha`, `event in FULL_EVENTS`, `path == ".github/workflows/ci.yml"`.
- AC3: A unit whose listing the index dropped resolves through the corroborated run
  (`runs_via=check-runs`); a unit with corroborated-empty reads stays `no-run`
  (`runs_via=corroborated-no-run`); a failed corroborating read is `runs-read:` not-evaluable.
- AC4: `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` exits 0 including the new fixture
  rows and mutation kills; `DECLARED_TOTAL` updated.
- AC5: `receipts/rerun/` carries the re-run commands, `replay-summary.txt`,
  `ejections-window.json`, the `runs_via` and `reason` histograms, and the `verdict` output line;
  the criterion-a status is computed from the printed `point`/`cp95_upper_on_worst_case` values
  against the ≤2%/<12% bars and stated in the receipt.
- AC6: Runbook §4 names the corroborated `no-run` semantics and `runs_via`.
- AC7: `python3 -I scripts/ci-pr-affected-replay.py ratchet` exits 0 on this branch (required
  check green; the audit must see no new gap pairs from the suite's new literal strings).

## Test Scenarios

- `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` — full suite green (mutations included).
- `python3 -I scripts/ci-pr-affected-replay.py ratchet` on this branch — exit 0.
- Evidence re-run (Phase 4) completes with `aggregate` exit 0 and the summary committed.
- A one-shot smoke: `collect --commits 2 --out /tmp/x` against the real repo resolves both units
  with `runs_via` set — proves the live `gh` seam end to end.

## Risks & Mitigations

- **Risk:** corroboration multiplies `gh` calls during an index outage (~40 run fetches per
  affected sha). **Mitigation:** it only fires on the empty-after-filter path, run ids are
  deduped, and each fetch goes through the retried `gh_text`; a real outage degrades to slower
  not-evaluable reads, never wrong verdicts.
- **Risk:** `details_url` shape changes upstream. **Mitigation:** ids come from a regex over
  `details_url`; a check-run without one is skipped, and with zero corroborating runs the unit is
  `corroborated-no-run` — the failure direction is the old (conservative) verdict, except where
  check-runs names ci.yml runs, which is what it must find.
- **Risk:** the re-run's fresh window lands inside a new index outage. **Mitigation:** that is
  exactly what the fix exercises — `runs_via` histogram shows the corroboration at work; the
  receipt states whichever way the units resolved.

## Sharp Edges

- Do NOT trust the numbers quoted from the issue comments — every figure in `receipts/cause.md`
  is re-derived by re-running the named command this session (the plan's "re-derive, do not
  trust" rule).
- The re-run must use `--base origin/main` on the FRESH window (runbook §3/§4: "re-run on a
  fresh window"), not `-n 300` against the stale October tip.
- `verdict` is arithmetic only: it exits 0 whatever it prints — record `computed=`, never the rc.
- `gh pr checks` cannot see a required check that has not been created — ship's own poll owns the
  merge wait; this plan's `oracle-review-required` exposure is the authored arm only.
- Known residual, recorded not fixed: `ejections` reads `?event=merge_group&created=…`, the same
  search-index class, and its `total_count == len` check cannot see a dropped entry (the count is
  index-computed too). The issue's deliverable is collect's `no-run`; the receipt names this.
