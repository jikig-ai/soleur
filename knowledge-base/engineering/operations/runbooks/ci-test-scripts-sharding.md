---
title: "Runbook: test-scripts sharding — leg composition, re-derivation, and runner-availability data"
category: observability
tags: [ci, test-sharding, timings, fail-closed]
date: 2026-09-22
triggers: []
---

# Runbook: test-scripts sharding

**TL;DR:** `test-scripts` leg membership comes from the committed manifest
`scripts/suite-shard-legs.tsv` — a sticky-LPT assignment regenerated from CI
timing artifacts (ADR-240). The runner only looks labels up; labels the
table does not know hash onto a leg deterministically, and an absent/stale/
n-mismatched table degrades to the old positional round-robin — coverage
never depends on the table. The three heaviest suites live in the dedicated
`test-scripts-heavy` matrix (#8006) with their own manifest
`scripts/suite-shard-legs-heavy.tsv` under the identical contract; the
light group runs K=7. Regenerate the manifests when legs skew or when
`scripts-shard-manifest.test.sh` reds. For a suite add/remove use
`python3 scripts/regenerate-shard-manifest.py --incremental --write`
(`--group heavy` for the heavy table) — incumbent rows pin verbatim and only
newly-registered labels place, so the diff stays confined to the changed
rows; for leg-balance corrections use the full
`python3 scripts/regenerate-shard-manifest.py --run <green-ci-run> --write`.

## Current topology (post-#8006 phase 2, duration-aware)

| Job | Legs | Contents | Worst leg |
|---|---|---|---|
| `test-scripts` | K=7 | light `scripts` group, manifest lookup + hash fallback | interim ~13 min on the -a leg pre-regen; ~9 min predicted equilibrium (the orphan-suite battery is now two `--rows` halves — see Measured history 2026-09-26) |
| `test-scripts-heavy` | K=3 | heavy manifest lookup + hash fallback | battery floor ≈ 9 min + setup |
| `shard-totality-mutations` | 3 | battery rows split `--rows 1-14` / `15-28` / `29-42` | ~6 min each + setup |

Heavy legs (manifest-assigned, sticky-LPT over measured durations):
`1/3` → `tests/scripts/registry-gate-mutation-battery`,
`2/3` → `scripts/battery-tag-authorship-mutations`,
`3/3` → `.github/scripts/test/run-all.sh`. If `want_scripts_heavy` gains a
registration the untabled label hash-falls onto a leg — total but
unbalanced until a regen; widen the matrix deliberately, and let
`scripts-shard-totality.test.sh` prove the union still covers the
reference set.

## The manifests: `suite-shard-legs{,-heavy}.tsv`

Generated data (ADR-235 product artifact — committed). Header carries `n`
(the leg count of the matrix it was generated for) plus provenance
(`generated-from-run`, `generated-at`, `generator`); rows are
`label<TAB>leg`, sorted by label so refreshes diff minimally. Two files,
one format, one parser: `suite-shard-legs.tsv` serves `TEST_GROUP=scripts`,
`suite-shard-legs-heavy.tsv` serves `TEST_GROUP=scripts-heavy`. Separate
files keep a heavy regen from rewriting the light table's
insertion-stable surface (ADR-240 amendment).

**Runtime engagement is narrow.** The runner uses the group's table only
when all of: `SCRIPTS_SHARD` set, `TEST_GROUP` is `scripts` or
`scripts-heavy`, that group's `n` == the spec's N. Anything else — absent
file, an unrelated group, a K bump pending regen — takes the positional
path with a stderr notice. Malformed rows, duplicate labels, or
out-of-range legs exit 2 at parse. `SOLEUR_SHARD_MANIFEST` /
`SOLEUR_SHARD_MANIFEST_HEAVY` override the paths for tests (`off`
disables; set-but-empty, relative, or missing paths all exit 2). The
lookup is parallel indexed arrays scanned with literal `==` — a packed
`"|label=leg|"` string searched by glob was measured at 6+ CPU-minutes
per enumerate (glob backtracking); if the structure is ever revisited,
benchmark the lookup, not the parse.

**Regeneration.**

```bash
# Routine add/remove regen (#9402): incumbent rows pin verbatim, unregistered
# rows drop, registered-but-untabled labels deal onto least-loaded legs priced
# from the committed durations table (floor = median of measured rows). No
# timing fetch; the durations table takes only the parity delta (stale rows
# out, new labels in at floor with src=floor; measured rows byte-identical) —
# the manifest diff is exactly the added/removed rows. Refuses
# --run/--runs/--timings-dir.
python3 scripts/regenerate-shard-manifest.py --incremental --write
python3 scripts/regenerate-shard-manifest.py --group heavy --incremental --write
# Full regen — the balance-correction path; median over the last 5 green main
# runs. This is the only mode that rebalances incumbents and the only one that
# re-aggregates the durations tables from fresh measurements.
python3 scripts/regenerate-shard-manifest.py --runs 5 --write
python3 scripts/regenerate-shard-manifest.py --run <green-ci-run-id> --write   # single-run override
python3 scripts/regenerate-shard-manifest.py --group heavy --runs 5 --write
# INFRA (#8736): the infra table lives at apps/web-platform/infra/suite-shard-legs.tsv.
# Its runs are green infra-validation.yml runs on main (the suite-timings-infra-N
# artifacts — paths-filtered, so many green runs contribute nothing; --runs
# skips them). --runs counts SCANNED runs, not contributing ones — for an
# effective 5-sample median on a sparse group, raise N (e.g. --runs 10).
python3 scripts/regenerate-shard-manifest.py --group infra --runs 5 --write
```

Without `--write` it prints predicted per-leg totals and the incumbent diff.
`--runs N` (default 5) aggregates the N most recent green main runs by
**median** per label — a sustained drift moves a weight, a one-run contention
spike does not; `--timings-dir` (repeatable — one run per dir) reads local
`suite-timings.tsv` files instead. Sticky-LPT keeps incumbent legs within 5%
of optimal, so each refresh moves only what balance requires — but "what
balance requires" still re-seats drifted rows, which is why a suite-add PR's
regen once moved 10 unrelated suites (#9402). `--incremental` exists for the
add/remove case precisely to avoid that churn; it never rebalances, so a
suite that lands on a crowded leg stays put until the next full regen —
reach for `--runs 5 --write` when leg balance, not membership, is the
problem.

**Floor rule (#9232).** A registered label absent from every timing input is
still tabled — at `floor_ms`, the median of the group's measured labels, or
`DEFAULT_SUITE_MS = 60000` when nothing measured at all (an all-floor,
count-balanced manifest with a WARN — never a die). Floor rows carry
`src=floor` in the durations table so a later aggregation re-derives the
estimate rather than entrenching it as a measurement.

**The durations tables.** The same `--write` emits `suite-durations.tsv`
(light), `suite-durations-heavy.tsv`, and `apps/web-platform/infra/
suite-durations.tsv` — `label<TAB>ms<TAB>src` rows, label-sorted, the single
duration source both consumers read. `--durations <path>` repacks from a
table instead of fetching; `--durations-out <path>` redirects the write.

**Arbitrary-K emission (`--legs K`, #8231).** The packing can be emitted at
any leg count for offline consumers — the local parallel scheduler packs W
host-chosen workers from the committed table with zero `gh` calls:

```bash
python3 scripts/regenerate-shard-manifest.py \
  --durations scripts/suite-durations.tsv --legs "$W" \
  --manifest "$WORK/local-legs.tsv" --write
# then W workers, each: SCRIPTS_SHARD=k/W \
#   SOLEUR_SHARD_MANIFEST="$WORK/local-legs.tsv" bash scripts/test-all.sh scripts
```

`--write` to the group's *committed* manifest with K != the workflow's
declared leg count is refused (exit 2) — a committed n-mismatch degrades
every leg to positional while reading as applied. Dry-run or an explicit
`--manifest` path is the sanctioned K-simulation surface.

Regenerate when:

- a suite was added, removed, or renamed → `--incremental --write` (pins all
  incumbent rows, drops the phantom, tables the new label — the diff is
  exactly the membership change),
- `scripts-shard-manifest.test.sh` reds (n drift, phantom rows, malformed —
  the same lint now covers the durations tables: well-formed rows, `src`
  enum, keys == sibling manifest keys),
- the `suite-timings-*` artifacts show one `test-scripts*` leg drifting well
  past its peers → the full `--runs 5 --write` rebalance (the post-merge
  `ci-leg-balance-9232` followthrough probe sweeps this daily once enrolled),

**Merge conflict on the TSV → regenerate, never hand-merge.** Re-run the
command against a current green run and commit the output. The TSVs are
deliberately NOT in `resolve-regenerable-conflicts.sh`'s RESOLVABLE-SET:
regeneration needs `gh` plus a chosen green run id, which the pure-local
resolver cannot supply — this path stays manual.

## Why the OLD positional method is retained

`SCRIPTS_SHARD=k/K` keeps suites whose registration ordinal ≡ k−1 (mod K)
under C collation — it remains the degrade path for both groups. Any
change to the registered set shifts every later ordinal and
silently re-composes every leg: during the #7931 review, adding two suites
and removing one swung K=3's worst leg between 15.09 and 20.73 minutes
purely from ordinal position, and on the post-carve-out light group the
positional tail measured 797s vs 237s on the best leg (run 35840517639) —
the asymmetry the manifest exists to remove. A positional K table is a
fact about a commit, not about the repo; the manifest is the same shape
made honest — derived, provenance-stamped, and degradable.

## Re-deriving leg composition (reproducible method)

Per-suite durations come from the run's own `suite-timings-scripts-*` /
`suite-timings-scripts-heavy-*` artifacts (uploaded with `if: always()`,
retention 14 days), each a TSV written in execution order. To reconstruct
the registration order that produced them:

1. Download all legs' TSVs for one run (`gh run download <run-id> -n
   'suite-timings-*'` or via the artifacts API).
2. Interleave the legs back into ordinal order: leg k holds ordinals
   k−1, k−1+K, k−1+2K, … under the runner's C-collation sort — recover the
   sequence by round-robin merge, NOT by concatenating legs.
3. To simulate a different K, replay that ordinal order through
   `ordinal % K == leg−1` and sum durations per leg. Sanity check: the
   attributed total must equal the group's wall clock; a shortfall means
   a nested-runner suite's span was attributed to its child marks rather
   than folded into the parent registration.

Alternative source (pre-artifact method, still valid): a job log's
`--- <label> ---` marks, filtered to labels in
`bash scripts/test-all.sh --enumerate scripts`, attributing each mark's
span to the NEXT registered mark.

## Measured history

- **#7902 (pre-shard):** 35.25 min single job, 374 suites, run
  34152496134. K-simulation on that order:
  K=2 → 21.91, K=3 → 15.09, K=4 → 16.09, K=5 → 10.37, K=6 → 10.05,
  K=7 → 9.44 (slowest-leg minutes).
- **#8006 (this topology):** on the 480-suite order, the three heaviest
  suites shared leg 2/3 → measured 31–39 min on every sampled run.
  K-only alternatives simulated: K=5 → ~21.5 min, K=8 → ~13.6 min —
  round-robin cannot separate the heavies at any K. Carve-out was chosen;
  suite timings: battery 523 s, tag-authorship 380 s, run-all.sh 371 s
  (run 35743569887 artifacts).
- **The floor no K beats** is the longest single suite:
  `registry-gate-mutation-battery`, declared budget 41.67 min
  (~1.5× its own measured max; load alone moves it ~1.9×, measured
  14.3–27.9 min under contention). `timeout-minutes: 60` on both jobs is
  the hang cap, sized above the DECLARED expectation — a silent bound must
  never fire below a duration the repo calls legitimate (#7902 review).
- **2026-09-25 K=6→K=7 rebalance:** suite growth (374→502 light
  registrations) drifted the K=6 manifest's worst leg to 13.0 min wall
  on run 36123485360 (12.9 min suite + ~0.4 min setup). Dry-run regen at K=6
  predicted a 614 s worst leg — above the ~10-min ceiling even after
  rebalancing — so the matrix moved to K=7 and the manifest regenerated
  from run 36125573947: legs 486–589 s, leg 5 = the atomic
  `lint-orphan-test-suites-mutations` (588.8 s alone — no K splits a single
  suite; the suite-internal split is a deferred follow-up).
- **2026-09-26 suite-internal `--rows` split (#8864):** the deferred
  follow-up landed — `lint-orphan-test-suites-mutations` registers as
  `-a`/`--rows 1-8` and `-b`/`--rows 9-16` (DECLARED_TOTAL=16 in the
  battery; the union tiles it, asserted by the run_suite-argv tiling block
  in `scripts-shard-totality.test.sh`). Interim pins: `-b` stays on leg 5
  (the emptied suite leg), `-a` on leg 3 — one pre-regen run can overshoot
  (~780 s on the -a leg); the first green run carrying both halves'
  timings is the regen input, and the predicted equilibrium worst leg is
  ~9 min ((2989139 ms + ~590 s + ~170 s duplicated preamble)/7 — each
  half pays the suite's build+control overhead, so the split is ~76%-of-
  suite per leg, not a halving). Re-splitting later = bump
  DECLARED_TOTAL + move the range boundary in the SAME commit; the battery
  records per-row elapsed seconds in its replay table so the next boundary
  choice is a data lookup.

## Runner-availability data (why extra legs are not free)

Measured 2026-09-09 over 29 consecutive `main` push CI runs. "Group
occupied" = the predecessor run's `test` had not completed when this run
was created; jobs with `runner_id: null` or zero steps excluded; start
spread measured over the 23 no-`needs:` jobs.

| cohort | n | first-job delay | queue term | start spread |
|---|---|---|---|---|
| group OCCUPIED | 7 (24%) | med 460 s, max 1249 s | med 393 s, max 1245 s | med 68 s, max 913 s |
| group DRAINED | 22 (76%) | med 4 s, max 731 s | 0 | med 412 s, max 1708 s |

The model is additive: time-to-`test` = queue (only when occupied) +
runner availability + execution. The queue binds on ~a quarter of runs;
the window's worst time-to-`test` (4156 s) came from a run whose group
was EMPTY. Cite the cohort shape, not a median — the medians did not
reproduce between the 35-run and 29-run readings while every maximum and
the entire occupied cohort reproduced to the second.

Reproduction (two-stage jq: `gh --jq` does NOT forward `--arg`):

```bash
for p in 1 2 3 4 5 6; do
  gh api "/repos/{owner}/{repo}/actions/runs?event=push&branch=main&per_page=100&page=$p" \
    --jq '.workflow_runs[] | select(.name=="CI") | [.created_at,.id,.conclusion] | @tsv'
done | sort -ru | awk -F'\t' '$1>="<start>" && $1<="<end>"' > ci-win.tsv
while IFS=$'\t' read -r created rid concl; do
  gh api "/repos/{owner}/{repo}/actions/runs/$rid/jobs?per_page=100" > j.json
  jq -r --arg rid "$rid" --arg created "$created" \
    '.jobs[] | [$rid,$created,.name,(.started_at//""),(.completed_at//""),
                (.conclusion//""),(.runner_id|tostring),(.steps|length|tostring)] | @tsv' j.json
done < ci-win.tsv > jobs.tsv
```

`sort -ru` is load-bearing: GitHub's pagination is not stable while new
runs are being created, so a plain `sort -r` can carry the same run on
two pages and inflate the population. The raw `jobs.tsv` is committed at
`knowledge-base/project/specs/feat-one-shot-7931-5806-ci-concurrency-and-workflow-run-deploy/measurement-jobs-2026-09-09.tsv`.

## Verification surfaces

- `plugins/soleur/test/scripts-shard-totality.test.sh` — both partitions
  union exactly to their statically extracted reference sets; no drop, no
  duplicate, no valid-but-empty assignment.
- `plugins/soleur/test/scripts-shard-manifest.test.sh` — manifest hygiene:
  n == ci.yml leg count, labels ⊆ registered, no dups, every leg pinned,
  provenance present.
- `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` — toolchain
  parity asserted on both jobs (bun, likec4, gitleaks).
- `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` — the
  synthetic `test` check has six `needs:` jobs; a failed or skipped heavy
  matrix fails it.
