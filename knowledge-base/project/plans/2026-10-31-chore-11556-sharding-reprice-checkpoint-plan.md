---
title: "chore: epic #11556 post-merge closeout — re-price sharded test-scripts arms from real CI timings"
date: 2026-10-31
slug: 11556-sharding-reprice-checkpoint
branch: feat-one-shot-11556-reprice-checkpoint
issue: 11556
type: chore
lane: cross-domain
---

## Overview

The Lever-A arm-sharding slice of epic #11556 merged 2026-10-30 (merge commit
8598aae15e, PR #11561) with seeded arm prices in `scripts/suite-durations.tsv`
(CI-median x local-share estimates). The runbook's ownership checkpoint
(`knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`,
"Measured history", 2026-10-30 entry) requires re-pricing those arms from the
first green post-merge artifact runs. Eight green ci.yml runs now carry real
`suite-timings-scripts-*` artifacts (6 merge_group + 2 pull_request; main push
runs elide the shards job so `--runs` cannot aggregate them). This checkpoint:
downloads the artifacts per run, produces the measured table via
`regenerate-shard-manifest.py --timings-dir ... --manifest`, re-prices the
committed tables via the incumbent-preserving `--durations` seed (CTO ruling,
2026-10-31 — see `decision-challenges.md`), verifies observed leg
spread vs the ~28-min worst-leg prediction, records measured legs in the
runbook, and restores the lost session-state Updates 18-19 (enqueue + merge
record) that sit uncommitted in the stale `feat-11556-required-check-time`
worktree.

## Enhancement Summary

**Deepened on:** 2026-10-31 (sequential-fallback — all gates and review lenses
run inline; no subagents spawned)
**Sections enhanced:** User-Brand/Observability (new `## Observability`
section), Phase 4 runbook workstream, Acceptance Criteria (AC-8)
**Research agents used:** repo-research-analyst + learnings-researcher roles
(inline, plan Phase 1); eng review panel (dhh/kieran/code-simplicity lenses,
inline); CTO devex lens (inline); spec-flow edge-case pass (inline)

### Key Improvements

1. `## Observability` added — deepen-plan Phase 4.7's detection counts the
   two committed TSVs as non-docs; the section documents the pre-existing
   verification surface (shard lint + artifact wall clocks) and declares a
   compliant `grep` discoverability probe.
2. Mechanical plan-review findings applied: AC-8 now enumerates
   pipeline-written artifacts (INDEX.md, tasks.md, spec-dir files) so the
   diff-scope AC is true on the final tree; the runbook edit also fixes the
   `-n 'suite-timings-*'` exact-name flag to `-p 'suite-timings-scripts-*'`.
3. All deepen halt gates verified: User-Brand (valid `none`, no sensitive
   paths), PAT, UI-wireframe, Encryption, Guard Contract, Scope Check (1
   unfenced, all subsections, no BLOCKED/unmapped), Task-Design — pass.

### New Considerations Discovered

- **#9763 fast-tier ratchet interaction (deciding):** a direct
  `--timings-dir --write` re-prices the 8 always-on drifters #11648 tracks to
  real 11-378 s weights → `test-all-fast-tier-budget.test.sh` reds on the
  committed-weight caps (10 s/suite, 300 s total; current: 120 labels /
  200,061 ms / 0 over-cap — measured 2026-10-31). Resolved via the
  incumbent-preserving `--durations` seed — the same mechanism merge commit
  `8598aae15e` used ("incumbent-preserving regen via --durations seed" in its
  own commit body). Recorded as `pending - assumed` technical ruling in
  `decision-challenges.md` for parent escalation to `soleur:engineering:cto`.
- Attribution verified live: `8598aae15e` is an ancestor of `origin/main`;
  #11562 CLOSED (the split issue this checkpoint closes out); rule id
  `cq-ac-must-not-depend-on-concurrent-sessions` confirmed active-migrated;
  `timeout-minutes: 60` on the test-scripts job verified at ci.yml:1494;
  `gh run download -p` glob flag verified via `--help`.
- Precedent-diff gate: the seed-regen mechanism has in-repo precedent
  (`8598aae15e`) — not novel.

## Research Insights

_Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed)._

### Relevant file paths

- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` —
  the authority. "Measured history" 2026-10-30 entry ends with the ownership
  checkpoint: re-check leg spread + worst leg on the first green post-merge
  PR/merge_group runs; their `suite-timings-*` artifacts are the re-price input;
  main `push` runs elide the shards job so `--runs` is NOT usable.
- `scripts/regenerate-shard-manifest.py` — `--timings-dir` is repeatable, one
  run per dir (`LIGHT_ARTIFACT = ^suite-timings-scripts-\d+$`, line 121; nested
  `*/suite-timings.tsv` glob, line ~246); folds each run's TSVs into
  `{label: ms}` and medians across runs; `--write` emits BOTH
  `scripts/suite-shard-legs.tsv` (sticky-LPT re-seat) and
  `scripts/suite-durations.tsv`. Dry-run (no `--write`) prints predicted per-leg
  totals + incumbent diff.
- `scripts/suite-durations.tsv` — committed arm rows today (src=measured, from
  `durations:seed-durations.tsv` provenance): `ci-pr-affected-replay-a/b/c` =
  635037/336324/351151 ms; `test-all-affected-a/b/c/d` =
  153713/912865/297241/382585 ms.
- `scripts/suite-shard-legs.tsv` — current arm→leg map: replay-{a→2, b→7, c→4};
  affected-{a→4, b→1, c→8, d→3}. Leg 1 carries `test-all-affected-b` at a seeded
  912865 ms (~15.2 min) — the seeded worst leg.
- `.github/workflows/ci.yml` — `test-scripts` job (line 1428): `if:` runs on
  merge_group + pull_request + non-elided push; uploads
  `suite-timings-scripts-${{ strategy.job-index }}` (0-7) with `if: always()`
  at line 1641, retention 14 days. `push-dedupe` elides the job on main pushes —
  the mechanism behind "main push runs carry no artifacts."
- `plugins/soleur/test/scripts-shard-manifest.test.sh:284-320` — the lint over
  the durations tables: well-formed `label<TAB>ms<TAB>src` rows, `src ∈
  {measured, floor}`, keys == sibling manifest keys. Sibling suites:
  `regenerate-shard-manifest.test.sh`, `scripts-shard-totality.test.sh`,
  `scripts-shard-runtime-coverage.test.sh`.
- `knowledge-base/project/specs/archive/20261030-170617-feat-11556-required-check-time/session-state.md`
  — ends at Update 17 on main; stale worktree
  `.worktrees/feat-11556-required-check-time` holds the uncommitted Updates
  18-19 diff (verified present).
- Open deferrals: #11647 (`--rows` arm debt), #11648 (always-on fast-tier
  drift — 8 labels exceed the 10 s committed cap), #11654 (KB-archive early
  warning).

### Premise validation (Phase 0.6)

- Cited issues all OPEN: #11556 (epic, this plan's umbrella), #11647, #11648,
  #11654 — none block; #11648 is adjacent (see interplay note).
- Merge commit `8598aae15e` (PR #11561) is on main; every cited path exists on
  `origin/main`.
- All 8 run ids verified via `gh run view`: green `CI` runs — merge_group
  41132662609, 41136687119, 41138355176, 41141190932, 41146395715, 41180934660;
  pull_request 41133279254, 41135223254.
- Stale-worktree diff confirmed: `git -C .worktrees/feat-11556-required-check-time
  diff` shows Updates 18-19 appended to the archived session-state.md.
- Collision precheck (`collision-precheck.sh` ×4): no open PRs cite the issues;
  two foreign `test-all.sh` processes (pids 948828, 965577) run in
  `.worktrees/feat-one-shot-11578-ruling-gate-midnight-flake` — reported;
  non-colliding for a data/docs PR.
- CLI-verification (Phase 6 gate, verified 2026-10-31 via `gh run download
  --help`): glob selection is `-p/--pattern`, target dir is `-D/--dir`. The
  runbook's documented `-n 'suite-timings-*'` is loose — `-n` is exact-name;
  the plan prescribes `-p 'suite-timings-scripts-*' -D <dir>`.

### Property list (Phase 0.6b)

1. Committed light-group arm prices in `scripts/suite-durations.tsv` reflect
   real CI-measured medians, not seeded estimates.
2. `scripts/suite-shard-legs.tsv` re-seats drifted rows if measured weights
   require (sticky-LPT).
3. Observed leg spread + worst leg measured from the 8 runs and compared
   against the ~28-min bound the split was predicted to deliver.
4. The runbook's "Measured history" records the measured legs and the re-price
   outcome (ownership-checkpoint closure).
5. Session-state Updates 18-19 (enqueue + merge record) restored to the
   archived file.

### Cut list (Phase 0.6b)

- **Committed download/aggregation helper script** → property: per-run artifact
  fetch → covered by the runbook's documented `gh run download` idiom; this is
  a one-time checkpoint, not recurring machinery.
- **Automation/CI for future re-pricing** → property: periodic re-price →
  deliberately out of scope: the `ci-leg-balance-9232` soak closed 2026-09-30
  and re-pricing stays a manual runbook procedure; filing automation would
  duplicate #11648/#11647 territory.

### Institutional learnings

- `knowledge-base/project/learnings/2026-02-22-worktree-loss-stash-merge-pop.md`
  — uncommitted work in a stale worktree is fragile; reproduce the diff
  verbatim and commit it early in the work phase, before any rebase/cleanup
  can lose it again.
- `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`
  — two-stage `--json` + standalone `jq --arg` for the jobs-API measurement;
  `gh --jq` does not forward `--arg`.
- `knowledge-base/project/learnings/2026-05-12-ci-test-job-speedup-replan-and-validation-mechanics.md`
  — validation-mechanics pitfalls: verify against measured runs, not the
  committed estimate (the exact error mode this checkpoint exists to fix).
- `knowledge-base/project/learnings/2026-06-29-ci-backstop-already-in-test-shard-and-empty-stdin-body-wipe.md`
  — the deterministic check usually already exists; here the shard lint
  (`scripts-shard-manifest.test.sh`) is the verification suite, no new gate.

### External research

Skipped — the task is repo-internal bookkeeping over repo-owned machinery
(regen script + runbook procedure); no external best-practice surface.

### Functional overlap (Phase 1.5b — sequential-fallback)

Community registries cannot cover a repo-specific regen invocation +
runbook bookkeeping task; no overlap, nothing installed.

### Conventions

- Issue shape: `type/chore`, `domain/engineering`, `priority/p1-high`-class
  bookkeeping under the #11556 epic.
- Durations-table `src` enum is `{measured, floor}` — lint-enforced; the re-price
  legitimately keeps `measured` (now honest) and may introduce `floor` rows for
  labels absent from all 8 inputs — the dry-run "0 at floor" check is the
  runbook's stated precondition for `--write`.
- Runbook merge-conflict rule: TSV conflicts regenerate, never hand-merge.

# chore: epic #11556 post-merge closeout — re-price sharded test-scripts arms from real CI timings

## Problem Statement / Motivation

PR #11561 (epic #11556 Lever-A, merged 2026-10-30 as `8598aae15e`) split the two
atomic mega-suites into in-runner `--rows` arms:
`plugins/soleur/test/ci-pr-affected-replay-{a,b,c}` and
`scripts/test-all-affected-{a,b,c,d}`. Their committed prices in
`scripts/suite-durations.tsv` are seeds (CI-median x local arm-share), so the
manifest's leg packing is built on estimates. The runbook's ownership
checkpoint records the obligation: re-price once the first green post-merge
runs carry real arm timings, and verify the ~28-min worst-leg bound the split
was predicted to deliver (pre-split measured worst legs: 49.4 / 51.0 / 43.2
min on the three-run baseline). Eight green runs now carry that data. Until the
re-price lands, the committed table mis-prices the seven heaviest labels in the
light group — and every `--incremental` regen keeps packing on the seeds.

A second, unrelated piece of lost state rides along: session-state Updates
18-19 (enqueue + merge record) sit uncommitted in the stale
`.worktrees/feat-11556-required-check-time` worktree and were never committed
anywhere. The diff is captured verbatim at
`knowledge-base/project/specs/feat-one-shot-11556-reprice-checkpoint/session-state-updates-18-19.patch`.

## Proposed Solution

One bookkeeping PR with four workstreams:

1. **Capture inputs.** Download `suite-timings-scripts-*` artifacts from the 8
   named green runs into per-run directories (one run per dir — the
   `--timings-dir` contract). Verify each dir holds all 8 leg artifacts.
2. **Measure.** Produce the fully-measured scratch table (8-dir aggregation),
   extract per-run leg sums for the observed-spread record, and read per-leg
   wall clocks from the jobs API — the same method the 2026-10-30 baseline
   entry used.
3. **Re-price (incumbent-preserving).** Feed the regen a durations seed equal
   to the committed table with the 7 arm rows replaced by measured medians —
   the identical mechanism the merge commit itself used ("incumbent-preserving
   regen via --durations seed" — `8598aae15e` commit body) so the #9763
   fast-tier budget ratchet stays green while arm prices become honest. A full
   `--timings-dir --write` is rejected as the default: it re-prices all ~600
   labels including the 8 always-on drifters #11648 tracks, which reds
   `scripts/test-all-fast-tier-budget.test.sh` (committed-weight caps 10 s /
   300 s; today: 120 labels, 200 s, 0 over-cap) and silently folds a deferred
   scope-out into this PR. Recorded as a pending technical ruling — see
   `decision-challenges.md`.
4. **Record + restore.** Append the measured-legs entry to the runbook's
   "Measured history" (closing the ownership checkpoint), note the observed
   always-on drift as evidence on #11648, and apply the session-state patch
   verbatim to the archived file.

## Implementation Phases

### Phase 1 — Artifact capture (no committed output)

```bash
WORK="$(mktemp -d -t reprice-11556.XXXXXXXX)"
for r in 41132662609 41136687119 41138355176 41141190932 41146395715 \
         41180934660 41133279254 41135223254; do
  mkdir -p "$WORK/$r"
  gh run download "$r" -p 'suite-timings-scripts-*' -D "$WORK/$r"
