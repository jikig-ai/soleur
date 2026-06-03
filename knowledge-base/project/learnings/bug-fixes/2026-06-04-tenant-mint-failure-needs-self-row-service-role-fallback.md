# Learning: tenant-JWT-mint failure on a self-row read should fall back to service-role, not 503

## Problem

The "Generate link" button in the Share popover silently dead-ended — clicking it
bounced back to the identical idle panel instead of producing a `/shared/<token>`
link. Regression introduced by PR #3854 (`#3244` PR-C tenant migration, merged
2026-05-16), which changed `apps/web-platform/app/api/kb/share/route.ts:37` from
`resolveUserKbRoot(serviceClient, user.id)` → `resolveUserKbRoot(user.id)`.

After #3854, `resolveUserKbRoot` mints a **tenant-scoped JWT** internally
(`getFreshTenantClient` → full GoTrue `generateLink + verifyOtp`, gated by a
60/hr per-founder ceiling, migration 048) just to read the caller's own
`users.workspace_path`. On any mint failure it threw `RuntimeAuthError` and the
helper returned **503 "Workspace not ready"**. The client `generateLink`
callback (`share-popover.tsx`) resets to `status: "idle"` on any non-ok response
— so a transient mint failure or a ceiling trip rendered as "the button does
nothing." The GET path was unaffected (it uses `createServiceClient()` directly),
which is why the popover still opened — a classic POST-only regression where
"the popover opens fine" is NOT evidence the feature works.

## Solution

On `RuntimeAuthError`, fall back to a **service-role read of the user's own row**
(`createServiceClient().from("users").select(cols).eq("id", userId).single()`)
instead of returning 503. The same post-read validation (`workspace_status ===
"ready"` + `extras` null-check) runs on the fallback result, so a genuinely
not-ready workspace still 503s. `reportSilentFallback` still fires so a
chronically-failing mint stays visible in Sentry even though users recover.

Implementation: reassign `tenant = createServiceClient()` in the
`catch (mintErr instanceof RuntimeAuthError)` branch and let the existing
`.from("users")...` read + validation run unchanged against it. ~12 LOC.

## Key Insight

**A tenant-scoped JWT mint is the wrong dependency to put in front of a
self-row read whose downstream write is already service-role.** The ceiling
that makes the fallback safe for ALL three `RuntimeAuthError` causes
(`jwt_mint | rotation | denied_jti`, incl. the deliberate-revocation case):

1. The fallback read is hard-scoped `.eq("id", userId)` where `userId` is the
   already-authenticated session user (`supabase.auth.getUser()`), so even a
   deny-listed token can only ever read its OWN row — never another tenant's.
2. The privileged **write** on this path (`createShare`) was never tenant-scoped
   — it uses service-role at the route — so the deny-list never gated a
   privileged action here in the first place; `denied_jti` only blocked a
   self-read.

The deny-list's real purpose (blocking a replayed runtime JWT's cross-tenant
PostgREST reach) is fully preserved. When relaxing a defense, **name the new
ceiling explicitly in a code comment** (per
[[2026-05-05-defense-relaxation-must-name-new-ceiling]]) — the choice must be
explicit, not incidental.

**Caveat — mutation paths differ.** The sibling helper
`authenticateAndResolveKbPath` has the identical 503-on-mint-failure pattern but
serves file PATCH/DELETE *mutation* routes, where a `denied_jti` deny-list trip
IS meant to block the action. Do NOT blindly copy the fallback there — a
service-role fallback on a mutation path needs a per-cause adjudication
(fall back for `jwt_mint`/`rotation` availability failures only; re-throw on
`denied_jti`). Tracked in #4914; the unchanged helper now carries a NOTE comment
explaining the deliberate asymmetry.

## Test note

The existing test wired the tenant client and service-role client to the SAME
`mockFrom`, so a fallback assertion would pass **vacuously** (it couldn't prove
the service-role client — not the tenant client — produced the row). Fix: a
distinct `mockServiceFrom` wired only to `createServiceClient`, plus
`expect(mockFrom).not.toHaveBeenCalled()` counter-assertions so a regression
where the fallback silently reads via the tenant client fails the test.

## Session Errors

- **CWD-not-persisted vitest run** — ran a multi-file `./node_modules/.bin/vitest`
  sweep without `cd`-ing into `apps/web-platform` in the same Bash call →
  `EXIT=127 No such file or directory`. **Recovery:** re-ran as
  `cd <worktree>/apps/web-platform && ./node_modules/.bin/vitest …`.
  **Prevention:** already covered by the existing "Bash tool does NOT persist
  CWD; chain `cd <abs> && <cmd>`" rules — no new rule warranted.
- **Wrong `gh` label guess** — `gh issue create --label type/enhancement` failed
  ("not found"). **Recovery:** `gh label list` then used `type/chore` +
  `deferred-scope-out`. **Prevention:** verify labels against the live set
  before filing (one `gh label list` call). One-off.

## Tags
category: bug-fixes
module: apps/web-platform/server/kb-route-helpers
