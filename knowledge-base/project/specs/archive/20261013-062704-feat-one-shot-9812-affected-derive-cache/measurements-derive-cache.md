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
telemetry line itself (emitted on **stderr** post-review — `--print-selection`'s stdout is a
machine-compared surface; the bench's repeat-run `cmp` determinism leg would flag cold-vs-warm
counter drift as fake nondeterminism); every `AFFECTED_SELECTED` row and the `AFFECTED_SUMMARY`
are identical.

Cold-path cost: the recording overhead (read-set hashing + probe recording + one atomic store
per record) is real and grows with contention — cold head paid ~27s extra CPU at load ~5 and
~71s extra at load ~9 across the two bench runs (record+validate+store for 586 records).
The overhead is paid once per record per tree-state, then amortised.

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

Re-run post-rebase (merge-base ceb1c6c1ba, load ~8–11, `--head HEAD` on the rebased tree):

| probe | verdict | base CPU | head CPU | factor |
|---|---|---|---|---|
| 1 README.md | IDENTICAL — 587 rows + 1 added | 109.9 s | 181.1 s | 0.6x |
| 2 worktree-manager+cookie-policy | IDENTICAL — 588 rows + 1 added | 115.8 s | 16.1 s | 7.2x |

The "1 added row" is the new `scripts/test-affected-derive-cache` registration; the 30 rows
carrying `^scripts/lib/test-affected-derive-cache.sh` are the declared added-file edge.

## 3. Reading

- Warm-run derive collapses from ~87–97 s CPU to ~5–11 s CPU — a 7.8–18x reduction on the
  pre-pass, worth ~1.9–2.5 min wall per run depending on contention. Matches the ~2.4 min/run
  lever the continuation measurements predicted.
- Cold run is ~27–71 s CPU *slower* than uncached (recording + hashing + atomic stores for 586
  records; the gap widens under contention). One cold pass amortises across every subsequent run
  until an input drifts; a developer iterating on the tree pays it once per derive-affecting
  change, not once per run.
- Selection is byte-identical by the bench contract in both cold and warm states — the cache
  replays classification metadata only; `_diff_touches` and the verdict walk are unchanged.
- A harness that mints a fresh worktree per task pays the cold pass once per worktree — `.soleur/`
  is per-worktree by construction (sibling isolation is the point). Agents typically run the gate
  twice per worktree minimum, so it amortises; a slow FIRST gate on a fresh worktree is expected,
  not a regression.

## 4. Post-review deltas (design-validity + 8-seat panel)

The review panel surfaced and fixed, all re-verified by the suite (19/19) and a re-run bench:

- **P1 — memo probe slice (`_FE_PROBESETS`/`_FE_RECTRACKED`):** the `_FE_FILES` memo replayed a
  shared file's edges into memo consumers without the probes that produced them — a file created
  at a recorded-miss path inside a helper invalidated only the extractor's record. Now the probe
  slice is memoised per file and replayed into each consumer's record (T13 pins it).
- **P1 — telemetry off stdout:** the emit moved to stderr with a `state=on|off` field; the bench's
  default `--runs 5` determinism arm `cmp`s whole stdout and would have flagged cold-vs-warm
  counters as nondeterminism.
- **P2 — `sum` integrity trailer:** a cksum over the record body verified before replay; an
  in-body bit-flip or line drop is now a structural reject (T16 pins it).
- **P2 — span-hash preimage:** the code hash covers the EXTRACTED derive span (same anchors the
  derive suites pin, each leg asserted non-empty with whole-file fallback) instead of all ~6.8k
  lines of the runner — unrelated runner edits no longer flush all ~586 records. The two edge libs
  and the cache lib itself stay whole-file (their content IS the input set).
- **P2 — environment fingerprint in the key:** BASH_VERSION (patsub_replacement flips on 5.2),
  LC_ALL/COLLATE/CTYPE/MESSAGES/LANG, glob/case shell options, and IFS — channels that reach the
  derive's output are keyed, so a record minted under one environment can't replay under another.
- **P1-adjacent — `set -f` on the `-c` payload word-split:** the unquoted expansion also
  pathname-expanded glob tokens against cwd — a directory-listing input no recorded probe could
  invalidate. The sibling invocation arm already splits glob-free; selection was unchanged
  (derive suite 116/116, bench IDENTICAL).
- **Boundary + census hardening:** `cwd` record field, hex-bounded keys, probe-operand `\n`/`\t`
  poisoning (`_ADC_REC_BAD`), `_ADC_DIRREADY` store hoisting, prune sweeps the schema root and
  tmp orphans, T10 census widened to conjunct-position predicates + the full file-test class +
  a read-side census + the out-of-span callee boundary ({`_affected_emit_receipt`,
  `_wt_missing_die`}).
- **Documented residual — torn-record TOCTOU:** record hashing runs after classify, so a file
  edited mid-walk can mint edges-of-v1 keyed to hash-v2 — a record that validates while replaying
  stale edges until the file changes again; the memo widens the same window to a shared file's
  consumers. The uncached derive carries the same race but self-heals next run. Bounded to a
  concurrent mid-walk edit (~per-record seconds); hashing at read time would cost the per-file
  forks the design exists to avoid.
