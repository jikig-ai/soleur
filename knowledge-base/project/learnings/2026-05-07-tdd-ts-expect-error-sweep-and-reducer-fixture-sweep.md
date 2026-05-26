---
date: 2026-05-07
title: "TDD GREEN sweep: @ts-expect-error directives and reducer-fixture seeding when ChatState shape changes"
module: web-platform
problem_type: build_errors
component: tests
severity: medium
category: best-practices
tags:
  - tdd
  - typescript
  - vitest
  - useReducer
  - refactor-sweep
  - "@ts-expect-error"
related_prs:
  - 3469
related_issues:
  - 3448
synced_to: []
---

# TDD GREEN sweep: `@ts-expect-error` directives and reducer-fixture seeding when ChatState shape changes

## Problem

During PR2 of #3448 (`feat-abort-conversation-web-pr2`, PR #3469), two distinct
`tsc --noEmit` regressions surfaced AFTER the implementation was working —
both caused by stale type-system artifacts that survived the GREEN phase:

1. **`TS2578: Unused '@ts-expect-error' directive`** — the RED-phase tests in
   `apps/web-platform/test/useWebSocket-abort.test.tsx` placed
   `// @ts-expect-error — streamState is added in this PR` directives above
   each `result.current.streamState` access so the test file would compile
   while the hook return type didn't yet have the field. Once the hook was
   widened in GREEN, those directives became unused — `tsc --noEmit` emits
   `TS2578` per directive. Eleven directives across the file failed
   compilation simultaneously.

