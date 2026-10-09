# Measurements — affected-derive cross-run cache (#9812)

Date: 2026-10-09. Host: the dev box, load average ~5–6 during measurement (contended — the
idle-host estimate in `measurements-continuation-2026-10-09.md` predicted ~2.4 min/run; the
loaded-host delta is recorded, not hidden). bash 5.3.15, locale en_US.UTF-8.

## 1. Direct timing — `--print-selection --paths=README.md` in the feature worktree

Command (from the worktree root, `.soleur/cache/affected-derive` deleted between runs):

```bash
time bash scripts/test-all.sh --print-selection --paths=README.md
```

| run | real | user | sys | AFFECTED_DERIVE_CACHE |
|---|---|---|---|---|
| cold (cache dir absent) | 2m03.0s | 1m36.8s | 0m33.5s | hits=0 misses=586 derived=0 |
| warm (unchanged tree)    | 0m09.4s | 0m05.3s | 0m04.9s | hits=586 misses=0 derived=0 |

Deterministic leg (AC1): the second consecutive unchanged-tree run reports `misses=0` over all
586 served records — the saving does not depend on ambient load being kind.

Selection identity in the worktree: `diff` over the two runs' `AFFECTED_*` lines shows only the
telemetry line itself; every `AFFECTED_SELECTED` row and the `AFFECTED_SUMMARY` are identical.

Cold-path cost: the recording overhead (read-set hashing + probe recording + one atomic store
per record) is visible — cold head pays ~113s wall where the uncached baseline pays ~87s
(bench numbers below). The overhead is paid once per record per tree-state, then amortised.

## 2. Acceptance bench — `affected-prepass-bench.sh` (the byte-identity gate)

```bash
bash scripts/affected-prepass-bench.sh --base 8729cc0dfa --head HEAD --runs 1 \
  --added-edges scripts/lib/test-affected-derive-cache.sh
```

Exit 0. Both sides ran in fresh scratch checkouts (symmetric tree contents — a first pass with
`--head` on the working tree flagged 12 rows carrying `^node_modules/.bin/`, an environment
artifact: the worktree has installed deps, the bench's checkout does not; the derive honestly
probes what exists).

| probe | verdict | base CPU | head CPU | factor |
|---|---|---|---|---|
| 1 README.md (head cache cold) | IDENTICAL — 585 rows + 1 added | 76.8 s | 104.3 s | 0.7x |
| 2 worktree-manager+cookie-policy (head cache warm from probe 1) | IDENTICAL — 586 rows + 1 added | 87.6 s | 11.3 s | 7.8x |

The "1 added row" is the new `scripts/test-affected-derive-cache` registration; the 30 rows
carrying `^scripts/lib/test-affected-derive-cache.sh` are the declared added-file edge.

## 3. Reading

- Warm-run derive collapses from ~87–97 s CPU to ~5–11 s CPU — a 7.8–18x reduction on the
  pre-pass, worth ~1.9–2.5 min wall per run depending on contention. Matches the ~2.4 min/run
  lever the continuation measurements predicted.
- Cold run is ~25 s CPU *slower* than uncached (recording + hashing + atomic stores). One cold
  pass amortises across every subsequent run until an input drifts; a developer iterating on
  the tree pays it once per derive-affecting change, not once per run.
- Selection is byte-identical by the bench contract in both cold and warm states — the cache
  replays classification metadata only; `_diff_touches` and the verdict walk are unchanged.
