---
title: Workstream tab — Linear-style kanban board + issue detail with human-in-the-loop Concierge panel
type: feat
date: 2026-06-26
lane: cross-domain
brand_survival_threshold: none
---

# Workstream tab — Linear-style kanban board + issue detail with Concierge "Decision Making" panel

> Spec lacks valid `lane:` (no `knowledge-base/project/specs/feat-one-shot-workstream-kanban-tab/spec.md`) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-26
**Sections enhanced:** Overview, Technical Considerations, Phase 1/3, Acceptance Criteria, Deferred Work, + new Research Insights
**Review agents used:** code-simplicity-reviewer, architecture-strategist, agent-native-reviewer, Explore (codebase patterns); upstream Phase-2.5: cpo, spec-flow-analyzer, ux-design-lead

### Key Improvements
1. **Read/context parity now ships in v1.** agent-native-reviewer caught that "read-only board" left the board *invisible to agents*. Added a `workstream_issues_list` read tool (~20 LoC over a shared accessor, mirrors the shipped `routines_list`) so an agent can see what the user sees. Only *write* parity is deferred.
2. **The seam is the shared accessor, not the HTTP route.** `server/workstream/seed-issues.ts` exposes a pure `getWorkstreamIssues()` that BOTH the route handler AND the read tool import directly (no HTTP self-call) — the routines "same shared fn, no duplicated query" rule.
3. **Architecture P2 fixes:** Sheet uses `router.push` (Back closes the Sheet, per inbox precedent); the role→color map lives in `lib/workstream.ts` (avoids a `lib → components` layering inversion that would pull `components/` into the node unit-test graph).
4. **Concrete patterns pinned** (Sheet props, inbox error/empty/loading hierarchy + `ErrorCard` retry, `SwrTestProvider`, chat deep-link target) — see Research Insights.

### New Considerations Discovered
- code-simplicity-reviewer argued for a fully read-only board (cut New Issue) and dropping the HTTP route. **Resolved:** keep New Issue (user explicitly specified the button) and the wired-disabled Concierge window (user explicitly asked to "build the conversation UI window, wired and ready"); keep the route (matches the shipped routines precedent + is the read tool's HTTP twin over the same accessor). Recorded as a deliberate disagreement.
- Deferral compliance: tracking issues are split **read-shipped / write-deferred** with ready-to-run `gh issue create` commands; filing is gated to ship/work phase (issue creation is blocked in this planning-only phase) per `wg-when-deferring-a-capability-create-a`.

## Overview

Add a new **Workstream** tab to the web-platform dashboard: a Linear-style kanban board for following the project's tasks/issues, plus a per-issue detail view that includes a human-in-the-loop **"Decision Making"** Concierge conversation panel.

- **Board:** 7 columns — Backlog, Todo, In Progress, In Review, Blocked, Done, Cancelled — each with a per-column count badge. A top bar carries a "Search issues…" field and a gold "New Issue" button.
- **Cards:** issue ID (e.g. `SOLAA-198`), title, a priority indicator (colored dot), an assignee chip with role initials (CTO/COO/CMO/…), and a green **"Live"** badge on active/in-progress items.
- **Detail (right slide-in Sheet):** description + Status, Assignee, Priority, Created, Updated. A clearly-separated **"Decision Making"** section renders a Concierge conversation window — built **wired and ready** but shown in a **visibly offline/preview** state in v1 (the live conversation backend is non-functional), paired with a working **"Discuss in Chat"** deep-link to the existing live chat so the human-in-the-loop path is real, not a dead end.

**Deliberate v1 simplifications (per "keep it simple — do not overdo it"):**
1. **Seed-backed, read-only data.** Issues come from an in-repo seed module served via `GET /api/workstream/issues`. No Supabase table, no migration, no operator/live-verify burden.
2. **In-session, optimistic mutations.** "New Issue" and status changes update the SWR client cache optimistically and are **not persisted across reload** — surfaced honestly with a visible "Preview — changes aren't saved yet" notice (never silent loss).
3. **No drag-and-drop.** Status changes happen via a select in the detail Sheet (no new dnd dependency).
4. **Concierge composer is wired but disabled** behind a single `CONCIERGE_ONLINE = false` flag, so going live later is a one-flag-flip + websocket connection.

Design reference: user-provided kanban screenshot + committed wireframes at `knowledge-base/product/design/workstream/workstream-kanban.pen` (screenshots in `screenshots/`).

## Problem Statement / Motivation

The dashboard has Chat, Inbox, KB, Routines — but no single surface to **see the project's work** at a glance. A kanban board makes the agent organization's work visible (the L4 North Star "interactive command center"), and the per-issue Concierge panel is the strategically important human-in-the-loop affordance: a place to converse about a specific decision. Shipping the board surface now (honestly labeled Preview) establishes the UI and the read API seam; real persistence, GitHub-backing, and agent write-parity are tracked follow-ups (see Deferred Work).

## Proposed Solution

A new server-component page renders a client board that fetches from a session-gated read-only API backed by an in-repo seed. Cards open a URL-driven detail Sheet (`?issue=<id>`) so reload/deep-link re-open the same issue. The Sheet embeds the offline-but-wired Concierge panel and a live "Discuss in Chat" deep-link. Nav + ⌘K palette pick the tab up automatically from the shared `NAV_ITEMS` registry.

## Research Reconciliation — Spec vs. Codebase / Advisory

| Claim / assumption | Reality (verified) | Plan response |
|---|---|---|
| "Add a new tab" needs a registry edit | `NAV_ITEMS` in `components/command-palette/nav-items.ts` is the single source of truth; sidebar **and** ⌘K palette both read it (`app/(dashboard)/layout.tsx`, `components/command-palette/use-shortcuts.tsx`). Icons are local fns in `layout.tsx` keyed by href via `NAV_ICONS` (line 104). | Add one `NAV_ITEMS` entry + one new local icon fn + one `NAV_ICONS` entry. Palette auto-syncs (no separate registration). |
| "Issues table exists" | **No** `issues`/`tasks`/`tickets`/`workstream` table in `apps/web-platform/supabase/migrations/` (verified through mig 113). | v1 ships seed-backed (no migration). Persistence deferred + tracked. |
| Concierge backend is non-functional (user) vs. chat runtime is live (CPO) | Chat/agent runtime (`server/agent-runner.ts`, `components/chat/chat-surface.tsx`, `lib/ws-client.ts`) **is** live; the per-issue Concierge conversation is what's not wired. | Build the in-issue panel UI wired+disabled (offline), AND deep-link to the **existing live chat** for a real HITL path (honors user's ask + CPO honesty mandate). |
| CPO: back board with **real GitHub issues** (read tools exist: `server/github-read-tools.ts`) instead of a fake seed | True — a real read path exists. But GitHub issues don't map cleanly to Linear-style columns/`SOLAA-` IDs/role-initial assignees, and require a connected repo (empty board for many users) → a mapping layer = "overdoing it" for v1. | **Documented decision:** v1 uses seed behind a pure `getWorkstreamIssues()` accessor (the single swap point — imported by both the route and the read tool); GitHub-backing + persistence + write-parity deferred to tracked issues. |
| ADR-067 tab-content cache | SWR client cache; keys in `lib/swr-config.ts swrKeys`, cleared on sign-out + workspace-switch. | Add `workstreamIssues` key; board uses `useSWR`. Tests wrap renders in `SwrTestProvider`. |

