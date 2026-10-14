# Measurements — #9815 vitest `related` narrowing

## Baselines (full projects, per run; #9763 arc + plan measurement)

| Suite | Shape | Time |
|---|---|---|
| `apps/web-platform [repo-wide+component]` | `npm run test:ci -- --project repo-wide --project component` | ~80 s (plan: 81,554 ms bundle) |
| `apps/web-platform [unit]` | `npm run test:ci -- --project unit` | ~82 s |

## Narrowed runs (real vitest 4.1.11, worktree install; planner-measured)

| Changed file | Resolved test files | Time | vs full |
|---|---|---|---|
| `app/lib/lru-cache.ts` | 133 | 19.97 s | ~62 s saved |
| `app/lib/redaction-allowlist.ts` | 203 | 44.47 s | ~38 s saved |
| `app/components/ui/button.tsx` (component) | 185 | 44.24 s | ~36 s saved |

Breadth is import-graph dependent — leaf-utility diffs save the most;
a file imported by most of the suite narrows less (still bounded by the
~82 s full cost).

## Zero-resolution behaviour (measured, vitest 4.1.11)

`vitest related <uncovered-path> --run --project unit` prints
`No test files found, exiting with code 0` and exits 0 — the silent-green
shape the wrapper's marker grep exists to catch (falls back to the full
project, `outcome=full-zero`).

## Fixture-project arm timings (synthesized, 3-file project)

Each real-binary arm (A1-A8, M1-M3) completes in ~0.3-0.6 s per vitest
invocation; the whole suite runs in ~10-15 s.

## CI unchanged

The `CI` conjunct leaves `WEBPLAT_RELATED` empty; the empty path IS the
pre-existing `npm run test:ci -- --project <p>` invocation with the same
`VITEST_SHARD` forward — CI legs byte-identical in shape.
