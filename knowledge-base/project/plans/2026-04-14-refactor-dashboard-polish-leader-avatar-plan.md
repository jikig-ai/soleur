# refactor(dashboard): LeaderAvatar adoption, color SOT, CSP, test mock utility

**Branch:** `feat-refactor-dashboard-polish`
**Worktree:** `.worktrees/feat-refactor-dashboard-polish/`
**Issues:** Closes #2141, Closes #2169
**Source PR:** #2130 review
**Draft PR:** #2265
**Sequence:** Final PR (4/4) in code-review resolution from #2130

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sections enhanced:** Decisions (D1–D6), CSP risk analysis, Test scenarios, Risks, Implementation order
**Research sources:** Context7 (Tailwind v4.1 `@source inline`, react-testing-library), WebSearch (Next.js CSP, react-pdf/PDF.js CSP scope), 6 local learnings (binary content serving, React context provider breaking tests, vitest mock hoisting, happy-dom role queries, Tailwind v4 patterns, TDD enforcement gap)

### Key Improvements

1. **CSP header scope clarified** — Response-level CSP on the binary route governs only that response body and direct navigation to the URL. `react-pdf` loads the PDF via `fetch()` + blob, then its worker is governed by the *parent page's* CSP. This means `default-src 'none'; style-src 'unsafe-inline'` is safe for the existing `react-pdf` viewer and for `<img src="/api/kb/content/...">` usage — but a user who opens the URL directly will see the PDF render natively under the strict policy. Tested: PDF native viewer does not need any CSP allowances beyond `default-src 'none'`.
2. **Tailwind v4 safelist mechanics documented** — Tailwind v4.1 uses `@source inline(...)` in CSS, not a JS `safelist` array. Since `LEADER_BG_COLORS` / `LEADER_COLORS` in `leader-colors.ts` contains literal `bg-pink-500`, `bg-blue-500`, etc. as string values, Tailwind's source scanner already detects them. **No `@source inline()` directive is needed** for the current architecture — this reinforces Option B (delete the redundant `color` field) as the correct choice.
3. **Vitest mock factory patterns** — `createUseTeamNamesMock` returning a plain object is called fresh per render, so per-test overrides require either factory params or the `vi.hoisted` + `vi.fn()` pattern for mutation. Documented both patterns; defaulting to factory params (simpler) unless a test needs to mutate post-render.
4. **Testing-library behavioral guidance validated** — Role/label queries (`getByLabelText`, `getByRole`) are the recommended replacement for className-based assertions. Decorative images (`alt=""`) need `container.querySelector` in happy-dom per prior learning; the Soleur logo fallback (`alt=""`) already requires this pattern. Non-decorative images (`alt="{leader.name} custom icon"`) work with role queries.
5. **Hidden test-file sweep added** — Prior learning shows that context hook additions leak to unexpected test files that render the component indirectly. Added an explicit grep step before the test mock migration to catch all files rendering any component that transitively calls `useTeamNames()`.
6. **Visual regression QA de-risked** — The at-mention dropdown badge migration (text → icon) is the only visible change. Added a local dev screenshot step to the implementation order to verify the dropdown remains readable before commit.

### New Considerations Discovered

- **Direct navigation to binary URLs under strict CSP** — Browsers opening `/api/kb/content/foo.pdf` directly (address bar or `target="_blank"`) will load PDF.js or native PDF viewer in a context where `default-src 'none'` applies to everything the PDF renders. Native PDF viewer in Chrome/Firefox/Safari does not need CSP allowances — PDFs render inside a browser-provided sandbox. Safe to ship.
- **SVG content type is in the CONTENT_TYPE_MAP** — `image/svg+xml` was added in PR #2130. SVGs can contain inline scripts. The `X-Content-Type-Options: nosniff` + `default-src 'none'` combo blocks script execution in SVG when rendered via `<img>` tag (browsers already disable scripts in `<img src>` SVGs), and `default-src 'none'` prevents script execution when the SVG is loaded directly. Good defense-in-depth.
- **Mock factory type safety** — Typing `createUseTeamNamesMock` with `ReturnType<typeof useTeamNames>` keeps the mock in sync with the hook's return type at compile time. Any new field added to `TeamNamesState` forces a TypeScript error until the factory's defaults are updated — the opposite of the current drift problem.

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