done
# Completeness gate: every run dir must hold 8 leg files (K=8 light matrix).
for r in "$WORK"/*/; do
  n=$(find "$r" -name suite-timings.tsv | wc -l); echo "$r $n"
done
```

- `-p/--pattern` is the glob flag (`-n/--name` is exact-name) — verified
  2026-10-31 via `gh run download --help`. The runbook's documented
  `-n 'suite-timings-*'` spelling is loose; use `-p`.
- Each artifact extracts as `<dir>/suite-timings-scripts-<i>/suite-timings.tsv`
  — the nested `*/suite-timings.tsv` shape `fetch_timings_from_dir` globs
  (`scripts/regenerate-shard-manifest.py` ~line 246).
- Completeness gate: a dir short of 8 leg files means a leg failed before
  upload or retention expired — drop that dir from inputs AND record it in the
  runbook entry; do not let a partial run skew the median. Fewer than 3 usable
  dirs aborts the checkpoint (re-list newer green merge_group/PR runs per the
  runbook's `Re-deriving leg composition` method).
- Retention note: artifacts live 14 days; these runs are 2026-10-30/31 — if the
  work phase runs late, re-list fresh runs first.

### Phase 2 — Measure observed legs + produce measured table

```bash
# Fully-measured scratch emission — redirected --manifest keeps committed files
# untouched (durations pair lands beside it; regen ~line 634-640).
python3 scripts/regenerate-shard-manifest.py \
  --timings-dir "$WORK/41132662609" --timings-dir "$WORK/41136687119" \
  --timings-dir "$WORK/41138355176" --timings-dir "$WORK/41141190932" \
  --timings-dir "$WORK/41146395715" --timings-dir "$WORK/41180934660" \
  --timings-dir "$WORK/41133279254" --timings-dir "$WORK/41135223254" \
  --manifest "$WORK/measured-legs.tsv" --write