2. **`TS2741: Property 'streamState' is missing` in pre-existing fixtures** —
   PR2 folded `streamState` into the reducer-managed `ChatState` interface
   (response to a 3-reviewer convergence on the atomicity invariant — see
   PR #3469 review). Pre-existing test fixtures in
   `apps/web-platform/test/chat-reducer.test.ts` build `ChatState` literals
   directly via `emptyState()` and inline shape constructors (lines 5-12,
   51-57, 71-79). All three fixture sites missed the new field. The
   compile failure was four fixture sites at once, in a file that was not
   touched by the feature edit.

The shared root: a TypeScript-shape change at one site (the hook return type,
the reducer state interface) had a sweep cost in unrelated locations
(test directives, fixture constructors) that `tsc --noEmit` flagged
deterministically — but only AFTER the implementation was done. Neither
vitest nor the feature-specific tests caught these in the GREEN phase.

## Solution

For (1), the fix is mechanical: after GREEN, search the new test file for
`@ts-expect-error` and remove every directive whose underlying error has
been resolved. Vitest also surfaces this as a test failure with a clear
error message (`TS2578: Unused '@ts-expect-error' directive`), but
running `./node_modules/.bin/tsc --noEmit` is the deterministic gate.

For (2), the fix is to grep for every constructor of the widened type and
extend each one in the same edit cycle as the interface change:

```bash
# After widening ChatState with `streamState: StreamState`:
grep -rn "messages: \[\].*activeStreams: new Map" apps/web-platform/test/
# OR for any shape that builds ChatState directly:
grep -rn "ChatState\b" apps/web-platform/test/ apps/web-platform/lib/
```

Then add `streamState: "idle"` (or the type's appropriate default) to each
hit in the same commit that widens the interface.

A third related issue surfaced separately: `MockInstance` from vitest must
be imported explicitly when typing a `vi.spyOn` return — `ReturnType<typeof
vi.spyOn>` is too loose and doesn't unify with vitest's typed mock signature.
The existing `apps/web-platform/test/ws-client-resume-history.test.tsx`
demonstrates the right pattern (`import { ..., type MockInstance } from
"vitest"`); copying that import line at the start of any new spy-based test
prevents the regression.

## Key Insight

**TDD's RED-phase tools (`@ts-expect-error`, type-asserting mocks, exhaustive
fixtures) are scaffolding, not durable code.** Each tool's lifecycle ends at
GREEN. If the GREEN sweep is informal ("I'll fix tsc errors as I go"), the
sweep often lands AFTER the feature is "done" and surfaces as a flurry of
mechanical TS errors that look like a regression but are actually
unswept scaffolding.

The reducer-fixture variant is a more general pattern: **any pre-existing
type literal that builds an instance of an interface MUST be touched in the
same edit cycle that widens the interface**. `tsc --noEmit` is the deterministic
detector, but the sweep is a manual grep+edit pass — there's no "auto-fix"
for missing required fields. The cheapest preventative is to grep for the
type name (or a shape signature) before commit, AND to colocate
fixture-builder helpers (`emptyState()`) so a single edit is the only sweep
needed. The current `chat-reducer.test.ts` has both `emptyState()` and three
inline shape constructors — splitting the fixture across four sites is what
forced the four-site sweep.

## Prevention

1. **Run `./node_modules/.bin/tsc --noEmit` as part of the GREEN gate**, not
   just at "ready to ship" time. The work-skill's TDD Gate already runs the
   test suite after each RED→GREEN cycle; running `tsc --noEmit` in the same
   cycle catches `TS2578` (directive sweep) and `TS2741` (fixture sweep)
   immediately, before they accumulate across the whole feature.

2. **Centralize fixture builders.** When a test file builds the same `ChatState`
   shape in multiple places, extract a single `emptyState()` (or
   `withStreamState({...})`) helper and use it everywhere. This ensures a
   single-site sweep on interface changes. The `chat-reducer.test.ts` file
   has the helper but three test cases still build the shape inline — those
   three are the friction.

3. **`@ts-expect-error` directives carry an explicit lifetime comment.** The
   convention `// @ts-expect-error — <field> is added in this PR` makes the
   GREEN sweep trivial: a regex pass for `@ts-expect-error.*added in this PR`
   surfaces every directive ready for removal.

4. **For new spy-based test files, copy the `MockInstance` import from a
   sibling test file** rather than reaching for `ReturnType<typeof vi.spyOn>`.
   The existing `ws-client-resume-history.test.tsx` is the precedent — start
   from its template.

## Session Errors

These surfaced during the PR2 work session beyond the main implementation
investigation:

1. **Bare repo path resolution miss** — Initial `Read` on the spec file at
   `/home/jean/git-repositories/jikig-ai/soleur/knowledge-base/project/specs/feat-abort-conversation-web/tasks.md`
   returned "File does not exist" because that path is the bare-repo root,
   which has no working tree. Recovered by switching to the worktree path
   (`/home/jean/.../feat-abort-conversation-web-pr2/knowledge-base/...`).
   **Prevention:** AGENTS.md `hr-when-in-a-worktree-never-read-from-bare`
   already covers this; reinforce by always passing
   `<worktree-root>/<rel-path>` for absolute reads when in a worktree.

2. **Bash CWD non-persistence** — After
   `cd apps/web-platform && ./node_modules/.bin/vitest`, a follow-up
   `grep -rn` invoked from a separate `Bash` call returned "No such file or
   directory" because CWD did not persist across calls. Recovered by chaining
   with `&&` or absolute paths. **Prevention:** the work-skill already
   documents this; the rule is "chain `cd <abs-path> && <cmd>` in a single
   Bash call." Already enforced by skill instruction.

3. **PR1 test path didn't match plan path** — Plan §1.9 specified
   `apps/web-platform/server/__tests__/abort-turn.test.ts`; PR1 actually
   shipped at `apps/web-platform/test/server/abort-turn.test.ts`. Recovered
   via `git ls-tree -r HEAD --name-only | grep abort`. **Prevention:** when
   a multi-PR feature has merged predecessor PRs, verify the actual file
   locations of the merged PR's deliverables before honoring the plan's
   prescribed paths. The plan was written before PR1 was implemented; PR1
   diverged on test location; the plan was not retroactively edited. Adding
   "verify merged-PR file locations from `git ls-tree HEAD` before starting
   the next PR" to the work-skill's Phase 1 would close the gap.

4. **`TS2578` unused `@ts-expect-error` directives** — Eleven directives
   placed during RED became unused after GREEN; `tsc --noEmit` errored.
   **Prevention:** see §Solution + §Prevention above. The work-skill could
   add a Phase 2.5 step "after each RED→GREEN transition, grep the test file
   for `@ts-expect-error` and remove resolved directives" — but this is a
   skill-instruction-level fix that's small enough to leave as a Sharp Edge
   note rather than a hook.

5. **`TS2741` missing `streamState` in fixtures** — Pre-existing
   `chat-reducer.test.ts` fixtures missed the new field after the reducer
   state was widened. **Prevention:** see §Prevention above. The fix is a
   workflow practice, not a hook — there's no static analysis path for
   "field constructors that must be updated alongside an interface widening."

6. **`fetchSpy` type mismatch** — `let fetchSpy: ReturnType<typeof vi.spyOn>`
   is too loose and doesn't unify with vitest's typed mock signature.
   **Prevention:** copy the import line from
   `ws-client-resume-history.test.tsx` (which uses `import { ..., type
   MockInstance } from "vitest"; let fetchSpy: MockInstance;`). See §Solution.

## Related

- AGENTS.md `cq-write-failing-tests-before` (the TDD Gate that surfaces these
  scaffolding-sweep concerns when followed strictly).
- AGENTS.md `cq-ref-removal-sweep-cleanup-closures` (the sibling pattern for
  React `useRef` cleanups — same "sweep at the end" mechanic).
- `knowledge-base/project/learnings/best-practices/2026-04-27-wrapper-extension-test-mock-chain-sweep.md`
  (data-layer fluent-API extension sweep — same general class of "extend an
  interface, sweep the test mocks in the same edit cycle").
- PR #3469 (this PR; landed the streamState reducer fold + the fixture sweep).
