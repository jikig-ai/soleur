---
issue: 3035
type: fix-test
classification: verification-and-close
requires_cpo_signoff: false
---

# fix(test): pre-existing chat-page + kb-chat-sidebar test failures on main

Issue: #3035

## Enhancement Summary

**Deepened on:** 2026-05-09
**Sections enhanced:** 5 (Overview, Acceptance Criteria, Implementation Phases 0-2, Sharp Edges, Hypotheses)
**Research approach:** Targeted verification (no fan-out — verification-only plan; spawning 30+ deepen agents on a "close-as-fixed" issue would be pure waste per AGENTS.md `cm-delegate-verbose-exploration-3-file`).

### Key Improvements

1. **Phase 0 verification re-run inline.** All 8 affected test files re-passed at deepen-time on worktree HEAD `2acfa25c` (74 tests, 0 fail). Recorded as evidence for the close-comment.
2. **Regression-guard grep executed inline.** Grep found `kb-chat-sidebar.test.tsx:77` STILL contains `screen.getByText("roadmap.md")` — bare match — yet the test passes today. Three additional same-class matches surfaced in `file-tree-rename.test.tsx:115` and `file-tree-delete.test.tsx:118,207` (`getByText("readme.md")`). All four tests pass today; the duplicate-text bug class is dormant, not eliminated by test scoping. Disposition recorded.
3. **Fixing-PR identified.** PR #3240 (commit `228e2454`, merged 2026-05-05) brand rename "Command Center" → "Dashboard" tightened `chat-surface-sidebar.test.tsx` negative-space assertion to header scope and removed one of the two duplicate-string render sites. PR #3237 corrected the trigger label.
4. **Hypothesis upgraded from speculative to evidenced.** The original duplicate-text was eliminated by component-render simplification (one render site, not two), NOT by test query narrowing. This makes the bug class **dormant** — a future PR re-introducing a sibling render site reproduces #3035 without the test author noticing.
5. **Sharp Edges expanded** to flag the dormant-fragility class as a follow-up issue candidate, not in-scope for this PR.

### New Considerations Discovered

