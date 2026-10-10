---
title: "A specifier-resolution pin written as a regex is always narrower than the grammar it guards"
date: 2026-10-09
category: code-quality
module: apps/web-platform/test
related_issues: [9860, 2640]
related_prs: [9889]
---

# Learning: specifier-resolution pins belong on the AST extractor, not regexes

## Problem

The deploy-time workspace-isolation canary probe (#2640, PR #9809) failed on
every deploy with `workspace_isolation_failed reason=vitest_rc_1:
[UNRESOLVED_IMPORT] Could not resolve 'vitest/config'` (#9860). The image runs
vitest as a global `npm install -g` and `/app` carries only prod deps
(`npm ci --omit=dev`), so the config file's
`import { defineConfig } from "vitest/config"` resolved against nothing. The
fix — a plain-object export — was four lines, but the PR-time guard proved the
harder half.

The first-round pin `expect(code).not.toMatch(/^\s*import\b/m)` was narrower
than the grammar it claimed to ban: `export {…} from` re-exports (including
multiline forms — standard prettier output), `import()` past a line anchor,
`require()`, `;`-separated imports, and block-comment-prefixed declarations all
evaded it while reproducing the identical in-image failure. It also had no
vacuity floor and no self-pin, so a weakened regex would read green in both
worlds. Two review rounds found successive layers: specifier-valued config
*keys* (`environment: "jsdom"` resolves packages in-image), lost `UserConfig`
checking (typo'd keys no-op silently), and payload-file bare specifiers (a
devDep import in the suite greens locally and fails only at deploy).

## Solution

`apps/web-platform/test/dockerfile-vitest-version-pin.test.ts` now layers:

1. `specifiersOf(parseModule(file, stripComments(src)))` must be `[]` for the
   config — the shared AST walker (`test/helpers/ts-import-graph.ts`) covers
   import/export-from/import-equals/require()/import() in any position,
   quoting, or line break, and fails closed on non-literal arguments.
   Type-only clauses are correctly permitted (TypeScript erases them).
2. Regex arms only for what the module graph does not model:
   `import.meta.resolve|glob`, the `vi.mock`/`importActual` family, and
   `new URL(_, import.meta.url)` — with non-literal args flagged as problems.
3. `toEqual` on the imported config pins the exact exported shape — keys AND
   values, so `environment`, `coverage`, `reporters`, and typo'd keys all go
   RED at PR time (replacing the excess-property checking `defineConfig`
   provided; a JSDoc `@type` would not have worked — tsc ignores JSDoc types
   in `.ts` files).
4. The payload's specifiers are classified against builtins
   (`isBuiltin`), vitest-internal (`vitest`, `vitest/*`), prod
   `dependencies`+`optionalDependencies`, and in-payload relative paths.
5. The runner payload set is pinned bidirectionally: test list == Dockerfile
   runner `COPY` set == `.dockerignore` bang set, so renames and additions
   both force the guard to move.
6. Self-pin probes assert every predicate fires on its own banned shape, and
   a `literals`-contains-known-imports floor defeats a vacuous extraction.

## Key Insight

A regex over module syntax is a grammar one adoption step behind — each
review seat found another evasion because the predicate described a *shape*,
not the *property* ("resolves a specifier in-image"). The repo already owns
the honest tool: `test/helpers/ts-import-graph.ts` (`specifiersOf`,
`moduleEdges`, `parseModule`) plus `test/helpers/strip-comments.ts`, built for
the watchdog/placement guards and kept AST-complete by their own tests. The
same lesson has now been paid for three times in this codebase (the #8603
regex-stripper migration, the domain-router boundary pin, and #9860): **when
the invariant is "this file resolves nothing / only these modules," extract
with `specifiersOf` and assert on the set — do not pattern-match keywords.**
The second half is equally load-bearing: a guard that can extract zero items
while staying green is measuring nothing — every negative assertion needs a
positive floor or a self-pinning probe.

## Session Errors

1. Collision probes missed sibling draft PR #9884 because it was keyed to the
   adjacent issue #9871; the full issue comment named it. **Prevention:** when
   collision-checking an issue, grep the latest comments for `PR #N` /
   `feat-*` branch references and `gh pr view` each, not only the issue's
   linked-PR graph.
2. The feature branch was 7 behind `origin/main`; the defect's files did not
   exist locally until a sync merge. **Prevention:** fetch + compare before
   planning; if the referenced code is absent on the branch, sync first.
3. `git checkout <file>` as a mutation-restore reverted an uncommitted edit.
   **Prevention:** in mutation testing, restore from the `/tmp` snapshot, never
   `git checkout` (index ≠ working state).
4. A spurious todo-tool warning ("completed items removed") was investigated
   and dismissed. **Prevention:** none needed — cosmetic.
5. `fix-round-seats.sh --finding-seats` requires comma-separated args; a
   space-separated list exits 2. **Prevention:** read the usage line first.
6. The initial fix shipped a regex predicate narrower than the grammar it
   guarded; fix-round review caught the evasions and the guard was rebuilt on
   the AST extractor. **Prevention:** when the invariant quantifies over
   specifier-resolution, reach for `ts-import-graph.ts` before writing a
   keyword regex — and pin the extractor with positive probes plus a
   non-vacuity floor.

## Tags

category: code-quality
module: apps/web-platform/test
