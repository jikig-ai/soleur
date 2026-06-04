---
title: "Fix KB document viewer — share-link UX + C4 diagram chat panel collapse/reveal"
date: 2026-06-04
type: fix
branch: feat-one-shot-kb-doc-viewer-share-chat-fixes
status: ready
lane: single-domain
brand_survival_threshold: none
---

# 🐛 Fix KB document viewer — share-link UX + C4 diagram chat panel collapse/reveal

## Enhancement Summary

**Deepened on:** 2026-06-04

### Key Improvements (verified in deepen pass)
1. **Premise validated live:** PR #4922 confirmed `MERGED` + reachable from HEAD (`gh pr view 4922` → `MERGED`; `git merge-base --is-ancestor 2ddccc7b HEAD` → OK). Item 1 re-scoped from "re-fix the insert" to "client error UX + residual hardening" — the bug's dominant cause is already fixed.
2. **No-regression precedent confirmed:** the markdown viewer passes `onClose={closeSidebar}` (`kb-desktop-layout.tsx:78`, `kb-mobile-layout.tsx:51`) — a different callback than the C4 workspace's `onClose={() => setRightTab("code")}` (`c4-workspace.tsx:126`). Repointing the C4 caller cannot regress the markdown side panel (AC7 holds).
3. **Server insert-branch structure confirmed:** `createShare` has a `23505` branch at `kb-share.ts:316` falling through to generic `db-error` at `:340`. The new `23503` branch slots cleanly before `:340` (Phase 2 line refs accurate).
4. **Wireframe produced + committed:** 3 frames at `knowledge-base/product/design/kb-viewer/kb-doc-viewer-share-chat-fixes.pen` (gate 4.9 satisfied) — error state, Concierge-expanded (in-header X collapse), Concierge-collapsed (gold "Open Concierge" reveal pill).
5. **`react-resizable-panels` collapse API verified** in installed `.d.ts` (`collapsible`/`collapsedSize`/`panelRef.collapse()`/`expand()`); local-`useState` conditional-render chosen as simpler, API noted as fallback.

### New Considerations Discovered
- The reveal-control design choice is now locked by the wireframe (top-right gold pill on the full-width diagram), removing the one open design question.
- The Concierge must stay **mounted** across collapse↔reveal (CSS-hide, not unmount) to preserve the in-progress thread — mirrors the existing `rightTab` "stays mounted across toggles" comment (`c4-workspace.tsx:121-122`) and the stale-context learning's keep-mounted reasoning.

## Overview

