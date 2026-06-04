---
title: "Condensed/collapsed affordance labels must match their ACTUAL action, not borrow a sibling's verb"
date: 2026-06-04
category: ui-bugs
module: web-platform/dashboard-nav
tags: [a11y, labels, collapsed-nav, review-finding, e2e-flake]
---

# Learning: condensed affordance labels must name what they DO, not what a richer sibling does

## Problem

While building the collapsed (56px) Knowledge Base rail affordance (sidebar-UX
follow-up Issue 6), the icon-only "sync" button was labeled **"Sync now"** —
borrowed from the expanded rail's `KbSyncStatus` control. But the collapsed
button's handler only called `refreshTree()` (a client-side refetch of
`/api/kb/tree`), whereas the real "Sync now" (`KbSyncStatus.handleSyncNow`)
**POSTs `/api/kb/sync`** with an in-flight `pending` guard and an error path.
Two controls sharing the label "Sync now" did materially different things; the
collapsed one silently skipped the actual repo sync.

Two independent review agents (code-quality-analyst + architecture-strategist)
flagged it as the one finding worth acting on. `tsc` and the new button's own
unit test passed green — the label/behavior mismatch is invisible to type-check
and to a test that only asserts the label exists.

## Solution

Relabel the collapsed button to **"Refresh file tree"** (accurate to
`refreshTree`) instead of duplicating the full sync POST + pending/error state
into a 56px icon button. The richer "Sync now" remains reachable via
`KbSyncStatus` once the rail is expanded. Updated the unit assertion to expect
the `/refresh/i` accessible name and renamed the test id `kb-rail-collapsed-sync`
→ `kb-rail-collapsed-refresh`.

## Key Insight

When you add a **condensed variant** of an existing affordance (collapsed rail,
overflow menu, compact toolbar), the temptation is to reuse the full version's
label. Don't — bind the label to the **handler you actually wired**, not to the
verb of the affordance you're echoing. The cheap gate at implementation time:
for every condensed control, read the handler and confirm the `aria-label`/text
names that exact action. If the condensed control does *less* than its sibling
(refetch vs sync, preview vs publish, draft vs send), the label must say the
lesser thing. This is the UI-label analogue of `hr-write-boundary-sentinel-sweep`:
the label is a contract with the user, and a borrowed contract over a weaker
action is a silent misrepresentation. See
[[2026-06-04-exactly-one-affordance-across-composition-boundary-needs-integration-count-assertion]]
for the sibling "two affordances, one state" class on the same nav rail.

## Session Errors

1. **nav-states e2e test #1 cold-compile flake.** The first authenticated hit to
   the heavy *expanded* `/dashboard/kb` route (mounts `FileTree` + `SearchOverlay`
   dynamic imports) exceeded the 30s `page.goto` timeout, then on a warm-but-still-
   compiling retry rendered a transient Next.js **404 shell** (`error-context.md`
   showed `heading "404"`). It is NOT an assertion failure — the diff never touched
   routing or the `rail-secondary-slot` it asserts on, and the test passes on retry
   against a fully-warm server (`--retries=2` → EXIT 0). **Recovery:** start a
   persistent auth dev server (PORT=3100 + the playwright auth env: `NEXT_PUBLIC_SUPABASE_URL=http://localhost:54399`,
   mock keys), let one authed request compile the route, then re-run (playwright
   reuses the existing server when not CI). **Prevention:** distinguish a
   cold-compile flake from a real regression by reading `test-results/**/error-context.md`
   — a rendered `404` page (or a bare `page.goto` timeout) is a compile/routing
   artifact; an assertion mismatch on real dashboard DOM is a regression. The two
   tests that exercise the actual diff (collapsed Settings Issue 4, collapsed KB
   Issue 6, both with the 56px no-overflow check) passed on first attempt.
2. **Dev-server cleanup needed multiple kills.** `kill <npm-run-dev-PID>` left the
   child `next-server` listening on 3100. **Prevention:** kill by port —
   `kill $(lsof -ti :3100)` — not by the `npm run dev` parent PID.
3. **Next.js multiple-lockfile workspace-root warning** (worktree has its own
   `package-lock.json` alongside the root one) — pre-existing environmental noise,
   not actionable here.

## Tags
category: ui-bugs
module: web-platform/dashboard-nav