# Produces $WORK/measured-legs.tsv + $WORK/measured-legs.tsv.durations.tsv
```

- Record the dry-run-equivalent report (per-leg predicted totals, spread,
  floor count, moved/new/gone vs incumbent) for the runbook entry.
- **Floor check:** any registered label absent from all 8 inputs tables at
  floor (`src=floor`). Require the 7 arm labels to be measured — an arm at
  floor means the premise is broken (timing log does not carry arm labels) and
  the checkpoint halts for diagnosis. Non-arm floor rows are tolerable (labels
  registered after the staged runs); list them in the runbook entry.
- **Observed leg spread (the verification the ask names):** per run, sum each
  leg's `suite-timings.tsv` rows (suite-time per leg; add ~30 s setup to
  compare against wall) AND read `test-scripts (k/8)` job wall clocks via the
  two-stage jobs-API form (`gh api repos/.../runs/<id>/jobs` piped to
  standalone `jq` — `gh --jq` does not forward `--arg`). Compare worst leg vs
  the ~28-min bound and vs the 43-51 min pre-split baseline; record per-run
  spread. Both surfaces land in the runbook entry (suite sums isolate packing;
  wall clocks include queue/setup — the baseline entry distinguishes them).

### Phase 3 — Incumbent-preserving re-price + commit

```bash
# Seed = committed table with the 7 arm rows' ms replaced by the measured
# medians (src stays "measured"). Same shape as the merge commit's seed.
awk -F'\t' 'NR==FNR { if ($1 ~ /(ci-pr-affected-replay-[abc]|test-all-affected-[abcd])$/) m[$1]=$2; next }
  { if ($1 in m) $2=m[$1]; print }' OFS='\t' \
  "$WORK/measured-legs.tsv.durations.tsv" scripts/suite-durations.tsv \
  > "$WORK/seed-durations.tsv"
