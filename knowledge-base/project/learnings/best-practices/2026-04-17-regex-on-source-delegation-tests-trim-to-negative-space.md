---
name: regex-on-source delegation tests trim to negative-space only
description: When using source-text regex assertions as a negative-space regression gate after extracting a helper, keep only the assertion that cannot be replicated behaviorally (absence of a specific symbol). Drop positive assertions (import present, call present) — they are transitively proven by the existing end-to-end tests and are brittle under legitimate refactors (barrel re-exports, aliases, formatting).
type: best-practice
category: testing
module: test-design
---

# Regex-on-source delegation tests trim to negative-space only

## Problem

After extracting `prepareUploadPayload` from the KB upload route (PR #2502), the
plan prescribed a dedicated test file with three regex-on-source assertions:

1. Route source matches an import regex for the helper.
2. Route source matches `await prepareUploadPayload(` regex.
3. Route source does NOT match `linearizePdf(` (negative-space).

Four review agents independently flagged the positive assertions (#1 and #2) as
brittle. They duplicate coverage from the existing end-to-end route tests
(which mock `linearizePdf` and verify bytes reach the GitHub PUT body —
transitively proving the helper is invoked), and they fail on harmless edits
like:

- Renaming the import to an alias (`import { prepareUploadPayload as prep }`).
- Routing the symbol through a barrel re-export.
- Reformatting whitespace around `await`.

The negative-space assertion (#3) has no behavioral equivalent: a future edit
could add an inline `linearizePdf(` call *alongside* the helper call, and every
behavioral test would still pass because the helper branch still fires.

## Solution

Keep only the negative-space assertion. Delete the positive regex assertions.

## Key Insight

**Negative-space regression gates belong in source-regex tests only when they
assert something mock-based tests cannot express.** Asserting "a symbol is
absent from a file" requires reading the file as text. Asserting "the route
calls the helper" does not — it's a mock-and-spy pattern. Mixing the two
approaches duplicates coverage at the cheap layer (behavioral tests) and
increases coupling at the expensive layer (source-regex tests).

The plan over-specified the gate by copying all three assertions from the
source learning (`2026-04-15-negative-space-tests-must-follow-extracted-logic.md`).
That learning's point is about *preserving the negative-space gate* after an
extraction — it never said to also add positive assertions. The positive
assertions were a defensive addition that reviewers correctly identified as
noise.

## Session Errors

- **Plan internal contradiction on Sentry message string** — Helper Contract and Acceptance Criteria specified `"pdf linearization failed"`; Scenario 3 and Test Implementation Sketch used `"pdf linearization failed, committing original"`. Recovery: cross-checked pre-refactor route source to pick the Sentry-continuity string. Prevention: during /deepen-plan, scan explicit string-literal occurrences in the plan for inconsistencies (the deepen pass already rewrites tests; string mismatches between tests and the helper contract are a detectable class of drift).
- **Proof-of-delegation test collided with existing `node:fs` mock** — placing regex-on-source assertions inside `kb-upload.test.ts` (which mocks `node:fs` with only `writeFileSync`/`unlinkSync`) caused "No `readFileSync` export defined" at test collection. Recovery: moved to a standalone file. Prevention: when adding source-reading regex tests, always use a standalone test file — never add them to an existing test file that already mocks `node:fs` or `node:path`.
- **One Edit-tool string-not-found miss on the Acceptance Criteria section during planning** (forwarded from session-state.md). Recovery: re-read and retried successfully. Prevention: already covered by AGENTS.md `hr-always-read-a-file-before-editing-it`.

## Related

- `knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md` (source learning — this refines the three-assertion pattern down to one).
- PR #2502 (extraction + review-fix inline commits).
- Issue #2474 (scope-out rationale for the narrow extraction).
