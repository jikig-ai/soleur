# Learning: WSErrorCode has a second canonical copy in ws-zod-schemas, and a new mount-fetch breaks sibling blanket-no-fetch tests

## Problem

While adding `repo_setup_failed` to the `WSErrorCode` union for the #5394 Concierge
dispatch readiness gate, two recurring traps surfaced — both caught by the
authoritative gates (tsc + full-suite exit), but each cost a debug cycle that a
sharper sweep would have avoided:

1. **`WSErrorCode` lives in TWO canonical sources, not one.** The TS union is in
   `apps/web-platform/lib/types.ts`, but the wire schema has an INDEPENDENT copy
   of the same string set as a `z.enum([...])` in
   `apps/web-platform/lib/ws-zod-schemas.ts` (`errorSchema.errorCode`). The
   `cq-union-widening-grep-three-patterns` sweep over `lib/ws-client.ts` +
   `components/` does NOT surface the zod copy (it's a producer-side schema, not
   a consumer `===` branch). Widening only `types.ts` compiles the type but fails
   `tsc` at the `_SchemaCovers`/`WSMessage`-assignability proof
   (`ws-zod-schemas.ts` ~line 661) because the zod enum no longer covers the
   widened union. The zod enum also carries codes the TS union omits
   (`delegation_*`), confirming the two drift independently.

2. **Adding a mount-time fetch to a shared chat component breaks sibling page
   tests that assert blanket `expect(fetchSpy).not.toHaveBeenCalled()`.** Wiring
   `useActiveRepo()` (a `/api/workspace/active-repo` poll) into `chat-surface.tsx`
   made `chat-page.test.tsx`'s two `?context=` "no KB fetch" tests fail — they
   used a blanket no-fetch assertion that the new unrelated mount fetch trips. The
   touched-file test loop never ran `chat-page.test.tsx` (it doesn't import the
   changed files directly); only the **full-suite exit gate** caught it.

## Solution

1. **When widening `WSErrorCode`, edit BOTH `lib/types.ts` AND
   `lib/ws-zod-schemas.ts` in the same change**, then `tsc --noEmit` — the
   `_SchemaCovers` bidirectional proof fails closed if either side drifts. Treat
   `WSErrorCode` as a replicated-literal pair, not a single source. The canonical
   sweep for a `WSErrorCode` widening is:
   `git grep -nE '"<new_code>"|WSErrorCode' apps/web-platform/lib/types.ts apps/web-platform/lib/ws-zod-schemas.ts apps/web-platform/lib/ws-client.ts apps/web-platform/components/`.

2. **When a shared component gains a new mount-time fetch, grep sibling page
   tests for blanket `expect(fetchSpy).not.toHaveBeenCalled()` and narrow them to
   the specific URL they care about** (filter out the new unrelated call) in the
   same PR. The fix shape:
   `fetchSpy.mock.calls.filter(([url]) => typeof url === "string" && !url.includes("/api/workspace/active-repo"))` then assert `.toHaveLength(0)`.

## Key Insight

A union/enum widening sweep must cover **producer-side schemas (zod), not just
consumer `===` branches** — the `_SchemaCovers` proof is the backstop, but the
sweep should pre-empt it. And a blanket `not.toHaveBeenCalled()` on `fetch` is a
latent trip-wire for any future mount-time fetch added to a shared component
the test transitively renders; the authoritative catch is the full-suite exit
gate, never the touched-file loop.

## Session Errors

- **WSErrorCode widening missed the ws-zod-schemas.ts zod copy** — Recovery:
  tsc's `_SchemaCovers` proof failed; added `repo_setup_failed` to the zod enum.
  Prevention: sweep both `types.ts` + `ws-zod-schemas.ts` for any `WSErrorCode`
  widening (above).
- **chat-page.test.tsx blanket no-fetch assertions broke on the new
  useActiveRepo mount fetch** — Recovery: narrowed both assertions to "no
  KB-content fetch" by filtering the active-repo URL. Prevention: grep sibling
  page tests for blanket no-fetch assertions when adding a shared-component mount
  fetch.
- **AC9 sanitization gap (one-off)** — the plan's Phase-1 evaluator prose said
  "reason via parseErrorPayload" but AC9 required no raw-stderr/path leak; the
  RED test caught that a legacy plain-stderr row would leak. Recovery: added
  `sanitizeGitStderr` on top of `parseErrorPayload` in the evaluator. Prevention:
  when a plan's implementation prose and its AC disagree on a security property,
  follow the AC.
- **Failed Edit + over-claimed commit message (one-off)** — an Edit on
  `ws-start-session-cap-hit.test.ts` failed (file not Read first) and was never
  re-applied; the file was `git add`ed (no-op) and the commit message claimed a
  4-file mock sweep (actual: 3). The file didn't need the export (doesn't reach
  the factory). Prevention: after a failed Edit, verify `git status` shows the
  file modified before claiming it in a commit message.

## Tags
category: integration-issues
module: apps/web-platform (ws wire schema, chat surface)
issue: 5394