python3 scripts/regenerate-shard-manifest.py \
  --durations "$WORK/seed-durations.tsv" --write
```

- `--durations` is the top of source precedence; `--write` re-emits
  `scripts/suite-shard-legs.tsv` (sticky-LPT re-seat against honest arm
  weights) and `scripts/suite-durations.tsv` with provenance
  `durations:seed-durations.tsv`. Expected committed diff: the 7 arm rows +
  any floor re-derivation + manifest re-seat — bounded, reviewable.
- **Verify before commit:** dry-run the same command first and read the
  incumbent-diff summary (moved/new/gone); the 7 arm legs may re-seat, that is
  the point. Confirm `scripts-shard-manifest.test.sh` expectations: keys ==
  keys, `src` enum clean, n=8.
- Run the local shard verification set:
  `plugins/soleur/test/scripts-shard-manifest.test.sh`,
  `regenerate-shard-manifest.test.sh`, `scripts-shard-totality.test.sh`,
  `scripts-shard-runtime-coverage.test.sh`, and
  `scripts/test-all-fast-tier-budget.test.sh` (must stay GREEN — that is the
  load-bearing property of the chosen path).
- Merge-conflict rule (runbook): if this branch's TSVs conflict on rebase,
  regenerate — never hand-merge.

### Phase 4 — Record + restore + report

- Append a `**2026-10-31 post-merge re-price (#11562 checkpoint):**` bullet to
  the runbook's `## Measured history`: the 8 input run ids, measured leg
  spread (suite-time + wall, per run), arm medians before/after, post-reprice
  predicted worst leg vs the ~28-min bound, floor count, and a pointer to the
  #11648 drift evidence (the measured table shows the 8 always-on labels at
  real values — carry the numbers, the demotion stays deferred).
- Same runbook edit, one mechanical fix: the `Re-deriving leg composition`
  section prescribes `gh run download <run-id> -n 'suite-timings-*'` — `-n` is
  exact-name and matches nothing; correct it to `-p 'suite-timings-scripts-*'`
  (verified 2026-10-31 via `gh run download --help`).
- Apply
  `knowledge-base/project/specs/feat-one-shot-11556-reprice-checkpoint/session-state-updates-18-19.patch`
  to `knowledge-base/project/specs/archive/20261030-170617-feat-11556-required-check-time/session-state.md`
  verbatim (`git apply`); commit early in the work phase — the source diff is
  uncommitted in a stale worktree and dies with it.
- Post the measured always-on medians as a comment on #11648 (evidence for
  the deferred demotion).

## Technical Considerations

- **Why not `--runs` / `--run`:** those aggregate green *main* runs; main
  `push` events elide `test-scripts` via `push-dedupe` (`.github/workflows/ci.yml:1430`),
  so main runs carry no `suite-timings-scripts-*` artifacts. `--timings-dir`
  over the named merge_group/PR runs is the only path — the runbook says so.
- **Why not a full `--timings-dir --write`:** see Proposed Solution item 3 —
  it is honest but reds the #9763 budget ratchet and imports #11648's
  demotion scope. Pending technical ruling in `decision-challenges.md`; the
  assumed default is the incumbent-preserving seed path.
- **Sticky-LPT:** incumbents keep their leg within 5% of optimal — the re-price
  re-seats only what the honest weights require; expect arm-adjacent churn.
- **`-<letter>` rule:** arms of one suite must sit on distinct legs — the
  totality suite asserts it; verify post-reprice.
- **NFR:** none — generated-data refresh + docs.
- **#11648 interplay:** the measured scratch table makes the 8 drifting
  always-on labels' real weights visible; recording them is evidence, demoting
  them is out of scope.

