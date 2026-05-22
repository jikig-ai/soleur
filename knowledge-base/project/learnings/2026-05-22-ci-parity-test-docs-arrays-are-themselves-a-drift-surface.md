---
title: "CI parity-test DOCS arrays are themselves a drift surface"
date: 2026-05-22
category: process
component: ci/legal-doc-consistency
related_pr: 4289
related_issue: 4324
tags: [ci, parity-test, drift, legal-docs, scope-creep]
---

# CI parity-test DOCS arrays are themselves a drift surface

## Problem

PR #4289 added the §Workspace Members section to `docs/legal/terms-and-conditions.md`, `docs/legal/acceptable-use-policy.md`, and their Eleventy mirrors at `plugins/soleur/docs/pages/legal/*.md`. The PR claimed `legal-doc-consistency.test.ts` (22/22 passing) gated canonical↔mirror parity.

Multi-agent review (`git-history-analyzer` led, `data-integrity-guardian` + `pattern-recognition-specialist` concurred) caught a P1 regression that the test silently ignored:

- `docs/legal/acceptable-use-policy.md` frontmatter `last-updated: 2026-05-18` was stale (mirror had `May 22, 2026`).
- The `**Last Updated:**` chain skipped the May 21 entry (Template-authorization revocation, PR-I #4078) and had wrong tail "previous: April 10, 2026" (mirror said March 29).

Root cause: `legal-doc-consistency.test.ts:29-35` had a hardcoded `DOCS` array that included `individual-cla`, `corporate-cla`, `privacy-policy`, `data-protection-disclosure`, `gdpr-policy` — but NOT `acceptable-use-policy` or `terms-and-conditions`. AUP and T&C had been added to canonical+mirror in prior PRs without ever extending the DOCS array. The parity gate had zero coverage on the two docs the team edits most often.

## Solution

Two-layer fix (PR #4289):

1. **Inline:** extended `DOCS` to cover `acceptable-use-policy` + `terms-and-conditions`. Required a paired edit to the T&C mirror (`plugins/soleur/docs/pages/legal/terms-and-conditions.md`) to add a `Last Updated <date>` line in the `<section class="page-hero">` block — the test's hero-date assertion exposed a pre-existing schema gap when the array was extended.
2. **Deferred (issue #4324, `deferred-scope-out`):** generalize `apps/web-platform/scripts/check-tc-document-sha.sh` from SHA-pinning only the T&C canonical to SHA-pinning all 9 legal docs, and lift the heading-sequence + sentinel test into a body-equivalence assertion.

The clean long-term shape would derive `DOCS` from a filesystem glob (`docs/legal/*.md` minus any explicitly skipped entries) instead of maintaining a hardcoded list — a hardcoded artifact list IS the drift surface.

## Key Insight

**When a CI parity test takes a hardcoded list of artifacts to compare, the list itself is a drift surface.** New artifacts added to one side (canonical or mirror) without updating the list have zero coverage indefinitely. The local test suite reports "all green" while the regression sits in production.

Generalized form: any test fixture whose scope is a hand-edited enumeration of "what to check" has a parallel obligation — every time the universe of "what to check" grows, the fixture must grow. This obligation is invisible at the time the new artifact is added; it only surfaces when the regression happens.

Three mitigations, in order of strength:

1. **Derive scope from filesystem.** `DOCS = glob('docs/legal/*.md')` removes the obligation entirely. Cost: a one-off skip-list for files that should not be parity-checked (e.g., a draft).
2. **Schema-attach the scope.** Move the list to a `legal-doc-registry.json` next to the docs themselves; the test reads the registry. Lower than glob but higher than inline arrays.
3. **Sentinel-test the test.** Add a meta-assertion: `expect(DOCS.length).toBeGreaterThanOrEqual(N)` where N is asserted-correct at the time the test is written. Breaks loudly when someone deletes a doc; still misses additions.

In this repo, also applies to: `__tests__/` snapshot lists, Vercel ignored-routes arrays, vector.toml route-class registries, MCP server allowlists, plugin component lists in `plugin.json`.

## Session Errors

1. **Working-directory drift between Bash calls** — `sed -n` on `apps/web-platform/test/legal-doc-consistency.test.ts` failed because a prior `cd apps/web-platform` persisted across the Bash call boundary. Recovery: re-`cd` to worktree root. **Prevention:** prefix multi-step Bash commands with explicit `cd <worktree>` or use absolute paths anchored at the worktree root.
2. **Edit-before-Read on `legal-doc-consistency.test.ts`** — first Edit call failed; recovered by Read then Edit. Already hook-enforced by Edit tool; no new rule needed.
3. **T&C mirror hero schema gap surfaced under test extension** — adding `terms-and-conditions` to `DOCS` triggered a hero-date assertion failure because the T&C mirror's `<section class="page-hero">` lacked the `Last Updated <date>` pattern other mirrors use. **Prevention:** when extending a parity-test's scope, dry-run before deciding inline-vs-scope-out — the surfaced gap is part of the cost of the extension and must be fixed in lockstep.
4. **frontend-anti-slop scanner produced 0 hits despite an eligible file** — `apps/web-platform/app/(auth)/accept-terms/page.tsx` should have matched the scanner regex `(apps/web-platform/(app|components)/.*\.(tsx|jsx|css))$` but the scanner reported no eligible files. The parenthesized `(auth)` route-group component is a Next.js path convention; the scanner's regex may treat the inner `(auth)` as a capture group rather than literal text. Uninvestigated this session. **Prevention:** add a Next.js route-group test case to the scanner's smoke tests; file follow-up to verify regex behavior against `app/(group)/*.tsx` paths.

## References

- PR: #4289 (commit `29d80b80` — `review: AUP canonical history-drift + extend mirror-parity DOCS + TC_BUMP_METADATA constant`)
- Scope-out: #4324 (generalize SHA + mirror-equivalence to all 9 legal docs)
- Test: `apps/web-platform/test/legal-doc-consistency.test.ts`
- Canonical: `docs/legal/{terms-and-conditions,acceptable-use-policy}.md`
- Mirror: `plugins/soleur/docs/pages/legal/{terms-and-conditions,acceptable-use-policy}.md`
