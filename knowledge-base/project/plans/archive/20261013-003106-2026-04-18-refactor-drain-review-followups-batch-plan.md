# Plan: drain review follow-ups batch (#2268 + #2269 + #2272 + #2337 + #2419 + #2440 + #2566)

**Date:** 2026-04-18
**Branch:** `feat-one-shot-review-followups-batch`
**Worktree:** `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-review-followups-batch`
**Type:** refactor (multi-issue review-backlog drain)
**Estimated scope:** 1 PR, 7 issues closed

---

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** T1, T5, T6, T7 (highest risk tranches)
**Research inputs:** 7 institutional learnings (KB project learnings), 2 live `gh api` verifications, file-level grep of every target path, code-review overlap check against 32 open issues.

### Key Improvements

1. **T5 (KbLayout split) — added 4 concrete sharp edges from past PR #2433 and PR #2500 sessions:** (a) `react-resizable-panels` v4 parses numeric sizes as PIXELS, not percentages — keep the existing `"18%"` / `"22%"` string form (plan already uses it; re-verify post-split). (b) Extracting a component changes effect-ordering — the `prevContextPathRef` mount-skip guard MUST be preserved verbatim; extracting into a hook can put the reset effect on the parent side of a new boundary. (c) `usePanelRef()` must be called inside `useKbLayoutState` — splitting the ref across hook+child breaks the resize callback closure. (d) Dead-ref sweep after extraction (`cq-ref-removal-sweep-cleanup-closures`): grep every ref name in all three new files post-extraction.
2. **T6 (composite action) — caught a divergence between the two callers:** `scheduled-weekly-analytics.yml:34` still declares `statuses: write` but `rule-metrics-aggregate.yml` dropped it after PR #2270 review (the Checks API never uses the Statuses endpoint). Migration MUST align both workflows to the least-privilege set `checks + contents + pull-requests`. Verified via direct grep.
3. **T6 — shell-expansion caveat is real:** confirmed via the canonical learning `2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md`. The plan's chosen option (b) — push `$DATE_SUFFIX` evaluation inside the composite's `run:` block — matches the canonical pattern. Documented the PR title format literal so it round-trips byte-identical.
4. **T7 (CLI-verification gate) — AGENTS.md byte budget is tight:** current file is 33.3 KB / 100 rules (Compound step-8 warns at 40 KB / 100 rules). Adding `cq-docs-cli-verification` hits the 101-rule ceiling. Acceptable (warning, not block), but the new rule was re-drafted to ~540 bytes and the Why-annotation kept to one sentence per `cq-agents-md-why-single-line`.
5. **T7 — advisory hook output contract verified:** advisory hooks that do NOT block must exit 0 and emit warnings to stderr (NOT via the `jq -n '{hookSpecificOutput:{permissionDecision:"deny",...}}'` pattern used by `pencil-open-guard.sh`). Hook skeleton now matches this contract.

### New Considerations Discovered

- **PR #2270 review dropped `statuses: write`** because the workflow uses only the Checks API; this same cleanup applies to `scheduled-weekly-analytics.yml` and should land in T6.
- **Test-mocked `next/navigation` must include `useSearchParams`** (not just `useRouter` + `usePathname`) when any descendant of the rendered tree mounts chat/form surfaces. The T5 rendered-test for `KbChatContent` will trip this if omitted (learning: `2026-04-17-kb-chat-stale-context-on-doc-switch.md`).
- **Icon consolidation pattern for #2269 item 2:** the god-component-extraction learning recommends a single `components/icons/index.tsx` with named exports over individual SVG files under ~10 lines. Not directly applicable to this PR but is the pattern if further extractions surface.
- **T1 (NamingNudge) — test file `test/naming-nudge.test.tsx` ALREADY exists (8 cases).** The test passes `leaderTitle="Chief Technology Officer"` on line 18 — removing the prop from `NamingNudgeProps` requires updating this call site OR making the prop optional + ignored. Since #2268 explicitly asks to remove the dead prop, update the test to drop the argument. Add three NEW cases (rejection renders error; button disabled during pending; re-enables after resolve) to the existing `describe` block; do not create a second file.

---

## Overview

Single-PR drain of seven unlinked `code-review` follow-ups that cluster around `apps/web-platform` UI/tooling plus two repo-wide docs/CI items. The goal is net-positive backlog reduction: fix inline where the scope is bounded, scope-out only if a sub-item balloons. Each tranche is an independent commit inside the same branch so bisect remains useful.

**Issues folded in:**

| # | Title | Tranche |
| --- | --- | --- |
| #2268 | NamingNudge silently swallows onSave errors | T1 |
| #2269 | dashboard polish grouping (P3) — items 1-8 | T2 |
| #2337 | name magic numbers and clarify byte-vs-char cap in vision-helpers | T3 |
| #2419 | code review for PR #2414 — progressive task surfacing | T4 (close-only) |
| #2440 | split KbLayout into desktop/mobile sub-components | T5 |
| #2272 | extract composite action for bot-PR + synthetic-checks pattern | T6 |
| #2566 | add docs CLI-verification gate | T7 |

**Out of scope (kept as separate open issues):**

- #2269 items 9 (`DashboardPage` god-component extraction — the issue itself says "Separate PR"), 10 (CSP duplicate documentation — not a code change), 11 (`.svg` → `ATTACHMENT_EXTENSIONS` — `ATTACHMENT_EXTENSIONS` is not declared in `apps/web-platform`; belongs to a different codebase scope). Each will be handed back to #2269 as "still open" or split into a fresh sibling issue labeled `code-review`.
- #2333 vision-helpers symlink hardening (a separate and larger concern; overlap check confirms independence — see `## Open Code-Review Overlap`).

---

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (verified this plan) | Plan response |
| --- | --- | --- |
| #2419 says finding 1 fixed inline in commit `847382af`; finding 2 deferred as YAGNI | Verified: `gh api .../commits/847382af` returns `review: fix chip SVG a11y — use aria-hidden instead of aria-label`; PR #2414 merged 2026-04-16. No residual code changes owed. | T4 is comment-only close ("review complete, all findings addressed or deliberately skipped"). No scope balloon — do not file a `code-review` sibling. |
| #2269 item 3 (conversation-row dead code) cites line 136 | Verified: `test/components/conversation-row.test.tsx:135-136` contains the literal `vi.mocked(vi.fn()).mockReturnValue({ push: mockPush })` line — exactly as the issue describes. | Delete lines 135-136 (both the comment and the no-op). |
| #2269 item 11 mentions `ATTACHMENT_EXTENSIONS` | Grep returns zero hits in `apps/web-platform/`. The constant lives in the plugin skills (docs-uploader context), not the web-platform SVG-upload path. | Scope out — file a narrow sibling issue against the correct codebase. |
| #2272 says migrate both workflows to one composite action | Verified: `rule-metrics-aggregate.yml:44-97` and `scheduled-weekly-analytics.yml:68-119` contain the shared bash block (git config + diff-guard + branch + `gh pr create` + four identical `gh api check-runs` calls + `gh pr merge --squash --auto`). Differences are `git add` path, branch prefix, commit message, PR title/body, check-run summary. | Proceed as issue describes. |
| #2337 says the only consumer of `MAX_VISION_CONTENT` is `vision-helpers.ts` and `test/vision-creation.test.ts:83` | Verified: three references total in `vision-helpers.ts` (lines 5, 32, 33); test file references the value `5000` indirectly via the computed length `5011` at line 84. No other `MAX_VISION_CONTENT` imports. | Rename is internal — no cross-module ripple. |
| #2566 proposes three implementation candidates (skill instruction / hook / review agent) | Hook approach: `.claude/hooks/` contains 5 existing guards — precedent exists. Skill approach: `plugins/soleur/skills/plan/` and `…/review/` both editable. Review-agent approach: would touch `pattern-recognition-specialist` config (harder to verify end-to-end). | Ship the **skill-instruction** path (cheapest, reversible, auditable) + a **lightweight codeblock-detector hook** warning (non-blocking) to catch stragglers. Explicitly scope out wiring into `pattern-recognition-specialist` to a future PR if a second fabricated command ships. |

