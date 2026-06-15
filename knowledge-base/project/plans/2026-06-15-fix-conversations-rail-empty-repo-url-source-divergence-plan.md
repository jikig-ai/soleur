---
title: "fix: Recent Conversations rail empty — repo_url source-of-truth divergence (users vs workspaces)"
type: fix
date: 2026-06-15
branch: feat-one-shot-recent-conversations-rail-empty
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: Recent Conversations rail shows empty state while user is in an active conversation

## Overview

The **Recent Conversations** rail (`components/chat/conversations-rail.tsx`, fed by the
`useConversations` hook in `hooks/use-conversations.ts`) renders the empty state
**"No conversations yet. — Start one →"** even when the user is actively chatting with the
Soleur Concierge. The active conversation — and all recent ones — never appear.

**Root cause (confirmed by repo research, ADR-044, and 6 institutional learnings):
a `repo_url` source-of-truth divergence.**

- **Server (write path):** `createConversation` in `server/ws-handler.ts:855` stamps every
  new conversation with `repo_url = await getCurrentRepoUrl(userId)`. Per ADR-044's
  read-cutover, `getCurrentRepoUrl` (`server/current-repo-url.ts:29`) reads the source of
  truth — **`workspaces.repo_url`** resolved via the active workspace
  (`resolveCurrentWorkspaceId` → `user_session_state.current_workspace_id`, solo fallback
  `= userId`). It explicitly does **not** read `users.repo_url` ("to avoid the
  dual-ownership divergence trap", `current-repo-url.ts:20-27`).

- **Client (read path):** `useConversations` (`hooks/use-conversations.ts:121-147`) scopes
  the list query by reading the **deprecated** `users.repo_url` column directly
  (`supabase.from("users").select("repo_url")`), and **hard-returns an empty list**
  (`setConversations([])`) when that value is null (`:143-147`). The list query then filters
  `.eq("repo_url", currentRepoUrl)` (`:154`).

When `users.repo_url` is null or has diverged from `workspaces.repo_url`, the rail filters
out the active conversation and shows the empty state. This is guaranteed for a **joined
workspace member** (whose own `users.repo_url` is empty — the exact #4543 wrong-repo bug
restated at the UI layer, per `api/workspace/active-repo/route.ts:9-11`), and for any user
whose repo state lives only in `workspaces` post-ADR-044.

**RLS does not and cannot salvage this:** the conversations SELECT policies
(`075_conversation_visibility.sql:55-61`: `conversations_owner_select` =
`user_id = auth.uid()`, plus `conversations_shared_select`) contain **no `repo_url`
predicate**. The empty list is produced 100% by the client-side app-filter, and the
`setConversations([])` early-return fires *before* the RLS-scoped query even runs.

**The fix:** make the client read the repo scope from the canonical
**`GET /api/workspace/active-repo`** route (which resolves `workspaces.repo_url` via the
active workspace and self-heals revocation, per ADR-044) instead of reading `users.repo_url`.
This is the established client pattern — `hooks/use-active-repo.ts` already consumes that
exact route for the live-repo badge.

This is the **only** client-side read of `users.repo_url` for repo scoping
(repo-research confirmed; `use-onboarding.ts` reads `users` but only UI-state columns, not
repo columns). Scope is one hook + its tests + a thin coalesced fetch.

## User-Brand Impact

**If this lands broken, the user experiences:** the Recent Conversations rail keeps showing
"No conversations yet" forever — the user cannot navigate back to any prior conversation
with the Concierge from the nav rail, making the product feel like it forgets every session.
A regression here (e.g. fetching the wrong workspace's repo) could surface *another* user's
conversations in the rail.

**If this leaks, the user's workflow/data is exposed via:** showing conversation titles +
previews scoped to the wrong `repo_url`/workspace would leak conversation content across
workspaces. The active-repo route already gates this server-side (resolves the caller's OWN
active workspace, RLS gates conversation rows by `user_id`/workspace membership), so the fix
must route through that boundary and never reintroduce a client-trusted workspace id.

**Brand-survival threshold:** single-user incident — a single user seeing an empty rail
while mid-conversation (or, worse, seeing someone else's conversations) is a brand-damaging
incident on its own. `requires_cpo_signoff: true` set; `user-impact-reviewer` runs at review.

## Research Reconciliation — Spec vs. Codebase

| Claim (from issue / hypothesis) | Reality (verified) | Plan response |
| --- | --- | --- |
| "conversation isn't persisted until some event" | False — `createConversation` persists immediately on first dispatch (`ws-handler.ts:855`); it even aborts with an error if no repo is connected (`:828`). | No persistence change needed. |
| "list query is scoped/filtered such that the in-progress conversation is excluded" | True, and the discriminating filter is `repo_url` read from the wrong table — not status/visibility/archive. | Fix the repo_url *source*, not the filter logic. |
| "a fetch is failing silently" | Partially — `getCurrentRepoUrl` (server) returns null on transient auth error → would abort conversation insert, not the rail; the rail's silent failure is the `users.repo_url` null early-return. | Route client read through `/api/workspace/active-repo`, which returns last-known on transient null (`use-active-repo.ts:38-44`). |
| RLS scopes the list by repo, so app-filter is redundant | False — RLS (`075`) scopes by `user_id`/workspace only; the app-level `repo_url` filter is load-bearing for repo-swap isolation (`use-conversations.ts:116-120`, plan `2026-04-22-fix-command-center-stale-conversations-after-repo-swap`). | Keep the `repo_url` filter; only correct its *source*. |
| `use-conversations.ts:146` still filters `.eq("user_id")` (learning #2) | Stale — the user_id filter was already removed from the list query (`:149-156`, "no app-level user_id filter needed"). Remaining `.eq("user_id")` are on the realtime channel + updateStatus write, which are correct. | No change to the user_id sites; confine fix to the repo_url read. |

## Hypotheses

1. **(Primary — confirmed) `users.repo_url` ≠ `workspaces.repo_url`.** Client reads the
   deprecated per-user column; server stamps conversations with the per-workspace column.
   Joined members and post-ADR-044 users hit null/divergent `users.repo_url` → empty rail.
   *Evidence:* `current-repo-url.ts:20-27`, `ws-handler.ts:825-859`,
   `use-conversations.ts:121-147`, ADR-044, `api/workspace/active-repo/route.ts:9-11`.
2. **(Secondary) Null `users.repo_url` early-return.** Even when `workspaces.repo_url` is
   set, a null `users.repo_url` triggers `setConversations([])` at `:143-147`. Same root,
   same fix.

## Files to Edit

- **`apps/web-platform/hooks/use-conversations.ts`** — replace the `users.repo_url` read
  (`:121-147`) with a fetch to `GET /api/workspace/active-repo`; derive `currentRepoUrl`
  from the route's `repoUrl` field (already normalized server-side) and `workspaceId` from
  the route's `workspaceId` field (replacing the `workspace_members` read at `:127-133`).
  Keep `setConversations([])` early-return when `repoUrl` is null (a user with no connected
  repo genuinely has no scoped conversations). Keep the normalize-on-read as defense-in-depth
  but the route already returns normalized. Keep the realtime subscriptions and the
  `repoUrlRef` mirror unchanged in shape; feed them from the new source. **Drift safeguard:**
  add a code comment citing ADR-044 + this plan so the next reader doesn't re-introduce the
  `users.repo_url` read.
- **`apps/web-platform/test/conversations-rail.test.tsx`** — extend/verify coverage:
  rail renders rows when the active-repo route returns a `repoUrl`; renders the empty state
  only when `repoUrl` is null. (Currently mocks `useConversations`; add/confirm a case for
  the populated path.)
- **`apps/web-platform/test/api-conversations.test.ts`** *(or the closest existing hook
  test — see Sharp Edges for runner/glob verification)* — add a hook-level RED→GREEN test:
  given `/api/workspace/active-repo` returns `{ repoUrl: "...", workspaceId: "..." }` and a
  conversation row stamped with that `repoUrl`, the hook surfaces the conversation (today it
  would be filtered out because `users.repo_url` is null). This is the regression that locks
  the fix.

## Files to Create

- *(Possibly none.)* Prefer reusing the coalesced fetch helper pattern from
  `hooks/use-active-repo.ts`. **Decision for /work:** if `useConversations` and
  `useActiveRepo` would both fetch `/api/workspace/active-repo`, extract the coalesced
  `fetchActiveRepoCoalesced()` into a tiny shared module (e.g.
  `hooks/active-repo-fetch.ts`) and have both import it, rather than duplicating the
  in-flight latch. Otherwise call the route inline. Do not add a new API route — the
  canonical one already exists.

## Open Code-Review Overlap

Run at /work after the file list is final:
```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
# then per path:
jq -r --arg path "hooks/use-conversations.ts" \
  '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' \
  /tmp/open-review-issues.json
```
None known at plan time (no open code-review issue grep run yet — /work must run the above
for `hooks/use-conversations.ts`, `test/conversations-rail.test.tsx`,
`test/api-conversations.test.ts` and fold-in / acknowledge / defer each match).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (root fix):** `hooks/use-conversations.ts` contains **no**
  `.from("users").select("repo_url")` read. Verify:
  `git grep -n 'from("users")' apps/web-platform/hooks/use-conversations.ts` returns 0 lines
  referencing `repo_url`.
- [ ] **AC2 (correct source):** `hooks/use-conversations.ts` derives `currentRepoUrl` from
  `GET /api/workspace/active-repo`. Verify:
  `git grep -n 'workspace/active-repo' apps/web-platform/hooks/use-conversations.ts` returns
  ≥1 line.
- [ ] **AC3 (workspace source):** the workspace id used for the workspace-shared realtime
  channel comes from the active-repo route's `workspaceId`, not a separate
  `workspace_members` client read. Verify the `workspace_members` read at the former
  `:127-133` is gone:
  `git grep -n 'from("workspace_members")' apps/web-platform/hooks/use-conversations.ts`
  returns 0.
- [ ] **AC4 (regression test — RED before, GREEN after):** the hook-level test asserts the
  active conversation appears when the active-repo route returns its `repoUrl` and the
  conversation row carries the same `repoUrl`; the test FAILS against the pre-fix hook and
  PASSES against the fixed hook. (Confirm the RED by stashing the fix or by a `git stash`
  of the hook edit during /work.)
- [ ] **AC5 (empty-state preserved):** rail still shows the empty state when the route
  returns `repoUrl: null` (no connected repo) — verified by
  `test/conversations-rail.test.tsx`.
- [ ] **AC6 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  exits 0. (NOT `npm run -w` — repo root declares no workspaces field.)
- [ ] **AC7 (targeted tests):** run the conversations test suite via the package's actual
  runner — `cd apps/web-platform && ./node_modules/.bin/vitest run test/conversations-rail.test.tsx <hook-test-path>`
  — all pass. (Confirm the file path matches `vitest.config.ts` `include` globs before
  running; see Sharp Edges.)
- [ ] **AC8 (no other divergent reads):**
  `git grep -rn 'from("users")' apps/web-platform/hooks apps/web-platform/components | grep repo_url`
  returns 0 (confirms no sibling client-side `users.repo_url` repo-scoping read was missed).

### Post-merge (operator)

- [ ] **AC9 (deploy verification — automatable):** the web-platform release pipeline
  (`web-platform-release.yml`) auto-restarts the container on merge to main touching
  `apps/web-platform/**`; merge IS the remediation. No separate operator restart step.
- [ ] **AC10 (live smoke — automatable via Playwright MCP):** as a connected user, open the
  chat shell, confirm the active conversation appears in the Recent Conversations rail.
  *Automation:* Playwright MCP against the dev deploy. (Plan-time note: route through
  `/soleur:qa` or `test-browser` at ship time, not a manual operator click.)

## Domain Review

**Domains relevant:** Product (UI surface — existing component modified)

### Product/UX Gate

**Tier:** advisory — this modifies the data source feeding an existing rail component; it
adds no new user-facing page, flow, modal, or interactive surface. The visible change is
that the rail now *correctly* populates. Mechanical UI-surface override check: `Files to
Edit` touches `components/chat/conversations-rail.tsx`? No — only the hook + tests. The
component file is unchanged. So no new `components/**/*.tsx` file is created → not forced to
BLOCKING.
**Decision:** auto-accepted (pipeline) — bug fix restoring intended behavior of an existing
surface; no new flow to wireframe.
**Agents invoked:** none (advisory, pipeline)
**Skipped specialists:** ux-design-lead — N/A (no new UI surface; existing component
behavior restoration, not a new page/flow). copywriter — none (the empty-state copy "No
conversations yet. — Start one" is unchanged).
**Pencil available:** N/A (no UI surface created)

#### Findings

No cross-domain implications beyond Product. The fix is a data-source correction. CPO
sign-off is required at plan time per `requires_cpo_signoff: true` (single-user-incident
threshold) — confirm CPO has reviewed the User-Brand Impact framing before `/work`.

## Infrastructure (IaC)

Skipped — pure code change against an already-provisioned surface. No new server, secret,
vendor, cron, DNS, or persistent runtime process. Edits are confined to
`apps/web-platform/hooks/` and `apps/web-platform/test/`; the consumed API route already
exists.

## Observability

```yaml
liveness_signal:
  what: existing conversations rail render + /api/workspace/active-repo 200s
  cadence: per chat-shell mount (client) / per request (route)
  alert_target: existing web-platform Sentry project (no new monitor)
  configured_in: apps/web-platform/infra/sentry/
error_reporting:
  destination: Sentry (client error boundary + route-level reportSilentFallback already in current-repo-url.ts / workspace-resolver.ts)
  fail_loud: the hook already sets `error` state on query failure (use-conversations.ts:175); the active-repo fetch returns last-known on transient null (no silent data loss). Keep both.
failure_modes:
  - mode: /api/workspace/active-repo returns non-200 (transient)
    detection: hook keeps last-known repoUrl (use-active-repo precedent) — no empty-rail flash; route errors already mirror via reportSilentFallback in current-repo-url.ts
    alert_route: Sentry (existing repo-scope op slugs)
  - mode: route returns repoUrl=null for a genuinely-disconnected user
    detection: rail shows empty state (correct behavior, not a failure)
    alert_route: none (expected)
  - mode: conversations list query error
    detection: hook sets error state (use-conversations.ts:175); surfaced in UI
    alert_route: client Sentry
logs:
  where: Sentry (client) + existing reportSilentFallback ops (repo-scope feature) in workspaces resolver path
  retention: existing Sentry retention
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/conversations-rail.test.tsx <hook-test-path>"
  expected_output: "all conversations rail tests pass (populated + empty-state paths)"
```

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the
  threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled with concrete
  artifact/vector/threshold — keep it that way through revisions.
- **Test runner is vitest, not bun test.** `apps/web-platform/bunfig.toml` may block bun
  test discovery. Use `./node_modules/.bin/vitest run <path>`. Typecheck is in-package
  `tsc --noEmit`, NOT `npm run -w apps/web-platform typecheck` (repo root has no
  `workspaces` field → `-w` aborts).
- **Vitest `include` globs only collect `test/**/*.test.ts(x)`** per
  `apps/web-platform/vitest.config.ts`. A co-located `hooks/*.test.ts` is silently never
  run. Place the new hook regression test under `test/` and `grep` the `include:` globs
  before fixing the path. Confirm whether an existing hook test
  (`test/use-conversations-limit.test.tsx`) is the right home for the regression case rather
  than authoring a duplicate — `git grep -l "use-conversations" apps/web-platform/test/`
  first.
- **Do not reintroduce `users.repo_url` as a fallback.** ADR-044 forbids a `users` read-time
  fallback ("Repo reads come from `workspaces` only"). The route is the single source.
- **Realtime workspace-shared channel** depends on `workspaceId`. The active-repo route
  returns the resolved (self-healed) `workspaceId` — use it so the realtime channel and the
  list query agree on the same workspace; do not keep a separate `workspace_members` read
  that could resolve a different workspace than the route's J5-corrected claim.
- **Fetch coalescing:** if both `useConversations` and `useActiveRepo` fetch the route, share
  one in-flight latch (extract `fetchActiveRepoCoalesced`) to avoid duplicate GETs + duplicate
  J5 corrective writes on mount (the route performs a corrective write on revocation).
- **RED test must actually be RED first.** The fix is "swap the read source"; an easy
  failure mode is writing a test that passes against both old and new code. Drive the test
  from a mocked active-repo route returning a `repoUrl` while the (simulated) `users.repo_url`
  is null — the pre-fix hook returns `[]`, the fixed hook returns the row.

## Test Scenarios

1. Connected user, single active Concierge conversation → rail lists it (currently: empty).
2. Connected user, `users.repo_url` null but `workspaces.repo_url` set (joined member) →
   rail lists the conversation (currently: empty — the core bug).
3. Disconnected user, route returns `repoUrl: null` → rail shows empty state (preserved).
4. Transient route failure (non-200) → rail keeps last-known, no empty flash.
5. Repo swap: route returns a new `repoUrl` → list re-scopes; old-repo conversations hidden
   (preserves `2026-04-22` repo-swap isolation invariant).
6. Realtime UPDATE on a workspace-shared conversation in the resolved `workspaceId` → row
   updates in place.

## References

- `apps/web-platform/server/current-repo-url.ts:20-73` — ADR-044 read-cutover, source of truth.
- `apps/web-platform/server/ws-handler.ts:813-865` — `createConversation` repo_url stamp.
- `apps/web-platform/hooks/use-conversations.ts:121-156` — the buggy `users.repo_url` read.
- `apps/web-platform/app/api/workspace/active-repo/route.ts` — canonical client repo source.
- `apps/web-platform/hooks/use-active-repo.ts` — client consumer precedent (coalesced fetch).
- `apps/web-platform/supabase/migrations/075_conversation_visibility.sql:55-61` — RLS (no repo predicate).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`.
- `knowledge-base/project/learnings/2026-05-27-client-server-rls-mismatch-post-workspace-sweep.md` — names this hook.
- `knowledge-base/project/learnings/2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md` — audit all conversation queries.
- `knowledge-base/project/learnings/security-issues/2026-05-28-dual-write-mirror-must-fail-closed-on-credential-clear.md` — read-path divergence.
