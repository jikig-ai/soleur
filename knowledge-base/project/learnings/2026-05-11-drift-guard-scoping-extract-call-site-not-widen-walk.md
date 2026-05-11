---
date: 2026-05-11
category: best-practices
module: testing-drift-guards
tags: [drift-guard, sentry-tag-coverage, scoping, refactor, multi-agent-review]
related-prs: [3576]
related-issues: [3039]
---

# Learning: Drift-guard scoping — extract the call site, don't widen the walk

## Problem

The dashboard sidebar's `Sign out` button (`apps/web-platform/app/(dashboard)/layout.tsx`) needed a `reportSilentFallback` mirror with `feature: "auth"` + `op: "signOut"` tags so the Sentry alert pipeline could page on signout failures.

The existing drift-guard in `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` walks two source directories (`app/(auth)` and `components/auth`) for files calling any of five auth verbs, and demands every match include `feature: "auth"` + `op:"<verb>"` literals. The walk did NOT include `app/(dashboard)`.

The work-phase implementation took the shortest path: add `"signOut"` to `AUTH_VERBS` AND add `"app/(dashboard)"` to `AUTH_DIRS`. Tests passed. CI would have been green.

## Root Cause

The drift-guard's directional rule was *"auth verbs live in auth-owned directories."* Widening `AUTH_DIRS` to a 16-file route group containing settings, KB, chat, admin etc. inverted that rule into *"any file in the dashboard that happens to call an auth verb must carry auth Sentry tags."* The guard now follows the call site instead of the call site following the architectural convention. Every future settings/admin/etc. file that legitimately calls `.signOut(` for a non-paging reason would either fail the test or be coerced into carrying `feature:"auth"` tags it doesn't deserve.

This was a `pr-introduced` widening — the PR itself caused the regression — and would not have surfaced in unit tests, lint, or `tsc`. It surfaced only via two independent review agents (architecture-strategist P1, code-quality-analyst P2 D10) running in parallel.

## Solution

Extract the call site into the existing tight scope. Concretely:

1. Move `handleSignOut` from `app/(dashboard)/layout.tsx` into a new hook `apps/web-platform/components/auth/use-sign-out.ts` exporting `{ handleSignOut, isSigningOut }`.
2. Layout calls `const { handleSignOut, isSigningOut } = useSignOut();` and renders the modal as before.
3. Revert `AUTH_DIRS` back to `["app/(auth)", "components/auth"]`. The new hook lives in `components/auth/` so the existing walk finds it.

The drift-guard's directional rule is preserved, the new hook is reusable for any future "sign out from all devices" / settings-page sign-out / etc., and the layout file shrinks by ~30 lines.

## Key Insight

**Drift-guards encode an architectural convention, not a coverage requirement.** When a new call site needs guard coverage:

1. Identify the convention the guard encodes (e.g., "auth logic lives in `app/(auth)` + `components/auth`").
2. Move the call site to honor the convention.
3. Don't widen the guard's walk — that erases the convention.