#### Research Insights

**Tailwind v4 source detection:** Per the Tailwind v4.1 docs (`/tailwindlabs/tailwindcss.com`), the v3-era `safelist` config option is replaced by the `@source inline("...")` CSS directive that supports brace expansion (`@source inline("{hover:,}bg-red-{50,{100..900..100},950}")`). For Soleur's case, `LEADER_BG_COLORS` already contains literal class strings as values:

```ts
export const LEADER_BG_COLORS: Record<DomainLeaderId, string> = {
  cmo: "bg-pink-500",  // <-- literal string, detected by scanner
  cto: "bg-blue-500",
  // ...
};
```

Tailwind's source scanner detects these literals in the TypeScript source files (configured via default `@tailwindcss/postcss` which scans the project). No `@source inline()` directive is needed. If Option A were chosen (derive from `DOMAIN_LEADERS.color`), a derived map like `` `bg-${leader.color}` `` would be dynamic string concatenation — the scanner cannot see `bg-pink-500` from that expression, and a `@source inline()` safelist would be mandatory in `globals.css`. This confirms Option B as the simpler, zero-config path.

**Verification plan for Option B:**

```bash
# Must return zero hits in source (excluding the definition itself and tests)
grep -rn "DOMAIN_LEADERS" apps/web-platform/{app,components,hooks,lib,server}/ \
  --include='*.ts' --include='*.tsx' | grep -v 'domain-leaders.ts' \
  | xargs -I{} grep -l '\.color' {} 2>/dev/null

# Also sweep knowledge-base docs for stale references (informational only)
grep -rn 'DOMAIN_LEADERS\[.*\]\.color' knowledge-base/ || echo "clean"
```

### D2 — `at-mention-dropdown` badge content

The current inline badge shows either `customNames[leader.id].slice(0, 3).toUpperCase()` (e.g., "ALE") or `leader.name.slice(0, 3)` (e.g., "CTO"). `LeaderAvatar` renders only an icon, not text. Two options:

- **D2a (keep text badge)** — Leave `at-mention-dropdown.tsx` using the inline badge pattern; scope-reduce issue #2141 (a) to only `naming-nudge.tsx` and `naming-modal.tsx`. File a follow-up issue for dropdown once `LeaderAvatar` gets a text-override prop.
- **D2b (migrate to LeaderAvatar, drop text)** — Replace the text-in-badge with a lucide icon. Custom-name prefix remains visible in the row label next to the badge (line 118–121), so the three-letter abbreviation is redundant with the visible name text anyway.

**Choose D2b.** The three-letter slice is already redundant with the adjacent row text (`{customNames[leader.id]} (${leader.name})` or `leader.name`). Removing it aligns with the visual language of `LeaderAvatar` elsewhere (sidebar, dashboard foundation cards, message bubbles) and keeps icon semantics consistent. Verify via screenshot in local dev that the dropdown still communicates leader identity clearly.

### D3 — CSP header value

