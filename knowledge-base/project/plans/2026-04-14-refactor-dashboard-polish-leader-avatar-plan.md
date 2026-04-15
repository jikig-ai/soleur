# refactor(dashboard): LeaderAvatar adoption, color SOT, CSP, test mock utility

**Branch:** `feat-refactor-dashboard-polish`
**Worktree:** `.worktrees/feat-refactor-dashboard-polish/`
**Issues:** Closes #2141, Closes #2169
**Source PR:** #2130 review
**Draft PR:** #2265
**Sequence:** Final PR (4/4) in code-review resolution from #2130

## Summary

Address two GitHub issues from the PR #2130 code review in a single PR:

1. **#2141** — Five P3 polish items:
   - (a) Finish `LeaderAvatar` adoption in three components that still render inline badges
   - (b) Resolve triple source of truth for leader colors (`DOMAIN_LEADERS.color` vs `LEADER_BG_COLORS` vs `LEADER_COLORS`)
   - (c) Add defense-in-depth CSP header on binary responses at `/api/kb/content/`
   - (d) Replace Tailwind class-name assertions in `leader-avatar.test.tsx` with behavioral assertions
   - (e) Extract duplicated foundation cards grid in `dashboard/page.tsx` into `FoundationCards`
2. **#2169** — Extract a shared `useTeamNames` mock factory used by 7 test files (~105 duplicated lines), including updating two files with stale mocks (`error-states.test.tsx`, `chat-page-resume.test.tsx`) that predate the `iconPaths`/`updateIcon`/`refetch`/`getIconPath` additions.

This is a pure refactor/polish PR: no new user-facing behavior, no API changes, no migrations.

## Context

- PR #2130 merged the `LeaderAvatar` component and `useTeamNames` hook with `iconPaths`/`updateIcon`/`getIconPath` additions but did not migrate every inline badge callsite nor remove the now-dead `color` field on `DOMAIN_LEADERS`.
- Tailwind v4.1 is in use (`apps/web-platform/package.json`, `apps/web-platform/app/globals.css: @import "tailwindcss";`). v4's scanner detects literal classnames from source; dynamic `bg-${color}` interpolation is not auto-detected. This constrains option (b) below.
- Existing shared test-mock convention: `apps/web-platform/test/mocks/` already holds `agent-runner-mocks.ts`, `mock-supabase.ts`. Add `use-team-names.ts` here.
- No route handler conventions for CSP on binary responses yet — `/api/kb/content/[...path]/route.ts` already sets `X-Content-Type-Options: nosniff` and `Cache-Control: private`; add `Content-Security-Policy` alongside.

## Scope (in)

- `apps/web-platform/components/chat/naming-nudge.tsx` — replace inline badge with `<LeaderAvatar>`
- `apps/web-platform/components/onboarding/naming-modal.tsx` — replace inline badge with `<LeaderAvatar>`
- `apps/web-platform/components/chat/at-mention-dropdown.tsx` — replace inline badge with `<LeaderAvatar>` (keep dynamic label via `getBadgeLabel` / custom-name prefix — see Design note below)
- `apps/web-platform/server/domain-leaders.ts` — remove dead `color` field (Option B, see Decisions)
- `apps/web-platform/components/chat/leader-colors.ts` — keep as single SOT (unchanged) OR, if Option A chosen, replace with derived export from `DOMAIN_LEADERS`
- `apps/web-platform/app/api/kb/content/[...path]/route.ts` — add CSP header to the binary `Response`
- `apps/web-platform/test/leader-avatar.test.tsx` — refactor to behavioral assertions using `@testing-library/react`
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — extract `FoundationCards` component
- `apps/web-platform/components/dashboard/foundation-cards.tsx` — new file
- `apps/web-platform/test/mocks/use-team-names.ts` — new shared mock factory
- 7 test files updated to use the shared mock (listed in Test Impact)

## Scope (out)

- No changes to the visual design of avatars/badges (colors, sizes, shapes stay identical)
- No changes to the `/api/team-names` API or Supabase migrations
- No Playwright/browser QA required (zero UX changes — internal refactor only)
- No README/knowledge-base doc updates beyond this plan

## Decisions

### D1 — Color triple SOT: remove `color` field (Option B)

Option A ("derive `LEADER_BG_COLORS` from `DOMAIN_LEADERS.color`") requires either:

- A Tailwind v4 `@source inline(...)` safelist in `globals.css` listing every `bg-<color>` value, OR
- Shipping a runtime map anyway so Tailwind's scanner sees literal classnames

Since option A still requires a literal-class map somewhere for Tailwind to pick it up, deriving buys no single-SOT benefit — it creates two coupled lists. **Choose Option B: delete the `color` field from all 9 entries in `DOMAIN_LEADERS`.** `LEADER_BG_COLORS` / `LEADER_COLORS` in `leader-colors.ts` become the sole color SOT. Rationale: simpler, zero Tailwind safelist config, no runtime indirection, matches existing component read path.

**Risk:** Any external consumer of `DOMAIN_LEADERS[*].color` breaks. Verification: grep `\.color` references to the type and all usages before deleting.

### D2 — `at-mention-dropdown` badge content

The current inline badge shows either `customNames[leader.id].slice(0, 3).toUpperCase()` (e.g., "ALE") or `leader.name.slice(0, 3)` (e.g., "CTO"). `LeaderAvatar` renders only an icon, not text. Two options:

- **D2a (keep text badge)** — Leave `at-mention-dropdown.tsx` using the inline badge pattern; scope-reduce issue #2141 (a) to only `naming-nudge.tsx` and `naming-modal.tsx`. File a follow-up issue for dropdown once `LeaderAvatar` gets a text-override prop.
- **D2b (migrate to LeaderAvatar, drop text)** — Replace the text-in-badge with a lucide icon. Custom-name prefix remains visible in the row label next to the badge (line 118–121), so the three-letter abbreviation is redundant with the visible name text anyway.

**Choose D2b.** The three-letter slice is already redundant with the adjacent row text (`{customNames[leader.id]} (${leader.name})` or `leader.name`). Removing it aligns with the visual language of `LeaderAvatar` elsewhere (sidebar, dashboard foundation cards, message bubbles) and keeps icon semantics consistent. Verify via screenshot in local dev that the dropdown still communicates leader identity clearly.

### D3 — CSP header value