Three scoped fixes to the KB document viewer in `apps/web-platform`, concentrated on the **C4 diagram surface** (a markdown doc embedding a ` ```likec4-view ` block, rendered full-screen by `components/kb/c4-workspace.tsx`):

1. **Share-link UX (BUG, partly fixed upstream):** The "Generate link" popup silently resets to its idle "Generate a Link" prompt on any server failure. PR #4922 (MERGED, in HEAD) already fixed the *dominant* root cause (a missing `workspace_id` on the `createShare` insert → Postgres 23502 → 500 → silent reset). The residual problem is purely client-side: `share-popover.tsx` swallows **every** non-OK response and every thrown error into a silent reset to `idle`, so any remaining/transient failure still looks like "nothing happened." Fix = surface the error in the popup instead of silently resetting, plus minor server hardening (map FK 23503 distinctly, handle the 409 concurrent-retry response client-side).

2. **C4 Concierge panel cannot be dismissed (FEATURE/BUG):** In `c4-workspace.tsx` the right panel is permanently present (default 38%) and only toggles between Concierge and Code tabs. The Concierge's `onClose` is wired to `setRightTab("code")` (line 126) — it does NOT collapse/hide the panel. Add a real collapse so the diagram can take full width.

3. **No "open chat" affordance on the diagram (BUG/FEATURE):** Once item 2 lands, the user needs a way to re-reveal the collapsed Concierge. Add a reveal control. The shared `KbChatTrigger` is intentionally hidden on diagrams (`page.tsx` sets `suppressSidebar=true` → trigger returns `null` at `kb-chat-trigger.tsx:53`), and that suppression must stay (it prevents the desktop side panel from double-mounting a second Concierge with the same `contextPath`). So the reveal control lives **inside the C4 workspace**, paired with the collapse from item 2 — one collapse/reveal state.

Items 2 and 3 are the same surface and the same state machine: a single "right panel collapsed?" boolean in `c4-workspace.tsx`, with a collapse control in the panel header and a reveal control shown when collapsed.

This is a pure code change against an already-provisioned surface — no new infrastructure, no migrations, no new secrets.

## Research Reconciliation — Premise vs. Codebase

| Premise (from bug report) | Codebase reality (verified 2026-06-04) | Plan response |
|---|---|---|
| "Generate link does nothing, returns to Generate-a-Link prompt" | PR #4922 (MERGED, commit `2ddccc7b`, reachable from HEAD) already fixed the dominant cause: migration 059 added `kb_share_links.workspace_id` NOT NULL (FK→`workspaces(id)`), and `createShare`'s insert now sets it via `resolveCurrentWorkspaceId` (`server/kb-share.ts:309`). The 23502 path that produced the exact symptom is gone on `main`. | **Symptom is largely stale on `main`.** Re-scope item 1 to: (a) confirm via QA, (b) fix the client's silent-reset-on-error UX (the real residual that makes *any* failure look identical), (c) harden two remaining `createShare` failure modes. Do NOT re-fix the 23502 path. |
| "Operator suspects client-side caching" | No caching on the POST path. `generateLink()` (`share-popover.tsx:76-99`) POSTs and on `!res.ok` (line 84) or `catch` (line 96) sets `status:"idle"` with **no error message**. The GET-on-open path (lines 42-74) also resets to idle on failure. | Root cause is **missing client error surfacing**, not caching. The popup needs an `"error"` state. |
| "side chat panel has no way to dismiss" (on the diagram) | True for the C4 surface. `c4-workspace.tsx` right `<Panel>` is permanent; `KbChatContent onClose={() => setRightTab("code")}` (line 126) only switches tabs. The **non-diagram** markdown viewer side panel already closes fine (`kb-desktop-layout.tsx` passes `onClose={closeSidebar}`; `KbChatContent` renders an X button at lines 158-168). | Add collapse to the C4 workspace only. Markdown viewer is already correct. |
| "missing chat-about-this button at top of diagram doc" | Intentional: `page.tsx:74-79` sets `suppressSidebar=true` for C4 embeds; `kb-chat-trigger.tsx:53` returns `null` when suppressed. The C4 workspace embeds its own Concierge instead. | Keep the suppression (prevents double-mount). Add the reveal control **inside** the C4 workspace, coupled to item 2's collapse state. |

## Affected Surfaces (verified)

- `apps/web-platform/components/kb/share-popover.tsx` — `ShareState` union, `generateLink`/`checkShare` handlers, popup render (idle/loading/active branches).
- `apps/web-platform/server/kb-share.ts` — `createShare` insert error mapping (`insertError.code` branches at lines 315-351); `CreateShareErrorCode` union.
- `apps/web-platform/app/api/kb/share/route.ts` — thin POST wrapper (maps `result` → HTTP). No structural change expected; verify it passes `result.code` through if item 1c adds a code branch.
- `apps/web-platform/components/kb/c4-workspace.tsx` — right `<Panel>` + `<ResizeHandle>` + tab strip; add collapse/reveal state.
- `apps/web-platform/components/chat/kb-chat-content.tsx` — already has an X "Close panel" button (lines 158-168); its `onClose` is the hook the C4 workspace will repoint from "switch to code" to "collapse panel."

## Technical Context (verified against installed code)

- `react-resizable-panels` (this fork) exports `Group`/`Panel`/`Separator` (verified `node_modules/react-resizable-panels/dist/react-resizable-panels.d.ts:26,193,359`). `Panel` supports `collapsible`, `collapsedSize`, imperative `panelRef.collapse()`/`expand()`, and an `isCollapsed` state. Both `c4-workspace.tsx` and `kb-desktop-layout.tsx` already use this fork's `Group/Panel/Separator` names.
- **Simplest viable approach for items 2+3** (preferred): a local `useState` boolean (`conciergeCollapsed`) in `c4-workspace.tsx` that conditionally renders the right `<Panel>` + `<ResizeHandle>`. When collapsed, the left diagram `<Panel>` takes full width and a small "Open Concierge" pill/button is shown (e.g., floating top-right of the diagram pane, or in a thin rail). This keeps all state local, mirrors the existing `rightTab` local-state pattern, and avoids the imperative-ref ceremony. (The `collapsible` Panel API is the documented alternative — note it in Alternatives.)
- Test runner: **vitest** (`package.json:15` `"test": "vitest"`, CI `vitest run`). Node tests `test/**/*.test.ts`, component tests `test/**/*.test.tsx` (happy-dom) per `vitest.config.ts:44,60`. Co-located `components/**/*.test.tsx` are NOT collected — new tests go under `test/`.
- When a new component test mocks `next/navigation`, stub `useSearchParams` alongside `useRouter`/`usePathname` (KbChatContent → ChatSurface mounts all three) — see learning `2026-04-17-kb-chat-stale-context-on-doc-switch.md` Session Errors.
- **Wireframe (committed):** `knowledge-base/product/design/kb-viewer/kb-doc-viewer-share-chat-fixes.pen` — 3 frames: (1) Share popup error state with generic copy + "Try again" CTA; (2) C4 workspace with Concierge expanded showing the in-header X collapse control; (3) C4 workspace collapsed showing the full-width diagram + gold-gradient "Open Concierge" reveal pill. The implementation FRs (Phase 1 error state, Phase 3 collapse + reveal) realize these three frames.

## User-Brand Impact

**If this lands broken, the user experiences:** a share popup that still silently fails to mint a link (no error shown), or a diagram Concierge that can't be collapsed/reopened — i.e., the exact frustrations being fixed, plus possible regression of the working markdown-viewer side panel if the shared `KbChatContent.onClose` contract is changed carelessly.

**If this leaks, the user's data is exposed via:** N/A for items 2/3 (pure layout/UX). For item 1, the share surface already mints public read-only tokens; this change adds NO new exposure vector — it only surfaces error text to the authenticated owner in their own popup. Error copy MUST be generic ("Couldn't generate a link. Please try again.") and MUST NOT echo raw server error strings, DB codes, or paths.

**Brand-survival threshold:** none. Reason: layout/UX polish + client error surfacing on an already-owner-authenticated surface; no new persisted data, no new public exposure, no regulated-data surface. (Sensitive-path scope-out: the diff touches an API route file `app/api/kb/share/route.ts` only to pass through an existing error `code`; no auth/authz/RLS logic changes.)

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
- [ ] `grep -n "onClose" components/chat/kb-chat-content.tsx` — confirm `onClose` is invoked only by the X button (line ~161) and passed to `ChatSurface` (line ~180); changing what the C4 caller passes for `onClose` must NOT change markdown-viewer behavior (different caller).
- [ ] `grep -n "setRightTab\|rightTab" components/kb/c4-workspace.tsx` — confirm `rightTab` is local `useState` and the only place `onClose` is wired is line 126.
- [ ] Confirm `react-resizable-panels` collapse approach choice (local-state conditional render vs `collapsible` Panel) — local-state chosen; note in Alternatives.
- [ ] Re-confirm PR #4922 reachable from HEAD: `git merge-base --is-ancestor 2ddccc7b HEAD && echo OK`.

### Phase 1 — Item 1a: Client error surfacing in `share-popover.tsx` (TDD)
- [ ] **RED:** add `test/share-popover.test.tsx` (new) — render `<SharePopover documentPath="…">`, open popup, mock `fetch` POST → 500; assert the popup shows an error message AND a retry affordance, and does NOT silently return to the bare "Generate a public link" idle prompt with no feedback. Also assert the happy path (POST 201 → active state with the link) still works.
- [ ] **GREEN:** extend `ShareState.status` union with `"error"` (and optionally an `errorMessage: string | null`). In `generateLink`, on `!res.ok` and on `catch`, set `status:"error"` with a **generic** message (never echo server text). Render an `"error"` branch with the message + a "Try again" button that calls `generateLink` again. Apply the same to the GET-on-open `checkShare` path (currently resets to idle silently — at minimum keep idle but consider a non-blocking inline note; do not block the user from generating).
- [ ] **REFACTOR:** keep the error copy as a single hoisted constant; ensure outside-click and `confirmRevoke` reset still clear the error state.

### Phase 2 — Item 1b: Server `createShare` hardening (TDD)
- [ ] **RED:** extend `test/kb-share.test.ts` — (a) mock the insert returning `{ code: "23503" }` (FK violation: workspace row missing) → assert `createShare` returns a distinct `ok:false` result (new code, e.g. `"workspace-missing"`, status 409 or 500) rather than the generic `db-error`; (b) assert the 23505 concurrent path still returns the existing 409 `concurrent-retry`.
- [ ] **GREEN:** in `server/kb-share.ts` insertError handling (lines ~315-351), add a `23503` branch (before the generic `reportSilentFallback`/`db-error`) returning a distinct `CreateShareErrorCode` so telemetry can discriminate "user's workspace row missing" from generic DB error. Keep `reportSilentFallback` mirroring to Sentry (per `cq-silent-fallback-must-mirror-to-sentry`).
- [ ] **GREEN:** in `share-popover.tsx`, handle the POST `409` response specifically: re-run `checkShare` (the concurrent winner row now exists) so the user lands on the `active` state instead of an error. (For `409 concurrent-retry`, the active row exists; for any other `409`, fall to the generic error state.)
- [ ] Verify `app/api/kb/share/route.ts` POST passes any new `result.code` through to the JSON body (it currently returns `{ error }` on failure; add `code` so the client can branch). Keep `cq-nextjs-route-files-http-only-exports` — route file exports only HTTP verbs.

### Phase 3 — Items 2+3: C4 Concierge collapse/reveal (TDD)
- [ ] **RED:** add `test/c4-workspace.test.tsx` (new — no existing c4-workspace test). Mock `useC4Project` (`@/components/kb/c4-shared`) and `KbChatContent`, and stub `next/navigation` (`useRouter`/`usePathname`/`useSearchParams`). Assert: (1) the Concierge panel renders by default; (2) clicking the collapse control hides the right panel (Concierge + ResizeHandle gone, diagram full width); (3) a reveal control appears when collapsed; (4) clicking reveal restores the Concierge; (5) the Concierge thread is NOT lost across collapse→reveal (component stays mounted, visibility CSS-driven — mirror the existing `rightTab` "stays mounted across toggles" comment at c4-workspace.tsx:121-122). Decide explicitly whether collapse keeps the component mounted (preferred — preserves thread) or unmounts; the test encodes the choice.
- [ ] **GREEN:** in `c4-workspace.tsx`: add `const [conciergeCollapsed, setConciergeCollapsed] = useState(false)`. When collapsed, do not render the right `<Panel>` + `<ResizeHandle>` (or render the panel at `collapsedSize` with content hidden if keeping it mounted to preserve the thread — choose per the RED decision; mounting-preserved is preferred to keep the Concierge thread alive). Add a collapse control in the right-panel tab strip (a chevron/X button, `aria-label="Collapse Concierge"`). Repoint `KbChatContent onClose` from `setRightTab("code")` to `() => setConciergeCollapsed(true)` so the existing X button (kb-chat-content.tsx:158-168) collapses the panel (matches the markdown viewer's "X closes the panel" mental model).
- [ ] **GREEN:** add the reveal control when `conciergeCollapsed` — an "Open Concierge" / "Ask about this document" button. Placement options (pick one, note in Alternatives): (a) a floating pill top-right of the diagram pane, or (b) a thin always-visible rail on the right edge. Use the gold-gradient CTA tokens consistent with `KbChatTrigger` (`from-soleur-accent-gradient-start to-soleur-accent-gradient-end`) for brand consistency. `aria-label="Open Concierge"`.
- [ ] **REFACTOR:** keep `suppressSidebar=true` behavior unchanged (do NOT touch `page.tsx`/`kb-chat-trigger.tsx` suppression — the desktop side panel must remain suppressed to avoid double-mount). Confirm focus management: when collapsing, optionally move focus to the reveal control; when revealing, focus the chat input (KbChatContent already rAF-focuses its input on `visible`).

### Phase 4 — Verification
- [ ] `tsc --noEmit` clean (run via the package's typecheck script).
- [ ] `./node_modules/.bin/vitest run test/share-popover.test.tsx test/kb-share.test.ts test/c4-workspace.test.tsx` green.
- [ ] Full webplat shard green (or scoped runs above + `vitest run` for the changed-file neighborhood).
- [ ] Playwright/manual QA of the live share flow on a real diagram doc (e.g. `engineering/architecture/diagrams/c4-model.md`): open Share → Generate link → link appears; collapse Concierge → diagram full width → reveal → Concierge thread intact.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 (item 1a):** On a POST `/api/kb/share` failure (any non-2xx or thrown error), the Share popup renders a visible error message + a retry control, and does NOT silently re-render the bare idle "Generate a public link" prompt. Verified by `test/share-popover.test.tsx` asserting an error node + retry button after a mocked 500.
- [ ] **AC2 (item 1a):** Error copy is generic and contains no raw server error string, DB SQLSTATE, or filesystem path. Verified by asserting the rendered error text equals the hoisted generic constant (not the mocked server `error` payload).
- [ ] **AC3 (item 1b):** `createShare` returns a distinct (non-`db-error`) `CreateShareErrorCode` for insert SQLSTATE `23503`, while preserving the existing `409 concurrent-retry` for `23505`. Verified by `test/kb-share.test.ts` cases for both codes.
- [ ] **AC4 (item 1b):** On POST `409` with the concurrent-retry code, the client lands on the `active` state (re-runs `checkShare` and shows the existing link), not the error state. Verified by a `test/share-popover.test.tsx` case mocking 409 then GET→existing row.
- [ ] **AC5 (item 2):** In `c4-workspace.tsx`, clicking the collapse control (and clicking the existing KbChatContent X button) hides the right Concierge panel + its resize handle; the diagram pane expands to full width. Verified by `test/c4-workspace.test.tsx`.
- [ ] **AC6 (item 3):** When the Concierge is collapsed, a reveal control is visible; clicking it restores the Concierge panel with its prior thread intact (component stayed mounted). Verified by `test/c4-workspace.test.tsx` (assert the same KbChatContent instance/thread, not a fresh mount, unless the unmount choice was made explicitly).
- [ ] **AC7 (no-regression):** `page.tsx` C4-embed `suppressSidebar=true` and `kb-chat-trigger.tsx:53` null-return are unchanged; the non-diagram markdown viewer side panel still opens/closes via `closeSidebar` (no diff to `kb-desktop-layout.tsx` behavior). Verified by existing `test/kb-chat-trigger.test.tsx` + `test/kb-chat-sidebar*.test.tsx` staying green.
- [ ] **AC8:** `tsc --noEmit` clean; route file `app/api/kb/share/route.ts` exports only HTTP verbs (`cq-nextjs-route-files-http-only-exports`).

### Post-merge (operator)
- [ ] **AC9:** Manual/Playwright QA on the deployed diagram doc confirms Generate-link succeeds end-to-end (the #4922 fix + this UX layer). `Automation:` Playwright MCP can drive this — wire as a post-merge smoke if a logged-in fixture session is available; otherwise operator one-pass.

## Observability

```yaml
liveness_signal:
  what: createShare success/failure is already logged (pino `share_created` / `share_reissued_on_content_drift` events in server/kb-share.ts) and the client now surfaces failures to the user.
  cadence: per user "Generate link" click (interactive, not scheduled).
  alert_target: Sentry (existing reportSilentFallback for db-error / new 23503 branch).
  configured_in: apps/web-platform/server/kb-share.ts (reportSilentFallback) + server/observability.ts.
error_reporting:
  destination: Sentry via reportSilentFallback (createShare insert errors); client error state is user-visible.
  fail_loud: yes — server errors mirror to Sentry; client no longer swallows failures silently.
failure_modes:
  - mode: createShare insert FK violation (23503, workspace row missing)
    detection: new distinct CreateShareErrorCode + reportSilentFallback mirror
    alert_route: Sentry (feature kb-share, op create)
  - mode: createShare generic DB error (500)
    detection: existing reportSilentFallback
    alert_route: Sentry
  - mode: C4 Concierge collapse/reveal state bug (pure client)
    detection: component test + manual QA (no server signal)
    alert_route: n/a (client-only UI state)
logs:
  where: pino child logger "kb-share" (stdout → container logs); Sentry for errors.
  retention: existing container log + Sentry retention (unchanged).
discoverability_test:
  command: ./node_modules/.bin/vitest run test/share-popover.test.tsx test/kb-share.test.ts test/c4-workspace.test.tsx
  expected_output: all suites pass (RED→GREEN for the three items).
```

## Alternative Approaches Considered

| Approach | Chosen? | Rationale |
|---|---|---|
| Item 2/3: local `useState` boolean + conditional render of right Panel | ✅ | Mirrors existing `rightTab` local-state pattern in the same file; self-contained; no cross-context plumbing. |
| Item 2/3: `react-resizable-panels` `collapsible` Panel + `panelRef.collapse()/expand()` | ❌ (noted) | Documented API (verified in installed .d.ts) but adds imperative-ref ceremony for a binary show/hide the file can express with one `useState`. Keep as fallback if drag-to-collapse-to-zero is later desired. |
| Item 2/3: surface the reveal in the shared `KbContentHeader` (un-suppress `KbChatTrigger`) | ❌ | Would require relaxing `suppressSidebar`, risking double-mount of two Concierges with the same `contextPath`. Keeping the control inside the C4 workspace avoids that entirely. |
| Item 1: re-fix the workspace_id insert | ❌ | Already fixed by merged PR #4922 — re-doing it is wasted scope. |
| Item 1: investigate client-side caching (operator's hypothesis) | ❌ | No caching exists on the POST path; the real residual is silent-reset-on-error UX. |

## Domain Review

**Domains relevant:** Product (UI surface).

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed — modifies existing user-facing components (`share-popover.tsx`, `c4-workspace.tsx`); adds an error state and a new collapse/reveal interaction. A `.pen` wireframe was produced for the three changed surfaces (the collapse/reveal is a new layout interaction, so `wg-ui-feature-requires-pen-wireframe` applies even though no new component file is created).
**Agents invoked:** none (Task sub-agent spawning unavailable in this planning environment — recorded as a session note; wireframe authored directly via Pencil MCP).
**Skipped specialists:** none.
**Pencil available:** yes — wireframe committed at `knowledge-base/product/design/kb-viewer/kb-doc-viewer-share-chat-fixes.pen` (3 frames, screenshots under `knowledge-base/product/design/kb-viewer/screenshots/`).

#### Findings

UX-positive: makes a silent failure visible (item 1) and a permanent panel dismissible/restorable (items 2/3). Wireframe decisions locked: error copy is generic (no server-string echo); the C4 collapse control is the in-header X (reusing the existing `KbChatContent` X button semantics); the reveal control is a gold-gradient "Open Concierge" pill anchored top-right of the full-width diagram (brand-consistent with `KbChatTrigger`). The Concierge stays mounted across collapse↔reveal so the thread survives.

## Risks & Mitigations

**Precedent-diff (Phase 4.4):** The collapse/reveal pattern has a sibling precedent in the same codebase — the markdown viewer's side panel (`kb-desktop-layout.tsx`) uses `showChat && contextPath` gating + `closeSidebar` to mount/unmount the panel. The C4 workspace will instead keep the Concierge **mounted** and CSS-hide it (per the existing `rightTab` comment at `c4-workspace.tsx:121-122`) to preserve the thread — a deliberate divergence from the markdown viewer's unmount-on-close, justified by the C4 workspace's single full-screen surface (no navigation-driven `contextPath` change while the diagram is open). No SQL/lock/atomic-write precedent applies (pure client UI). Server-side, the new `23503` branch mirrors the existing `23505` branch shape at `kb-share.ts:316`.

- **Repointing `KbChatContent.onClose` for the C4 caller could regress the markdown viewer.** Mitigation: the markdown viewer passes a *different* `onClose` (`closeSidebar` via `kb-desktop-layout.tsx:78` + `kb-mobile-layout.tsx:51`); only the C4 caller's `onClose` (`c4-workspace.tsx:126`) changes. AC7 + existing sidebar tests guard the markdown path.
- **Collapse that unmounts the Concierge loses the in-progress thread.** Mitigation: prefer keep-mounted + CSS-hide (mirror the existing `rightTab` comment at c4-workspace.tsx:121-122); AC6 asserts thread survival.
- **Client error copy echoing server strings = info leak / brand-jank.** Mitigation: AC2 asserts a hoisted generic constant, not the server payload.
- **`23503` mapping assumes the FK target (`workspaces` row) can legitimately be missing.** This is a hardening/telemetry improvement, not a guaranteed reproduction; mark the 23503 branch as defensive (it should be rare post-#4922's `resolveCurrentWorkspaceId` solo fallback). Do not over-invest — the user-visible fix is item 1a.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled with threshold `none` + sensitive-path scope-out reason.)
- New component tests MUST live under `test/**/*.test.tsx` — `vitest.config.ts` does not collect co-located `components/**/*.test.tsx` (verified `vitest.config.ts:60`).
- When mocking `next/navigation` for the new `c4-workspace.test.tsx`, stub `useSearchParams` alongside `useRouter`/`usePathname` (KbChatContent → ChatSurface needs all three) — see learning `2026-04-17-kb-chat-stale-context-on-doc-switch.md` Session Errors.
- `react-resizable-panels` in this repo is a fork using `Group`/`Panel`/`Separator` names (NOT upstream `PanelGroup`/`PanelResizeHandle`); match the names already used in `c4-workspace.tsx`.
- Do NOT relax `suppressSidebar` for C4 docs — it prevents the desktop side panel from mounting a second Concierge with the same `contextPath` (double-mount). The reveal control belongs inside the C4 workspace.

## Open Code-Review Overlap

None — no open `code-review`-labeled issue references `share-popover.tsx`, `kb-share.ts`, `c4-workspace.tsx`, or `kb-chat-content.tsx` (checked the share/c4/chat surface; #3223 is a P3 dead-className issue on `prose-kb`, unrelated to these files).
