# Learning: Playwright-MCP visual verification of an authenticated Next.js dashboard on a local dev server

## Problem

A chat-input alignment fix needed live visual verification of the authenticated
`/dashboard` first-run surface (not just unit-tested className contracts). The
dashboard is gated behind Supabase auth + an onboarding funnel
(accept-terms → setup-key → billing), and the Playwright MCP server runs in a
restricted sandbox. Getting a single real screenshot took several dead-ends.

## Solution (reusable recipe)

To screenshot an authenticated web-platform surface locally via Playwright MCP:

1. **Start the dev server on an alternate port AND allowlist it for CSRF.** The
   operator may already hold port 3000. Use
   `PORT=3099 NEXT_PUBLIC_DEV_EXTRA_ORIGINS=http://localhost:3099 doppler run -p soleur -c dev -- npm run dev`.
   Without `NEXT_PUBLIC_DEV_EXTRA_ORIGINS`, every state-mutating POST (e.g.
   `/api/accept-terms`) returns **403** via `lib/auth/validate-origin.ts`
   (`[validate-origin] CSRF: rejected origin`). The allowlist builder only
   trusts `https://app.soleur.ai`, `http://localhost:3000`,
   `NEXT_PUBLIC_APP_URL`, and the comma list in `NEXT_PUBLIC_DEV_EXTRA_ORIGINS`.
2. **Mint a session cookie with the existing bot.** Dev Doppler has
   `UX_AUDIT_BOT_EMAIL`/`UX_AUDIT_BOT_PASSWORD`. Run
   `UX_AUDIT_STORAGE_STATE=<abs>/storage-state.json NEXT_PUBLIC_APP_URL=http://localhost:3099 doppler run -p soleur -c dev -- bun plugins/soleur/skills/ux-audit/scripts/bot-signin.ts`.
   `NEXT_PUBLIC_APP_URL=http://localhost:3099` makes the cookie domain `localhost`.
3. **Inject the cookie via `page.context().addCookies()`** — the MCP has no
   storageState option per call. The `browser_run_code_unsafe` sandbox has **no
   `require`, no `Buffer`, no `atob`** — pre-escape the cookie with Node
   (`node -e "...JSON.stringify(c.value)..."`) and embed the literal in the
   function body. Supabase `@supabase/ssr` accepts the raw-JSON cookie value
   `bot-signin.ts` writes (no `base64-` prefix needed for this version).
4. **Drive onboarding gates via `fetch()`, not UI clicks.** The accept-terms
   checkbox uses controlled React state that Playwright's `.check()` doesn't
   trigger (the submit button stays disabled). Instead:
   `page.evaluate(() => fetch('/api/accept-terms', {method:'POST', body:'{}', credentials:'same-origin'}))`.
5. **Pre-warm slow-compiling routes with `curl` before navigating.** A first-hit
   `/dashboard` compile (~8–18 s) exceeds the MCP navigation tool's window and
   closes the page (`Target page, context or browser has been closed`). `curl`
   the route twice first, then `browser_navigate`. Keep cookie-set and
   navigation in **separate** tool calls — a single long `run_code` that both
   adds cookies and navigates also trips the close.
6. **Clean up:** the storage-state file holds a live session token — `rm` it,
   never commit. The MCP saves screenshots to its own CWD (the bare-repo root),
   not the worktree — find + remove strays.

The dashboard first-run state (`"Tell your organization what you're building"`)
only renders for an account with **no** conversations — the ux-audit bot fixture
*seeds* conversations, so do NOT seed it when verifying the first-run surface.

## Key Insight

Authenticated-surface visual verification is gated by three orthogonal things —
**CSRF origin allowlist**, **session cookie injection**, and **onboarding funnel
state** — none of which the className unit tests touch. When the funnel can't be
fully satisfied locally (no BYOK key / billing), verify the reachable surface
(here: first-run dashboard) and rely on shared-component construction + unit
tests for the rest (the chat `ChatInput` shares the exact box construction the
dashboard box was verified to render correctly).

## Session Errors

1. **Bash CWD does not persist across tool calls** — Recovery: absolute paths or
   single `cd <abs> && <cmd>`. Prevention: never assume a prior `cd` holds; the
   work skill already documents this (`cd <worktree-abs> && <cmd>` in one call).
2. **Playwright `browser_run_code_unsafe` sandbox lacks `require`/`Buffer`/`atob`**
   — Recovery: pre-escape data with Node into a literal embedded in the function.
   Prevention: treat the sandbox as bare ES with `page` only; marshal all data
   in as pre-built literals.
3. **MCP browser closes on slow first-compile navigation** — Recovery: `curl`
   pre-warm + split cookie-set from navigate. Prevention: pre-warm any route
   expected to compile >5 s before `browser_navigate`.
4. **accept-terms POST 403 CSRF on alt port** — Recovery:
   `NEXT_PUBLIC_DEV_EXTRA_ORIGINS=<origin>` + restart. Prevention: set it
   whenever serving on a non-3000 port for Playwright.
5. **React controlled-checkbox `.check()` left submit disabled** — Recovery: POST
   the API directly via `page.evaluate(fetch(...))`. Prevention: for onboarding
   gates, prefer the API call over UI when only the side effect is needed.
6. **tsc false-positive from stale `.next/types`** (dev-server-generated route
   types for an untouched layout) — Recovery: `rm -rf .next/types` then re-run.
   Prevention: after running the dev server, clear `.next/types` before trusting
   a `tsc --noEmit` failure in a `.next/types/**` path.
7. **Orphan test suite asserted the old `min-h-[44px]`** (`command-center.test.tsx`,
   not in the touched-file set) — Recovery: updated to `36px` + strengthened to
   assert input/button height parity. Prevention: working as designed — the work
   Phase 2 full-suite exit gate exists for exactly this; the touched-file inner
   loop would have missed it.
8. **Edit failed "File has not been read yet"** on `constants.ts` — Recovery:
   Read before Edit. Prevention: Read-before-Edit is an existing hard rule.

## Tags
category: integration-issues
module: web-platform / playwright-mcp / auth
