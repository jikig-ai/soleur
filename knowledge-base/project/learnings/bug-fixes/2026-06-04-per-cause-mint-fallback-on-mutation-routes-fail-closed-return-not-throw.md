---
title: "Per-cause tenant-mint fallback on mutation routes: positive allow-list + return-not-throw"
date: 2026-06-04
category: bug-fixes
module: apps/web-platform/server/kb-route-helpers.ts
issue: 4914
pr: 4919
tags: [auth, tenant-jwt, service-role, fail-closed, kb-routes, runtime-auth-error]
related:
  - knowledge-base/project/learnings/bug-fixes/2026-06-04-tenant-mint-failure-needs-self-row-service-role-fallback.md
  - knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md
---

# Per-cause tenant-mint fallback on mutation routes

## Problem

`authenticateAndResolveKbPath` (the KB file PATCH/DELETE *mutation* helper) 503'd on
**any** tenant-JWT mint failure, dead-ending a founder's KB file rename/delete during a
transient mint blip (`jwt_mint`) or a 60/hr ceiling trip (`rotation`). This is the same
brand-survival dead-end PR #4913 fixed for the share button's `resolveUserKbRoot` — but
#4913 deliberately scoped this sibling **out** because it gates a mutation, not a read.

## Solution

A **per-cause** fallback on `RuntimeAuthError.cause`, diverging from #4913's all-causes shape:

- `jwt_mint` | `rotation` (availability failures) → fall back to a service-role read of the
  caller's own row (`.eq("id", user.id)`, server-derived) and let the mutation proceed.
- `denied_jti` (deliberate revocation) + **any future un-named cause** → fail CLOSED with
  `err(403, "Access denied")`.

## Key Insights (reusable)

1. **On a mutation route, branch on the POSITIVE allow-list of availability causes, not a
   negated `!== "denied_jti"`.** `if (cause === "jwt_mint" || cause === "rotation") { fallback }
   else { 403 }` makes a hypothetical future 4th `RuntimeAuthError.cause` fail CLOSED (the safe
   default when the fallback would otherwise let a revoked/unknown token proceed to mutate). The
   negated form fails OPEN. The read-route sibling (`resolveUserKbRoot`) can safely fall back for
   all causes only because its privileged write (`createShare`) was *already* service-role — the
   deny-list never gated a privileged action there.

2. **The fail-closed arm MUST RETURN a Response, never throw.** Both route handlers
   (`app/api/kb/file/[...path]/route.ts` DELETE + PATCH) call this helper **outside** their `try`
   block. A thrown `RuntimeAuthError` would escape to Next.js → an uncontrolled 500. Always check
   the call-site try-boundary before choosing throw-vs-return in a shared helper.

3. **`reportSilentFallback` fires for EVERY cause (incl. `denied_jti`) BEFORE the branch**, so a
   chronic mint failure AND a revocation hit both stay Sentry-visible
   (`cq-silent-fallback-must-mirror-to-sentry`).

4. **Inline the per-cause branch; do NOT extract a shared `resolve…(userId, policy)` helper.** A
   `policy` parameter re-couples two call sites whose entire reason for separate existence is
   divergent revocation semantics — and is the exact seam a future maintainer "simplifies" to
   re-introduce the `denied_jti` bypass. Six agents concurred (architecture-strategist explicitly).

5. **Test non-vacuity:** give the service-role mock a DISTINCT `workspace_path` from the tenant
   mock so the *value* assertion proves provenance, not just a `mockFrom not called` negative.

## Session Errors

1. **`vitest -t "...(#4914)"` filter matched 0 tests** — `#`/parens in the test-name filter
   matched nothing (43 skipped). **Prevention:** filter on a plain alphanumeric substring of the
   describe name, not one containing regex/shell metacharacters.
2. **`cd apps/web-platform` → "No such file or directory"** — the Bash tool persists CWD across
   calls, so a prior `cd apps/web-platform` left the shell already inside it. **Prevention:** chain
   `cd <absolute-path> && <cmd>` in a single call (already in the work-skill guidance) or use
   absolute paths.
3. **Plan `Edit` → "File has been modified since read"** after an in-band `sed` mutated the file.
   **Prevention:** re-read a file after any non-Edit mutation (sed/awk) before Editing it.