---

## Open Code-Review Overlap

Files this plan edits, checked against the 32 open `code-review` issues:

| Planned file | Matching open issue(s) | Disposition |
| --- | --- | --- |
| `apps/web-platform/components/chat/naming-nudge.tsx` | #2268 | **Fold in** — this is the primary issue for this file; `Closes #2268`. |
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx` | #2269 | **Fold in** (items 1-8); `Closes #2269` after scope split. |
| `apps/web-platform/server/vision-helpers.ts` | #2337, #2333 | #2337 **fold in** (`Closes #2337`). #2333 **Acknowledge** — different concern (symlink traversal in `workspace.ts`, which this plan does not touch; the `vision-helpers.ts:36` mention in #2333 is context, not the fix location). #2333 stays open. |
| `apps/web-platform/test/vision-creation.test.ts` | #2337 | **Fold in** — const-rename ripple. |
| `apps/web-platform/test/leader-avatar.test.tsx` | #2269 | **Fold in** (item 1). |
| `apps/web-platform/test/error-states.test.tsx` | #2269 | **Fold in** (item 2). |
| `apps/web-platform/test/components/conversation-row.test.tsx` | #2269 | **Fold in** (items 3-4). |
| `apps/web-platform/test/dashboard-layout-banner.test.tsx` | #2269, #2193 | #2269 **fold in** (item 5, import hoist). #2193 **Acknowledge** — #2193 is a banner-component unification refactor; hoisting one import line does not interact with that scope. #2193 stays open. |
| `.github/workflows/rule-metrics-aggregate.yml` | #2272 | **Fold in**; `Closes #2272`. |
| `.github/workflows/scheduled-weekly-analytics.yml` | #2272 | **Fold in**. |
| `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` | (none) | N/A — no overlap; primary issue is #2440. |
| `plugins/soleur/skills/plan/SKILL.md`, `plugins/soleur/skills/review/SKILL.md`, `.claude/hooks/docs-cli-verification.sh` (new) | (none) | N/A — primary issue is #2566. |

No silent overlaps. No scope-outs to file from overlaps.

---

## Tranches (commits)

Each tranche is a standalone commit. Tests run after each. Failing tests in a tranche block the next.

### T1 — fix(naming-nudge): surface onSave errors and disable during save (#2268)

**Files to edit:**

- `apps/web-platform/components/chat/naming-nudge.tsx`
- `apps/web-platform/test/naming-nudge.test.tsx` — extend existing test file (already has 8 cases; add 3 more for saving/error/re-enable behavior; drop `leaderTitle` from `renderNudge` helper at line 18)

**Changes:**

