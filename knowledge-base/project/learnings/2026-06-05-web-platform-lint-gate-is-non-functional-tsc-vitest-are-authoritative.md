# Learning: web-platform `npm run lint` is a non-functional gate — tsc + vitest are the authoritative quality gates

## Problem

During the `/work` Phase 3 quality check of a web-platform PR, running the project's
prescribed lint command (`apps/web-platform` `package.json` `scripts.lint = "next lint"`)
exited non-zero and dropped into an **interactive prompt**:

```
? How would you like to configure ESLint?
❯  Strict (recommended) / Base / Cancel
```

`next lint` is deprecated (removed in Next.js 16) and, finding **no eslint config in the
repo** (`eslint.config.*`, `.eslintrc*`, and `package.json#eslintConfig` are all absent),
prompts to scaffold one rather than running. In a non-interactive `/work`/`/ship` pipeline
this reads as a `LINT_EXIT=1` "failure" that can be mistaken for a real regression and
waste a debugging round.

## Solution

Do NOT treat `npm run lint`'s non-zero/interactive exit as a quality-gate failure for
web-platform changes. The authoritative gates are:

- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (typecheck)
- `cd apps/web-platform && ./node_modules/.bin/vitest run` (full suite)

Verified that **CI does not run lint at all** — `grep -rln 'next lint|eslint|run lint'
.github/workflows/*.yml` returns zero matches. So lint is not part of the merge gate;
tsc + vitest are what CI (and review) actually enforce.

If a real lint pass is ever wanted, that requires standing up an eslint flat config
(`eslint.config.mjs` + `eslint-config-next`) — a separate, deliberate decision, NOT
something to bolt onto an unrelated feature/drain PR.

## Key Insight

A `package.json` lint script existing does not make lint a functioning gate. Before
treating a prescribed gate's failure as load-bearing, confirm (a) it is actually
configured to run, and (b) CI enforces it. When a tool prompts interactively or errors
on missing config in a pipeline, it is tooling state — not a regression in your diff.

## Session Errors

- **`npm run lint` (next lint) prompted interactively / no eslint config.** Recovery:
  relied on tsc + full vitest (both green); confirmed CI does not run lint.
  Prevention: route a note to the work skill so future runs don't treat the lint exit
  as a regression (done — see Phase 3 quality-check note).
- **`tail -N` pipe masked tsc's real exit** (`TSC_EXIT=0` was `tail`'s exit). Recovery:
  re-ran with `tsc > log 2>&1; echo $?`. Prevention: already covered by the work skill's
  pipefail caveat (`bash ... | tail` reports tail's exit) — one-off.
- **Concurrent-subagent transient tsc errors** in the shared worktree during Tier-B
  fan-out (Phase 2 agent briefly saw a Phase 3 symbol not yet exported). Recovery: none
  needed — self-resolved when all phases landed; final integrated tsc was clean.
  Prevention: expected behavior of parallel fan-out on disjoint files; verify the
  INTEGRATED tree (not each agent's mid-run view) before trusting green — one-off.

## Tags
category: build-errors
module: apps/web-platform

## Addendum — 2026-08-19 (#1327)

The finding recorded above ("there is no eslint config in the repo; `next lint`
drops into an interactive prompt and exits 1; CI does not run lint at all") was
accurate when written and is **no longer true as of #1327**. The body above is
left byte-identical as the record of what was measured on 2026-06-05.

What changed:

- `apps/web-platform/eslint.config.mjs` now exists — an ESLint 9 flat config
  consuming `@next/eslint-plugin-next`'s native `flatConfig` export, with
  `@typescript-eslint/parser` for `.ts`/`.tsx` and node + browser globals. No new
  dependencies were required; `eslint-config-next` already supplied the parser
  and all five plugins transitively.
- `"lint"` is now `eslint .` rather than `next lint`.
- A `lint-webplat` job runs it on pull requests. It is **deliberately not a
  required check** — see the plan's Decision 1.

The original conclusion that `tsc --noEmit` + `vitest run` are the authoritative
**merge-gating** checks still holds: lint is reported, not required.

One thing this work uncovered that the original note could not have seen: ESLint
could not have run correctly here even with a config. A blanket npm override
pinned `brace-expansion` to `^5.0.9`, and `minimatch@3.1.5` — which `eslint`,
`@eslint/config-array`, `@eslint/eslintrc`, `eslint-plugin-import`, `-jsx-a11y`
and `-react` all depend on — requires `^1.1.7`. v5 exports an object where v1
exported a function, so any brace glob died with
`TypeError: expand is not a function`. Removing the blanket override (npm then
nests each major independently) was a prerequisite for this migration.
