# Learning: A behavior-reversal fix flips the existing test asserting the OLD behavior — that flip IS the RED

## Problem

PR #4713 (#4715) reverses a behavior that a PRIOR PR (#4641) deliberately
introduced: #4641 made a keyless invitee's validated `/invite/<token>` next-hop
get *wrapped* onto `/setup-key?redirectTo=…` (carry-forward through onboarding);
#4715 makes the invite target *outrank* `/setup-key` and return directly. The
existing test `test/accept-terms-redirect-to.test.ts` encoded #4641's behavior
verbatim:

```ts
test("no-key user with redirectTo → /setup-key CARRIES the target forward …", () => {
  expect(json.redirect).toBe(`/setup-key?redirectTo=${encodeURIComponent("/invite/tok123")}`);
});
```

The naive TDD instinct ("write a NEW failing test") would have created a second
test asserting the new behavior while the old test still asserted the reversed
behavior — leaving a contradictory pair where GREEN is impossible.

## Solution

For a behavior-reversal fix, the RED step is to **flip the existing assertion**
that encodes the old behavior, not to add a parallel test. The flipped assertion
fails against current code (RED); the implementation guard makes it pass (GREEN).
Keep a sibling test for the *unchanged* slice (here: non-invite keyless signups
still carry forward to `/setup-key`) so the reversal is scoped, not total.

Same shape recurred in the callback site: the buggy keyless-not-skipped branch
was exercised by adding the flipped case to `test/e2e-oauth-tc-consent.test.ts`,
which already had the mock infrastructure (`stubServiceUsersFullyOnboarded`,
`mockUserHasEffectiveByokKey`) — reuse the route's existing test home rather than
spawning a parallel file that becomes an orphan suite.

## Key Insight

When a fix intentionally reverses prior behavior, the test encoding the prior
behavior is not "a passing test to leave alone" — it is the precise RED signal.
Grep the route's existing test files first; the assertion to flip is already
written. A new parallel test risks a contradictory pair and an orphan suite.

## Session Errors

1. **Plan path was worktree-relative; first Read failed against bare-repo CWD.**
   The `/soleur:work` arg gave `knowledge-base/project/plans/…plan.md` but the
   session CWD was the bare repo root, not the worktree. — Recovery: `git
   worktree list`, then read from `.worktrees/<branch>/…`. — **Prevention:** when
   a pipeline arg names a plan path alongside a worktree, resolve the path
   against the worktree root before the first Read.

2. **tsc TS2322 — boolean gate consumed in a narrowing branch.**
   `isInviteReturnTarget(nextHop): boolean` left `nextParam` as `string|null` in
   `isInviteReturnTarget(nextParam) ? nextParam : "/setup-key"`. — Recovery:
   declared it `nextHop is string` (type predicate). — **Prevention:** when a
   `string|null` value is selected by a boolean helper in a ternary/branch whose
   true-arm uses the value as a non-null string, write the helper as a type
   predicate from the start so the narrowed branch typechecks.

3. **Route test broke when a new server-helper dependency was wired in.**
   Adding `userIsSharedWorkspaceMember` to `GET /api/byok/effective-status`
   broke its existing test (the createClient mock had no `from` chain for the
   new call). — Recovery: mocked `@/server/workspace-resolver` wholesale and
   updated the response-shape `.toEqual` assertions in the same edit. —
   **Prevention:** when a route gains a new `@/server/*` dependency, sweep that
   route's test file's mocks (add the dependency mock + extend any response-shape
   assertions) in the same cycle, before running the suite.

4. **Plan file "modified since read" on Edit (linter touched it).** — Recovery:
   re-read then re-edited. — **Prevention:** none needed; tooling race, the
   Read-again-then-Edit recovery is correct.

## Review Findings (fixed inline, same session)

- A fail-quiet membership probe (`userIsSharedWorkspaceMember`) initially did NOT
  mirror its error path to Sentry, while two sibling resolvers in the SAME file
  did (`cq-silent-fallback-must-mirror-to-sentry`). data-integrity-guardian
  caught it. **Reusable check:** when adding a fail-quiet helper next to siblings
  in the same module that already `reportSilentFallback`, copy the mirror — a
  degraded read on an integrity surface must page, not pino-stdout-only.

## Tags
category: test-failures
module: apps/web-platform (auth redirect gates, workspace-resolver)
