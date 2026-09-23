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
`test-scripts-heavy` matrix (#8006); the light group runs K=5. Regenerate
the manifest when legs skew or when `scripts-shard-manifest.test.sh` reds:
`python3 scripts/regenerate-shard-manifest.py --run <green-ci-run> --write`.

## Current topology (post-#8006, duration-aware)

| Job | Legs | Contents | Worst leg |
|---|---|---|---|
| `test-scripts` | K=5 | light `scripts` group, manifest lookup + hash fallback | ~7.5 min suite time + setup |
| `test-scripts-heavy` | K=3 | one suite per leg via `SCRIPTS_SHARD` (positional) | battery floor ≈ 9 min + setup |

Heavy legs: `1/3` → `tests/scripts/registry-gate-mutation-battery`,
`2/3` → `scripts/battery-tag-authorship-mutations`,
`3/3` → `.github/scripts/test/run-all.sh`. The assignments are ordinal —
if the `want_scripts_heavy` block gains a fourth registration, leg `4/3`
does not exist and the runner's zero-assignment refusal fires; widen the
matrix deliberately, and let `scripts-shard-totality.test.sh` prove the
union still covers the reference set.

## The manifest: `scripts/suite-shard-legs.tsv`

Generated data (ADR-235 product artifact — committed). Header carries `n`
(the light-matrix leg count it was generated for) plus provenance
(`generated-from-run`, `generated-at`, `generator`); rows are
`label<TAB>leg`, sorted by label so refreshes diff minimally.

**Runtime engagement is narrow.** The runner uses the table only when all
of: `SCRIPTS_SHARD` set, `TEST_GROUP=scripts`, `n` == the spec's N. Anything
else — absent file, `scripts-heavy`, a K bump pending regen — takes the
positional path with a stderr notice. Malformed rows, duplicate labels, or
out-of-range legs exit 2 at parse. `SOLEUR_SHARD_MANIFEST` overrides the
path for tests (`off` disables; set-but-empty, relative, or missing paths
all exit 2). The lookup is parallel indexed arrays scanned with literal
`==` — a packed `"|label=leg|"` string searched by glob was measured at
6+ CPU-minutes per enumerate (glob backtracking); if the structure is ever
revisited, benchmark the lookup, not the parse.

**Regeneration.**

```bash
python3 scripts/regenerate-shard-manifest.py --run <green-ci-run-id> --write
```

Without `--write` it prints predicted per-leg totals and the incumbent diff.
`--run` defaults to the latest green `ci.yml` run on `main`; `--timings-dir`
reads local `suite-timings.tsv` files instead. Sticky-LPT keeps incumbent
legs within 5% of optimal, so each refresh moves only what balance
requires. Regenerate when:

- `scripts-shard-manifest.test.sh` reds (n drift, phantom rows, malformed),
- the follow-through probe reports a leg >900s while others sit near-idle,
- a suite was renamed (its old row becomes a phantom; the lint names it).

**Merge conflict on the TSV → regenerate, never hand-merge.** Re-run the
command against a current green run and commit the output.

## Why the OLD positional method is retained

`SCRIPTS_SHARD=k/K` keeps suites whose registration ordinal ≡ k−1 (mod K)
under C collation — it remains the degrade path and the `scripts-heavy`
mechanism. Any change to the registered set shifts every later ordinal and
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
  synthetic `test` check has five legs; a failed or skipped heavy matrix
  fails it.
- `scripts/followthroughs/ci-leg-durations-8006.sh` — post-merge soak
  probe; auto-closes #8006 when ≥3 qualifying main runs show every
  `test-scripts*` leg under 900 s.