1. Add `saving` + `error` state to `NamingNudge`. Wrap `await onSave(...)` in `try/catch/finally`.
2. Disable the Save button when `saving` is true; label switches to `Saving...`.
3. Render `error` as a small amber-700 text line below the controls when non-null.
4. Remove unused `leaderTitle` prop from `NamingNudgeProps` + destructuring + consumer call sites. Search: `rg "NamingNudge" apps/web-platform/` and update every caller.
5. Optional tidy (#2269 item 7 pre-fold): replace `leaderId.toUpperCase()` with `DOMAIN_LEADERS.find(l => l.id === leaderId)?.name ?? leaderId.toUpperCase()`. Low risk; already touching the file. **Decision: include** — one-line change inside the same file that #2268 already rewrites.

**TDD gate (`cq-write-failing-tests-before`):**

- RED: Add `naming-nudge.test.tsx` with three cases:
  1. `onSave` rejection renders an error message.
  2. Save button becomes `disabled` while `onSave` is pending (use a never-resolving promise + rerender).
  3. Save button re-enables after `onSave` resolves.
- Run test → expect failure. Then implement. Then re-run.

**Acceptance:**

- [x] `onSave` rejection surfaces visible error text.
- [x] Save button shows `Saving...` and is disabled during in-flight request.
- [x] `leaderTitle` prop removed from interface AND all call sites.
- [x] `roleName` derived from `DOMAIN_LEADERS` lookup.
- [x] 3 new unit tests pass alongside the existing ones (10 total in `naming-nudge.test.tsx`).

#### Research Insights (T1)

**From general-purpose React-testing practice (confirmed against repo convention by reading `test/naming-nudge.test.tsx`):**

- The `vi.fn().mockResolvedValue(undefined)` default at line 5 means `onSave` always succeeds in existing tests. Adding a rejection case requires `mockOnSave.mockRejectedValueOnce(new Error("Network error"))` inside a specific `it()` block — do NOT change the global default (would break the 8 existing passing tests).
- For the "button disabled during pending" case, use a deferred promise handle:

  ```ts
  let resolveSave: () => void;
  mockOnSave.mockImplementationOnce(() => new Promise<void>((r) => { resolveSave = r; }));
  // click Save
  expect(screen.getByText(/saving/i)).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /saving/i })).toBeDisabled();
  resolveSave!();
  await waitFor(() => expect(screen.getByText("Save")).toBeInTheDocument());
  ```

- `cq-preflight-fetch-sweep-test-mocks` and `cq-raf-batching-sweep-test-helpers` do NOT apply here (no fetch, no rAF).
- `DOMAIN_LEADERS` import path: locate via `rg "export const DOMAIN_LEADERS" apps/web-platform/` before referencing — do not guess. If the module is server-side, use the client-safe equivalent (likely `@/lib/domain-leaders-client` or similar).

---

### T2 — refactor(dashboard): drain dashboard polish items 1-8 (#2269)

**Files to edit:**

1. `apps/web-platform/test/leader-avatar.test.tsx` (item 1) — stop asserting `svg[width]`; assert wrapper class (`h-5 w-5`, `h-7 w-7`, `h-8 w-8`) on the outer container. Add `data-avatar-size="sm|md|lg"` to `LeaderAvatar` wrapper if a class-based assertion is fragile.
2. `apps/web-platform/test/error-states.test.tsx` (item 2) — delete the `WebSocketError interface` describe block (lines 56-76). It asserts on its own inline literal. If a replacement is warranted, import the real error map from `components/chat/websocket-error-map.ts` (or equivalent — verify the actual module name exists before importing). If the module does not exist, delete-only is the correct fix.
3. `apps/web-platform/test/components/conversation-row.test.tsx` (item 3) — delete lines 135-136 (the `vi.mocked(vi.fn()).mockReturnValue(...)` no-op dead code).
4. `apps/web-platform/test/components/conversation-row.test.tsx` (item 4) — the line-65 `bg-blue-500` assertion: refactor to assert on `aria-label='CTO avatar'` presence (already matched at line 62) — drop the for-loop that checks `className.includes("bg-blue-500")`. Color coupling is the anti-pattern `leader-avatar.test` was rewritten to eliminate.
5. `apps/web-platform/test/dashboard-layout-banner.test.tsx` (item 5) — hoist the `createUseTeamNamesMock` import from line 31 to the top-of-file import block with the other imports.
6. `apps/web-platform/app/(dashboard)/dashboard/page.tsx` (item 6) — extract `FoundationSection` component (new file `apps/web-platform/components/dashboard/foundation-section.tsx`) that takes `{ cards, onIncompleteClick, getIconPath, className? }` and renders the `FOUNDATIONS` header + description + `<FoundationCards>`. Replace both duplicates (lines 455-469 and 510-524) with `<FoundationSection cards={allCards} ... />`.
7. (item 7 — `naming-nudge.tsx` roleName) — **already folded into T1**.
8. `apps/web-platform/components/chat/at-mention-dropdown.tsx` (item 8) — at line 32-33 hoist `const customName = customNames[leader.id];` once per map iteration; use it at the three read sites (lines 33, 112, 113).

**Scope-outs (file new sibling issues, label `code-review`, milestone `Post-MVP / Later`):**

- **Item 9 — `DashboardPage` god-component extraction** → file as `refactor(dashboard): extract useFirstRunAttachments + FirstRunComposer from DashboardPage` with a link to #2269. Issue body must include re-evaluation criteria ("close when `dashboard/page.tsx` drops below 500 lines OR when a new feature forces editing it"). The issue itself (#2269) explicitly says "Separate PR" for this item, so this is expected.
- **Item 10 — CSP duplicate header documentation** → file as `docs(security): document CSP middleware + route intersection for binary types` (not a code change, just a comment in `middleware.ts` explaining why the duplicate is intentional). Link to #2269.
- **Item 11 — `.svg` → `ATTACHMENT_EXTENSIONS`** → grep confirms `ATTACHMENT_EXTENSIONS` is not declared in `apps/web-platform`. File as `security: force download disposition for committed SVG files` scoped against the correct codebase path (probably `plugins/soleur/skills/*/scripts/` or wherever the constant actually lives). Link to #2269. Re-evaluation criterion: close when the correct owning module applies the fix or when a second SVG-XSS class surfaces.

**TDD gate:** items 1-5 are test changes themselves (the test IS the verification). For items 6 and 8, add:

- `test/foundation-section.test.tsx` — 2 RED cases (renders header + cards; applies `className`).
- Verify the existing `at-mention-dropdown.test.tsx` still passes unchanged (hoist is pure refactor).

**Acceptance:**

- [x] Items 1-8 resolved inline.
- [x] Items 9, 10, 11 filed as new `code-review` issues with re-evaluation criteria (#2590, #2591, #2592).
- [x] `#2269` will close via `Closes #2269` in PR body; split note added to issue on PR merge.

---

### T3 — refactor(vision-helpers): name magic numbers and clarify char-vs-byte cap (#2337)

**Files to edit:**

- `apps/web-platform/server/vision-helpers.ts`
- `apps/web-platform/test/vision-creation.test.ts`

**Changes:**

1. Add `const MIN_VISION_SEED_LENGTH = 10;` with comment `// reject bare @-mentions and /slash-commands that fall below this threshold`. Replace `trimmed.length < 10`.
2. Rename `MAX_VISION_CONTENT` → `MAX_VISION_CHARS = 5000` with comment `// code-unit cap (JS string length), not UTF-8 byte count`. Update both usages at lines 32-33.
3. Update the `// Truncate oversized content to prevent disk abuse` comment on line 31 → `// Truncate runaway content (rogue paste, LLM loop). Note: char count, not byte count — UTF-8 multibyte chars may exceed the byte cap.`
4. In `test/vision-creation.test.ts`, rename the `truncates content exceeding 5000 characters` test description to `truncates content exceeding MAX_VISION_CHARS (5000 chars, not bytes)`. Assertion (line 84) is already pinned to `5011` — OK.

**Explicit non-goal:** do NOT add a byte-cap enforcement in this PR. The issue lists it as optional; adding it changes behavior and deserves its own plan. If the founder wants byte-limiting, file a follow-up.

**TDD gate:** existing tests already cover the behavior. Re-run `vitest run test/vision-creation.test.ts` after the rename — the only change the tests see is a description string. No new RED tests needed (this is a pure rename + comment change, exempt under `cq-write-failing-tests-before`).

**Acceptance:**

- [x] `MIN_VISION_SEED_LENGTH` and `MAX_VISION_CHARS` are the only magic-number references.
- [x] Existing tests still pass.
- [x] No new imports; no new dependencies.

---

### T4 — chore: close #2419 with "review complete, all findings addressed" comment

**No code changes.**

**Action:**

- `gh issue close 2419 --comment "Review complete. Finding 1 (chip SVG a11y) fixed inline in commit 847382af (PR #2414). Finding 2 (useMemo card derivations) deliberately skipped as YAGNI — 10 items, negligible render cost. No residual work. Closes via this PR to keep the review-origin issue trail aligned with the final merge."`

The issue is filed with `code-review` label but has zero outstanding technical residue (verified against the PR #2414 merged diff). Closing-only is correct — filing a new sibling would be noise.

**Acceptance:**

- [ ] `#2419` closed with the comment above.
- [ ] PR body includes `Closes #2419` (GitHub auto-close covers the close action; the explicit comment preserves reasoning).

---

### T5 — refactor(kb-layout): split into KbDesktopLayout + KbMobileLayout + useKbLayoutState (#2440)

**Files to edit:**

- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` (shrinks from ~432 lines to ~80, becomes dispatcher)
- `apps/web-platform/components/kb/kb-desktop-layout.tsx` (new, ~150 lines)
- `apps/web-platform/components/kb/kb-mobile-layout.tsx` (new, ~90 lines)
- `apps/web-platform/hooks/use-kb-layout-state.ts` (new, ~180 lines)
- Existing tests: `test/*kb-layout*.test.tsx`, `test/*kb-sidebar-collapse*.test.tsx` must continue to pass

**Extraction contract:**

1. **`useKbLayoutState()` hook** returns a single object with: `{ ctxValue, chatCtxValue, sidebarContent, docContent, isDesktop, showChat, contextPath, loading, error, hasTreeContent, openSidebar }`. This is the data/behavior surface both layouts share.
2. **`KbDesktopLayout({ children, state })`** consumes `state` and renders the `<Group>` + three `<Panel>`s.
3. **`KbMobileLayout({ children, state })`** consumes `state` and renders the flex/aside/sheet tree.
4. **`KbLayout` (now dispatcher)** calls `useKbLayoutState()` + the early-return branches (loading/error/empty), then dispatches to `isDesktop ? KbDesktopLayout : KbMobileLayout` with children + state.

**Sharp edges:**

- `usePanelRef()` MUST be called inside the hook (not the child components) because the desktop layout's `onResize` handler mutates `setKbCollapsed`, which lives in the hook. Moving it to the child would split the ref between renders.
- `sidebarContent` and `docContent` are JSX fragments that both layouts render. They reference `toggleKbCollapsed` (which closes over `sidebarPanelRef`). Keep them computed inside the hook and return as values on `state`.
- The runtime feature-flag fetch (`/api/flags`) stays inside the hook — do not duplicate.
- `cq-ref-removal-sweep-cleanup-closures`: when deleting the hook-consolidated refs, grep inside all three new files after the extraction (`rg "<refName>" apps/web-platform/app/(dashboard)/dashboard/kb apps/web-platform/components/kb apps/web-platform/hooks`) and verify no orphaned references.

**TDD gate:** this is a pure structural refactor — no new observable behavior. The existing test suite (`kb-layout*.test.tsx`, `kb-sidebar-collapse*.test.tsx`) IS the regression harness. Exempt from writing new RED tests under `cq-write-failing-tests-before` (refactor-only; existing tests assert the contract).

**Mechanical escalation risk (`wg-for-user-facing-pages-with-a-product-ux`):** this refactor CREATES new `components/**/*.tsx` files. Per AGENTS.md, creating new component files is BLOCKING for the Product/UX Gate. **Mitigation:** these are non-visual structural extractions — every rendered DOM node remains byte-identical (same JSX returned, just routed through an extra function). Include a smoke-test task that diffs `render(<KbLayout/>)` output pre-/post-extraction to prove visual parity. The Product/UX Gate can auto-accept with `Tier: advisory, Decision: auto-accepted (pipeline) — structural-only refactor, DOM parity verified`.

**Acceptance:**

- [x] `KbLayout` is ≤100 lines (60 lines); `KbDesktopLayout` + `KbMobileLayout` + `useKbLayoutState` together cover the remaining scope.
- [x] All existing `*kb-layout*.test.tsx` and `*kb-sidebar-collapse*.test.tsx` tests pass unchanged (25/25).
- [x] Cmd+B shortcut still toggles the KB sidebar on desktop + mobile (covered by kb-sidebar-collapse.test.tsx).
- [x] The chat-panel open/close flow around document navigation works (kb-layout-chat-close-on-switch.test.tsx green).
- [x] `cq-ref-removal-sweep-cleanup-closures`: grep confirms no dangling ref references.

#### Research Insights (T5)

**From `knowledge-base/project/learnings/ui-bugs/2026-04-16-react-resizable-panels-v4-numeric-size-is-pixels.md`:**

- `react-resizable-panels` v4 `parseSize()` returns `[e, "px"]` for numeric inputs — the docstring's "percentage (0..100)" claim is wrong. The current `KbLayout` correctly uses string-percentage form (`"18%"`, `"22%"`, `"40%"`, `"10%"`). **Preservation requirement:** during the split, every `defaultSize`/`minSize`/`maxSize`/`collapsedSize` prop must stay as a quoted string with a `%` or `px` suffix. A refactor pass that "cleans up" the quotes back to numeric literals will silently render an 18-pixel sidebar.
- Verification step after the split: `rg '(default|min|max|collapsed)Size=[^"]' apps/web-platform/components/kb/kb-desktop-layout.tsx` — zero hits is the pass signal.

**From `knowledge-base/project/learnings/ui-bugs/2026-04-16-react-effect-ordering-on-component-extraction.md`:**

- When a component is extracted, child effects fire before parent effects — a mount-side reset in the parent can overwrite state the child just set. The current `prevContextPathRef` guard (layout.tsx:225-230) is the fix for exactly this class of bug (#2417).
- **T5-specific risk:** if `useKbLayoutState` owns the `prevContextPathRef` effect but `KbDesktopLayout`/`KbMobileLayout` mount children that call setters in their own effects, the ordering re-shifts. The guard still works (the ref compares the previous path to the current), but introduce a rendered regression test that: (a) mounts the extracted layout, (b) navigates pathnames via `rerender`, (c) asserts `sidebarOpen` flips to `false` on change and stays true on equal-path rerender.

**From `knowledge-base/project/learnings/2026-04-17-kb-chat-stale-context-on-doc-switch.md`:**

- Test-mock `next/navigation` must include `useSearchParams` (not just `useRouter` + `usePathname`) when the rendered tree mounts chat surfaces. The KB chat sidebar is a chat surface. **T5 test setup:** every new/edited test file MUST include `useSearchParams: () => new URLSearchParams()` in the `vi.mock("next/navigation", ...)` block.

**From `knowledge-base/project/learnings/2026-04-17-raf-batching-and-dead-ref-cleanup.md`:**

- **Ref removal hazard:** when the extraction consolidates `sidebarPanelRef`, `chatPanelRef`, `prevContextPathRef` into the hook, the OLD references inside cleanup closures (`return () => ...`) can become orphaned. TS `--noEmit` will NOT catch this; the ReferenceError surfaces only at component unmount in a test. Post-extraction grep: `rg "(sidebarPanelRef|chatPanelRef|prevContextPathRef)" apps/web-platform/` — every hit must be inside either `use-kb-layout-state.ts` OR a consumer that correctly destructures from the hook's return.

**From `knowledge-base/project/learnings/2026-04-05-god-component-extraction-refactoring.md`:**

- "Smart parent / dumb children" is the right pattern: `useKbLayoutState` owns state + effects + handlers; `KbDesktopLayout` and `KbMobileLayout` receive only props. Do NOT allow the child components to call hooks that mutate layout state — they must be pure renderers. The 100-line target for the dispatcher `KbLayout` is realistic because the four early-return branches are irreducible.

---

### T6 — ci: extract `bot-pr-with-synthetic-checks` composite action (#2272)

**Files to create:**

- `.github/actions/bot-pr-with-synthetic-checks/action.yml` (new composite action)

**Files to edit:**

- `.github/workflows/rule-metrics-aggregate.yml` (migrate lines 44-97 to composite action)
- `.github/workflows/scheduled-weekly-analytics.yml` (migrate lines 68-119)

**Composite action interface:**

```yaml
name: bot-pr-with-synthetic-checks
description: Commit bot-authored changes, open a PR, post synthetic check-runs to satisfy required rulesets, and queue auto-merge.
inputs:
  add-paths:
    description: Space-separated paths to `git add` (passed through a shell array — no globs)
    required: true
  branch-prefix:
    description: Prefix for the feature branch name (date suffix appended automatically)
    required: true
  commit-message:
    description: Commit message for the bot PR
    required: true
  pr-title:
    description: PR title
    required: true
  pr-body:
    description: PR body
    required: true
  summary:
    description: Summary text used in every synthetic check-run output[summary]
    required: false
    default: "Bot PR, no code changes"
  gh-token:
    description: GITHUB_TOKEN with contents/pull-requests/checks=write
    required: true
runs:
  using: composite
  steps:
    - shell: bash
      env:
        GH_TOKEN: ${{ inputs.gh-token }}
      run: |
        set -eo pipefail
        git config user.name "github-actions[bot]"
        git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
        # shellcheck disable=SC2086
        git add ${{ inputs.add-paths }}
        if git diff --cached --quiet; then
          echo "No changes to commit"
          exit 0
        fi
        BRANCH="${{ inputs.branch-prefix }}$(date -u +%Y-%m-%d)"
        git checkout -b "$BRANCH"
        git commit -m "${{ inputs.commit-message }}"
        git push -u origin "$BRANCH"
        gh pr create \
          --title "${{ inputs.pr-title }}" \
          --body "${{ inputs.pr-body }}" \
          --base main \
          --head "$BRANCH"
        COMMIT_SHA=$(git rev-parse HEAD)
        for check in test cla-check dependency-review e2e; do
          title="Bot PR"
          [ "$check" = "cla-check" ] && title="CLA pre-approved"
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name="$check" \
            -f head_sha="$COMMIT_SHA" \
            -f status=completed \
            -f conclusion=success \
            -f "output[title]=$title" \
            -f "output[summary]=${{ inputs.summary }}"
        done
        gh pr merge "$BRANCH" --squash --auto
```

**Sharp edges (mandatory checks):**

- **YAML heredoc compliance** (`hr-in-github-actions-run-blocks-never-use`): the composite action uses a `run: |` block. Confirm every line is indented ≥6 spaces relative to the YAML root. Specifically the `for check in ...; do ... done` loop body — each indented at ≥8 spaces. NO column-0 heredoc terminators.
- **`cq-in-github-actions-run-blocks-never-use` guard:** The `--body "${{ inputs.pr-body }}"` pattern works only if `pr-body` is single-line. If either workflow passes a multi-line body, add a preceding step: `{ echo "${{ inputs.pr-body }}"; } > /tmp/pr-body.md && gh pr create --body-file /tmp/pr-body.md ...`. Verify both callers pass single-line bodies today — both current workflows pass single-line bodies (confirmed).
- **Check-run title per iteration:** the loop sets `title="Bot PR"` and special-cases `cla-check`. Two of the four current calls have `output[title]=Bot PR`, one has `CLA pre-approved`. Original workflows do not differentiate `dependency-review` title — the loop flattens correctly.
- **Path inputs with spaces:** `add-paths` is shell-expanded; consumers must not pass paths with embedded spaces. Both current callers pass paths without spaces (`knowledge-base/project/rule-metrics.json`, `knowledge-base/marketing/analytics/`). Document this constraint in the action description.
- **Preflight CLI form verification (`cq-cli-form-verification`):** include a workflow_dispatch smoke-test on a test branch that runs the composite action with a no-op commit to verify `gh pr create --title --body --base --head` and `gh api check-runs -f "output[title]=..."` still work — both invocations have been in production for months, so this is confirmation, not discovery. Document this check in the PR description.

**Migration (both workflows):**

```yaml
- name: Create PR with rule-metrics snapshot
  uses: ./.github/actions/bot-pr-with-synthetic-checks
  with:
    add-paths: knowledge-base/project/rule-metrics.json
    branch-prefix: ci/rule-metrics-
    commit-message: "chore(rule-metrics): weekly aggregate"
    pr-title: "chore(rule-metrics): weekly aggregate $(date -u +%Y-%m-%d)"  # NOTE: see shell-expansion caveat below
    pr-body: "Automated weekly rule-metrics snapshot from .claude/.rule-incidents.jsonl + AGENTS.md. See scripts/rule-metrics-aggregate.sh."
    summary: "Rule metrics aggregation only, no code changes"
    gh-token: ${{ github.token }}
```

**Shell expansion caveat:** `$(date -u +%Y-%m-%d)` inside a YAML `with.pr-title` input is NOT evaluated as a shell substitution by the composite action runtime — it arrives as a literal string. The CURRENT workflow relies on bash expansion because the title is interpolated inside a `run: |` block. Solutions (pick one; plan prescribes option (b)):

- **(a)** Add a preceding `steps.date.outputs.today` step: `run: echo "today=$(date -u +%Y-%m-%d)" >> $GITHUB_OUTPUT` → reference `${{ steps.date.outputs.today }}`.
- **(b) (chosen)** Add a `date-suffix` input to the composite action that defaults to `$(date -u +%Y-%m-%d)` evaluated inside the action's `run:` block (where shell expansion works), and interpolate into `pr-title` inside the action itself: `gh pr create --title "${{ inputs.pr-title-prefix }} $DATE_SUFFIX" ...`. Rename `pr-title` input to `pr-title-prefix` for clarity.
- **(c)** Accept that the title becomes a literal `$(date ...)` string — BAD, rejected.

Plan chooses **(b)** — it preserves the composite action's simplicity and keeps the date format consistent with the branch name. Update `action.yml` accordingly before the test run.

**Post-merge verification (`wg-after-merging-a-pr-that-adds-or-modifies`):**

- `gh workflow run rule-metrics-aggregate.yml` manually, then `gh run view <id> --json status,conclusion` poll until complete.
- Repeat for `scheduled-weekly-analytics.yml`.
- Investigate any failure before closing #2272.

**Acceptance:**

- [x] Composite action at `.github/actions/bot-pr-with-synthetic-checks/action.yml` implementing the six-input interface above.
- [x] Both workflows migrated; `run: |` blocks for the PR-creation step shrink to single `uses:` blocks.
- [x] Existing check-run names (test, cla-check, dependency-review, e2e) preserved.
- [x] Branch prefix and PR title format identical to pre-migration (date suffix evaluated inside action).
- [ ] Post-merge manual dispatch succeeds for both workflows (post-merge verification).
- [x] **Permissions cleanup (new — surfaced during deepen):** dropped `statuses: write` from `scheduled-weekly-analytics.yml`.

#### Research Insights (T6)

**From `knowledge-base/project/learnings/2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md` (the canonical reference for THIS pattern):**

- **Permissions drift:** `scheduled-weekly-analytics.yml` currently declares `actions: write, checks: write, contents: write, pull-requests: write, statuses: write`. `rule-metrics-aggregate.yml` declares only `checks: write, contents: write, pull-requests: write`. The composite action needs `checks + contents + pull-requests` only. `statuses: write` is dead privilege — four review agents flagged it on PR #2270 and it was dropped. Fold the cleanup into T6. `actions: write` is needed by `scheduled-weekly-analytics.yml`'s subsequent `gh workflow run` steps (SEO audit, growth exec, content gen) — KEEP that permission at the job level, but the composite action itself does not need it.
- **Bot email:** the canonical form is `41898282+github-actions[bot]@users.noreply.github.com` (with the leading numeric user-id). Both current workflows use this form. The composite action hard-codes it inside `run:` — OK.
- **PreToolUse security-reminder hook:** first `Edit` on a `.github/workflows/*.yml` file will trip the advisory hook and reject the edit. Re-issue the same edit unchanged; second attempt succeeds. Expect this during T6 implementation, do not treat it as a failure.
- **`gh issue create --milestone`** (for the three scope-out siblings from T2): use the milestone TITLE, not the numeric ID. `--milestone "Post-MVP / Later"` — not `--milestone 6`. Already covered in AGENTS.md `cq-gh-issue-create-milestone-takes-title`.

**From `knowledge-base/project/learnings/2026-03-30-dependency-graph-enablement-and-synthetic-check-coverage.md`:**

- When adding/modifying synthetic-check workflows, audit ALL token-based PR-creating workflows, not just the ones in scope. The broad audit query is:

  ```bash
  grep -rl "GITHUB_TOKEN\|github.token" .github/workflows/ | \
    xargs grep -l "gh pr create\|peter-evans/create-pull-request"
  ```

- **Out of scope for T6:** this plan migrates only `rule-metrics-aggregate.yml` and `scheduled-weekly-analytics.yml` (the two enumerated in #2272). A sweep of the query above may surface additional workflows — if so, file a follow-up `code-review` issue linking #2272 and recommending they adopt the composite action too. Do NOT expand T6's scope mid-implementation.

**From `knowledge-base/project/learnings/2026-02-21-github-actions-workflow-security-patterns.md` (referenced transitively):**

- SHA-pin third-party actions. The composite action uses no third-party actions (only `gh` CLI inside a `run:` block), so no SHA-pinning is owed. The two callers still use `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` — leave untouched.

**Live verification performed during deepen:**

```bash
$ grep -n "statuses:" .github/workflows/scheduled-weekly-analytics.yml .github/workflows/rule-metrics-aggregate.yml
scheduled-weekly-analytics.yml:34:  statuses: write
# rule-metrics-aggregate.yml: (no match) — already cleaned in PR #2270
```

This live-verified divergence is the "permissions cleanup" acceptance item above.

---

### T7 — feat(plan+review): add docs CLI-verification gate (#2566)

**Problem scope:** PR #1810 shipped `ollama launch claude --model gemma4:31b-cloud` — a fully fabricated invocation — to the `/getting-started/` page. Caught 8 days later. `soleur:plan` did not verify CLI snippets. `soleur:review` caught nothing. #2566 asks for a gate.

**Chosen implementation (see Research Reconciliation for why):**

Ship the **skill-instruction path + a lightweight warning hook** in this PR. Scope out `pattern-recognition-specialist` integration as a follow-up if a second fabrication ships.

**Files to edit:**

1. `plugins/soleur/skills/plan/SKILL.md` — add a "Sharp Edges" bullet + a new checklist item in Section 6 (Final Review).
2. `plugins/soleur/skills/review/SKILL.md` — add a new §N "CLI-verification check" step in the finding-classification procedure.
3. `.claude/hooks/docs-cli-verification.sh` (new) — non-blocking post-edit hook that warns when common tool invocations appear in `.njk`, `.md`, or `apps/**` code blocks without a verification annotation.
4. `AGENTS.md` — new Code Quality rule (capped at 600 bytes per `cq-agents-md-why-single-line`).

**Rule text (proposed, AGENTS.md `Code Quality` section):**

```text
- When prescribing a CLI invocation in user-facing docs (*.njk, *.md, README, apps/**), verify the subcommand/model/flag exists before committing [id: cq-docs-cli-verification]. Run `<tool> --help` locally, link the tool's official doc/registry, or annotate `<!-- verified: YYYY-MM-DD source: <url> -->`. `tsc` and Eleventy build do NOT catch fabricated tokens. **Why:** #1810/#2550 shipped `ollama launch claude --model gemma4:31b-cloud` — every token fabricated.
```

**Byte-budget check:** measure the rule above; must be ≤600 bytes. Draft above is ~570 bytes — OK. If close to cap, move the `Why` anchor text shorter.

**`plan/SKILL.md` addition (after the existing `## Sharp Edges` section or as a Phase 6 checklist item):**

```markdown
- [ ] **CLI verification gate (#2566):** For every CLI invocation the plan prescribes to land in user-facing docs (`*.njk`, `*.md`, README, `apps/**`), verify the tokens exist:
      - Run `<tool> --help` or `<tool> <subcommand> --help` and paste the exit into the Research Insights section.
      - OR cite the tool's official command reference URL (e.g., the project's `docs/cli.md` on GitHub).
      - OR annotate the plan snippet with `<!-- verified: YYYY-MM-DD source: <url> -->`.
      A plan that embeds a CLI invocation without ONE of the three MUST NOT ship. Silence (omit the snippet) beats fabrication.
```

**`review/SKILL.md` addition (new §N, after the existing finding-classification):**

```markdown
### N. CLI-verification check (user-facing docs only)

When reviewing a PR that changes `*.njk`, `*.md`, README, or content under `apps/**`, scan every fenced code block tagged `bash`, `sh`, `shell`, or untagged-but-CLI-shaped. For each `<command> <subcommand>` pair:

1. If the tool is well-known (git, gh, npm, bun, curl, ollama, supabase, etc.), verify the subcommand exists. Cross-reference the tool's official docs (WebFetch or `<tool> --help`). If unsure, flag as `cli-verification-unverified` and require an explicit annotation or citation before approving.
2. If the tool is project-local (`./scripts/*`, `plugins/soleur/skills/*/scripts/*`), verify the script exists at the path.
3. If the snippet is a model name or registry tag (`<model>:<tag>`, `@<version>`), curl the registry or cite the registry URL.

Flag any unverified CLI invocation as `P1 (docs-trust)` — NOT P3 polish. A fabricated CLI command on a high-intent landing page breaks first-touch trust (see #1810/#2550).
```

**Hook (`.claude/hooks/docs-cli-verification.sh`, new) — lightweight advisory:**

- Triggers on `PostToolUse` for `Write|Edit` tools.
- File-pattern gate: only `.njk`, `.md`, or `apps/**/page.tsx` / `apps/**/*.njk`.
- Bash regex scan for fenced code blocks starting with a known CLI prefix (`ollama`, `npm run`, `bun run`, `supabase`, `gh`, `curl`, `doppler`).
- If a match is found AND the block is not annotated with `<!-- verified: ... -->`, emit a non-blocking warning to stderr: `[docs-cli-verify] unverified CLI invocation in <file>: <line> — consider running --help and annotating`.
- Exit 0 always (advisory, not blocking).

**Deliberate non-goals (scope-out as follow-up):**

- Running `<tool> --help` automatically from the hook (requires pkg-managed tools; not every CI runner has them).
- Extending `pattern-recognition-specialist` to recognize CLI invocations. File as a sibling `code-review` issue if the skill + hook prove insufficient (re-evaluation criterion: close when (a) a gate exists that would have blocked #1810, OR (b) a second fabricated CLI command ships).

**TDD gate:** hook is CI-testable via a fixture.

- RED: add `.claude/hooks/docs-cli-verification.test.sh` that (a) passes a fixture `.md` containing `ollama run gemma2:27b` (unverified) → expects warning. (b) passes a fixture with `<!-- verified: 2026-04-18 source: ... -->` → expects no warning. (c) passes a `.ts` fixture containing `ollama` in a string literal → expects no warning (file-pattern gate skips `.ts`).
- Implement the hook. Re-run tests.

**Retroactive gate application (`wg-when-fixing-a-workflow-gates-detection`):** the gap that exposed this (#1810) is already remediated via #2563 (the removal PR). No additional retroactive case to apply — verified by `gh issue view 2550 --json state` showing CLOSED.

**Acceptance:**

- [ ] `plan/SKILL.md` has the CLI-verification checklist item.
- [ ] `review/SKILL.md` has the CLI-verification classification step.
- [ ] `.claude/hooks/docs-cli-verification.sh` exists, is non-blocking, warns on unverified CLI invocations in docs files.
- [ ] `.claude/hooks/docs-cli-verification.test.sh` passes (3 fixtures).
- [ ] `AGENTS.md` has new rule `cq-docs-cli-verification` (≤600 bytes).
- [ ] Hook registered in `.claude/settings.json` or the equivalent hook-loading mechanism — verify by reading existing hook registration for `pencil-open-guard.sh`.

#### Research Insights (T7)

**From `knowledge-base/project/learnings/2026-04-18-fabricated-cli-commands-in-docs.md` (the originating learning for #2566):**

- Every token was fabricated in the #1810 payload: no `ollama launch` subcommand, no `claude` model in the Ollama registry, no `gemma4:31b-cloud` published tag. Caught 8 days later.
- Root cause was structural: `soleur:plan` treated the unverified CLI string as authoritative; `soleur:work` implemented the plan verbatim; `soleur:review` had no step that validated CLI tokens against reality. `pattern-recognition-specialist` checks markup patterns, not CLI validity; `security-sentinel` checks code-execution paths, not content accuracy.
- **Removal beat replacement** for #2550. The audit R5 finding deliberately did NOT substitute `ollama run gemma2:27b` because the next Soleur ↔ Ollama wiring step would also have failed. Silence beats invalid for trust-bearing pages. The T7 skill/hook must NEVER suggest a "best-guess substitution" — only warn, cite, or omit.

**Hook output-contract verification (live-read `pencil-open-guard.sh`):**

- Existing BLOCKING hooks use `jq -n '{hookSpecificOutput:{permissionDecision:"deny",permissionDecisionReason:"..."}}'` and always `exit 0` (the JSON carries the verdict). `pencil-open-guard.sh` is the canonical example — reads `$INPUT` from stdin, extracts `tool_input.filePath`, checks git-tracked status, emits the deny JSON on violation.
- Advisory hooks must NOT emit the `permissionDecision:"deny"` JSON — that blocks. Correct advisory pattern: `echo "[docs-cli-verify] warn: ..." >&2` + `exit 0` with no JSON. The warning appears in the session transcript but does not block the tool call.
- Hook registration pattern: `pencil-open-guard.sh` is wired via `.claude/settings.json` PreToolUse config (inspect during T7 impl to find the exact key — do not assume). The new `docs-cli-verification.sh` should register as `PostToolUse` on `Write|Edit` matching the file-pattern gate.

**From `knowledge-base/project/learnings/best-practices/2026-04-18-agents-md-byte-budget-and-why-compression.md` (byte budget context):**

- AGENTS.md is 33.3 KB / 100 rules before T7. The Compound step-8 soft cap is 40 KB / 100 rules. Adding `cq-docs-cli-verification` crosses the 100-rule threshold (lands at 101); stays under the 40 KB cap. Warning will trigger, NOT a block. Acceptable — but the Why-annotation MUST be one line per `cq-agents-md-why-single-line`.
- **Drafted rule (verify byte-count before committing):** `When prescribing a CLI invocation that will land in user-facing docs (*.njk, *.md, README, apps/**), verify the subcommand/model/flag exists [id: cq-docs-cli-verification]. Run <tool> --help locally, cite the tool's official doc/registry, or annotate <!-- verified: YYYY-MM-DD source: <url> -->. tsc and Eleventy build do NOT catch fabricated tokens. **Why:** #1810/#2550 — ollama launch / gemma4:31b-cloud every token fabricated.`
- That draft is ~560 bytes. Re-measure after any editorial tweak; keep under 600.

**From `knowledge-base/project/learnings/2026-03-26-case-study-three-location-citation-consistency.md`:**

- CLI invocations often appear in THREE locations (visible HTML, FAQ `<details>`, JSON-LD `FAQPage` schema). The T7 hook file-pattern must match `.njk` + `.md`, not just `.md`, so Eleventy templates with embedded JSON-LD are scanned too. The hook's regex over code fences will miss JSON-LD `text` properties; **scope-out**: adding JSON-LD CLI-token scanning is a follow-up. File as sibling code-review issue if it's missed.

**Skill-file byte budgets:**

- `plan/SKILL.md` is currently 633 lines / ~25 KB. Adding the CLI-verification checklist item (≤15 lines) keeps it well under any threshold.
- `review/SKILL.md` is 567 lines. Same headroom.

**Retroactive gate application check (`wg-when-fixing-a-workflow-gates-detection`):**

```bash
$ gh issue view 2550 --json state
{"state":"CLOSED"}
```

The originating P0 is closed via #2563 (removal PR). No additional retroactive case exists. The #1810 docs surfaces were also cleaned. Gate retroactive application: **none needed** — this is forward-only prevention.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — because T5 KbLayout refactor creates new component files)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The batch is a net-positive backlog drain: 7 issues closed, 3 scope-outs filed with re-evaluation criteria (items #2269/9, #2269/10, #2269/11). Four tranches touch UI code (T1, T2, T5 — inside `apps/web-platform`), one touches server-side helpers (T3), one touches CI (T6), one touches the plan/review skills + a new hook (T7). The surface area is broad but the per-tranche blast radius is narrow. Risk concentrations:

- T5 (KbLayout split) is the riskiest — it reorganizes a high-traffic component. The mitigation is existing-test regression coverage + DOM-parity smoke test.
- T6 (composite action) requires a manual workflow_dispatch verification post-merge — `wg-after-merging-a-pr-that-adds-or-modifies` enforces it.
- T7 adds a new hook. Hook must be non-blocking (advisory warn-only) so a false positive doesn't block a legitimate commit. The existing five hooks in `.claude/hooks/` are all blocking; this one intentionally is not.

Bisect-friendliness: each tranche is a single commit, so `git bisect` can isolate regressions.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (auto-accept path)
**Skipped specialists:** ux-design-lead (structural-only refactors; no visual changes; DOM parity guaranteed), copywriter (no user-facing copy added — `Saving...` and the NamingNudge error message text are functional microcopy, not brand copy)
**Pencil available:** N/A

**Findings:** T5 mechanically creates new `components/kb/kb-desktop-layout.tsx` and `components/kb/kb-mobile-layout.tsx` files, which triggers the BLOCKING-tier mechanical escalation in AGENTS.md. However, these are pure structural extractions — every rendered DOM node is byte-identical to the pre-refactor output. The acceptance criterion includes a DOM-parity smoke test. Per the auto-accept rubric for pipeline-mode advisory reviews, this is acceptable. T1 adds a new `Saving...` label and an error-text line in NamingNudge — functional microcopy; the nudge component is a small internal-dashboard element, not a marketing-surface page. No brand review needed.

---

## Implementation Order & Dependencies

```
T3 (vision-helpers rename)    ──┐
T1 (naming-nudge fix)         ──┤
T2 (dashboard polish 1-8)     ──┤
T4 (close #2419 no-op)        ──┼─── merge as one PR, one per tranche commit
T6 (composite action)         ──┤
T7 (docs CLI gate)            ──┤
T5 (kb-layout split) ─────────┘   (last, highest blast-radius, isolated by position)
```

- T1, T2, T3 are independent — run in parallel if useful.
- T5 comes last so a regression blows up before the dependency-free tranches get muddied in bisect.
- T6 and T7 are CI/tooling — do them after the web-platform changes settle so the composite-action migration doesn't conflict with another in-flight PR.
- T4 is zero-code, done at PR-creation time with the close comment.

---

## Test Strategy

**Web-platform (T1-T3, T5):**

```bash
cd apps/web-platform
./node_modules/.bin/vitest run test/naming-nudge.test.tsx test/leader-avatar.test.tsx test/error-states.test.tsx test/components/conversation-row.test.tsx test/dashboard-layout-banner.test.tsx test/vision-creation.test.ts test/foundation-section.test.tsx
```

Full suite (after all tranches):

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run
```

Per `cq-in-worktrees-run-vitest-via-node-node` — use the app-local binary, NOT `npx vitest`.

**Hook (T7):**

```bash
bash .claude/hooks/docs-cli-verification.test.sh
```

**CI (T6):**

- No pre-merge runtime test (composite action behavior surfaces only on schedule/workflow_dispatch).
- **Post-merge verification** (mandatory): `gh workflow run rule-metrics-aggregate.yml && gh run view <id> --json status,conclusion` poll until complete, then same for `scheduled-weekly-analytics.yml`. Investigate any failure; do not close #2272 until both pass.

**Acceptance criteria (pre-merge PR-level):**

- [ ] All `apps/web-platform` unit tests green.
- [ ] Hook self-tests green.
- [ ] `gh pr view <N>` shows all seven `Closes #N` trailers in the body.
- [ ] Seven issues transition to CLOSED on merge.
- [ ] Three new scope-out issues created (items #2269/9, #2269/10, #2269/11) with `code-review` label.

**Acceptance criteria (post-merge, operator):**

- [ ] `scheduled-weekly-analytics.yml` workflow_dispatch succeeds.
- [ ] `rule-metrics-aggregate.yml` workflow_dispatch succeeds.
- [ ] `.claude/hooks/docs-cli-verification.sh` fires on a sample edit to a `.njk` file in a follow-up PR (spot check).

---

## PR Body Template

```markdown
Drains seven unlinked `code-review` issues clustered around `apps/web-platform` UI/tooling, with two repo-wide docs/CI items folded in.

## What's in this PR

- **T1** fix(naming-nudge): surface onSave errors + remove unused `leaderTitle` prop — **Closes #2268**
- **T2** refactor(dashboard): drain polish items 1-8 (test decoupling, foundation-section extract, at-mention hoist) — **Closes #2269** (items 9/10/11 split to new sibling issues)
- **T3** refactor(vision-helpers): name magic numbers, clarify `MAX_VISION_CHARS` (code-unit cap, not byte cap) — **Closes #2337**
- **T4** chore: close #2419 — PR #2414 review complete, finding 1 fixed inline in 847382af, finding 2 YAGNI-deferred — **Closes #2419**
- **T5** refactor(kb-layout): split into `KbDesktopLayout` + `KbMobileLayout` + `useKbLayoutState` — **Closes #2440**
- **T6** ci: extract `bot-pr-with-synthetic-checks` composite action (shared by rule-metrics + weekly-analytics) — **Closes #2272**
- **T7** feat(plan+review): docs CLI-verification gate (plan checklist + review step + advisory hook) — **Closes #2566**

## Test plan

- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` — green
- [ ] `bash .claude/hooks/docs-cli-verification.test.sh` — green
- [ ] T5 DOM-parity smoke test: `KbLayout` pre/post extraction renders identical tree
- [ ] Post-merge: `gh workflow run scheduled-weekly-analytics.yml` succeeds
- [ ] Post-merge: `gh workflow run rule-metrics-aggregate.yml` succeeds
```

---

## Sharp Edges (this plan specifically)

1. **Tranche T5 (KbLayout split) is a refactor-only claim.** Verify DOM parity via snapshot test before merging — the claim is load-bearing. If DOM diverges, the "refactor-only" classification is wrong and the Product/UX Gate must escalate to BLOCKING.
2. **Tranche T6 chose option (b)** for the date-suffix shell expansion caveat. If option (a) or (c) is preferred during implementation, the composite action's input schema changes — re-run the "migrate both workflows" step.
3. **Tranche T7 rule-id collision:** before inserting `cq-docs-cli-verification` into AGENTS.md, `rg "cq-docs-cli-verification"` across the repo — IDs are immutable (`cq-rule-ids-are-immutable`) so reuse of a near-miss id would break the lint hook.
4. **#2269 items 9/10/11 MUST be filed as sibling issues BEFORE the PR merges**, not after. Filing after merge means the re-evaluation trail is broken and the next cleanup-scope-outs run re-discovers them as "orphan" work.
5. **The PR body Closes trailer ordering matters.** GitHub auto-closes in the order they appear. List them grouped by tranche, not by issue number, so the merge notification mirrors the actual commit sequence.

---

## Session Summary Data (for pipeline)

- Plan file: `knowledge-base/project/plans/2026-04-18-refactor-drain-review-followups-batch-plan.md`
- Branch: `feat-one-shot-review-followups-batch`
- Worktree: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-review-followups-batch`
- Issues closed by this PR: #2268, #2269, #2272, #2337, #2419, #2440, #2566
- New sibling issues to file: 3 (DashboardPage extraction, CSP doc comment, SVG download disposition)
- New composite action: `.github/actions/bot-pr-with-synthetic-checks/action.yml`
- New skill edits: `plugins/soleur/skills/plan/SKILL.md`, `plugins/soleur/skills/review/SKILL.md`
- New hook: `.claude/hooks/docs-cli-verification.sh`
- New AGENTS.md rule: `cq-docs-cli-verification`