The shortest path (widen the walk) usually leaves a worse architecture than the original. The slightly-longer path (extract to the convention's home) leaves a better one.

**Generalization:** This applies to any boundary-enforcing test in the codebase — CSRF coverage scanners, RLS audit walks, secret-scan path filters, dependency-injection conformance checks. When you encounter one and your new code is "outside" its walk, the right question is "should my code be inside?" not "should the walk be wider?"

## Prevention

- During plan / deepen-plan: when a plan proposes extending a drift-guard's `*_DIRS` / `*_PATHS` / `*_GLOBS` array, treat that as an architectural-pivot signal and require a 1-sentence justification *or* a refactor that puts the call site in the existing scope.
- During work-phase TDD GREEN: before extending such an array, run `git log -p -- <test-file> | grep -c "+ *.*_DIRS"` to see how often the array has been widened historically. Repeated widening is a code smell that the test has lost its convention.
- During review: pattern-recognition-specialist and architecture-strategist agents reliably catch this. The two-agent parity is load-bearing — a single review agent can miss it.

## Session Errors

**AUTH_DIRS widening was wrong architectural direction.**
- Recovery: extracted `handleSignOut` to `components/auth/use-sign-out.ts`; reverted AUTH_DIRS.
- Prevention: see "Prevention" section above. The bullet on the work skill's Phase 2 "Follow Existing Patterns" sub-step should call out drift-guard array extension as a refactor signal.

**Missing local-state purge on signOut failure (shared-device leak).**
- Recovery: in both `signOut.resultError` and `signOut.throw` branches, follow up with `supabase.auth.signOut({ scope: "local" })` before redirecting.
- Prevention: when the plan's User-Brand Impact paragraph names a "shared-device leak" or any session-cookie-survives-failure scenario, work-phase MUST add a test that mocks the server signOut as failing AND asserts a local-only fallback runs before `/login` redirect. The plan documented the threat but the implementation only added Sentry visibility, not mitigation.

**Focus-trap selector didn't filter `:disabled`.**
- Recovery: added `:not(:disabled)` filter to the focusable query, plus an empty-NodeList early return.
- Prevention: the canonical focus-trap implementation in `cancel-retention-modal.tsx:42-44` has the same bug and was copy-pasted. When porting a focus-trap from a precedent, audit the disabled-button case in the new context — if the new modal has a button that can transition to disabled while open (sign-out's `isSigningOut`, payment forms' `isProcessing`, etc.), the precedent's selector needs `:not(:disabled)`.

**Sidebar/modal accessible-name collision + label mutation.**
- Recovery: `inert={signOutModalOpen}` on `<aside>` so the sidebar button leaves the a11y tree while the modal is open; pinned `aria-label="Sign out"` + `aria-busy` on the modal confirm so the accessible name stays stable across visual states.
- Prevention: when a modal's trigger button shares a name with the modal's confirm button, the modal MUST either `inert` the trigger's container or use a disambiguating `aria-label` on confirm. When a button's visible text mutates mid-flow (e.g., "Sign out" → "Signing out…"), pin the accessible name via `aria-label` so agent-driven E2E selectors and screen-reader announcements stay stable.

**`Closes #3039` fold-in missed item 3 (Sentry alert rule).**
- Recovery: added a 4th rule `auth-signout-burst` to `apps/web-platform/scripts/configure-sentry-alerts.sh`.
- Prevention: when a plan's "Open Code-Review Overlap" section folds in an issue via `Closes #N`, the plan author MUST enumerate every numbered item in the issue's Proposed Fix section and either (a) include each in the plan's Acceptance Criteria, or (b) explicitly note which items are deferred and why. Asserting that a sub-item is "a triage heuristic, not a quality bar" is a unilateral redefinition of the issue's contract — file a comment on the issue first.

**Untested `signOut.resultError` and backdrop-while-signing-out branches.**
- Recovery: added two tests.
- Prevention: when an error branch produces a distinct Sentry `extra.stage` tag, that tag IS the test target — a Sentry stage tag with no test is a contract claim the test suite can't enforce. Same for visual states (`isSigningOut=true`) gating event handlers — every gated handler needs a test that the gate works AND a test that the open state still works.

**`vi.mock` factory referencing non-hoisted variable + TypeScript narrowing on signOutMock factory.**
- Recovery: wrap mock-state declarations in `vi.hoisted(() => (...))`; explicit return-type annotation on the factory to permit wider mockImplementationOnce values.
- Prevention: these are already covered by existing rules in the work skill ("When creating test files with `vi.mock()` factories that reference shared variables, use `vi.hoisted()` from the start") — the failure was discoverability, not the rule's absence. No new rule needed; agent missed the existing one.

**Bash CWD doesn't persist across calls.**
- Recovery: chain `cd <abs-path> && <cmd>` in a single Bash call, or use absolute paths.
- Prevention: already covered by the work skill's "Test Continuously" section. No new rule needed.

**`rg -t tsx` rejected.**
- Recovery: switched to `-g '*.tsx'`.
- Prevention: discoverability-class (clear error, no silent failure). No rule.

**Tried to Edit a file I'd only `Bash`-head'd, not `Read`.**
- Recovery: Read first.
- Prevention: discoverability-class (Edit tool error). Already covered by `hr-always-read-a-file-before-editing-it`.

## Related

- PR #3576 (this PR) — adds sign-out confirmation modal and the refactor described above.
- Issue #3039 — open code-review fold-in for Sentry mirror + drift-guard coverage on signOut.
- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — broader pattern of multi-agent review catching defects unit tests miss.
- `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` — the drift-guard in question.
- `apps/web-platform/components/auth/use-sign-out.ts` — the extracted hook.
- `apps/web-platform/scripts/configure-sentry-alerts.sh` — Sentry alert rule registration (now includes `auth-signout-burst`).
