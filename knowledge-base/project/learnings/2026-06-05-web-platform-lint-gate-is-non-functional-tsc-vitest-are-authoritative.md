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
