---
title: "feat: nav-rail position resume — last-open file/conversation + KB tree state"
type: feat
date: 2026-07-16
status: ready
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
issue: 4826
pr: 6542
parent_issue: 4813
parent_adr: ADR-047
wireframes: knowledge-base/product/design/navigation/nav-rail-position-resume.pen
related:
  - knowledge-base/project/plans/2026-06-02-feat-single-nav-rail-drill-in-plan.md
  - knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md
---

# Plan: Nav-rail position resume (#4826)

## Enhancement Summary

**Deepened on:** 2026-07-16  
**Sections enhanced:** Proposed Solution, Implementation Phases, Risks, Acceptance Criteria, Technical Considerations  
**Research agents / lenses used:** deepen-plan gates 4.6–4.9, precedent-diff (`safeSession` / scroll instrumentation), Context7 Next.js App Router `router.replace` docs, negative-claim verify, learnings filter (nav/sessionStorage/hydration)

### Key Improvements

1. **Chat resume must wait for `workspaceId`** before reading keys — avoid writing/reading under a null workspace (race with `useActiveRepo`).
2. **Validate stored KB path / chat id shape** on read (no `..`, no `//`, UUID for chat) — mirror `safeReturnTo` guards; never interpolate raw sessionStorage into `href`.
3. **Chat client resume pattern** confirmed: Next.js App Router uses `useRouter().replace` inside `useEffect` (+ optional `startTransition`); show a minimal "Opening…" shell to avoid blank flash.
4. **Expanded-set seed is one-shot** — don't re-apply session expanded on every pathname change or user collapses fight the restore.
5. **Gates passed:** User-Brand Impact filled; Observability 5-field schema; no PAT shapes; `.pen` artifact on disk (commit with plan).

### New Considerations Discovered

- Server `redirect()` in `chat/page.tsx` **cannot** be sessionStorage-aware — conversion to client is mandatory, not optional polish.
- `conversationId` is UUID-shaped in server tools (`z.string().uuid()`) — resume validator should require UUID, not arbitrary strings.
- Prior #4826 infra PRs must not close this product issue; PR body language: `Closes #4826` only after product ACs land.
- Settings deferral filed as **#6543**.

---

## Overview