## User-Brand Impact

- **If this lands broken, the user experiences:** a mis-packed `test-scripts`
  leg set — CI wall time on their PR's required checks regresses toward the
  40-50 min pre-split shape with no failure signal (the plugin's own users hit
  the same required-check wait the epic is cutting).
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing — committed data is CI suite durations already derived from public
  CI artifacts; no secret surface.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** bookkeeping over generated CI data +
  docs; worst case is slow CI, a convenience impact, not data/trust loss.

## Observability

(Not a new observability surface — this section exists because deepen-plan
Phase 4.7's detection counts the two TSVs in Files to Edit as non-docs. The
verification surface below is entirely pre-existing: no probe, alert, or
monitor is introduced by this change.)

```yaml
liveness_signal:
  what: test-scripts per-leg wall clocks and suite-time sums from the suite-timings-scripts-* artifacts, plus the committed provenance header
  cadence: per CI run (merge_group / pull_request); the Measured-history cadence is the reading of them
  alert_target: PR required-check failure; manual runbook checkpoint (the ci-leg-balance-9232 soak closed 2026-09-30 — the documented gap this checkpoint reads by hand)
  configured_in: .github/workflows/ci.yml (test-scripts job) and plugins/soleur/test/scripts-shard-manifest.test.sh
error_reporting:
  destination: PR required-check failure on the consuming run
  fail_loud: scripts-shard-manifest.test.sh exits non-zero on malformed rows / src-enum / keys!=keys violations; a leg over timeout-minutes: 60 fails the job loudly
failure_modes:
  - mode: malformed or key-drifted committed tables degrade the packing
    detection: scripts-shard-manifest.test.sh + scripts-shard-totality.test.sh on every PR
    alert_route: PR required-check failure
  - mode: stale prices drift legs past peers (the class this checkpoint reads)
    detection: per-leg wall clocks and suite sums from suite-timings-* artifacts, read per the runbook
    alert_route: manual runbook ownership checkpoint (this plan's Phase 2 measurement)
logs:
  where: ci.yml suite-timings-scripts-N artifacts + committed TSV provenance headers (generated-from-runs)
  retention: 14 days (artifacts); git history (tables)
discoverability_test:
  command: grep -h 'generated-from' scripts/suite-durations.tsv
  expected_output: generated-from
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI bookkeeping over generated
data files and ops docs. (Product/UX gate: no UI-surface file in either Files
list — override does not fire. Domain leaders not spawned; sequential-fallback
single-pass assessment.)

## GDPR / IaC / ADR / Encryption / Guard / Task-Design gate notes

- **GDPR (2.7):** skipped — no regulated-data surface; no (a)-(d) trigger
  (no LLM processing, threshold `none`, no KB-reading cron, no new
  distribution surface).
- **IaC (2.8):** skipped — no infrastructure introduced; `gh run download` /
  `gh api` reads are not provisioning.
- **ADR/C4 (2.10):** skipped — no architectural decision; the sharding
  architecture landed in #11561.
- **Encryption (2.11):** skipped — no new store or cross-component connection.
- **Guard Contract (2.12):** skipped — the deliverable contains no guard; the
  shard lint suites are pre-existing verification.
- **Task Design (2.9.3):** skipped — no new autonomous-task surface.

## Open Code-Review Overlap

One hit: `#10245 review: merge-queue learning on PR 9707` mentions a
`session-state.md` — a different file
(`specs/feat-one-shot-9614-9618-canary-capture-fixture/session-state.md`), not
the archived `20261030-170617` file this plan edits. **Disposition:**
acknowledge — no shared file, no fold-in. All other planned paths: no open
code-review issue bodies reference them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "download all suite-timings-scripts-* artifacts from those runs into per-run dirs" | Phase 1 | mapped |
| 2 | "re-price via `python3 scripts/regenerate-shard-manifest.py --timings-dir <dir> [repeated] --write` (main push runs elide the shards job so `--runs` is NOT usable — the runbook says so explicitly)" | Phases 2-3 — `--timings-dir` produces the measured table; the committed `--write` runs via `--durations` seed to keep the #9763 budget green (pending ruling — see decision-challenges.md) | mapped |
| 3 | "verify observed leg spread vs the ~28-min worst-leg prediction" | Phase 2 observed-spread block + AC-4 | mapped |
| 4 | "record the measured legs in the runbook's Measured history" | Phase 4 first bullet | mapped |
| 5 | "reproduce that content on this branch" (session-state Updates 18-19) | Phase 4 `git apply` of `session-state-updates-18-19.patch` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Per-run download loop + completeness gate | "download all suite-timings-scripts-* artifacts from those runs into per-run dirs" | asked |
| Measured scratch table via redirected `--manifest --write` | "re-price via `python3 scripts/regenerate-shard-manifest.py --timings-dir <dir> [repeated] --write`" | asked |
| Jobs-API leg wall measurement | "verify observed leg spread vs the ~28-min worst-leg prediction" | asked |
| `--durations` seed committed re-price | "re-price via `python3 scripts/regenerate-shard-manifest.py --timings-dir <dir> [repeated] --write`" | inferred — justification: a direct `--timings-dir --write` reds the #9763 fast-tier budget ratchet on pre-existing drift (#11648, deferred); the merge commit's own "incumbent-preserving regen via --durations seed" is the sanctioned mechanism that delivers honest arm prices without importing deferred scope |
| Runbook Measured-history entry | "record the measured legs in the runbook's Measured history" | asked |
| `session-state-updates-18-19.patch` apply | "reproduce that content on this branch" | asked |
| #11648 evidence comment | — | inferred — justification: the checkpoint already produces the measured values the deferred issue needs; a comment carries them at zero diff cost |
| `session-state-updates-18-19.patch` capture artifact | "reproduce that content on this branch" | inferred — justification: the source diff is uncommitted in a stale worktree; the patch freezes it against worktree cleanup before the work phase applies it |