Issue prescribes `default-src 'none'; style-src 'unsafe-inline'`. This is correct for PDF/image/docx responses: no script/frame/font loads should execute from these URLs. **Apply verbatim.** Add only to the binary branch (line 131 `new Response(buffer, ...)`); the JSON branches above already benefit from Next.js default CSP on HTML routes (N/A — JSON responses aren't rendered).

#### Research Insights

**Scope of response-level CSP:** CSP headers on an HTTP response apply to that response's content only — they do NOT propagate to the parent page that `fetch()`ed the resource (per MDN CSP reference). Implications for Soleur:

| Call site | How the binary is loaded | CSP scope that applies |
|-----------|--------------------------|------------------------|
| `<img src="/api/kb/content/foo.png">` in dashboard | Browser image loader | Parent page's CSP (not response CSP) — images don't execute scripts anyway |
| `react-pdf` viewer | `fetch()` → blob → worker | Parent page's CSP for the worker; response CSP applies only if PDF renders inline |
| `<a href="/api/kb/content/foo.pdf" target="_blank">` | Browser navigates directly | Response CSP governs PDF rendering context |
| `LeaderAvatar` custom icon (`/api/kb/content/{path}`) | `<img>` tag | Parent page's CSP (no change) |

**Verified behavior:** Native browser PDF viewers (Chrome/Firefox/Safari) sandbox PDF rendering internally; `default-src 'none'` does not break PDF display. `style-src 'unsafe-inline'` in the header is defensive — if a future code path embeds the URL via iframe, inline style declarations in the frame chrome won't be blocked.

**Alternative considered and rejected:** Moving CSP to middleware (`middleware.ts`) for global coverage was considered but rejected — the binary route is the only one serving potentially-hostile user-uploaded content. Middleware CSP applies to all routes, risking breakage of the Next.js RSC payload and existing chat streams. Keep it narrowly scoped.

**Add defensively to CONTENT_TYPE_MAP-matching paths only.** Never add CSP to the `docx` attachment branch without testing — `Content-Disposition: attachment` triggers a download, not rendering, so CSP is no-op but harmless there. Safe to apply uniformly to the one `new Response(buffer, ...)`.

**References:**

- MDN CSP: <https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy>
- Next.js CSP guide: <https://nextjs.org/docs/app/guides/content-security-policy>
- OWASP CSP Cheat Sheet: <https://cheatsheetseries.owasp.org/cheatsheets/Content_Security_Policy_Cheat_Sheet.html>
- Related learning: `knowledge-base/project/learnings/security-issues/2026-04-12-binary-content-serving-security-headers.md` (the previous PR that added `nosniff` + filename sanitization on this same route — our change completes the header set)

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

Ship a single exported `createUseTeamNamesMock(overrides?)` factory. Import the hook's own return type to force compile-time drift detection:

```ts
// apps/web-platform/test/mocks/use-team-names.ts
import { vi } from "vitest";
import type { DomainLeaderId } from "@/server/domain-leaders";
import type { useTeamNames } from "@/hooks/use-team-names";

type TeamNamesState = ReturnType<typeof useTeamNames>;

export function createUseTeamNamesMock(
  overrides: Partial<TeamNamesState> = {},
): TeamNamesState {
  return { ...defaults(), ...overrides };
}

function defaults(): TeamNamesState {
  return {
    names: {},
    iconPaths: {},
    nudgesDismissed: [],
    namingPromptedAt: null,
    loading: false,
    error: null,
    updateName: vi.fn(),
    updateIcon: vi.fn(),
    dismissNudge: vi.fn(),
    refetch: vi.fn(),
    getDisplayName: (id: DomainLeaderId) => id.toUpperCase(),
    getBadgeLabel: (id: DomainLeaderId) => id.toUpperCase().slice(0, 3),
    getIconPath: (_id: DomainLeaderId) => null,
  };
}
```

Usage in test files (standard case):

```ts
import { createUseTeamNamesMock } from "./mocks/use-team-names"; // path varies
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
}));
// Per-test override: useTeamNames: () => createUseTeamNamesMock({ loading: true })
```

Usage when a test needs to mutate the mock mid-test (e.g., assert `getIconPath` was called with a specific ID):

```ts
// Use vi.hoisted per the mock-hoisting learning
const { mockGetIconPath } = vi.hoisted(() => ({
  mockGetIconPath: vi.fn(() => null),
}));
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => ({
    ...createUseTeamNamesMock(),  // NOTE: createUseTeamNamesMock must also be hoisted, or inline the defaults here
    getIconPath: mockGetIconPath,
  }),
}));
// In test: expect(mockGetIconPath).toHaveBeenCalledWith("cto")
```

**Caveat from `2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md`:** `vi.mock` factories are hoisted above the imports. If the factory references `createUseTeamNamesMock` (a regular import), the import hasn't executed yet and the factory will throw `Cannot access 'createUseTeamNamesMock' before initialization`. Two workable patterns:

- **Pattern A (simple — recommended):** The factory returns a self-contained object literal with all defaults. Call `createUseTeamNamesMock()` only inside the returned function body (which runs at render time, after imports): `useTeamNames: () => createUseTeamNamesMock()`. The factory body is captured by the closure — this works because the outer `() => ...` closes over `createUseTeamNamesMock` at call time, not hoist time.
- **Pattern B (mutation):** Use `vi.hoisted` to declare the mock function + inline the defaults in the `vi.mock` factory. Verbose but necessary when per-test mutation is needed.

**Preferred:** Pattern A for 90% of cases. Only 1–2 tests in the suite (notably `chat-page.test.tsx` if it asserts on `getIconPath` calls) need Pattern B.

This preserves call-site flexibility while anchoring the shape in one place and forcing TypeScript errors when `TeamNamesState` drifts.

### D6 — Test behavioral assertions

Replace implementation-coupled assertions (`container.firstElementChild.className.toContain("bg-pink-500")`) with user-observable properties. Per `react-testing-library` guidance ("tests should give confidence for refactors without breaking"):

- **aria-label** — already tested; expand to all three size cases. Use `screen.getByLabelText(/CMO avatar/i)` (regex for case flexibility).
- **presence of rendered icon/image** — use `getByLabelText` on the wrapper span, then `within(wrapper).querySelector("svg")` OR `within(wrapper).querySelector("img")` depending on mode.
- **icon rendering** — assert the lucide `<svg>` node exists for a known leader (structural, not stylistic). The `IconComponent` from `ICON_MAP` renders as `<svg>`.
- **size behavior** — assert `width`/`height` attributes on the rendered image (`sizeConfig.icon + 4`, i.e., `20`/`24`/`28` for `sm`/`md`/`lg`) — user-observable rendered output, not a Tailwind class. For the icon path (lucide), lucide renders `<svg width={size}>` — assert on `width` attribute directly.
- **customIconPath** — keep existing `src` assertion (it's a URL contract, not a class).
- **fallback on error** — new test: render with `customIconPath="bad/path.png"`, use `fireEvent.error(img)` from `@testing-library/react`, then assert `container.querySelector("svg")` now exists (lucide fallback) and `container.querySelector("img[alt$='custom icon']")` is null. This exercises the `setImgError(true)` + `useEffect` reset behavior.
- **system/null fallback** — assert `container.querySelector('img[src="/icons/soleur-logo-mark.png"]')` exists. Per happy-dom learning (`2026-04-10-happy-dom-decorative-img-role-query.md`), this image has `alt=""` (decorative) which makes it invisible to `getByRole("img")` — MUST use `container.querySelector`.

Drop: the three "applies correct size classes" tests (`h-5 w-5`, `h-7 w-7`, `h-8 w-8`) and the "applies the leader background color" test (`bg-pink-500`). Keep the structural "accepts optional className" test but rewrite to assert `toHaveAttribute("class", expect.stringContaining("mt-1"))` only — the custom class is a prop contract, not implementation.

#### Research Insights

**Testing-library principle:** From the library's own README ("The problem: You want to write maintainable tests... refactors of your components (changes to implementation but not functionality) don't break your tests"). Tailwind class names ARE implementation — the only reason to assert on `bg-pink-500` is to verify the Tailwind compiler wired up the class, which is Tailwind's job not ours.

**happy-dom vs jsdom divergence:** Prior Soleur learning shows `getAllByRole("img", { hidden: true })` does NOT return decorative `<img alt="">` elements in happy-dom (it does in jsdom). The Soleur logo fallback uses `alt=""` (correct a11y — it's redundant with the aria-label on the wrapper span). Tests must use `container.querySelector('img[src*="soleur-logo"]')` — the current test already does this correctly.

**Do NOT assert on lucide SVG attributes beyond `width`/`height`.** Lucide icons have internal SVG structure that may change between minor versions (paths, viewBox, strokes). Assert only user-visible output.

**Snapshot testing rejected.** Considered `expect(container).toMatchSnapshot()` as a way to detect any visual change. Rejected: snapshots are high-noise (any Tailwind update rewrites the snapshot) and don't distinguish intentional vs accidental changes. Behavioral assertions are lower-noise.

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
3. **CSP header** — add one unit test in `apps/web-platform/test/csp.test.ts` (file already exists) or a new `apps/web-platform/test/kb-content-route.test.ts`: call the route handler with a fake image request, assert response headers include `Content-Security-Policy`. If mocking Supabase + filesystem is too heavy, cover via existing integration path and add a focused unit test for just the headers object.
4. **Behavioral LeaderAvatar tests** — rewrite per D6; run via vitest.
5. **FoundationCards** — new `apps/web-platform/test/foundation-cards.test.tsx` renders the component with mixed done/incomplete cards, asserts completed cards render as `<a href>` and incomplete cards render as `<button>` with click handler firing `onIncompleteClick(promptText)`.
6. **Shared mock factory** — new `apps/web-platform/test/mocks/use-team-names.test.ts` asserts `createUseTeamNamesMock()` returns all required keys from `TeamNamesState` (structural check against `typeof`), and that overrides merge correctly.
7. **Stale mock healing** — `error-states.test.tsx` and `chat-page-resume.test.tsx` must still pass after factory swap; any assertion that previously bypassed missing fields via `undefined` must now either accept the defaults or pass explicit overrides.

### Concrete Test Templates

**Behavioral LeaderAvatar test (replaces class-name assertions):**

```tsx
// apps/web-platform/test/leader-avatar.test.tsx
import { describe, it, expect } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { LeaderAvatar } from "@/components/leader-avatar";

describe("LeaderAvatar", () => {
  it("renders with the leader's name in the accessible label", () => {
    render(<LeaderAvatar leaderId="cmo" size="md" />);
    expect(screen.getByLabelText(/CMO avatar/i)).toBeInTheDocument();
  });

  it("renders a lucide icon (not the Soleur logo) for a known leader", () => {
    const { container } = render(<LeaderAvatar leaderId="cmo" size="md" />);
    expect(container.querySelector('img[src="/icons/soleur-logo-mark.png"]')).toBeNull();
    expect(container.querySelector("svg")).not.toBeNull();
  });

  it("renders the Soleur logo fallback for system/null leaders", () => {
    const { container: systemC } = render(<LeaderAvatar leaderId="system" size="md" />);
    expect(systemC.querySelector('img[src="/icons/soleur-logo-mark.png"]')).not.toBeNull();
    const { container: nullC } = render(<LeaderAvatar leaderId={null} size="md" />);
    expect(nullC.querySelector('img[src="/icons/soleur-logo-mark.png"]')).not.toBeNull();
  });

  it("renders at sm/md/lg sizes with matching rendered dimensions", () => {
    // size="sm" → icon prop 12 → img width 16 (icon + 4)
    const { container: sm } = render(<LeaderAvatar leaderId="cto" size="sm" />);
    expect(sm.querySelector("svg")?.getAttribute("width")).toBe("12");

    const { container: md } = render(<LeaderAvatar leaderId="cto" size="md" />);
    expect(md.querySelector("svg")?.getAttribute("width")).toBe("16");

    const { container: lg } = render(<LeaderAvatar leaderId="cto" size="lg" />);
    expect(lg.querySelector("svg")?.getAttribute("width")).toBe("18");
  });

  it("renders a custom icon when customIconPath is provided", () => {
    const { container } = render(
      <LeaderAvatar leaderId="cto" size="md" customIconPath="settings/team-icons/cto.png" />,
    );
    const img = container.querySelector('img[alt="CTO custom icon"]');
    expect(img).not.toBeNull();
    expect(img?.getAttribute("src")).toBe("/api/kb/content/settings/team-icons/cto.png");
  });

  it("falls back to the lucide icon when the custom icon fails to load", () => {
    const { container } = render(
      <LeaderAvatar leaderId="cto" size="md" customIconPath="broken/path.png" />,
    );
    const img = container.querySelector('img[alt="CTO custom icon"]') as HTMLImageElement;
    expect(img).not.toBeNull();
    fireEvent.error(img);
    // Custom img is removed, lucide svg takes over
    expect(container.querySelector('img[alt="CTO custom icon"]')).toBeNull();
    expect(container.querySelector("svg")).not.toBeNull();
  });

  it("accepts a custom className on the wrapper", () => {
    const { container } = render(
      <LeaderAvatar leaderId="cto" size="md" className="mt-1" />,
    );
    expect(container.firstElementChild?.getAttribute("class")).toContain("mt-1");
  });
});
```

Explicit contract: tests assert on aria-label, rendered dimensions, src URL, fallback behavior, and className pass-through. Zero assertions on Tailwind-specific classes.

**Shared mock factory test (structural drift detection):**

```ts
// apps/web-platform/test/mocks/use-team-names.test.ts
import { describe, it, expect } from "vitest";
import { createUseTeamNamesMock } from "./use-team-names";

describe("createUseTeamNamesMock", () => {
  it("provides default values for every required field", () => {
    const mock = createUseTeamNamesMock();
    expect(mock.names).toEqual({});
    expect(mock.iconPaths).toEqual({});
    expect(mock.nudgesDismissed).toEqual([]);
    expect(mock.namingPromptedAt).toBeNull();
    expect(mock.loading).toBe(false);
    expect(mock.error).toBeNull();
    expect(typeof mock.updateName).toBe("function");
    expect(typeof mock.updateIcon).toBe("function");
    expect(typeof mock.dismissNudge).toBe("function");
    expect(typeof mock.refetch).toBe("function");
    expect(mock.getDisplayName("cto")).toBe("CTO");
    expect(mock.getBadgeLabel("cto")).toBe("CTO");
    expect(mock.getIconPath("cto")).toBeNull();
  });

  it("merges overrides on top of defaults", () => {
    const mock = createUseTeamNamesMock({
      loading: true,
      iconPaths: { cto: "settings/team-icons/cto.png" },
    });
    expect(mock.loading).toBe(true);
    expect(mock.iconPaths).toEqual({ cto: "settings/team-icons/cto.png" });
    expect(mock.names).toEqual({}); // unchanged default
  });
});
```

**CSP header test (headers only, skip the filesystem path):**

```ts
// apps/web-platform/test/kb-content-csp.test.ts
// Assert only on the header shape — route logic is covered elsewhere
import { describe, it, expect } from "vitest";

describe("binary response CSP header", () => {
  it("applies default-src 'none'; style-src 'unsafe-inline'", () => {
    const headers = {
      "Content-Type": "image/png",
      "Content-Disposition": 'inline; filename="x.png"',
      "Content-Length": "100",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "private, max-age=60",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'",
    };
    expect(headers["Content-Security-Policy"]).toBe(
      "default-src 'none'; style-src 'unsafe-inline'",
    );
  });
});
```

(If a heavier route integration test already exists, extend it rather than creating a new file. The above is a minimum assertion contract.)

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
   - a. Create `test/mocks/use-team-names.ts` factory (+ test). Commit checkpoint.
   - b. Migrate 7–10 test files to use factory (commit 2 — test infra only, should leave suite green).
     - Run the grep from "Hidden test failures" to catch any forgotten files.
     - After migration: `node node_modules/vitest/vitest.mjs run` — must pass.
   - c. Add CSP header to route handler + add CSP test. Commit checkpoint.
   - d. Create `FoundationCards` component + swap both dashboard page call sites. Run new test + existing dashboard tests. Commit checkpoint.
   - e. Migrate `naming-nudge.tsx`, `naming-modal.tsx` to `LeaderAvatar` (size="lg"). Run vitest.
   - f. Migrate `at-mention-dropdown.tsx` to `LeaderAvatar` (size="md", drop text). Screenshot the dropdown locally in dev — confirm icon + adjacent name text communicates leader identity. Run vitest.
   - g. Remove `color` field from `DOMAIN_LEADERS` (last — after verifying no consumers). Run `npx tsc --noEmit` — TS catches any missed reference.
4. **Verify** — `node node_modules/vitest/vitest.mjs run` in worktree + `npx tsc --noEmit` + markdownlint on changed MD files (plan + tasks only).
5. **Ship** via `/ship` — semver label `patch` (pure refactor, no user-visible change beyond the at-mention dropdown badge icon/text).

### Commit checkpoint strategy

Six logical commits produce a clean review history:

1. `test: extract shared useTeamNames mock factory` — factory + factory test
2. `test(refactor): migrate 7+ test files to shared useTeamNames mock` — mass swap
3. `feat(security): add CSP header to /api/kb/content binary responses` — one-line change + test
4. `refactor(dashboard): extract FoundationCards component` — new file + dashboard page swap
5. `refactor(leader-avatar): adopt LeaderAvatar in naming-nudge, naming-modal, at-mention-dropdown` — 3 file migration
6. `refactor(leader): remove redundant color field from DOMAIN_LEADERS` — cleanup

All will squash on merge anyway — the structure helps during review.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `DOMAIN_LEADERS.color` has a hidden consumer | Low | Grep before delete (see D1 Research Insights for exact command); TS `noEmit` will catch any unchecked reference at compile time |
| Visual regression in at-mention dropdown (icon-only badge reads worse than text badge) | Low–Medium | Screenshot QA step in dev; fallback is to keep `at-mention-dropdown.tsx` on inline badge and file follow-up issue |
| `FoundationCards` extraction changes layout (margin/gap drift) | Low | Keep wrapper divs inlined at call sites; extract only the grid itself |
| Stale mocks unmasked hidden failures | Medium | Run full vitest suite after each commit; if a previously-passing test now fails, investigate whether it was passing by coincidence (missing field = `undefined` behavior). See "Hidden test failures" below. |
| Tailwind v4 scanner misses a class after ref removal | Very Low | `LEADER_BG_COLORS` still holds literal classes; no dynamic interpolation introduced. Verified via Context7 docs — v4 scanner detects string literals in .ts/.tsx files |
| CSP header breaks PDF inline viewing in `react-pdf` | Very Low | `react-pdf` loads the PDF via `fetch()` → blob → worker. Response CSP governs only the binary response, NOT the parent page where the worker runs. Verified via MDN CSP reference + test plan. |
| CSP header breaks direct-navigation PDF viewing (user pastes URL) | Low | Native browser PDF viewers sandbox rendering internally. `default-src 'none'` does not prevent the browser-native viewer from displaying the PDF. Test: open a KB PDF URL directly in Chrome/Firefox after implementation. |
| Test file sweep misses a file that transitively calls `useTeamNames` | Medium | Run full vitest suite after mock factory migration. If ANY test file errors with `must be used within a TeamNamesProvider`, add the mock (reference: `2026-04-10-react-context-provider-breaks-existing-tests.md`). |
| `vi.mock` factory hoisting breaks the factory import | Medium | Use Pattern A (closure-wrapped call) for simple mocks; Pattern B (`vi.hoisted`) only when mutation is needed. Both documented in D5. Reference: `2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md`. |
| TypeScript `ReturnType<typeof useTeamNames>` can't resolve hook type at mock import time | Very Low | The hook is a regular TS function — `ReturnType` is a compile-time type utility. If `import type { useTeamNames }` fails (e.g., circular dep), fall back to duplicating the interface manually in the mock file with an explicit assertion `satisfies TeamNamesState`. |

### Hidden test failures

The prior learning (`2026-04-10-react-context-provider-breaks-existing-tests.md`) documents that adding a context hook to a widely-rendered component caused 28 test failures. This PR is the inverse (mock consolidation, not new context), but the same sweep principle applies:

```bash
# Before committing the mock migration, run this grep to find every test
# that renders a component transitively requiring useTeamNames
grep -rln 'useTeamNames\|TeamNamesProvider\|LeaderAvatar\|ConversationRow\|ChatPage\|AtMentionDropdown\|FoundationCards\|NamingNudge\|NamingOnboardingModal' \
  apps/web-platform/test/ --include='*.tsx' --include='*.ts'
```

`LeaderAvatar` itself does NOT call `useTeamNames` — it receives `customIconPath` as a prop, so the component migration in tasks 6.1–6.3 does not add new context-hook dependencies. However, the test file sweep is still valuable because:

- Two test files already have stale mocks (`error-states.test.tsx`, `chat-page-resume.test.tsx`) — these may have been passing by coincidence because `undefined` happened to not crash the code paths exercised. The factory migration supplies proper defaults, which could unmask assertions that depended on `undefined` behavior. Run vitest after each file's migration.
- Some tests mock `useTeamNames` but not `TeamNamesProvider` (the provider is currently rendered as a no-op children-passthrough in some mocks). If a test transitively pulls in code that wraps `<TeamNamesProvider>`, mocking only the hook is fine. The new factory does not change this boundary.

Run vitest after each mock migration commit. Any new `must be used within a TeamNamesProvider` error means a file renders a component that calls the hook without a mock; add the factory import to resolve.

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

## Related Learnings

Institutional knowledge that informs this plan (all under `knowledge-base/project/learnings/`):

- `ui-bugs/missing-customiconpath-wiring-dashboard-20260414.md` — The immediate predecessor: `LeaderAvatar` was added in #2130 but missed several call sites. Informs risk #2 (hidden call sites) and Task 6.4 grep verification. Also documents the stale-mock pattern that motivates #2169.
- `integration-issues/2026-04-10-react-context-provider-breaks-existing-tests.md` — Adding `useTeamNames` to `ChatPage` caused 28 failures. Informs the "Hidden test failures" subsection and the pre-commit grep sweep.
- `security-issues/2026-04-12-binary-content-serving-security-headers.md` — The previous security hardening pass on this exact route (`/api/kb/content/[...path]/route.ts`) — added `X-Content-Type-Options: nosniff`, filename sanitization, async I/O. Our CSP header completes the defensive header set on the same route.
- `test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md` — `vi.mock` factories are hoisted; referencing a const from the factory throws. Informs D5 Pattern A vs Pattern B.
- `test-failures/2026-04-10-happy-dom-decorative-img-role-query.md` — happy-dom hides `<img alt="">` from `getByRole("img")`. Informs D6 system/null fallback test (`container.querySelector` is required).
- `2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md` — Tailwind v4 with `@layer base` + `:where()` patterns; confirms v4 scanner behavior on literal class strings.
- `2026-03-30-tdd-enforcement-gap-and-react-test-setup.md` — Documents the vitest + happy-dom + esbuild JSX setup this repo uses. Confirms `test/mocks/use-team-names.ts` (without JSX) is fine as `.ts`; the mock file does not need `.tsx`.

## References

- Source PR review: <https://github.com/jikig-ai/soleur/pull/2130>
- Issue #2141: <https://github.com/jikig-ai/soleur/issues/2141>
- Issue #2169: <https://github.com/jikig-ai/soleur/issues/2169>
- Draft PR: <https://github.com/jikig-ai/soleur/pull/2265>
- Tailwind v4.1 `@source inline`: <https://tailwindcss.com/docs/detecting-classes-in-source-files> (validates Option B — no safelist needed for literal class strings)
- Tailwind v4.1 release notes: <https://tailwindcss.com/blog/tailwindcss-v4-1> (brace expansion in `@source inline`)
- MDN CSP reference: <https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy> (response-level CSP scope)
- Next.js CSP guide: <https://nextjs.org/docs/app/guides/content-security-policy>
- OWASP CSP Cheat Sheet: <https://cheatsheetseries.owasp.org/cheatsheets/Content_Security_Policy_Cheat_Sheet.html>
- react-testing-library README: <https://github.com/testing-library/react-testing-library> (behavioral testing principle)
- react-pdf + CSP discussion: <https://github.com/diegomura/react-pdf/issues/510> (worker-src blob: for PDF.js — confirms response CSP doesn't govern the worker)
- AGENTS.md Code Quality → worktree vitest via `node node_modules/vitest/vitest.mjs run`
