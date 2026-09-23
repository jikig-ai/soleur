# Guard 1 mutation battery (2026-09-22)

Each row applied one mutation to a pristine copy, confirmed with `cmp` that it landed, ran the
named suite, and restored from the pristine copy (never `git checkout`). After the run, every
file compared byte-identical to its pristine copy. The unmutated controls were green immediately
before the run: `c4-canonical.test.ts` 14/14, the C4 vitest set 84/84, `c4-from-components.test.sh`,
`c4-from-components.test.ts` 43/43 and `c4-model-freshness.test.sh` all passed.

| Row | Mutation | Result | The failing row |
|---|---|---|---|
| m1 | One byte in `apps/web-platform/lib/c4-canonical.mjs` only | RED | vitest `is byte-identical to the plugin source of truth` |
| m2 | `c4-render.ts` returns `raw` | RED | `returns the validated temp model as json …` (canonical bytes) |
| m3 | `regenerate-c4-model.sh` publishes the raw export AND the artifact is regenerated raw in the same diff | RED | freshness `committed model.likec4.json is not canonical`. The byte cmp stayed green, as predicted. |
| m4 | `generate-c4-from-components.ts` skips canonicalize | RED | `published model.likec4.json is in the canonical line-per-value format` |
| m5 | `canonicalizeC4Model` blanks only the first view's hash | RED | `blanks EVERY view hash that exists` and the round-trip row |
| m6 | Plugin `LIKEC4_VERSION` set to 1.50.1 alone | RED | `c4-from-components.test.ts` drift guards (pinned against `regenerate-c4-model.sh`, which the version-pin test ties to the Dockerfile) |
| h1 | Harness: the mirror row's SOURCE path points at the mirror itself | RED | the `paths differ` assertion |

Must-PASS input (not canonical, no mutation): the bun fixture `RAW` has non-empty view hashes, a
view with no hash key, non-alphabetical key order and a non-view `hash`. It canonicalizes, and
every row passes on it.

Axes not mutated: the likec4 renderer itself, and the CLI's argument parsing beyond the rows
listed in `c4-canonical.test.ts`.

## Round 2: guards added during review (2026-09-22)

Each guard the review fixes added was mutated back out on the working tree, from pristine copies
with a landing check and a byte-identical restore. All six went RED on the intended row.

| Row | Mutation | Result | The failing row |
|---|---|---|---|
| n1 | Canonical strip reverted to `/^ +/gm` (both copies) | RED | `preserves spaces after a U+2028 inside a string value` and the round-trip row |
| n2 | `--check` compares whitespace-insensitively | RED | the single-axis `--check rejects input that is …` rows |
| n3 | `regenerate-c4-model.sh` stops referencing the canonical CLI | RED | the writer census |
| n4 | A new tracked script runs `likec4 export json -o model.likec4.json` | RED | the writer census (population growth) |
| n5 | `c4-render.ts` try/catch around canonicalize removed | RED | `maps a canonicalize failure to io_error and returns no json` (the deep-nesting fixture) |
| n6 | The project route reports the raw `SyntaxError` again | RED | AC7b (fixed message, no model text in the report) |
