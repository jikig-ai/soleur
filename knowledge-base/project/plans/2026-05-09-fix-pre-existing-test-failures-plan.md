---
issue: 3035
type: fix-test
classification: verification-and-close
requires_cpo_signoff: false
---

# fix(test): pre-existing chat-page + kb-chat-sidebar test failures on main

Issue: #3035

## Overview

Issue #3035 was filed on 2026-04-29 against commit `62581167` reporting 13 vitest failures across 8 files in `apps/web-platform/test/` — all variants of `Found multiple elements with the text: roadmap.md` (or similar duplicate-text getByText ambiguity in `getByText`). Symptom-cause: a recently-shipped layout change rendered the filename in two places simultaneously (sidebar header + breadcrumb), and the `getByText` queries had not been narrowed.

**Current state (verified 2026-05-09 on commit `cc138d11` + worktree init):** all 8 affected test files pass, and the full vitest suite passes (3956 / 4007 tests, 51 skipped, 0 failed). The failures described in #3035 have been fixed indirectly by intermediate PRs landed between issue-filing (2026-04-29) and now (2026-05-09).

This plan is therefore not a fix-plan — it is a **verify-and-close** plan: confirm resolution, identify the fixing PR(s), close the issue with a one-line comment citing the verification, and add a regression-guard test entry only if a same-class bug pattern still exists.

## Research Reconciliation — Spec vs. Codebase

| Spec / Issue Claim | Codebase Reality (2026-05-09) | Plan Response |
| --- | --- | --- |
| 8 test files / 13 tests failing on main | All 8 files pass; full suite 3956/4007 pass, 0 failed | Verify + close issue. No code change needed. |
| Symptom: `Found multiple elements with the text: roadmap.md` (duplicate-text rendering in sidebar header + breadcrumb) | Not reproducible; no `getByText('roadmap.md')` ambiguity surfaces | Identify fixing PR(s) for the close-comment trail. |
| Filed against commit `62581167` (2026-04-29) | Worktree branched from `cc138d11` (2026-05-08, 9 days later); PRs #3237, #3240, #3276, others touched chat surface in between | Likely fixers: PR #3240 brand-rename (Command Center → Dashboard) tightened `chat-surface-sidebar.test.tsx` negative-space assertion to header scope; PR #3237 corrected trigger label. |

## Open Code-Review Overlap

None. (Code-review query returned no open scope-outs touching these test files.)

## User-Brand Impact

**If this lands broken, the user experiences:** N/A — verification-only PR. No user-facing surface changes.
**If this leaks, the user's data is exposed via:** N/A — no production code, no credentials, no schema, no feature flag.
**Brand-survival threshold:** none — test cleanliness only.