Issue prescribes `default-src 'none'; style-src 'unsafe-inline'`. This is correct for PDF/image/docx responses: no script/frame/font loads should execute from these URLs. **Apply verbatim.** Add only to the binary branch (line 131 `new Response(buffer, ...)`); the JSON branches above already benefit from Next.js default CSP on HTML routes (N/A — JSON responses aren't rendered).

### D4 — `FoundationCards` component API

Inline card grid appears twice (lines 477–515 and 591–628 of `dashboard/page.tsx`) with identical card rendering logic. Extract to `components/dashboard/foundation-cards.tsx`:

```tsx
interface FoundationCardsProps {
  cards: FoundationCard[];
  getIconPath: (id: DomainLeaderId) => string | null;
  onIncompleteClick: (promptText: string) => void;
}
export function FoundationCards(props: FoundationCardsProps): JSX.Element
```

The outer wrapper (header "FOUNDATIONS", description copy, grid container classes) differs slightly between call sites (`mb-10 w-full` vs `mb-6`). Keep the outer wrapper inlined at each site; `FoundationCards` owns only the `<div className="grid ...">` + card list. This preserves the existing layout without re-threading margin props.

### D5 — `useTeamNames` mock shape

Ship a single exported `createUseTeamNamesMock(overrides?)` factory:

```ts
// apps/web-platform/test/mocks/use-team-names.ts
import { vi } from "vitest";
import type { DomainLeaderId } from "@/server/domain-leaders";

export function createUseTeamNamesMock(overrides: Partial<ReturnType<typeof defaults>> = {}) {
  return { ...defaults(), ...overrides };
}

function defaults() {
  return {
    names: {} as Record<string, string>,
    iconPaths: {} as Record<string, string>,
    nudgesDismissed: [] as string[],
    namingPromptedAt: null as string | null,
    loading: false,
    error: null as string | null,
    updateName: vi.fn(),
    updateIcon: vi.fn(),
    dismissNudge: vi.fn(),
    refetch: vi.fn(),
    getDisplayName: (id: DomainLeaderId) => id.toUpperCase(),
    getBadgeLabel: (id: DomainLeaderId) => id.toUpperCase().slice(0, 3),
    getIconPath: (_id: DomainLeaderId) => null as string | null,
  };
}
```

Usage in test files:

```ts
import { createUseTeamNamesMock } from "./mocks/use-team-names"; // or "../mocks/use-team-names"
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
}));
// or per-test: useTeamNames: () => createUseTeamNamesMock({ loading: true })
```

This preserves call-site flexibility (overrides for loading/error states) while anchoring the shape in one place.

### D6 — Test behavioral assertions

Replace implementation-coupled assertions (`container.firstElementChild.className.toContain("bg-pink-500")`) with user-observable properties:

- **aria-label** — already tested; expand to all three size cases.
- **role/presence of img** — use `queryByAltText` / `getByLabelText` instead of `querySelector` on CSS classes.
- **icon rendering** — assert the lucide `<svg>` node exists for a known leader (e.g., `container.querySelector("svg")` still OK — structural, not stylistic).
- **size behavior** — assert `width`/`height` attributes on the rendered image or icon (`sizeConfig.icon + 4`), which is user-observable output, not a Tailwind class.
- **customIconPath** — keep existing `src` assertion (it's a URL contract, not a class).
- **fallback on error** — add a test that fires `onError` on the img and asserts the lucide icon appears (behavioral fallback guarantee from `useState`+`setImgError`).

Drop the three "applies correct size classes" tests and the "applies the leader background color" test in their current form.

## Files to Change

### Component migrations (issue #2141 a)

- `apps/web-platform/components/chat/naming-nudge.tsx`
  - Remove `import { LEADER_BG_COLORS } from "./leader-colors";`
  - Replace the inline `<span className={...${LEADER_BG_COLORS[leaderId]}}>{roleName}</span>` with `<LeaderAvatar leaderId={leaderId} size="lg" />`
  - Preserve the `gap-3`, wrapper layout, and `roleName` usage in the description copy
- `apps/web-platform/components/onboarding/naming-modal.tsx`
  - Remove `import { LEADER_BG_COLORS } from "@/components/chat/leader-colors";`
  - Replace inline span badge with `<LeaderAvatar leaderId={leader.id} size="lg" />`
  - Keep `gap-4` flex row
- `apps/web-platform/components/chat/at-mention-dropdown.tsx`
  - Remove `import { LEADER_BG_COLORS } from "./leader-colors";`
  - Replace inline text-badge span with `<LeaderAvatar leaderId={leader.id} size="md" />`
  - Keep the row label (`customNames[leader.id] ? "{name} ({role})" : leader.name`) — badge becomes icon-only

### Color SOT (issue #2141 b)

- `apps/web-platform/server/domain-leaders.ts`
  - Delete the `color` field from all 9 entries (cmo, cto, cfo, cpo, cro, coo, clo, cco, system)
  - Confirm no consumer reads `DOMAIN_LEADERS[*].color` before deletion (grep verification step)
- `apps/web-platform/components/chat/leader-colors.ts` — unchanged (remains SOT)

### CSP on binary route (issue #2141 c)

- `apps/web-platform/app/api/kb/content/[...path]/route.ts`
  - Add `"Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'"` to the `headers` object in `new Response(buffer, { headers: { ... } })` (around line 132)

### Test refactor (issue #2141 d)

- `apps/web-platform/test/leader-avatar.test.tsx`
  - Rewrite per D6: aria-label, size (via rendered dimensions), custom icon src, fallback-on-error, system/null fallback to Soleur logo
  - 10–12 tests total; all assertions against user-observable output

### Foundation cards extraction (issue #2141 e)

- **NEW** `apps/web-platform/components/dashboard/foundation-cards.tsx`
  - Exports `FoundationCards({ cards, getIconPath, onIncompleteClick })`
  - Renders only the `<div className="grid grid-cols-2 gap-3 md:grid-cols-4">` + card map (the inner grid — not the outer header/description wrapper)
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
  - Replace both inline card grids (lines 477–515 and 591–628) with `<FoundationCards cards={foundationCards} getIconPath={getIconPath} onIncompleteClick={handlePromptClick} />`
  - Keep the outer `<p>FOUNDATIONS</p>` + description + wrapper divs at each call site (they differ per branch)

### Shared mock utility (issue #2169)

- **NEW** `apps/web-platform/test/mocks/use-team-names.ts` — factory per D5
- Update 7 test files to import and use the factory:
  - `apps/web-platform/test/start-fresh-onboarding.test.tsx`
  - `apps/web-platform/test/team-names-hook.test.tsx` — check if this file mocks *itself* (hook unit tests likely don't mock); if it does not mock `useTeamNames`, leave unchanged
  - `apps/web-platform/test/team-settings.test.tsx`
  - `apps/web-platform/test/display-format.test.tsx`
  - `apps/web-platform/test/error-states.test.tsx` — also heals stale mock (missing `iconPaths`, `updateIcon`, `refetch`, `getIconPath`, `error`)
  - `apps/web-platform/test/components/status-badge-interaction.test.tsx`
  - `apps/web-platform/test/dashboard-layout-banner.test.tsx`
  - `apps/web-platform/test/chat-page-resume.test.tsx` — also heals stale mock
  - `apps/web-platform/test/chat-page.test.tsx`
  - `apps/web-platform/test/command-center.test.tsx`
  - `apps/web-platform/test/components/conversation-row.test.tsx`
  - **Note:** grep returned 11 files — audit during implementation and update all that mock `useTeamNames` (exclude the hook's own unit test if it doesn't mock).

## Acceptance Criteria

- [ ] `naming-nudge.tsx`, `naming-modal.tsx`, `at-mention-dropdown.tsx` import `LeaderAvatar` and no longer import `LEADER_BG_COLORS` directly for inline badges
- [ ] No grep hits for `LEADER_BG_COLORS\[` outside `components/leader-avatar.tsx` and `components/chat/leader-colors.ts`
- [ ] `DOMAIN_LEADERS` entries have no `color` field; TypeScript type `(typeof DOMAIN_LEADERS)[number]` no longer exposes `color`
- [ ] `/api/kb/content/[...path]` binary responses include header `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'`
- [ ] `leader-avatar.test.tsx` contains no `toContain("bg-")`, `toContain("h-")`, or `toContain("w-")` assertions
- [ ] `FoundationCards` component exists at `components/dashboard/foundation-cards.tsx` and is used in both branches of `dashboard/page.tsx`
- [ ] `test/mocks/use-team-names.ts` exports `createUseTeamNamesMock`
- [ ] All 7+ test files use the shared factory; no duplicated inline mock literals for `useTeamNames` remain
- [ ] `error-states.test.tsx` and `chat-page-resume.test.tsx` mocks include `iconPaths`, `updateIcon`, `refetch`, `getIconPath` (via shared factory)
- [ ] `node node_modules/vitest/vitest.mjs run` passes in the worktree (zero new failures vs. main)
- [ ] TypeScript compiles without errors (`npx tsc --noEmit`)

## Test Scenarios

Every acceptance criterion maps to at least one test or verification command:

1. **LeaderAvatar adoption** — existing `leader-avatar.test.tsx` + visual grep: `grep -rE 'LEADER_BG_COLORS\[' apps/web-platform/components/` returns only `leader-avatar.tsx`.
2. **Color field removed** — `grep -rE '\.color\b' apps/web-platform/server/domain-leaders.ts` returns nothing; TS `noEmit` passes.
3. **CSP header** — add one unit test in `apps/web-platform/test/csp.test.ts` (file already exists per `ls` output) or co-locate in a new `apps/web-platform/test/kb-content-route.test.ts`: call the route handler with a fake image request, assert response headers include `Content-Security-Policy`. If mocking Supabase + filesystem is too heavy, cover via existing integration path and add a focused unit test for just the headers object.
4. **Behavioral LeaderAvatar tests** — rewrite per D6; run via vitest.
5. **FoundationCards** — new `apps/web-platform/test/foundation-cards.test.tsx` renders the component with mixed done/incomplete cards, asserts completed cards render as `<a href>` and incomplete cards render as `<button>` with click handler firing `onIncompleteClick(promptText)`.
6. **Shared mock factory** — new `apps/web-platform/test/mocks/use-team-names.test.ts` asserts `createUseTeamNamesMock()` returns all required keys from `TeamNamesState` (structural check against `typeof`), and that overrides merge correctly.
7. **Stale mock healing** — `error-states.test.tsx` and `chat-page-resume.test.tsx` must still pass after factory swap; any assertion that previously bypassed missing fields via `undefined` must now either accept the defaults or pass explicit overrides.

## Test Impact — affected files

Full list of files to audit (from grep `useTeamNames|use-team-names` in `apps/web-platform/test/`):

1. `start-fresh-onboarding.test.tsx`
2. `team-names-hook.test.tsx` (likely unchanged — unit tests the hook itself)
3. `team-settings.test.tsx`
4. `display-format.test.tsx`
5. `error-states.test.tsx` *(stale mock)*
6. `components/status-badge-interaction.test.tsx`
7. `dashboard-layout-banner.test.tsx`
8. `chat-page-resume.test.tsx` *(stale mock)*
9. `chat-page.test.tsx`
10. `command-center.test.tsx`
11. `components/conversation-row.test.tsx`

Expected net line delta: ~105 lines removed across 7–10 files, ~30 lines added to the factory + tests = net ~75 lines removed.

## Implementation Order

1. **Read** all five source files to be edited (already read during plan phase — re-read after any compaction).
2. **Write failing tests first** (TDD gate per AGENTS.md Code Quality):
   - Write new `foundation-cards.test.tsx`
   - Write new `mocks/use-team-names.test.ts`
   - Rewrite `leader-avatar.test.tsx` behavioral assertions (expect old assertions to pass pre-refactor, new ones to remain green after)
   - Add CSP header test (either new route test or csp.test.ts extension)
3. **Implement** in this order to minimize breakage:
   - a. Create `test/mocks/use-team-names.ts` factory
   - b. Migrate 7–10 test files to use factory (commit 1 — test infra only, should leave suite green)
   - c. Add CSP header to route handler
   - d. Create `FoundationCards` component + swap dashboard page
   - e. Migrate `naming-nudge.tsx`, `naming-modal.tsx`, `at-mention-dropdown.tsx` to `LeaderAvatar`
   - f. Remove `color` field from `DOMAIN_LEADERS` (last — after verifying no consumers)
4. **Verify** — `node node_modules/vitest/vitest.mjs run` in worktree + `npx tsc --noEmit` + markdownlint on changed MD files (none expected).
5. **Ship** via `/ship` — semver label `patch` (pure refactor, no user-visible change).

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `DOMAIN_LEADERS.color` has a hidden consumer | Low | Grep before delete: `grep -rE '\.color\b' apps/web-platform/{app,components,hooks,lib,server}/` |
| Visual regression in at-mention dropdown (icon-only badge reads worse than text badge) | Low–Medium | Screenshot QA step in dev; fallback is to keep `at-mention-dropdown.tsx` on inline badge and file follow-up issue |
| `FoundationCards` extraction changes layout (margin/gap drift) | Low | Keep wrapper divs inlined at call sites; extract only the grid itself |
| Stale mocks unmasked hidden failures | Medium | Run full vitest suite after each commit; if a previously-passing test now fails, investigate whether it was passing by coincidence (missing field = `undefined` behavior) |
| Tailwind v4 scanner misses a class after ref removal | Very Low | `LEADER_BG_COLORS` still holds literal classes; no dynamic interpolation introduced |
| CSP header breaks PDF inline viewing in `react-pdf` | Low | `react-pdf` loads the PDF via `fetch` + worker, not iframe; `default-src 'none'` does not block fetches from same origin. Verify locally with a KB-hosted PDF. If it breaks, relax to `default-src 'self'` — still defense-in-depth. |

## Non-Goals

- Visual design changes (colors, sizes, icons unchanged)
- Behavior changes in `useTeamNames` hook itself
- New Tailwind safelist entries (not needed — Option B deletes the redundant field)
- Re-test of PR #2130 features (already covered by existing tests)
- Browser QA via Playwright (no new pages, no user flows touched)

## Domain Review

**Domains relevant:** none

This is a pure refactor/polish PR. No user-facing surface changes (icons already in place; migration is inline-badge → shared-component), no new capabilities, no content, no pricing/legal/sales/ops implications. CSP header is defense-in-depth on an existing route — security-adjacent but routine.

No cross-domain implications detected — tooling/cleanup change.

## Post-Ship

- Merge plan triggers squash-merge to main; CI handles semver tag + release.
- No migration applies, no external resources to verify post-deploy.
- `Closes #2141` and `Closes #2169` in PR body auto-close issues on merge.
- Update draft PR #2265 — promote from WIP to ready after implementation.

## References

- Source PR review: <https://github.com/jikig-ai/soleur/pull/2130>
- Issue #2141: <https://github.com/jikig-ai/soleur/issues/2141>
- Issue #2169: <https://github.com/jikig-ai/soleur/issues/2169>
- Draft PR: <https://github.com/jikig-ai/soleur/pull/2265>
- Tailwind v4 source scanning: <https://tailwindcss.com/docs/v4-beta#content-detection> (for Option B rationale)
- AGENTS.md Code Quality → worktree vitest via `node node_modules/vitest/vitest.mjs run`