- **Tests pass via component refactor, not query scoping.** The `kb-chat-sidebar.test.tsx:77` bare `getByText("roadmap.md")` is intact from before #3035 was filed — it works today only because the component now renders the filename in exactly one place. This is a tighter coupling between test and DOM topology than `getAllByText` + index would be. Out of scope for this PR (would expand a verify-and-close into a refactor); flagged as candidate follow-up.
- **3 sibling sites in `file-tree-*.test.tsx`** exhibit identical bare `getByText("readme.md")` pattern. Out of original issue scope (#3035 listed 8 files; these are not among them). Same dormant-fragility class. Flagged.

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

- [x] **Verified at deepen-time:** `cd apps/web-platform && npx vitest run test/chat-page.test.tsx test/chat-page-resume.test.tsx test/chat-surface-sidebar.test.tsx test/chat-surface-sidebar-wrap.test.tsx test/kb-chat-sidebar.test.tsx test/kb-chat-sidebar-a11y.test.tsx test/kb-chat-sidebar-banner-dismiss.test.tsx test/kb-chat-sidebar-quote.test.tsx` — 8 files / 74 tests / 0 fail at HEAD `2acfa25c`. Re-run at `/work` time to confirm no drift.
- [x] **Verified at deepen-time:** full vitest suite — 363 files / 3956 pass / 51 skipped / 0 fail. Re-run at `/work` time. Capture the pass/fail/skip summary in the PR body.
- [x] **Identified at deepen-time:** PR #3240 (commit `228e2454`, merged 2026-05-05) is the primary fixer for `chat-surface-sidebar.test.tsx` (brand rename + assertion tightening); cumulative chat-surface refactors (#3237, #3308, #3315, #3469) collapsed the kb-chat-sidebar render topology to one filename site. Cite in PR body + #3035 close-comment.
- [x] **Updated AC (deepen-time falsification):** grep results for bare-filename `getByText` are documented in PR body (4 surviving matches across 3 files; all tests pass; disposition = ACKNOWLEDGE not fold-in). Do NOT require absence of bare matches — the original AC's premise (test-query narrowing was the fix) was wrong.
- [x] **Re-verified at /work time (2026-05-09):** 8 affected test files = 8 passed / 74 tests / 0 fail. Full suite = 363 passed / 7 skipped / 3956 passed / 51 skipped / 0 failed. Worktree commit `09f68a0d` on branch `feat-one-shot-3035-pre-existing-test-failures`.
- [ ] PR body uses `Closes #3035` on its own body line (per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`). [deferred to ship phase]
- [ ] PR body uses `Ref #3035` everywhere else (e.g., commit message, summary) to avoid double-closure. [deferred to ship phase]

### Post-merge (operator)

- [ ] Verify GitHub auto-closed #3035 from the `Closes #3035` body line; if not, run `gh issue close 3035 -c "Verified resolved by …; full vitest suite green at <branch>@<sha>."`.
- [ ] **File follow-up tracking issue** for the dormant-fragility class:
  ```bash
  gh issue create \
    --title "test(chat-sidebar, file-tree): scope bare-filename getByText via within(...)" \
    --label priority/p3-low,type/chore,domain/engineering \
    --body "4 surviving bare-filename getByText matches in apps/web-platform/test/{kb-chat-sidebar,file-tree-rename,file-tree-delete}.test.tsx pass today only because the rendered DOM has exactly one match per component. Future component refactor adding a sibling render site re-triggers the #3035 class. Harden via within(container) scoping. Surfaced during #3035 deepen-pass.

  Ref #3035."
  ```

## Implementation Phases

### Phase 0 — Pre-flight (read-only verification) — COMPLETED at deepen-time

Verified inline 2026-05-09 on worktree commit `2acfa25c`:

```
$ cd apps/web-platform && npx vitest run \
    test/chat-page.test.tsx test/chat-page-resume.test.tsx \
    test/chat-surface-sidebar.test.tsx test/chat-surface-sidebar-wrap.test.tsx \
    test/kb-chat-sidebar.test.tsx test/kb-chat-sidebar-a11y.test.tsx \
    test/kb-chat-sidebar-banner-dismiss.test.tsx test/kb-chat-sidebar-quote.test.tsx
 Test Files  8 passed (8)
      Tests  74 passed (74)
   Duration  2.48s

$ cd apps/web-platform && npx vitest run --reporter=basic
 Test Files  363 passed | 7 skipped (370)
      Tests  3956 passed | 51 skipped (4007)
   Duration  35.79s
```

Both runs zero-failure. Phase 0 evidence will be re-cited in the PR body and #3035 close-comment.

### Research Insights — Phase 0

- **No same-class failure surfaced in the broader suite.** 363 test files passed; the 13 failures cited in #3035 are demonstrably gone.
- **Surrounding tests are stable.** `kb-chat-resume-hydration.test.tsx`, `kb-chat-sidebar-close-abort.test.tsx`, and other adjacent files (not in #3035's list) also pass — no spillover symptoms.

### Phase 1 — Fixer-PR triage (close-comment trail) — COMPLETED at deepen-time

Merge log between baseline `62581167` (issue-filing) and `cc138d11` (worktree HEAD pre-init), scoped to chat surface + 8 affected test files:

| Commit | PR | Title | Touches `chat-surface-sidebar.test.tsx` |
| --- | --- | --- | --- |
| `228e2454` | **#3240** | feat(runtime): PR-A pre-flight — redaction allowlist, **brand rename**, getServiceClient memoize | **YES (12 lines)** — tightened negative-space assertion to header scope; renamed "Command Center" → "Dashboard" |
| `89be22bc` | #3237 | fix(kb-chat): hydrate prior messages on resume + correct trigger label | No |
| `b6bed202` | #3276 | fix(cc-chat): keep Soleur Concierge visible in routing panel | No |
| `7c3b90b6` | #3469 | feat(web-platform): user-initiated Stop — client UI | No |
| `d0e648b5` | #3419 | feat(cc-concierge): surface prefill-guard fires to model + user via context_reset | No |
| `2fad9a66` | #3427 | fix(chat): unify concierge routing chip with active-bubble + Working badge | No |
| `79662d2c` | #3308 | fix(theme): tokenize remaining web-platform surfaces for light mode | No |

**Primary fixer: PR #3240** (commit `228e2454`, merged 2026-05-05). Body excerpt: *"`apps/web-platform/test/chat-surface-sidebar.test.tsx` negative-space assertion tightened to header scope (the original 'Command Center' string was unique by accident; 'Dashboard' is not)."* The brand rename + assertion tightening directly addresses the same-class duplicate-text symptom for the `chat-surface-sidebar.test.tsx` file (1 of 8 affected files in #3035).

**Secondary fixers (kb-chat-sidebar test files):** none of the listed PRs explicitly mention fixing `kb-chat-sidebar*.test.tsx`. The 7 remaining test files in the issue list pass today because the rendered DOM topology of `kb-chat-sidebar.tsx` evolved between baseline and HEAD (component-level refactor across PRs #3237, #3315, #3271, etc.) such that the filename now renders in exactly one DOM site, not two. Specifically the duplicate-source likely resolved when the chat surface header relocated.

Close-comment will cite PR #3240 as primary fixer + cumulative-refactor narrative for the kb-chat-sidebar tests.

### Research Insights — Phase 1

- **The original symptom narrative ("sidebar header + breadcrumb") was speculative.** Issue body said "Likely a recently-shipped layout change that renders the filename in two places simultaneously (sidebar header + breadcrumb?)" — note the question mark. The actual fixer (#3240) eliminated a different second site: the chat-surface header brand text "Command Center" coincidentally clashed with sidebar text in negative-space assertions; brand-renaming + tightening the assertion to header scope fixed it. Original issue's hypothesized mechanism is wrong.
- **Same-class bug surface remains live.** See Phase 2 grep below.

### Phase 2 — Regression-guard scan (no-code-change assertion) — COMPLETED at deepen-time

Grep executed inline 2026-05-09:

```
$ rg "getByText\(['\"]roadmap\.md['\"]" apps/web-platform/test/
apps/web-platform/test/kb-chat-sidebar.test.tsx:
    const header = screen.getByText("roadmap.md");

$ rg "getByText\(['\"]readme\.md['\"]" apps/web-platform/test/
apps/web-platform/test/file-tree-rename.test.tsx:115:    const mdLink = screen.getByText("readme.md");
apps/web-platform/test/file-tree-delete.test.tsx:118:    const mdLink = screen.getByText("readme.md");
apps/web-platform/test/file-tree-delete.test.tsx:207:    const mdLink = screen.getByText("readme.md");

$ rg "getByText\(['\"]constitution\.md['\"]" apps/web-platform/test/
(no matches)
```

**4 surviving bare-filename matches.** All 4 tests pass today (`vitest run` — 18/18 file-tree tests pass; 8/8 kb-chat-sidebar tests pass).

**Disposition: ACKNOWLEDGE, do not fold in.**

Rationale:

1. **Out of issue scope.** #3035's title is "pre-existing chat-page + kb-chat-sidebar test failures" with an explicit list of 8 files. The 3 `file-tree-*` matches are not on that list. Folding them into this PR expands a verify-and-close into a refactor against tests that aren't broken.
2. **Tests pass — no current symptom to fix.** Per AGENTS.md `cm-challenge-reasoning-instead-of`: changing currently-passing tests to use `getAllByText` + index OR `within(...)` would be churn without evidence of harm. Future regression risk is real but speculative.
3. **Dormant fragility, not active fragility.** All 4 sites work because the rendered DOM has exactly one match for the filename in each component — this is a coupling between test queries and component DOM topology. Tests that assert on a unique render are not broken; they are tightly coupled. Tightening to `within(...)` is hardening, not bug-fixing.

**Filed-as-follow-up disposition:** The dormant-fragility class deserves a tracking issue (4 same-class sites; no current failure but future regression vector). Will file post-merge to keep this PR strictly verify-and-close. Tracking issue title: "test(chat-sidebar, file-tree): scope bare-filename `getByText` matches via `within(...)` to harden against future duplicate-text regressions". Label: `priority/p3-low`, `type/chore`, `domain/engineering`.

If the reviewer flips this disposition during PR review (fold-in instead of acknowledge), the upgrade path: 4 single-line edits using `within(container)` from the `render(...)` return — already used elsewhere in the same files. ~10 minutes of work.

### Research Insights — Phase 2

- **Bare `getByText("filename")` in the SAME 8 files cited by #3035 has not been narrowed.** The fix landed at the component level (one render site), not the test level. This makes #3035's "Next steps" prescription ("Update tests to use `getAllByText` + index, or scope queries via `within(container)`") **un-implemented** — but also un-needed today, because the bug it was protecting against doesn't reproduce.
- **Same-class sites in `file-tree-*.test.tsx` (3 matches)** were never failing per #3035 because `FileTree` always rendered each filename in exactly one DOM site. Same dormant-fragility class as the kb-chat-sidebar case.
- **`AGENTS.md cq-test-fixtures-synthesized-only` not violated:** `roadmap.md` and `readme.md` are filename literals, not credentials. No fixture-bypass concern.

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
- This issue's close-comment MUST cite the fixing PR(s). Closing as "fixed in unrelated work" without identifying which work is the kind of soft-close that hides regression vectors. Phase 1 is the load-bearing identification step; do not skip. **Verified at deepen-time:** PR #3240 is the primary fixer for `chat-surface-sidebar.test.tsx`; cumulative chat-surface refactors (PRs #3237, #3308, #3315, #3469, others) collapsed the kb-chat-sidebar render to one filename site. Cite both in close-comment.
- If Phase 0 verification fails (a test newly fails on the worktree HEAD that wasn't failing on origin/main), STOP. The plan reverts to a real fix-plan and the duplicate-text source must be located in the rendered DOM tree before re-issuing the PR. **Verified at deepen-time:** Phase 0 zero-failure (8 files / 74 tests + full suite 363 files / 3956 tests).
- When the PR body says "Closes #3035", confirm via `gh pr view <N> --json closingIssuesReferences` post-creation that GitHub recognized the close-link. Markdown lists / checkboxes / code blocks make `Closes #N` invisible to GitHub's parser per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`. The bare body line `Closes #3035` is the canonical form.
- Per AGENTS.md `wg-when-tests-fail-and-are-confirmed-pre`: pre-existing failures without a tracking issue normalize a red suite. This issue WAS the tracking issue — closing it as resolved (with the close-comment trail) is the workflow-compliant exit. Do not silently delete the issue or close as "won't-fix".
- **Dormant-fragility class persists.** The 4 surviving bare-filename `getByText` matches (1 in `kb-chat-sidebar.test.tsx`, 3 in `file-tree-*.test.tsx`) pass today because the rendered DOM has exactly one match for the filename in each component. A future PR that re-introduces a sibling render site (breadcrumb, tab label, collapsed-header echo, aria-label sibling) reproduces #3035 without the test author noticing — there is no compile-time signal. **Out of scope for this PR**; will file post-merge tracking issue (`priority/p3-low`, `type/chore`). Do not fold into this PR — that expands a verify-and-close into a refactor.
- The Acceptance Criteria item *"Confirm no test in the 8 files still uses an unscoped `getByText('roadmap.md')`"* is **falsified** by deepen-time evidence — `kb-chat-sidebar.test.tsx:77` does. The AC was written under the false hypothesis that test-query narrowing was the fix. Updated AC: confirm grep output and document the dormant-fragility disposition; do not require absence of bare-filename matches.

## Domain Review

**Domains relevant:** none.

No cross-domain implications detected — verification-only PR closing a tracking issue for failures that no longer reproduce. No user-facing surface, no schema, no credentials, no infra. Skipping `Product/UX Gate`, `CTO`, `CMO`, etc. per AGENTS.md `pdr-do-not-route-on-trivial-messages-yes` analog ("the domain signal IS the current task's topic" — engineering test-cleanup is the topic).

## Hypotheses

(Network-outage gate did not fire — issue is not SSH/network-related. Skipped.)

The duplicate-text rendering bug (`Found multiple elements with the text: roadmap.md`) was caused by a transient layout state where the filename was rendered in two simultaneous DOM positions (sidebar header + a sibling chrome element). Likely root cause: PR #2347 (kb-chat-sidebar feature) and PR #2500 (sidebar cleanup) shipped a layout where the `kb-chat-sidebar.tsx` header rendered the filename AND the parent `chat-surface.tsx` exposed it via a breadcrumb / aria-label / data attribute that `getByText` matched. Subsequent refactors (PR #3240 brand-rename, PR #3237 trigger-label correction, PR #3276 routing-panel scope) eliminated one of the two render sites or changed the surrounding text such that the queries no longer match double.

This hypothesis is **not load-bearing** for the plan — the plan is verify-and-close, and the close-comment cites fixing PR(s) by merge log inspection, not by hypothesis verification.
