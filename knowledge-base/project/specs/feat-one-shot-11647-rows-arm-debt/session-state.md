# feat-one-shot-11647-rows-arm-debt — session state

Dispatch 2 of 2 for epic #11556 (dispatch 1: #11648, merged 0bc2634a40).

Issue #11647 — ci/test-scripts `--rows` arm debt, 5 bundled items:
1. `src=est` provenance tier in `scripts/suite-durations.tsv` (enum {measured, floor, estimate};
   widen `check_durations` enum in scripts-shard-manifest.test.sh)
2. Extract `scripts/lib/rows-range.sh` — the ~60-line `--rows` preamble (4 copies:
   totality-mutations, lint-orphan, ci-pr-affected-replay, test-all-affected)
3. Exit-code doctrine: harness/shape FATALs exit 2 uniformly (lint-orphan + replay exit 1 today)
4. Per-block declared case floors — hollowed-out blocks must red
5. Arm-convention ADR + `-<letter>` split checklist

Re-eval by 2026-11-14. Status: scaffold — planning pending.
