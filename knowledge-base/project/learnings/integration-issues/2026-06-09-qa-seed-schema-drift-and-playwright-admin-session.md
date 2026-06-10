# Learning: QA seed scripts rot against migrations; Playwright MCP admin-session injection pattern

**Date:** 2026-06-09
**PR:** #5083 (feat-one-shot-analytics-nav-content-gutter)
**Category:** integration-issues

## Problem

Completing the AC7 visual check for the analytics gutter fix required an
admin-authenticated Playwright session against a local dev server. Three
independent obstacles surfaced:

1. **`scripts/seed-qa-user.sh` was broken-at-birth and had rotted further.**
   It failed at five successive points: `repo_status: "connected"` was never a
   valid value (CHECK from migration 011 predates the script), `api_keys.iv`/
   `auth_tag` NOT NULL (004), `conversations.workspace_id` NOT NULL (059),
   `messages.template_id` NOT NULL (053), and PostgREST batch inserts reject
   mixed key sets (`PGRST102: All object keys must match` — user-role rows
   lacked `leader_id`). A sixth, argv-dependent bug: `\\$12,500` inside the
   double-quoted JSON heredoc expanded `$1` (the `--port` arg) producing the
   invalid JSON escape `\-` — the script's behavior depended on its own argv.
2. **Playwright MCP sandbox constraints.** `browser_run_code_unsafe` snippets
   run with NO `Buffer` and NO `atob`, and `filename:` loads are restricted to
   the repo-root allowed paths (`/tmp` is rejected).
3. **A running `next dev` server poisons `tsc --noEmit`.** Dev-server-generated
   `.next/types` made the typecheck fail with TS2344 (`OmitWithTag`) on a
   pre-existing non-route export in `(dashboard)/layout.tsx` — unrelated to the
   diff; a clean checkout (CI) passes.

## Solution

1. **Seed script repaired against live schema** (verify each seeded column
   against `supabase/migrations/`): `repo_status=ready`, dummy base64
   `iv`/`auth_tag` (decrypt-poisoned by design — GCM can never verify, so the
   row drives "key on file" UI without a usable key), workspace looked up via
   `workspace_members?role=eq.owner`, `template_id=default_legacy` (the 053
   backfill sentinel production writers use), explicit `"leader_id":null` on
   user rows so batch keys match, and `\$` instead of `\\$` for dollar
   literals. Review added: `DOPPLER_CONFIG=dev` guard (env var names are
   identical in prd!), `workspaces.repo_status` mirror (post-ADR-044 the
   KB/sync read path gates on the workspace row, not users), idempotent
   conversation seeding, 0600 perms on the session-token file.
2. **Admin session injection without mutating Doppler:**
   - Dev server: `doppler run -p soleur -c dev -- bash -c
     'ADMIN_USER_IDS="$ADMIN_USER_IDS,<qa-user-id>" PORT=3099 npm run dev'` —
     the inner `bash -c` lets the override compose with Doppler-injected env.
   - Cookie: the password-grant session JSON works raw as the
     `sb-<ref>-auth-token` cookie value via
     `encodeURIComponent(JSON.stringify(session))` through
     `page.context().addCookies(...)`.
   - Sandbox workarounds: write the snippet file under the repo root (not
     `/tmp`), and inline the session JSON as a JS object literal instead of
     base64-decoding (no `Buffer`/`atob` in the sandbox).
3. **Typecheck hygiene:** stop the dev server and `rm -rf .next` before
   trusting a local `tsc --noEmit` failure that points into `.next/types`.

## Key Insight

A QA seed script is a **schema consumer with no compiler**: every migration
that adds a NOT NULL column or CHECK constraint to a seeded table silently
breaks it, and nothing fails until someone needs QA state (usually mid-pipeline,
under time pressure). When repairing one, verify every seeded column against
the migrations directory, mirror what production writers emit (grep
`agent-runner.ts`/`cc-dispatcher.ts` for the same insert), and make each step
idempotent. And because the env-var names are identical across Doppler configs,
any service-role seed script MUST gate on `DOPPLER_CONFIG=dev`.

## Session Errors

1. **`$1: unbound variable` on documented no-args invocation** — Recovery:
   `"${1:-}"`. — Prevention: shellcheck passes this (it can't know `set -u`
   interactions are reachable); test the documented default invocation, not
   just the flagged one.
2. **Five sequential schema-drift failures in seed script** — Recovery: debug
   each curl with visible error body (`curl -s ... -w "HTTP=%{http_code}"`,
   never `-sf > /dev/null` while diagnosing). — Prevention: verify seeded
   columns against migrations before running; the `-sf`+`set -e` combination
   hides the PostgREST error JSON that names the exact violated constraint.
3. **Playwright MCP file access denied for `/tmp` snippet** — Recovery: write
   under the repo root (`.playwright-mcp/`). — Prevention: MCP file params
   resolve against the server's allowed roots (`hr-mcp-tools-playwright-etc-resolve-paths`).
4. **`Buffer is not defined`, then `atob is not defined` in
   `browser_run_code_unsafe`** — Recovery: inline JSON as a JS object literal.
   — Prevention: treat the snippet sandbox as bare ES — no Node globals, no
   DOM globals.
5. **`tsc --noEmit` false-fail from dev-server `.next/types`** — Recovery:
   stop server, `rm -rf .next`, re-run. — Prevention: run the typecheck gate
   before starting a dev server, or clean `.next` first when a failure points
   into generated types.
6. **Browser context recycled mid-session (cookie lost, redirect to /login)**
   — Recovery: re-inject cookie. — Prevention: one-off; re-injection is cheap.
7. **Screenshots + token-bearing snippet landed in the bare-repo root** —
   Recovery: moved screenshots to `/tmp`, deleted the snippet immediately
   after use. — Prevention: Playwright MCP writes relative outputs to its own
   root; never leave session-token-bearing files under the repo.

## Tags

category: integration-issues
module: web-platform / scripts / playwright-mcp