Rationale: this PR closes a tracking issue for failures that no longer reproduce. Sensitive-path scope-out: closing an issue does not touch any sensitive code path.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Verify: `cd apps/web-platform && npx vitest run test/chat-page.test.tsx test/chat-page-resume.test.tsx test/chat-surface-sidebar.test.tsx test/chat-surface-sidebar-wrap.test.tsx test/kb-chat-sidebar.test.tsx test/kb-chat-sidebar-a11y.test.tsx test/kb-chat-sidebar-banner-dismiss.test.tsx test/kb-chat-sidebar-quote.test.tsx` passes 8 files / 74 tests with 0 failures (re-run on the feature branch HEAD).
- [ ] Verify: full vitest suite (`cd apps/web-platform && npx vitest run`) passes with 0 failures (skipped count may vary). Capture the pass/fail/skip summary in the PR body.
- [ ] Identify the fixing PR(s) from the merge log between baseline `62581167` and the current branch HEAD; cite them in the PR body and in the issue close-comment.
- [ ] Confirm no test in the 8 files still uses an unscoped `getByText('roadmap.md')` (or similar bare filename) — grep `apps/web-platform/test/` for `getByText('roadmap.md')` and `getByText("roadmap.md")` and assert the only matches are inside `getAllByText` / `within(...)`-scoped queries OR are uniquely rendered.
- [ ] PR body uses `Closes #3035` on its own body line (per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

- [ ] Verify GitHub auto-closed #3035 from the `Closes #3035` body line; if not, run `gh issue close 3035 -c "Verified resolved by …; full vitest suite green at <branch>@<sha>."`.

## Implementation Phases

### Phase 0 — Pre-flight (read-only verification)

- Re-run the 8 affected test files locally on the worktree HEAD.
- Re-run the full vitest suite to confirm zero failures across the broader suite (defense against same-class regressions in adjacent files).
- Record the pass/fail summary and the worktree SHA for the PR body.

### Phase 1 — Fixer-PR triage (close-comment trail)

Reconstruct the merge log between `62581167` (issue-filing baseline) and current `HEAD`, scoped to:

- `apps/web-platform/test/{chat-page,chat-page-resume,chat-surface-sidebar,chat-surface-sidebar-wrap,kb-chat-sidebar,kb-chat-sidebar-a11y,kb-chat-sidebar-banner-dismiss,kb-chat-sidebar-quote}.test.tsx`
- `apps/web-platform/components/chat/{kb-chat-sidebar,chat-surface,chat-page,kb-chat-trigger}.tsx`
- `apps/web-platform/components/kb/`

Likely fixers (preliminary):

- **PR #3240** (commit `228e2454`, merged 2026-05-05) — brand rename "Command Center" → "Dashboard", tightened `chat-surface-sidebar.test.tsx` negative-space assertion to header scope (12 lines changed). The brand-rename eliminated one of the two duplicate-string sources by definition.
- **PR #3237** (commit `89be22bc`) — `fix(kb-chat): hydrate prior messages on resume + correct trigger label`.
- **PR #3276** (commit `b6bed202`) — `fix(cc-chat): keep Soleur Concierge visible in routing panel`.
- **PR #3324** / **PR #3326** — theme + reaper fixes that touched chat surface.

Cite the fixing PR(s) in both the close-comment and the PR body. If the symptom ("duplicate `roadmap.md` text") is traceable to a specific PR's diff, name it; if it was eliminated by the cumulative effect of several PRs, list them.

### Phase 2 — Regression-guard scan (no-code-change assertion)

For the 8 affected test files, grep for unscoped bare-filename `getByText` patterns:

```bash
rg "getByText\(['\"]roadmap\.md['\"]" apps/web-platform/test/
rg "getByText\(['\"]readme\.md['\"]" apps/web-platform/test/
rg "getByText\(['\"]constitution\.md['\"]" apps/web-platform/test/
```

If any unscoped match exists in code that runs (i.e., not inside `// @ts-expect-error`-disabled or `it.skip(...)`), flag it as a same-class trap and convert to `getAllByText` + index OR `within(container)` scope. If zero matches surface, the code is robust against the original duplicate-text class — record the grep output in the PR body as the regression-guard evidence.

### Phase 3 — PR + issue close

- Create a small PR that updates this plan + tasks document (no production-code changes expected).
- PR body uses `Closes #3035` on its own body line.
- Include the verification log (8-file pass + full-suite pass) and the fixing-PR trail.

## Files to Edit

- `knowledge-base/project/plans/2026-05-09-fix-pre-existing-test-failures-plan.md` (this file — already created)
- `knowledge-base/project/specs/feat-one-shot-3035-pre-existing-test-failures/tasks.md` (created in Save Tasks step)

## Files to Create

(None — verification-only plan.)

If Phase 2 surfaces a same-class trap, the plan upgrades to **MINIMAL+1 fix tier** and the affected test file is added to "Files to Edit" inline. The expected outcome is zero traps and zero file edits.

## Test Strategy

- **Local vitest run** on the 8 affected files — all pass.
- **Full vitest suite** — confirms no adjacent same-class failures.
- **Regression grep** — Phase 2 scan documents the absence of unscoped bare-filename `getByText`.
- **No new tests are added.** Adding a synthetic regression test for a fixed indirect-symptom failure would couple the test to brittle internals that have already been refactored away.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan: threshold = `none` with rationale.)
- This issue's close-comment MUST cite the fixing PR(s). Closing as "fixed in unrelated work" without identifying which work is the kind of soft-close that hides regression vectors. Phase 1 is the load-bearing identification step; do not skip.
- If Phase 0 verification fails (a test newly fails on the worktree HEAD that wasn't failing on origin/main), STOP. The plan reverts to a real fix-plan and the duplicate-text source must be located in the rendered DOM tree before re-issuing the PR.
- When the PR body says "Closes #3035", confirm via `gh pr view <N> --json closingIssuesReferences` post-creation that GitHub recognized the close-link. Markdown lists / checkboxes / code blocks make `Closes #N` invisible to GitHub's parser per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`. The bare body line `Closes #3035` is the canonical form.
- Per AGENTS.md `wg-when-tests-fail-and-are-confirmed-pre`: pre-existing failures without a tracking issue normalize a red suite. This issue WAS the tracking issue — closing it as resolved (with the close-comment trail) is the workflow-compliant exit. Do not silently delete the issue or close as "won't-fix".

## Domain Review

**Domains relevant:** none.

No cross-domain implications detected — verification-only PR closing a tracking issue for failures that no longer reproduce. No user-facing surface, no schema, no credentials, no infra. Skipping `Product/UX Gate`, `CTO`, `CMO`, etc. per AGENTS.md `pdr-do-not-route-on-trivial-messages-yes` analog ("the domain signal IS the current task's topic" — engineering test-cleanup is the topic).

## Hypotheses

(Network-outage gate did not fire — issue is not SSH/network-related. Skipped.)

The duplicate-text rendering bug (`Found multiple elements with the text: roadmap.md`) was caused by a transient layout state where the filename was rendered in two simultaneous DOM positions (sidebar header + a sibling chrome element). Likely root cause: PR #2347 (kb-chat-sidebar feature) and PR #2500 (sidebar cleanup) shipped a layout where the `kb-chat-sidebar.tsx` header rendered the filename AND the parent `chat-surface.tsx` exposed it via a breadcrumb / aria-label / data attribute that `getByText` matched. Subsequent refactors (PR #3240 brand-rename, PR #3237 trigger-label correction, PR #3276 routing-panel scope) eliminated one of the two render sites or changed the surrounding text such that the queries no longer match double.

This hypothesis is **not load-bearing** for the plan — the plan is verify-and-close, and the close-comment cites fixing PR(s) by merge log inspection, not by hypothesis verification.