## Technical Considerations

- **Data flow + seam:** `server/workstream/seed-issues.ts` exports a pure `getWorkstreamIssues()` accessor — the **single seam**. `GET /api/workstream/issues` (force-dynamic, session-gated, `Sentry.captureException` on error → 502, mirrors `app/api/dashboard/routines/route.ts`) imports the accessor; the `workstream_issues_list` agent read tool ALSO imports the accessor directly (never self-calls the HTTP route — the routines "same shared fn, no duplicated query" rule). Client: `useSWR(swrKeys.workstreamIssues(), jsonFetcher)`. Optimistic create/status-change via SWR `mutate` (local cache only). When persistence/GitHub-backing lands, only the accessor body changes.
- **Agent read parity (v1):** `server/workstream/workstream-tools.ts` exports `buildWorkstreamTools({ userId })` with an auto-approve read-only `workstream_issues_list` tool over `getWorkstreamIssues()`, wired in `server/agent-runner.ts` (mirrors `server/routines-tools.ts` / `routines_list`). Closes the read/context-parity gap an agent-native review would otherwise flag. Write tools (`create`/`set_status`) are deferred (see Deferred Work).
- **Detail Sheet is URL-driven:** open-state hydrates from `?issue=<id>` search param on mount (`useSearchParams`); use `router.push` to set/clear the param so the browser Back button closes the Sheet (matches `components/inbox/inbox-surface.tsx:62-64`; `router.replace` would make Back leave the tab entirely). Resolves spec-flow P0 #1/#4/#15 (reload, deep-link, stale id, filter-while-open) in one mechanism. Unknown id → "Issue not found" state with "Back to board".
- **Board states are explicit components:** loading (skeleton), empty (first-run CTA), search-no-results (distinct copy + clear-search), error (+ "Try again" re-triggering SWR `mutate`). Not a single conditional (spec-flow P0 #3, P1 #5/#9/#10).
- **Honesty (CPO P0):** board-level "Preview — changes aren't saved yet" banner + the same notice at the moment of action (New Issue success, status change). The Concierge composer is **disabled** with an explicit "Concierge is offline — opening soon" label; no enabled composer that silently drops messages.
- **Assignee roles:** the role→initials and role→color map live **in `lib/workstream.ts`** as a self-contained constant (do NOT import `LEADER_BG_COLORS` from `components/chat/` — that inverts the `lib → components` layer and pulls `components/` into the node unit-test graph; arch P2-1). Reuse the same Tailwind color values as the leader palette by copying them; ids `cto/cmo/cpo/cfo/cro/coo/clo/cco` map to their colors, `CEO`/other → neutral. A small dedicated initials chip (`assignee-chip.tsx`) renders the text (`LeaderAvatar` is icon-based, unsuitable for role text).
- **"Live" badge** derives from seed data (status In Progress + a seeded `live` flag) only; user-created local cards never claim Live (spec-flow P2 #14).
- **Styling:** Soleur dark tokens (`bg-soleur-bg-surface-1`, `border-soleur-border-default`, `text-soleur-text-secondary`, `text-amber-500/70`, gold `#c9a962`), `components/ui/*` primitives (`Sheet` — props `{ open, onClose, "aria-label", children }`, Esc handling built in; `Card`, `Badge`, `GoldButton`, `OutlinedButton`, `ErrorCard` for the error+retry state, `MarkdownRenderer` for description), `components/icons` (`SearchIcon`, `PlusIcon`).
- **NFR:** read-only seed → negligible perf/data risk; a11y covered (Sheet close via Esc/backdrop/X + focus return — spec-flow P2 #13).

## User-Brand Impact

- **If this lands broken, the user experiences:** a blank or perpetually-spinning **Workstream tab** (the kanban board fails to render, or the detail Sheet won't open) — a dashboard surface dead-ends.
- **If this leaks, the user's data is exposed via:** essentially nil — the API serves a static, non-PII, in-repo seed; it is session-gated; there is no new persistence and the Concierge composer is disabled (holds and sends nothing).
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: the new app/api route serves a read-only non-PII in-repo seed under cookie-session auth; no new persistence, no PII, no LLM call, and the Concierge composer is disabled so it neither stores nor transmits user input.*

## Observability

```yaml
liveness_signal:
  what:            "GET /api/workstream/issues returns 200 + { issues: [...] } on each Workstream tab load (no background job — read-only on-demand surface)"
  cadence:         per-request (on tab navigation)
  alert_target:    Sentry issue (web-platform project) on server-side failure; no cron/heartbeat (no scheduled component)
  configured_in:   apps/web-platform/app/api/workstream/issues/route.ts

error_reporting:
  destination:     Sentry web-platform via SENTRY_DSN (Sentry.captureException with tags { surface: "workstream-issues" })
  fail_loud:       HTTP 502 { error: "workstream_query_error" } on the route; client board renders an explicit error state with a "Try again" button

failure_modes:
  - mode:          seed read / JSON serialization throws in the route handler
    detection:     Sentry event tagged surface=workstream-issues
    alert_route:   Sentry (web-platform)
  - mode:          client SWR fetch fails (network / 401 / 502)
    detection:     board renders user-visible error+retry state (no server alert needed — read-only, user-recoverable)
    alert_route:   user-visible UI (retry)
  - mode:          unauthenticated request
    detection:     route returns 401 { error: "unauthorized" } (mirrors routines route)
    alert_route:   client redirect / login (no alert)

logs:
  where:           Sentry breadcrumbs + Vercel/Next.js server logs for the route
  retention:       per existing Sentry + hosting defaults (unchanged by this PR)

discoverability_test:
  command:         "cd apps/web-platform && ./node_modules/.bin/vitest run test/components/workstream/workstream-board.test.tsx test/workstream-helpers.test.ts"
  expected_output: "all tests pass — board renders 7 columns, error state exposes a retry affordance, route returns 401 unauth"
```

## Architecture Decision (ADR/C4)

**No ADR required.** This is a UI tab on existing containers (`webapp`/`dashboard` + `api`) reading an in-repo seed via an internal route. It introduces no new substrate, tenancy/ownership boundary, resolver/trust boundary, or external edge, and does not reverse/extend an existing ADR. The deliberate seed-vs-GitHub data choice is documented above and carried in a tracked follow-up issue (not an architectural decision that misleads the recorded architecture).

**No C4 impact.** Read all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) and checked, for this feature:
- **External human actors:** none added — no new correspondent/sender/recipient (only the existing `founder` interacts).
- **External systems / vendors:** none added — v1 reads an in-repo seed (no GitHub/Anthropic/Resend edge); the Concierge is offline (no `engine -> anthropic` edge introduced); "Discuss in Chat" reuses the existing `dashboard -> api -> claude` chat edge.
- **Containers / data stores:** none added — no new table; the seed lives in-repo inside the `webapp` container.
- **Access relationships:** none changed — `founder -> dashboard -> api -> supabase` (auth) edges already modeled; no new owner/sharing semantics.

> When the deferred GitHub-backing follow-up lands, it WILL add a `dashboard/api -> github` read edge — the C4 update is in scope of **that** issue, not this one.

## Acceptance Criteria

### Functional Requirements

- [ ] A "Workstream" item appears in the dashboard sidebar **and** the ⌘K palette (added once to `NAV_ITEMS`; a new local icon fn + `NAV_ICONS["/dashboard/workstream"]` entry in `layout.tsx`).
- [ ] `/dashboard/workstream` renders 7 columns in order (Backlog, Todo, In Progress, In Review, Blocked, Done, Cancelled), each with a correct count badge derived from the loaded issues.
- [ ] Each card shows: issue ID, title, a priority indicator, and an assignee role-initials chip. In Progress/active seeded cards show a green "Live" badge; user-created cards never show "Live".
- [ ] The "Search issues…" field filters cards by ID + title; a no-results query shows a distinct "No issues match …" state with a clear-search action (not the empty-board state).
- [ ] Board exposes explicit loading (skeleton), empty (first-run CTA), and error (+ "Try again") states.
- [ ] "New Issue" opens a dialog (title required; defaults to Backlog + a default priority + "Unassigned"); on submit the card appears at the top of Backlog optimistically, and the success affordance states the change isn't persisted yet.
- [ ] Clicking a card opens a right slide-in Sheet showing description + Status, Assignee, Priority, Created, Updated. The Sheet open-state is URL-driven (`?issue=<id>`, set/cleared via `router.push` so Back closes it): reload/deep-link re-opens it; an unknown id shows "Issue not found" + "Back to board"; closing clears the param. Close works via X, Esc, and backdrop, returning focus to the card.
- [ ] Changing Status in the Sheet moves the card between columns optimistically (counts recompute from cache) with a visible non-persistence note.
- [ ] The Sheet contains a "Decision Making" Concierge panel: Concierge avatar/header, a scrollable message area (one seeded Concierge intro message), and a composer that is present + wired but **disabled** behind `CONCIERGE_ONLINE = false` with an explicit "Concierge is offline — opening soon" notice (no silent message-drop), plus a working "Discuss in Chat" link to `/dashboard/chat` (the existing live chat surface).
- [ ] A board-level "Preview — changes aren't saved yet" notice is visible.
- [ ] **Agent read parity:** a `workstream_issues_list` agent tool returns the same issues the board shows (over the shared `getWorkstreamIssues()` accessor), wired in `server/agent-runner.ts` — so an agent can see what the user sees.

### Non-Functional Requirements

- [ ] `GET /api/workstream/issues` is `force-dynamic`, returns 401 when unauthenticated, 502 + Sentry (tag `surface: "workstream-issues"`) on error, mirroring `app/api/dashboard/routines/route.ts`.
- [ ] Sheet meets basic a11y (Esc/backdrop/X close, focus return, labelled controls).
- [ ] No new runtime dependency added (no drag-and-drop lib).

### Quality Gates

- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/workstream/ test/workstream-helpers.test.ts` passes. (bun test is blocked by `bunfig.toml`; use vitest. Component tests live under `test/**/*.test.tsx` per `vitest.config.ts`; lib/node tests under `test/**/*.test.ts`.)
- [ ] Component test renders wrapped in `SwrTestProvider` (`test/helpers/swr-wrapper.tsx`) to avoid SWR module-singleton cache leakage across files.

## Test Scenarios

### Acceptance Tests
- Given a logged-in user, when they open `/dashboard/workstream`, then 7 columns render with count badges and seeded cards.
- Given a populated board, when the user types a query matching no issue, then a "No issues match …" state with a clear-search action renders (distinct from empty/error).
- Given the issues API returns 502, when the board loads, then an error state with a working "Try again" button renders.
- Given a card, when clicked, then a Sheet opens with description + details and the URL gains `?issue=<id>`; on reload the same Sheet re-opens.
- Given `?issue=<unknown>`, when the page loads, then "Issue not found" + "Back to board" renders (no blank Sheet).
- Given the detail Sheet, then the Concierge composer is disabled with the offline notice and a "Discuss in Chat" link with an href into the chat surface; typing/sending is not possible (no silent drop).
- Given "New Issue" with a title, when submitted, then a new card appears atop Backlog and a non-persistence note is shown; it carries no "Live" badge.

### Edge Cases
- Empty seed (`[]`) → first-run empty state with a primary "New Issue" CTA.
- Status change on a card whose Sheet is open while a search filter excludes it → Sheet stays open (URL-driven, independent of filtered list).

### Integration Verification (for /soleur:qa)
- **Browser:** Navigate to `/dashboard/workstream`; verify 7 columns + counts; click a card → Sheet opens with `?issue=`; reload → Sheet persists; verify Concierge composer disabled + "Discuss in Chat" present.
- **API verify:** `curl -s -o /dev/null -w '%{http_code}' https://app.soleur.ai/api/workstream/issues` → `401` unauthenticated (authed session → `200`).

## Design Revision Addendum (operator sign-off — 2026-06-26)

After the initial wireframes, the operator requested 5 changes (now reflected in the committed `.pen` + screenshots, commit `6eade7f49`). These are **binding** on implementation:

1. **Subtle per-column colors.** Each of the 7 columns gets a faint, low-luminance tint + a matching colored status dot in its header (NOT saturated blocks). Mapping: Backlog=slate `#9AA3B2`, Todo=cool gray-blue `#5E84C4`, In Progress=amber `#E0A93B`, In Review=violet `#A87BE0`, Blocked=red `#E5534B`, Done=green `#3FB950`, Cancelled=dim gray `#595959`. Add a `accent`/`tintClass` per column to the `COLUMNS` config in `lib/workstream.ts`; `issue-column.tsx` applies the tint to the column background + header dot.
2. **Count badges = rounded pills.** The per-column count is a small rounded pill (subtle `bg-soleur-bg-surface-2`/`#1C1C1C`, `cornerRadius ~7`), right-aligned in the header (spacer), typographically de-emphasized (`text-soleur-text-tertiary`, weight 500) so it doesn't compete with the column title.
3. **Priority = labeled pill, not a bare dot.** Replace the ambiguous gold/gray dot with a Linear-style labeled priority pill: a small color accent bar + color-matched text label inside a subtle pill, with 5 distinct levels — Urgent (red), High (orange), Medium (yellow), Low (gray-blue), None (gray). Update `priorityDotClass` → add `priorityPillClass` + `priorityLabel` helpers in `lib/workstream.ts`; `issue-card.tsx` renders the pill.
4. **"Live" marker has no green background.** Remove the green fill. Render as a small green dot + green "Live" text with no padding/fill — a quiet status marker, not a block.
5. **New `user` field (a person, distinct from the role assignee).** Add `user?: { name: string; initials: string }` to the `WorkstreamIssue` type — a specific PERSON associated with the issue, semantically separate from the role assignee (CTO/COO/…). Seed a few issues with a `user`. In the **detail Sheet**, render two distinct rows: **"Assignee (role)"** (existing role chip) and a new **"User"** row (gray person avatar + name). On the **card**, show a small secondary gray user avatar next to the primary role chip (kept subtle; role chip stays primary). When `user` is absent, omit the User row / secondary avatar cleanly. The `workstream_issues_list` agent tool must include `user` in its output (read parity).

> The detail-sheet "In Progress" status pill was also recolored from green → amber to match the new In Progress column tint — keep `statusPillClass` consistent with the per-column color map.

## Implementation Phases

### Phase 1 — Data model + accessor seam + read API + agent read tool
- `apps/web-platform/lib/workstream.ts`: `WorkstreamStatus` union (7 values, ordered `COLUMNS` config with label), `WorkstreamPriority`, `WorkstreamIssue` type, and display helpers (`priorityDotClass/Label`, `assigneeInitials` + **self-contained** role→color map, `statusPillClass`, `isLive`). No `components/` import.
- `apps/web-platform/server/workstream/seed-issues.ts`: ~12 representative issues (`SOLAA-` ids, role assignees, a few `live`) + a pure `getWorkstreamIssues()` accessor (the single seam).
- `apps/web-platform/app/api/workstream/issues/route.ts`: GET (force-dynamic, session-gated, imports `getWorkstreamIssues()`, Sentry on error → 502).
- `apps/web-platform/server/workstream/workstream-tools.ts`: `buildWorkstreamTools({ userId })` → auto-approve read-only `workstream_issues_list` over `getWorkstreamIssues()` (mirror `server/routines-tools.ts`); wire into `server/agent-runner.ts` tool assembly.
- `apps/web-platform/lib/swr-config.ts`: add `workstreamIssues: () => ["/api/workstream/issues"] as const`.

### Phase 2 — Board + states
- `apps/web-platform/app/(dashboard)/dashboard/workstream/page.tsx`: server component (auth gate + Suspense) → `<WorkstreamBoard/>`.
- `components/workstream/workstream-board.tsx`: SWR fetch, search, New Issue trigger, columns, Preview banner, loading/empty/no-results/error states, Sheet wiring via `?issue=`.
- `components/workstream/issue-column.tsx`, `components/workstream/issue-card.tsx`, `components/workstream/assignee-chip.tsx`.
- Nav: `components/command-palette/nav-items.ts` (+entry) and `app/(dashboard)/layout.tsx` (+`KanbanIcon` fn +`NAV_ICONS` entry).

### Phase 3 — Detail Sheet + Concierge panel + New Issue
- `components/workstream/issue-detail-sheet.tsx`: details + description + status select (optimistic move) + "Issue not found" state.
- `components/workstream/issue-concierge-panel.tsx`: "Decision Making" window — one seeded Concierge intro message, disabled wired composer behind `CONCIERGE_ONLINE = false`, offline notice, "Discuss in Chat" link to `/dashboard/chat`.
- `components/workstream/new-issue-dialog.tsx`: title-required create form, optimistic insert + non-persistence note.

### Phase 4 — Tests
- `test/workstream-helpers.test.ts` (node): COLUMNS order/count, helpers, seed shape validity, `getWorkstreamIssues()` accessor returns the seed.
- `test/workstream-tools.test.ts` (node): `workstream_issues_list` returns the same issues as the accessor (read-parity assertion).
- `test/components/workstream/{workstream-board,issue-card,issue-detail-sheet,issue-concierge-panel}.test.tsx` (happy-dom, wrapped in `SwrTestProvider`, `waitFor`, exact `getByText`; query the Sheet via `getByRole("dialog", { name })`; model error+retry on `inbox-surface.test.tsx`).

## Alternative Approaches Considered

| Approach | Why not (v1) |
|---|---|
| **Real GitHub-issue backing** (CPO recommendation) | Read tools exist, but Linear-style columns/`SOLAA-` IDs/role assignees don't map to GitHub issues without a label taxonomy + role-mapping layer, and it requires a connected repo (empty board for many) → "overdoing it". Deferred + tracked; the `getWorkstreamIssues()` accessor is the swap seam. |
| **Fully read-only board (cut New Issue), drop the HTTP route** (code-simplicity-reviewer) | New Issue is an explicit user requirement (screenshot button); the route is the read tool's HTTP twin over the shared accessor and matches the shipped routines precedent. Kept both; recorded as a deliberate disagreement. |
| **Supabase table + write API** (full persistence) | Migration + RLS + live DEV apply + operator verify = operator burden in a one-shot, against "keep it simple". Deferred + tracked. |
| **Drag-and-drop columns** | New dependency + complexity; status-select move is sufficient for v1. Deferred. |
| **Enabled Concierge composer (local echo)** | CPO P0: an enabled composer that drops/echoes messages on a "human-in-the-loop" surface is actively misleading. Chosen: disabled+wired + live "Discuss in Chat". |
| **Flagsmith flag gate** | Requires Doppler dev+prd provisioning (operator burden). Honesty achieved via visible "Preview" labeling instead; flag-gating left as an optional operator choice. |
| **Dedicated `[issueId]` route** (vs `?issue=` param) | Param-driven Sheet deep-links + survives reload without a second server data path or new-issue dead-ends; simpler. |

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering (CTO concern, carried from CPO advisory)
**Status:** reviewed
**Assessment:** No new infra/schema/secret. The swap seam is the pure `getWorkstreamIssues()` accessor (imported by both the route and the read tool), so a later GitHub-proxy/DB read replaces only the accessor body. No architectural decision rising to ADR/C4 (see Architecture Decision section). Agent-native: **read** parity ships in v1 (`workstream_issues_list` tool); **write** parity is deferred + tracked (mandatory per constitution). Future write tools must call shared server primitives, not re-implement logic in route/component.

### Product/UX Gate
**Tier:** blocking (new page + new components + a chat/conversation interface; mechanical UI-surface + new-component-file override both fire)
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead
**Skipped specialists:** copywriter (none recommended; the small Preview/offline copy strings are written inline per CPO honesty guidance)
**Pencil available:** yes (Tier 0 headless CLI) — `.pen` committed

#### Findings
- **ux-design-lead:** wireframes generated + committed — `knowledge-base/product/design/workstream/workstream-kanban.pen` (commit 57c94d028); screenshots `01-workstream-kanban-board.png`, `02-workstream-issue-detail-sheet.png`. Board (Preview badge, 7 columns, cards, Live badge) + detail Sheet (details, description, offline Concierge composer + "Discuss in Chat"). Wireframes ready for async review (headless pipeline — no pause).
- **CPO (decisive):** (1) prefer real GitHub-issue backing over a seed → recorded as documented decision + deferral; (2) agent-native parity deferral is **mandatory** to track → deferral issue; (3) **do not ship an enabled composer that sends nothing** → adopted disabled+wired + "Discuss in Chat"; (4) surface non-persistence visibly ("Preview", at moment of action) → adopted; (5) file a Phase 4 roadmap issue → deferral list.
- **spec-flow-analyzer:** P0s adopted — URL-driven Sheet (reload/deep-link/stale-id/filter-while-open), non-persistence notice at moment of action, error+retry, issue-not-found. P1/P2 adopted — distinct no-results state, unambiguous offline copy, chat deep-link landing/context, count-badge recompute from cache, empty-state CTA, New Issue defaults+validation, created-card landing, Sheet close/focus a11y, Live-badge semantics.
- **agent-native-reviewer (deepen):** caught the read/context-parity gap (board visible to users, invisible to agents). Adopted: ship `workstream_issues_list` read tool in v1 over the shared accessor; split the deferral into read-shipped / write-deferred; lock the shared-accessor seam so future write tools reuse server primitives.

## GDPR / Compliance Gate

Skipped — no regulated-data surface. No schema/migration/auth change; the new API route serves a non-PII in-repo seed; the Concierge panel performs **no** LLM/external-API processing of session data (it is offline and the composer is disabled), so trigger (a) does not fire. No new artifact-distribution or cross-controller data-movement surface.

## Infrastructure (IaC)

Skipped — no new infrastructure (no server, service, cron, secret, vendor, DNS, or persistent runtime process). Pure application code against the already-provisioned web-platform.

## Open Code-Review Overlap

Checked open `code-review` issues against planned edit files (`nav-items.ts`, `(dashboard)/layout.tsx`, `swr-config.ts`, `components/workstream`). One match: **#2193** (billing past_due/unpaid banner unification) references `layout.tsx`. **Disposition: Acknowledge** — unrelated concern (billing banner component extraction); this plan only appends a nav icon fn + `NAV_ICONS` entry. The scope-out remains open.

## Deferred Work (tracking issues)

**Shipped in v1 (NOT deferred):** agent **read** parity (`workstream_issues_list` tool over the shared accessor).

Per `wg-when-deferring-a-capability-create-a`, file the issues below at **ship/work time** (issue creation is blocked in this planning-only phase). Labels verified to exist. Reference them in the PR body (`Refs #N`) once filed.

```bash
gh issue create --title "feat(workstream): back board with real GitHub issues + persistence + write API" \
  --label "type/feature,domain/engineering,deferred-automation" \
  --body "Replace the seed (server/workstream/seed-issues.ts getWorkstreamIssues()) with real GitHub issues (read tools at server/github-read-tools.ts) or a Supabase table + write path so New Issue/status-move persist. Carries C4 update: adds dashboard/api -> github read edge. Re-evaluate after v1 ships."
gh issue create --title "feat(workstream): agent-native WRITE tools for issues (create/set_status)" \
  --label "type/feature,domain/engineering,deferred-automation" \
  --body "Read parity shipped in v1 (workstream_issues_list). Deferred: workstream_issue_create / workstream_issue_set_status, calling shared server primitives (createWorkstreamIssue/setWorkstreamIssueStatus), not re-implementing logic in route/component. Registration: buildWorkstreamTools in server/agent-runner.ts. Re-evaluate alongside persistence."
gh issue create --title "feat(workstream): wire Decision Making Concierge panel to live conversation backend" \
  --label "type/feature,domain/product,deferred-automation" \
  --body "v1 ships the per-issue Concierge window wired but disabled (CONCIERGE_ONLINE=false) + offline notice + Discuss in Chat deep-link. Deferred: flip the flag and connect ChatSurface/websocket seeded with the issue context. Re-evaluate once the per-issue conversation backend is functional."
```

Optional follow-ups (file if/when warranted): roadmap home under Phase 4 (relate to #2004 Agent Work Visualization, #3691); drag-and-drop column reordering (`--label enhancement,deferred-automation`).

## Dependencies & Risks

- **Non-persistence UX (Medium):** mitigated by visible Preview notices at board + action level (no silent loss). Reload re-derives from seed; created/moved cards reset — framed, not hidden.
- **Offline Concierge clarity (Medium):** mitigated by explicit disabled state + label + the live "Discuss in Chat" escape hatch.
- **SWR test isolation (Medium):** wrap all component renders in `SwrTestProvider` (learning `2026-06-23-swr-adoption-test-isolation-and-shared-key-discipline.md`).
- **Layout `children` swap (Low):** the board/Sheet live inside the page (Sheet is client overlay), not the layout sidebar — avoids the KB-nav `children` pitfall (`2026-04-10-kb-nav-tree-disappears-on-file-select.md`).

## Research Insights (deepen-plan)

**Concrete codebase patterns (file:line) to follow:**
- **Sheet** (`components/ui/sheet.tsx:11-16,33-47`): props `{ open, onClose, "aria-label", children }`; Escape handling is built in (closes when focus is inside the panel or on `document.body`). Call-site model: `components/chat/kb-chat-sidebar.tsx:16-24`. Test via `screen.getByRole("dialog", { name })`; `test/sheet.test.tsx` shows mocking `window.innerHeight` + `matchMedia`.
- **SWR loading/empty/error hierarchy** (`components/inbox/inbox-surface.tsx:51-56,89-111`): `useSWR(key, fetcher)` → if `error && !items` render `ErrorCard` with a "Try again" button calling `mutate()`; surfaces stay rendered in every state (no stranding). Retry test model: `test/inbox-surface.test.tsx:140-154`.
- **URL-driven UI state** (`components/inbox/inbox-surface.tsx:62-64` uses `router.push(pathname + '?status=')`; `components/chat/chat-surface.tsx:207-211,483-489` reads `useSearchParams` and clears a consumed param with `router.replace(pathname, { scroll: false })`). For the Sheet, prefer `router.push` so Back closes it.
- **Chat deep-link target** (`app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:8-49`): supports `?context=<kb-path>` seeding, but a workstream issue is not a KB path and v1 has no per-issue conversationId — so "Discuss in Chat" links to `/dashboard/chat` (real, working surface). Seeded-issue-context bridge is part of the deferred Concierge-wiring issue.
- **Agent read-tool precedent** (`server/routines-tools.ts`): read tools are auto-approve, read-only, and call the SAME shared server fn the dashboard route uses (no duplicated query). `workstream_issues_list` mirrors this over `getWorkstreamIssues()`. Registration seam: `buildXTools({ userId })` assembled in `server/agent-runner.ts`.
- **SWR test isolation** (`test/helpers/swr-wrapper.tsx:15-38`): wrap every component render in `SwrTestProvider` (`provider: () => new Map()`, `dedupingInterval: 0`, `shouldRetryOnError: false`); usage model `test/inbox-surface.test.tsx:28-34`.

**Architecture verification (architecture-strategist):** nav registration confirmed correct — sidebar (`layout.tsx:165,386,391`) + palette (`use-shortcuts.tsx:127`) both read `NAV_ITEMS`; `/dashboard/workstream` returns drill `null` (`hooks/segment-to-drill-level.ts:25` allowlist) so it renders in the primary rail. Inbox `page.tsx`'s `<Suspense>` boundary is **required** for `next build` CSR-bailout — Phase 2 page must keep it. Route shape matches `routines/route.ts:10,17-19,23-26` exactly. vitest globs confirmed (`vitest.config.ts:42-44,62-64`).

**Disagreement resolution (code-simplicity vs. agent-native/architecture):** code-simplicity recommended dropping the HTTP route and New Issue. Kept both: New Issue + the Concierge window are explicit user requirements; the route is the read tool's HTTP twin over the shared accessor and matches the shipped routines precedent. The accessor (not the route) is the seam, so the residual "ceremony" is ~15 lines mirroring an existing pattern.

## References & Research

### Internal
- Tab registry: `apps/web-platform/components/command-palette/nav-items.ts`; icons `apps/web-platform/app/(dashboard)/layout.tsx:104`.
- Read API + surface precedent: `apps/web-platform/app/api/dashboard/routines/route.ts`, `apps/web-platform/components/inbox/inbox-surface.tsx`.
- Detail page precedent: `apps/web-platform/app/(dashboard)/dashboard/inbox/email/[emailId]/page.tsx`.
- Chat reuse / deep-link target: `apps/web-platform/components/chat/chat-surface.tsx`, `apps/web-platform/lib/ws-client.ts`, `apps/web-platform/server/agent-runner.ts`.
- SWR keys + cache: `apps/web-platform/lib/swr-config.ts`; test helper `apps/web-platform/test/helpers/swr-wrapper.tsx`.
- UI primitives: `apps/web-platform/components/ui/{sheet,card,badge,gold-button,outlined-button,markdown-renderer}.tsx`; tokens `apps/web-platform/app/globals.css`.
- Roles/colors: `apps/web-platform/server/domain-leaders.ts`, `apps/web-platform/components/chat/leader-colors.ts`, `apps/web-platform/components/leader-avatar.tsx`.
- Wireframes: `knowledge-base/product/design/workstream/workstream-kanban.pen`.

### Learnings
- `knowledge-base/project/learnings/best-practices/2026-06-23-swr-adoption-test-isolation-and-shared-key-discipline.md`
- `knowledge-base/project/learnings/ui-bugs/2026-04-10-kb-nav-tree-disappears-on-file-select.md`
- `knowledge-base/project/learnings/2026-04-06-chat-page-test-determinism-and-coverage.md`
- `knowledge-base/project/learnings/2026-04-14-next-dynamic-testing-pattern-vitest.md`