Implement the deferred **RQ4** from the single-nav-rail work (#4813 / ADR-047): when an operator leaves a drilled section and re-enters it, restore the **last-open item** for that section and the **KB tree expansion + scroll** so they do not lose their place mid-task.

**In scope (issue body only — product nav-rail scope):**

1. **KB last-open file path** — re-entry from section-root nav lands on the last `/dashboard/kb/...` doc (today main nav always goes to `/dashboard/kb`).
2. **Chat last conversation id** — bare `/dashboard/chat` re-entry lands on the last real conversation (today `chat/page.tsx` always `redirect`s to `/dashboard/chat/new`).
3. **KB tree expansion set + scrollTop** — persist and restore on section re-mount (main residual loss; file path is already partially preserved by URL when the user *stays* on the doc route).

**Explicitly out of scope:**

- Unrelated #4826 *issue-number reuse* for worktree/concierge infra (PRs #6071, #6108, #6115, etc.) — ignore; product scope only.
- Settings last-tab stickiness (not named in the issue body).
- localStorage / cross-tab persistence (sessionStorage only, per issue).
- Persisting document *content* or SWR cache to sessionStorage (ADR-067 forbids content persistence; this feature stores **chrome paths/ids/scroll only**).
- Changing ADR-047 portal/band/collapse architecture.

## Premise Validation

| Claim | Check | Result |
|---|---|---|
| Issue #4826 open product work | `gh issue view 4826` → `OPEN`, title nav-rail position resume | Holds |
| `closedByPullRequestsReferences` #6071/#6115 | Those PRs are worktree/concierge infra that **reused the issue number**; issue body still describes RQ4 product scope | **Stale references — ignore**; plan product scope only (operator instruction) |
| Parent deferred RQ4 | ADR-047 Consequences + plan `2026-06-02-feat-single-nav-rail…` RQ4 cut to #4826 | Holds |
| `use-kb-layout-state` ancestor auto-expand | `hooks/use-kb-layout-state.tsx:162-184` | Holds — file path from URL already expands ancestors |
| sessionStorage helper exists | `lib/safe-session.ts` | Holds — reuse, do not re-invent try/catch |
| Chat bare index always `/new` | `app/(dashboard)/dashboard/chat/page.tsx` server `redirect("/dashboard/chat/new")` | Holds — main conversation stickiness loss |
| Main KB nav href is section root | `nav-items.ts` → `/dashboard/kb` | Holds — main last-file loss on re-entry |
| Mechanism vs ADR | ADR-067 rejects sessionStorage for **SWR content**; chrome path/scroll is a different surface (already used for `kb.chat.sidebarOpen`, drafts, banners) | Holds — not an ADR-rejected mechanism |

**Premise Validation note:** Product premise is live and unshipped. Infra PRs that closed-by-reference #4826 did **not** implement position resume. No external research required — codebase patterns (`safeSession`, `useRailWidth` hydrate-after-mount, pathname-driven drill) are sufficient.

## Research Reconciliation — Spec vs. Codebase

| Issue / parent claim | Codebase reality | Plan response |
|---|---|---|
| "KB file path already preserved by URL" | True **only while the URL remains the file**. Section re-entry via main nav uses hardcoded `/dashboard/kb` | Persist path + rewrite **section-root** entry to last path |
| "Main loss is scroll + last-conversation" | Confirmed: `expanded` is in-memory `useState` (lost on unmount when leaving KB segment); chat index always `/new` | Expand+scroll persistence + chat resume |
| Position resume "fights key-by-segment" | Parent concern: sticky context across sections | Mitigate: resume **only** on section-root entry; deep links / `+ New` / palette / inbox win; workspace-keyed keys |
| Chat is a primary nav item | Chat is **not** in `NAV_ITEMS` (entry via dashboard cards, inbox, CRM, banners, palette) | Resume hook at bare `/dashboard/chat` + any client entry that targets section root |
| sessionStorage alone | Per-tab; survives SPA nav; cleared on tab close | Match issue; no localStorage |

## Problem Statement / Motivation

Single-nav-rail deliberately cut sticky resume to keep the brand-critical PR small. Accepted interim: section re-entry lands at root. Operators mid-task (deep KB file + tree position, or a running Concierge conversation) lose place every time they Back-to-menu and re-enter. This PR closes that friction without reopening ADR-047 invariants.

## Proposed Solution

### Storage contract (sessionStorage via `safeSession`)

Workspace-scoped keys (workspace id from `useActiveRepo().data?.workspaceId`):

| Key | Value | Written when | Read when |
|---|---|---|---|
| `soleur:nav.resume.<ws>.kb.path` | relative path after `/dashboard/kb/` (decoded), or empty clear | pathname is a KB doc view (`isKbDocView`) | Building KB section-root entry href; optional client redirect if landed on bare `/dashboard/kb` with a stored path |
| `soleur:nav.resume.<ws>.kb.expanded` | JSON array of expanded dir paths | `toggleExpanded` / merge after ancestor auto-expand | KB layout mount — seed `expanded` Set (union with ancestors of current path) |
| `soleur:nav.resume.<ws>.kb.scrollTop` | integer string | rAF-throttled scroll on tree scrollport | After tree paint, once |
| `soleur:nav.resume.<ws>.chat.id` | conversation UUID (never `"new"`) | pathname `/dashboard/chat/<uuid>` | Bare `/dashboard/chat` entry |

**Rules:**

1. **No write / no sticky href** when `workspaceId` is null (wait for active-repo settle; default to section root until known).
2. **Never write** chat id `"new"`.
3. **Never redirect** away from explicit deep links (`/dashboard/chat/<id>`, `/dashboard/kb/...`, `/dashboard/chat/new`, palette, inbox).
4. **Stale fail-closed:** chat id not found / 404 → clear key, land `/dashboard/chat/new`. KB path 404 → existing error UI; clear path key on confirmed not-found so next entry is root.
5. **Corrupt JSON / non-numeric scroll** → ignore, behave as no resume.
6. All access through `safeSession` (SSR-safe, swallows quota/SecurityError).
7. **Sanitize on read (deepen):** reject stored paths containing `..`, `//`, `\\`, or not matching `^[A-Za-z0-9._/-]+$` (relative under `/dashboard/kb/`). Reject chat ids that fail UUID shape (`/^[0-9a-f-]{36}$/i` or project’s existing UUID helper). Never trust raw sessionStorage as an href fragment.
8. **Expanded seed is once per KB segment mount** (ref latch) so later user collapses are not overwritten by re-reads.

### Module shape

New pure helpers (testable without React):

- `apps/web-platform/lib/nav-resume.ts`
  - `resumeKey(workspaceId, segment, field)`
  - `parseExpanded(raw) → string[]`
  - `isResumeableConversationId(id) → boolean` (reject `new`, empty; UUID-ish or at least non-`new`)
  - `kbPathFromPathname(pathname) → string | null`
  - `chatIdFromPathname(pathname) → string | null`

New hook:

- `apps/web-platform/hooks/use-nav-resume.ts`
  - Depends on `usePathname` + `useActiveRepo`
  - Effects: persist path/id on pathname change; expose `getKbEntryHref()`, `getChatEntryHref()`, `readExpanded()`, `writeExpanded()`, `readScrollTop()`, `writeScrollTop()`, `clearKbPath()`, `clearChatId()`

### Integration points

1. **Persist + expand seed — `use-kb-layout-state.tsx`**
   - On mount (client): seed `expanded` from session union pathname ancestors.
   - On `toggleExpanded`: persist next set.
   - On `isKbDocView` pathname: write `kb.path`.
   - Keep existing ancestor auto-expand effect (union, never shrink ancestors of open file).

2. **Scroll — `kb-sidebar-shell.tsx`**
   - Ref on `div.flex-1.overflow-y-auto` (`data-testid="kb-tree-scrollport"`).
   - `onScroll` → throttled `writeScrollTop`.
   - Restore once when tree content height allows (`requestAnimationFrame` ×2 or after `!loading && hasTree`).

3. **KB section-root entry — layout / nav href**
   - Primary: make the Knowledge Base `Link` href dynamic via a small client wrapper or resolve in the existing client `DashboardLayout` map: `href = getKbEntryHref() ?? "/dashboard/kb"`.
   - Defense-in-depth: if user lands on exact `/dashboard/kb` with a stored path (e.g. bookmark, external link still section root), **do not** auto-redirect from the landing itself unless the navigation intent was "section entry from main nav". Prefer **href rewrite** so bookmarks to `/dashboard/kb` still mean landing. (Explicit product choice: bookmarks stay root; main-nav re-entry uses sticky href.)

4. **Chat section-root entry — `chat/page.tsx`**
   - Server `redirect("/dashboard/chat/new")` cannot read sessionStorage (**verified:** file is a pure server redirect stub today).
   - Replace with a **`"use client"`** resume page:
     - Wait until `useActiveRepo` yields `workspaceId` (or times out → treat as no resume).
     - Read last id via sanitized helper; if valid UUID → `React.startTransition(() => router.replace(\`/dashboard/chat/${id}\`))` (Next.js App Router pattern from Context7 / `redirect-boundary.tsx`).
     - Else → `router.replace("/dashboard/chat/new")`.
     - Render a short “Opening conversation…” shell (not `null`) so layout + rail paint without a blank main pane.
   - **Do not** leave a residual server `redirect("/new")` that races the client (would wipe sticky intent on every bare hit).

5. **Stale chat validation**
   - After rail `useConversations` settles: if active id is resume-sourced and missing from list **and** not loading, clear + soft-replace to `/new` (coordinate with conversations-rail or chat page). Prefer validation at resume time via a lightweight HEAD/GET if list is empty-loading — simplest: resume optimistically; ChatSurface / route already handles missing conversation; on definitive not-found clear key.

6. **Settings:** no change.

### UX / wireframes

Wireframes (behavior-only; no new chrome):  
`knowledge-base/product/design/navigation/nav-rail-position-resume.pen`

- Frame 01: KB re-entry before/after  
- Frame 02: Chat re-entry before/after  
- Frame 03: expansion + scroll  
- Frame 04: fail-closed workspace + stale + explicit-intent  

Aesthetic direction: existing Soleur dark chrome, gold active row — no new visual components.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| localStorage | Cross-tab + longer-lived; issue mandates sessionStorage; higher stale risk |
| Always-mounted section keep-alive (hidden DOM) | Fights ADR-047 portal swap; double Realtime; heavier |
| URL query `?resume=1` | Noisy; breaks shareable URLs |
| Server-side last-path in user prefs | Overkill for tab-session chrome; GDPR surface |

**Deferred:** Settings last-tab resume → tracking issue **#6543**.

## Technical Considerations

- **Architecture:** No ADR change. Amends *usage* of ADR-047 cut-list only; optional one-line ADR-047 "Superseded for RQ4 by #4826" note in Consequences is **not** required (follow-up complete, not decision change). Skip `## Architecture Decision` production.
- **C4:** No new actors/systems/relationships — chrome-only client state. Checked `model.c4` / `views.c4` / `spec.c4` impact: none (no external system, no container change). "No C4 impact" with enumeration: human operator already modeled; no vendor; web-platform container unchanged; access relationships unchanged.
- **Performance:** scroll handler rAF-coalesced; expanded set JSON ≤ few KB.
- **Security:** paths/ids only — no document body, no tokens. Workspace-key prevents cross-tenant resume in multi-workspace tabs.
- **SSR:** never read sessionStorage during SSR; hydrate after mount (same as `useSidebarCollapse` / `kb.chat.sidebarOpen`).
- **NFR:** usability (task resumption); no availability/security NFR change.

## User-Brand Impact

**If this lands broken, the user experiences:** re-entering Knowledge Base or Chat lands on the wrong document/conversation (or loops), so they act on the wrong thread mid-task; or a flash of wrong content before correct route.

**If this leaks, the user's data/workflow is exposed via:** sessionStorage in the same browser profile could reveal last file path / conversation id to a co-user of the same OS account/tab session — **tab-local chrome metadata only**, not message bodies. No new server leak surface.

**Brand-survival threshold:** `aggregate pattern`  
(Not single-user-incident: wrong restore is recoverable friction; workspace-keyed keys + fail-closed avoid the tenant-action class that made #4813 single-user. Cross-workspace restore bug would elevate — tests must lock that.)

Sharp edge: empty / TBD User-Brand Impact fails deepen-plan Phase 4.6 — filled above.

## Implementation Phases

### Phase 0 — Preconditions

- [ ] Confirm `safeSession` contract (`test/safe-session.test.ts`).
- [ ] Confirm `isKbDocView` / `segmentToDrillLevel` exports.
- [ ] Confirm chat index is only a redirect stub.
- [ ] Confirm scrollport is `kb-sidebar-shell.tsx` `overflow-y-auto` div.
- [ ] Confirm vitest discovery: `test/**/*.test.ts(x)` under `apps/web-platform`.
- [ ] Typecheck command: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (not `npm run -w`).

### Phase 1 — Pure module + unit tests (RED → GREEN)

- [ ] Add `lib/nav-resume.ts` + `test/nav-resume.test.ts` (happy-dom not required for pure functions).
- [ ] Cover: key shape, path/id extraction, reject `new`, parseExpanded corrupt, workspace required.

### Phase 2 — Hook `use-nav-resume` + wiring persist

- [ ] Implement hook with `useActiveRepo` + pathname effects.
- [ ] Wire persist into `use-kb-layout-state` (path + expanded).
- [ ] Wire chat id persist from chat layout client boundary or conversations rail / chat page (any mount under `/dashboard/chat/*` except `new`).

### Phase 3 — Restore paths

- [ ] Dynamic KB main-nav href in `(dashboard)/layout.tsx` (client already).
- [ ] Convert `chat/page.tsx` to client resume.
- [ ] Scroll restore in `kb-sidebar-shell.tsx`.
- [ ] Expanded seed in `use-kb-layout-state`.

### Phase 4 — Fail-closed + stale

- [ ] Clear chat key on not-found / missing from list after load.
- [ ] Clear KB path key on tree/doc not-found when appropriate.
- [ ] Tests for workspace A vs B key isolation.

### Phase 5 — Tests + typecheck

- [ ] Component/hook tests: `test/nav-resume-hook.test.tsx`, extend `kb-layout-panels` / `nav-rail-drill` as needed.
- [ ] Scroll restore test with instrumented `scrollTop` (mirror `debug-stream-panel-autoscroll.test.tsx`).
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/nav-resume*.test.ts* test/safe-session.test.ts …`
- [ ] `tsc --noEmit`.

### Phase 6 — Docs / issue hygiene

- [ ] PR body: `Closes #4826` (product scope). State clearly that prior infra PRs that referenced #4826 did not implement this.
- [ ] Optional note in ADR-047 related list if needed — no Decision rewrite.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/lib/nav-resume.ts` | Pure key/path helpers |
| `apps/web-platform/hooks/use-nav-resume.ts` | Persist/restore API |
| `apps/web-platform/test/nav-resume.test.ts` | Pure unit tests |
| `apps/web-platform/test/nav-resume-hook.test.tsx` | Hook + sessionStorage behavior |
| `apps/web-platform/test/kb-tree-scroll-resume.test.tsx` | Scroll restore (instrumented scrollTop) |
| `knowledge-base/product/design/navigation/nav-rail-position-resume.pen` | Wireframes (done at plan) |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/hooks/use-kb-layout-state.tsx` | Seed/persist expanded; persist kb path |
| `apps/web-platform/components/kb/kb-sidebar-shell.tsx` | Scrollport ref, persist/restore scrollTop |
| `apps/web-platform/app/(dashboard)/dashboard/chat/page.tsx` | Client resume instead of hard `/new` only |
| `apps/web-platform/app/(dashboard)/layout.tsx` | Dynamic KB (and any bare-chat) entry hrefs from resume |
| `apps/web-platform/test/nav-rail-drill.test.tsx` (if needed) | Assert section-root href can be sticky |
| `apps/web-platform/test/kb-layout-panels.test.tsx` (if needed) | Expanded seed from session |

**Not edited:** settings shell, ADR-047 decision body (unless one-line related-issue note), server resolvers, SWR config.

## Open Code-Review Overlap

- **#2193** `refactor(billing): unify past_due…` mentions `layout.tsx` — **Acknowledge**: billing banner extraction, orthogonal to nav resume; do not fold.

No other open code-review issues touch planned paths.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — KB path persist:** Opening `/dashboard/kb/foo/bar.md` writes `soleur:nav.resume.<ws>.kb.path` = `foo/bar.md` (via `safeSession`).
- [ ] **AC2 — KB re-entry:** After visiting a KB doc, the main-nav Knowledge Base link `href` is `/dashboard/kb/foo/bar.md` (not bare `/dashboard/kb`).
- [ ] **AC3 — KB bookmark root:** Direct navigation to `/dashboard/kb` still shows landing (no forced redirect from bookmark).
- [ ] **AC4 — Expanded restore:** Expand dirs, leave KB, re-enter — previously expanded dirs are expanded (union with ancestors of open file).
- [ ] **AC5 — Scroll restore:** With instrumented scrollport, saved `scrollTop` is reapplied once after tree mount.
- [ ] **AC6 — Chat persist:** Visiting `/dashboard/chat/<uuid>` stores that uuid; never stores `new`.
- [ ] **AC7 — Chat re-entry:** Client mount of bare `/dashboard/chat` replaces to last uuid when present.
- [ ] **AC8 — Explicit new wins:** `/dashboard/chat/new` and `+ New` never redirect to last id.
- [ ] **AC9 — Workspace isolation:** Keys for workspace A are not read when `useActiveRepo` reports workspace B.
- [ ] **AC10 — Stale chat fail-closed:** Invalid/missing conversation clears key and lands on `/new` (no infinite replace loop).
- [ ] **AC11 — SSR/private mode:** No throw when sessionStorage unavailable; feature degrades to today's root entry.
- [ ] **AC12 — Typecheck + unit tests green:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and vitest on new/edited suites pass.
- [ ] **AC13 — No content persistence:** Grep shows resume module stores only path/id/expanded/scrollTop — no message bodies or tree JSON dumps.
- [ ] **AC14 — Sanitized reads:** Stored path with `..` or chat id `new`/non-UUID yields section root / `/new` and does not set a dangerous href.
- [ ] **AC15 — workspaceId gate:** Sticky href remains `/dashboard/kb` (root) until workspaceId resolves; no write under null workspace.

### Post-merge (operator)

None — pure client feature; no infra, no Doppler, no migration.

## Test Scenarios

- Given workspace W and doc path P open, when operator goes Back → main → KB, then `location` is `/dashboard/kb/P` and tree ancestors expanded.
- Given conversation C open, when operator navigates to bare `/dashboard/chat`, then they land on C.
- Given last id C deleted, when re-entering chat, then `/dashboard/chat/new` and key cleared.
- Given workspace switch A→B (hard nav), when opening chat on B, then A's conversation is not restored.
- Given sessionStorage throws, when using KB/Chat, then app behaves as pre-#4826 (no crash).
- Given scrollTop=400 saved, when remounting tree with instrumented element, then `scrollTop === 400` after restore effect.

## Observability

```yaml
liveness_signal:
  what: "Client-only chrome feature; no server heartbeat. Regression surface = unit/component tests in CI on apps/web-platform vitest job"
  cadence: "per-PR CI"
  alert_target: "CI failure on web-platform test job / PR checks"
  configured_in: ".github/workflows/ (existing web-platform test path filters)"

error_reporting:
  destination: "No new Sentry ops required for happy path. Optional: reportSilentFallback only if a resume redirect loops (should be impossible with replace+clear)"
  fail_loud: "User lands on section root or /chat/new (fail-closed) — never a blank screen"

failure_modes:
  - mode: "Corrupt sessionStorage JSON for expanded"
    detection: "parseExpanded returns []; unit test AC"
    alert_route: "none (degrades silently)"
  - mode: "Cross-workspace key collision"
    detection: "Unit test AC9; key includes workspaceId"
    alert_route: "CI fail"
  - mode: "Chat replace loop on stale id"
    detection: "clearChatId before replace to /new; test AC10"
    alert_route: "CI fail"

logs:
  where: "No production logs required; browser sessionStorage only"
  retention: "tab session"

discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/nav-resume.test.ts test/nav-resume-hook.test.tsx test/kb-tree-scroll-resume.test.tsx"
  expected_output: "all tests passed"
```

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override: edits `components/**/*.tsx`, `app/**/layout.tsx`, `app/**/page.tsx`)  
**Decision:** reviewed (pipeline / headless auto-accept on wireframes)  
**Agents invoked:** plan-orchestrator UX assessment + wireframe artifact (pencil MCP `.pen` write; CLI auth unavailable, file authored as structured wireframe JSON matching repo `.pen` schema)  
**Skipped specialists:** copywriter (no new marketing/persuasive copy); CPO formal spawn (threshold aggregate pattern, no single-user sign-off) — product assessment inline below  
**Pencil available:** yes (artifact on disk; Desktop AppImage unstable in this environment — file committed as source of truth)

#### Findings

- **No new interactive chrome** — restore is invisible when correct; failure mode is land-on-root (acceptable interim today).
- **Explicit intent must win** — deep links and `+ New` are non-negotiable (Frame 04).
- **Workspace keying** is the brand-adjacent invariant (avoid wrong-thread after switch).
- **Settings** deliberately out of issue scope; do not expand.
- Spec-flow: entry points = main nav KB, bare `/dashboard/chat`, optional future palette "Knowledge Base"; exit = correct doc/conversation or fail-closed root; dead-end risk = replace loop (mitigated AC10).

## Research Insights

### Local patterns (precedent-diff)

| Concern | Precedent | Plan adoption |
|---|---|---|
| sessionStorage wrapper | `lib/safe-session.ts` + `test/safe-session.test.ts` | All resume I/O via `safeSession` — **do not** add new try/catch blocks |
| Hydrate after mount | `useSidebarCollapse`, `useRailWidth`, `kb.chat.sidebarOpen` | Same: default root → effect hydrates sticky href |
| scrollTop in tests | `debug-stream-panel-autoscroll.test.tsx` `Object.defineProperty` | Copy instrument helper for tree scrollport |
| Path safety | `lib/safe-return-to.ts` (`..` / `//` / leading `/`) | Adapt relative-path variant for KB segments |
| `"new"` conversation sentinel | `chat-surface.tsx`, `ws-client.ts` | Never persist `"new"`; UUID-only store |
| Drill literals | `nav-drill-authority.test.ts` | Reuse `isKbDocView` / `segmentToDrillLevel` only |

### Learnings applied

- Alignment/toggle both states: N/A (no new toggle chrome).
- Proxy vs invariant: AC asserts **href/path/scrollTop values**, not merely that sessionStorage was written.
- Named artifact verification: paths grepped on worktree before plan write.
- Issue #4826 number pollution: product vs infra — called out in premise + PR body.
- Precedent search must include `lib/` helpers (`2026-05-04-plan-precedent-search-must-include-lib-helpers`) — found `safeSession` + `safeReturnTo`.

### Framework docs (Context7 `/vercel/next.js`)

- Client resume: `useRouter` + `useEffect` + `router.replace` (optionally inside `React.startTransition`) is the App Router-supported pattern (same as internal `HandleRedirect`).
- Prefer **`replace`** over **`push`** so Back does not re-hit the resume stub in a loop.

### External research

**Minimal** — Context7 for Next.js navigation only; industry scroll-restore patterns deferred to local debug-stream precedent (happy-dom limitation is repo-specific).

### Community discovery / functional overlap

- Stack: TypeScript/Next — covered by built-ins.
- Functional discovery: no community skill for app-specific nav resume; skip install.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Cross-workspace wrong conversation | Workspace-scoped keys; tests AC9 |
| Replace loop on `/dashboard/chat` | Clear key before navigating to `/new`; only resume once per mount |
| Bookmark to `/dashboard/kb` hijacked | Prefer sticky **href** on main nav, not unconditional redirect on landing |
| Expanded set grows unbounded | Cap list length (e.g. 200 dirs) or prune paths not under tree root on write |
| happy-dom scrollTop inert | Instrument like debug-stream tests |
| Fighting "key-by-segment" stale context | Resume only section-root entry; content routes always authoritative |
| XSS / open-path via poisoned sessionStorage | Sanitize path/id on every read (Rule 7); never assign unvalidated strings to `href` |
| Expanded re-seed fights user collapses | One-shot seed latch per mount (Rule 8) |
| Chat flash / double navigation | `replace` not `push`; wait for workspaceId; single effect with cleared deps |
| Race: active-repo null then switches | No write under null; key only after first non-null workspaceId |

## Success Metrics

- Operators re-entering KB/Chat mid-task land on prior item without manual re-navigation (manual dogfood on PR preview).
- Zero new Sentry noise from resume module.
- Unit/component suite green in CI.

## Dependencies

- Shipped single nav rail (#4813 / ADR-047).
- `useActiveRepo` for workspace id.
- `safeSession`.

## Non-Goals

- Persisting settings tab.
- Cross-tab (localStorage) resume.
- Restoring chat **message scroll** inside ChatSurface.
- Restoring collapsed/expanded **unified rail** width (already `useRailWidth` localStorage).

## MVP pseudo-shape

```ts
// apps/web-platform/lib/nav-resume.ts
export function resumeKey(ws: string, seg: "kb" | "chat", field: string) {
  return `soleur:nav.resume.${ws}.${seg}.${field}`;
}
export function kbPathFromPathname(pathname: string): string | null { /* isKbDocView slice */ }
export function chatIdFromPathname(pathname: string): string | null { /* reject new */ }
export function parseExpanded(raw: string | null): string[] { /* JSON array or [] */ }
```

```tsx
// chat/page.tsx (client)
useEffect(() => {
  const id = readLastChatId(workspaceId);
  router.replace(id ? `/dashboard/chat/${id}` : "/dashboard/chat/new");
}, [workspaceId]);
```

## References

- Issue: https://github.com/jikig-ai/soleur/issues/4826
- Parent: #4813, plan `knowledge-base/project/plans/2026-06-02-feat-single-nav-rail-drill-in-plan.md`
- ADR-047: `knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md`
- Wireframes: `knowledge-base/product/design/navigation/nav-rail-position-resume.pen`
- WIP PR: #6542

## Scoped Advisor Consult (Step 4.5)

Highest-leverage risks reviewed in-session (fable/opus Task spawn unavailable in this harness — inline consult):

1. **Server redirect cannot read sessionStorage** → client resume page is load-bearing; do not leave server `redirect("/new")` as the only path.
2. **Bookmark vs sticky nav** → sticky **href** not forced landing redirect (AC3).
3. **Workspace keying** is non-optional despite "sessionStorage tab isolation" — multi-workspace same tab after hard switch reuses tab storage.

## Plan Review (mechanical apply)

Self-panel (DHH / Kieran / simplicity / spec-flow) — mechanical findings applied in this draft:

- **YAGNI:** Settings out; no localStorage; no content cache.
- **Correctness:** Client chat resume; workspace keys; clear-before-replace; no resume of `new`.
- **Simplicity:** One `lib/nav-resume` + one hook; reuse `safeSession`.
- **Flow:** Explicit-intent entry points enumerated; fail-closed paths named.

Taste / user-challenge: none requiring operator decision beyond issue body scope (Settings deferred).

---

*Spec lacks prior `lane:` in branch spec.md — set `lane: single-domain` (client web-platform only).*