### Split Assessment

- Subsystems touched: 2 — `scripts` (2 generated TSVs), `knowledge-base` (runbook + archive session-state + spec artifacts)
- Planned files: 5 | Estimated changed lines: ~230 (mostly regenerated TSV rows)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `scripts/suite-durations.tsv` — regenerated via `--durations` seed; the 7 arm
  rows move to measured medians
- `scripts/suite-shard-legs.tsv` — regenerated manifest (sticky-LPT re-seat,
  provenance `durations:seed-durations.tsv`)
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` —
  new Measured-history entry
- `knowledge-base/project/specs/archive/20261030-170617-feat-11556-required-check-time/session-state.md`
  — Updates 18-19 appended verbatim via the captured patch

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-11556-reprice-checkpoint/session-state-updates-18-19.patch`
  — the captured diff (created at plan time, 2026-10-31)

## Acceptance Criteria

- [ ] **AC-1 — Artifacts complete.** For every one of the 8 run ids, a per-run
  dir exists containing exactly 8 `suite-timings.tsv` leg files; any
  incomplete/expired dir is excluded and named in the runbook entry (≥3
  complete dirs or the checkpoint aborts with a re-list note).
- [ ] **AC-2 — Arm prices measured.** In committed
  `scripts/suite-durations.tsv`, each of the 7 arm rows
  (`ci-pr-affected-replay-{a,b,c}`, `test-all-affected-{a,b,c,d}`) carries
  `src=measured` and an ms equal to the median of that label's per-run max
  across the included dirs (verified by recomputation against
  `$WORK/*/suite-timings-scripts-*/suite-timings.tsv`).
- [ ] **AC-3 — Incumbents preserved.** Every non-arm `measured` row in
  `scripts/suite-durations.tsv` is byte-identical to its pre-PR value;
  `src=floor` rows may re-derive (list them in the runbook entry).
- [ ] **AC-4 — Spread recorded + bound checked.** The runbook's Measured
  history carries a dated entry with: the 8 run ids, per-run worst-leg
  suite-time and wall-clock, per-run leg spread, and an explicit verdict vs
  the ~28-min bound. If the observed post-split worst leg exceeds ~28 min, the
  entry says so and the post-reprice predicted worst leg is quoted from the
  regen report instead of silently passing.
- [ ] **AC-5 — Lint green.** `scripts-shard-manifest.test.sh`,
  `regenerate-shard-manifest.test.sh`, `scripts-shard-totality.test.sh`,
  `scripts-shard-runtime-coverage.test.sh`, and
  `scripts/test-all-fast-tier-budget.test.sh` all pass on the branch.
- [ ] **AC-6 — `-<letter>` rule holds.** Post-reprice, same-suite arm labels
  occupy distinct legs in `scripts/suite-shard-legs.tsv` (verified by the
  totality suite AND a direct read).
- [ ] **AC-7 — Session-state restored.** The archived session-state.md tail
  matches `session-state-updates-18-19.patch` applied cleanly
  (`git apply --check` before apply); Updates 18-19 appear verbatim after
  Update 17.
- [ ] **AC-8 — No collateral.** `git diff --name-only` on the merged diff
  touches only: the 4 content files (2 TSVs, runbook, archived
  session-state.md) plus this branch's planning artifacts —
  `knowledge-base/project/specs/feat-one-shot-11556-reprice-checkpoint/{session-state-updates-18-19.patch,tasks.md,decision-challenges.md,session-state.md}`,
  `knowledge-base/project/plans/2026-10-31-chore-11556-sharding-reprice-checkpoint-plan.md`,
  and generated `knowledge-base/INDEX.md` if the index refresh commits. No
  `.github/workflows/`, no `scripts/*.sh`, no `plugins/` edits.

## Test Scenarios

- Given the 8 per-run dirs, when each is counted, then exactly 8
  `suite-timings.tsv` files are present per included dir — `integration`
  (`find <dir> -name suite-timings.tsv | wc -l` == 8).
- Given the downloaded TSVs, when the 7 arm labels' per-run maxes are folded
  and medianed, then the committed table's arm rows equal those medians —
  `integration` (recompute with awk over the downloaded files; compare to
  `scripts/suite-durations.tsv`).
- Given the pre-PR durations table, when the committed diff is inspected, then
  every changed row is either an arm row or a `src=floor` re-derivation —
  `integration` (`git diff scripts/suite-durations.tsv` row audit).
- Given the regenerated manifest, when
  `bash plugins/soleur/test/scripts-shard-totality.test.sh` runs, then it
  passes — `unit`-class suite (existing committed gate).
- Given the regenerated durations table, when
  `bash scripts/test-all-fast-tier-budget.test.sh` runs, then it stays green —
  `unit`-class suite (the property the mechanism choice exists to preserve).
- Given the patch file, when `git apply --stat` + `git apply --check` run
  against the archived session-state.md, then it applies cleanly and the tail
  shows Update 19 — `integration`.

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| Artifact retention (14 d) expires before the work runs | Re-list newest green merge_group/PR runs per runbook method; AC-1 requires ≥3 complete dirs |
| An arm label absent from all inputs → `src=floor` row | Floor check is a halt condition (Phase 2), not a silent pass |
| Full-reprice vs seed fork ruled the other way | `decision-challenges.md` carries `pending - assumed`; if CTO rules full re-price, fold #11648 demotion handling in explicitly — bigger diff, red-then-green budget suite |
| Stale worktree pruned before patch applies | Patch already captured under `specs/feat-one-shot-11556-reprice-checkpoint/` (committed with this plan) |
| TSV merge conflict on rebase | Runbook rule: regenerate, never hand-merge |
| Foreign worktree `test-all.sh` runs contend locally | Reported by collision-precheck; shard lint suites are cheap and contention-tolerant |

## Context

- Epic: #11556 (OPEN). This checkpoint closes the Lever-A re-price obligation;
  it does not close the epic.
- Merge under measurement: `8598aae15e` (PR #11561), merged 2026-10-30.
- Pre-split baseline (runbook, same section): worst legs 49.4 / 51.0 / 43.2
  min on runs 41037175716, 41036790949, 41030652561.
- Deferred neighbors: #11647 (arm debt), #11648 (always-on drift — 8 labels at
  11-378 s CI real vs ≤10 s committed), #11654 (KB-archive early warning).

## References

- Runbook: `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  ("Measured history" + "Re-deriving leg composition")
- Regen: `scripts/regenerate-shard-manifest.py` (LIGHT_ARTIFACT L121;
  `--timings-dir` L574-576; `--durations` L577-582; source precedence L68-69)
- Prior session state: `knowledge-base/project/specs/archive/20261030-170617-feat-11556-required-check-time/session-state.md`
  (Updates 1-17 on main; 18-19 patch under this branch's spec dir)
- Budget ratchet: `scripts/test-all-fast-tier-budget.test.sh` (caps: 10000 ms
  per-suite, 300000 ms total — reads `scripts/suite-durations.tsv`)
