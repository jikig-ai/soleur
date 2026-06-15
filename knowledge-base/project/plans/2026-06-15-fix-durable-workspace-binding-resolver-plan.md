---
title: "Durable workspace-binding resolver — eliminate getUserWorkspace 'No workspace binding' throw sites (AC4, #5240)"
type: fix
date: 2026-06-15
branch: feat-one-shot-5240-durable-workspace-binding-resolver
epic: "#5240"
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# 🐛 Durable workspace-binding resolver — eliminate `getUserWorkspace` "No workspace binding" throw sites

> **Sub-issue of OPEN epic #5240** (durable session/workspace resume). **Ref #5240 — do NOT `Closes`.** This closes the epic's **AC4** ("No consumer of `getUserWorkspace` throws 'No workspace binding' after a reconnect") and the `getUserWorkspace`-throw-site half of **design item #1**. It does NOT close #5240 (physical re-provision #2, restart-surviving boot rehydration, and in-flight-work preservation #4 remain).

## Overview

`getUserWorkspace(userId)` (`apps/web-platform/server/agent-session-registry.ts:252`) reads a **process-local** `Map<userId, workspaceId>` (`userWorkspaces`, `:45`). The Map is:

- **cleared on disconnect** (`clearUserWorkspace`, `:246`), and
- **only re-populated at WS-open** (`setUserWorkspace`, `ws-handler.ts:2734`, sourced from the resolved `current_organization_id`/workspace at handshake).

Two consumers **throw** `"No workspace binding for user"` when the Map is empty:

| Consumer | Site | Throw |
|---|---|---|
| Conversation insert | `ws-handler.ts:847` (`const wsId = getUserWorkspace(userId)`) | `:849-851` |
| Concurrency-slot acquire (deferred-creation `start_session`) | `ws-handler.ts:1682` (`const slotWorkspaceId = getUserWorkspace(userId)`) | `:1683-1687` |

A **backend process restart** wipes the Map entirely until the next WS-open, so any consumer that runs before re-population aborts. The merged FR1/FR4 resume-rebind work (#5256) narrowed the empty-Map window on the `resume_session` path but did **not** eliminate these two consumers (confirmed by the #5240 FR status-map comment, 2026-06-15: AC4 = 🔴 Outstanding, sites `ws-handler.ts:847,850,1629,1632` — drifted to `847,850,1682,1685` on current `origin/main`).

**Goal:** make both consumers resolve the binding **durably** — prefer the in-memory Map (hot path), then **rehydrate from the DB** (`user_session_state.current_workspace_id`, the same source `resolveCurrentWorkspaceId`/`resolveActiveWorkspacePath` already read) instead of throwing on an empty Map. A **single durable resolver** that both consumers call. **Fail-loud + Sentry** on a genuinely-unresolvable binding — **NOT** the `?? userId` silent solo-fallback that #5256 deliberately removed from the resume path.

### Why this is genuinely new scope (not covered by merged work)

Per the FR status-map on #5240, the merged session-resume PRs are: #5256 (verified-workspace-rebind FR1/FR4), #5290 (stream-since-disconnect replay buffer, closed #5273), #5299/#5282 (reconnect state-machine hardening), #5306 (false-positive watchdog), #5311 (concierge CWD-verify-loop guardrail, closed #5313). **None** touches the `getUserWorkspace` throw sites. #5256 re-aligns the *cwd resolver* field (`set_current_workspace_id` RPC) on resume — it does not rehydrate the in-memory `userWorkspaces` Map nor change the two throw-site consumers. AC4 is explicitly tracked as still-outstanding.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on `origin/main` (verified) | Plan response |
|---|---|---|
| `getUserWorkspace` ~line 252 | `agent-session-registry.ts:252` ✅ | Use as-is. |
| `userWorkspaces` Map ~line 45 | `agent-session-registry.ts:45` ✅ | Add a durable resolver *around* it, do not change the Map's lifecycle. |
| `clearUserWorkspace` ~line 246 | `:246` ✅ (cleared on WS close) | Unchanged — the Map staying ephemeral is fine once the DB is the durable backstop. |
| `setUserWorkspace` at ws-handler ~2681 | `ws-handler.ts:2734` (drifted +53) | Unchanged. |
| Throw sites `847,850` and `1629,1632` | `847,850` ✅; slot path drifted to `1682,1685` | Edit `847-852` and `1682-1687`. |
| `current_workspace_id` is the DB source `resolveActiveWorkspacePath` reads | `resolveCurrentWorkspaceId(userId, supabase)` reads `user_session_state.current_workspace_id` via tenant client (`workspace-resolver.ts:190-218`) ✅ | Reuse this read shape but **fail loud** instead of `?? userId`. |
| Consumers throw on empty Map | Both consumers already mint a **tenant client** in-scope: `createConversation` mints `tenant` at `ws-handler.ts:840`; slot path mints `tenantResume` at `~:1627` | Pass the already-minted tenant client to the new resolver — no extra mint. |

**Premise Validation:** Checked #5240 (`gh issue view 5240`) — OPEN, AC4 🔴 Outstanding per the 2026-06-15 status-map comment; the four merged session-resume PRs verified not to touch the throw sites. Cited file/symbol paths (`getUserWorkspace`, `userWorkspaces`, `resolveCurrentWorkspaceId`, `current_workspace_id`, both throw sites) all confirmed present on `origin/main`. The mechanism (DB rehydrate from `user_session_state.current_workspace_id`) is the **same** source the merged #5256 rebind path and `resolveActiveWorkspacePath` already read — not a rejected alternative; it is the canonical ADR-044 source-of-truth read. No stale premise.

## User-Brand Impact

**If this lands broken, the user experiences:** after a backend process restart (or a reconnect before WS-open re-populates the Map), the user sends a chat message or starts a session and the turn aborts with an internal error — "No workspace binding for user" — instead of resuming. This is the exact `single-user incident` failure class that motivated #5240 (the 4826 stuck-loop: "fresh session with no prior workspace context… Nothing to resume from").

**If this leaks, the user's workspace/data is exposed via:** a **mis-resolved binding** — if the durable resolver ever returned a *sibling* workspace id (cross-tenant), the user's conversation would be written into, and concurrency-counted against, another tenant's workspace. This plan's resolver fails **closed and loud** (throw + Sentry) on absence — it MUST NOT fall back to `userId` blindly the way `resolveCurrentWorkspaceId` does for the read-only cwd path, because here the value is written as `conversations.workspace_id` (a durable cross-tenant boundary), not just used to pick a read root.

**Brand-survival threshold:** single-user incident

> CPO sign-off required at plan time before `/work` begins. `user-impact-reviewer` will be invoked at review-time (handled by the review skill's conditional-agent block).

## The core design tension (must be resolved explicitly)

`resolveCurrentWorkspaceId` (`workspace-resolver.ts:190`) **already** reads `user_session_state.current_workspace_id` — but ends with `return result.data?.current_workspace_id ?? userId` (`:217`): on a null/absent row OR a transient error it **silently falls back to the solo workspace** (`= userId`). That is correct for the **read-only cwd/KB path** (a member viewing their own root degrades safely to solo), but it is the **exact `?? userId` solo-fallback** the prompt forbids reintroducing here, because these two consumers **WRITE** the value as a durable `conversations.workspace_id` / slot `p_workspace_id`.

Therefore the durable resolver MUST distinguish three cases and treat them differently from `resolveCurrentWorkspaceId`:

1. **In-memory Map hit** → return it (hot path, zero DB cost; preserves today's behavior exactly when the Map is warm).
2. **Map miss + DB row present with non-null `current_workspace_id`** → rehydrate: write it back into the Map via `setUserWorkspace` (so subsequent consumers in the same connection skip the DB) and return it. **This is the new durable path.**
3. **Map miss + DB row absent/null `current_workspace_id`, OR DB read error** → **throw + Sentry** (`reportSilentFallback`). Do NOT return `userId`. A genuinely-unbound user (never opened a session, or a corrupt `user_session_state`) is an honest, retryable failure — same fail-loud contract #5256 adopted for the resume-rebind path.

> **Sharp edge:** Case 3 is where a naive reuse of `resolveCurrentWorkspaceId` would silently solo-fallback and re-introduce the bug #5256 removed. The new resolver is a **fail-loud sibling**, not a wrapper that swallows the `?? userId`.

## Files to Create

- **`apps/web-platform/test/durable-workspace-binding-resolver.test.ts`** (vitest, node project — `test/**/*.test.ts` per `vitest.config.ts:44`). RED-first. Drives the resolver (and, via lightweight harness, the two consumers) with an **empty `userWorkspaces` Map** (simulating post-restart) and asserts DB rehydration instead of throw. See Test Strategy.

## Files to Edit

- **`apps/web-platform/server/agent-session-registry.ts`** — add the durable resolver `resolveUserWorkspaceBinding(userId, readDbWorkspaceId)` (async). It reads the Map first (`userWorkspaces.get(userId)`), and on a miss delegates the DB read to a small injected reader so the registry stays dependency-light (it currently imports only `review-gate` + `abort-classifier` — pulling in `workspace-resolver`/Supabase would bloat its test surface, which the module docblock at `:1-28` explicitly exists to keep minimal). Two viable shapes (decide at /work, default = **A**):
  - **A (preferred):** resolver signature `resolveUserWorkspaceBinding(userId: string, readDbWorkspaceId: (userId: string) => Promise<string | null>): Promise<string>`. The DB-read closure is supplied by the caller in `ws-handler.ts` (which already has the tenant client + `current_workspace_id` read shape). Keeps the registry free of a Supabase import; the resolver owns only the Map-hit / rehydrate-writeback / fail-loud-throw decision tree. Sentry mirror on the fail-loud throw lives in the registry via the existing `observability` import pattern OR is passed in.
  - **B:** put the resolver in `workspace-resolver.ts` instead (it already imports Supabase + `reportSilentFallback`), exporting `resolveUserWorkspaceBindingFailLoud(userId, supabase)`, and have the registry's Map-writeback happen at the call site. Rejected-by-default because the Map (`userWorkspaces`) lives in the registry and the rehydrate-writeback wants to be co-located with it.
  - Add a `__test_only__` seam if needed so the RED test can drive Map-empty + injected-DB-reader without spinning up Supabase.
- **`apps/web-platform/server/ws-handler.ts`** —
  - **`:847-852`** (`createConversation`): replace `const wsId = getUserWorkspace(userId); if (!wsId) throw …` with `const wsId = await resolveUserWorkspaceBinding(userId, <db-reader-bound-to-tenant>)`. The `tenant` client minted at `:840` is in scope. The resolver throws fail-loud on case 3, preserving the existing abort semantics but now only when the DB *also* has no binding.
  - **`:1682-1687`** (slot acquire, deferred-creation `start_session`): replace `const slotWorkspaceId = getUserWorkspace(userId); if (!slotWorkspaceId) throw …` with `const slotWorkspaceId = await resolveUserWorkspaceBinding(userId, <db-reader-bound-to-tenantResume>)`. `tenantResume` minted at `~:1627` is in scope. **Invariant preserved:** the slot's `p_workspace_id` MUST equal the conversation's `workspace_id` (mig 059/093 — both now resolve through the same resolver, so they cannot diverge).
  - The db-reader closure reads `user_session_state.current_workspace_id` via the tenant client (mirror `resolveCurrentWorkspaceId`'s select shape at `workspace-resolver.ts:203-207`) and returns `data?.current_workspace_id ?? null` — **null, not userId** (the fail-loud decision lives in the resolver, not the reader).

## Implementation Phases

### Phase 0 — Preconditions (verify before any edit)
- [ ] `grep -n "No workspace binding" apps/web-platform/server/ws-handler.ts` → expect exactly 2 hits (`:850`, `:1685`). If drifted, re-locate.
- [ ] Confirm `tenant` (`:840`) and `tenantResume` (`~:1627`) are in lexical scope at the two consumer sites.
- [ ] Confirm `resolveCurrentWorkspaceId`'s select shape (`from("user_session_state").select("current_workspace_id").eq("user_id", userId).maybeSingle()`, `workspace-resolver.ts:203-207`) so the db-reader closure mirrors it byte-for-byte (RLS: `user_session_state_owner_select` self-scopes to `auth.uid()`).
- [ ] `./node_modules/.bin/vitest --version` (confirm runner) from `apps/web-platform/`.

### Phase 1 — RED (failing test first; TDD)
- [ ] Write `test/durable-workspace-binding-resolver.test.ts`:
  - **Resolver unit tests** (drive `resolveUserWorkspaceBinding` directly with `__test_only__.clear()`'d Map):
    1. Map hit → returns Map value, **no** DB read invoked (spy asserts 0 calls).
    2. **Map miss + DB returns a workspaceId** (post-restart sim) → returns the DB value, AND `getUserWorkspace(userId)` now returns it (writeback assertion). **This is the test that fails today** because today's `getUserWorkspace` returns `undefined` and the consumer throws.
    3. Map miss + DB returns `null` (no `current_workspace_id`) → **throws** (fail-loud) and `reportSilentFallback` spy fired once. Asserts it does NOT return `userId`.
    4. Map miss + DB read error → throws + Sentry mirror. Does NOT return `userId`.
  - Confirm RED: at least test 2 fails against the un-edited consumer/resolver.

### Phase 2 — GREEN (implement)
- [ ] Add `resolveUserWorkspaceBinding` to `agent-session-registry.ts` (shape A).
- [ ] Rewire `ws-handler.ts:847-852` and `:1682-1687` to call it with the in-scope tenant client's db-reader.
- [ ] Run the new test → GREEN.

### Phase 3 — Regression + verification
- [ ] Run the existing suites that exercise these paths: `ws-deferred-creation.test.ts`, `ws-start-session-cap-hit.test.ts`, `ws-resume-by-context-path.test.ts`, `concurrency-acquire-slot-workspace-id.integration.test.ts`, `api-conversations.test.ts`, `conversation-writer.test.ts`. They mock the Map-warm path; assert they still pass (the Map-hit branch returns identically to today).
- [ ] Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Test Strategy

- Runner: **vitest** (`apps/web-platform/vitest.config.ts`); node project glob `test/**/*.test.ts` (`:44`). Test FILE path = `apps/web-platform/test/durable-workspace-binding-resolver.test.ts` (must satisfy the node-project include glob — a co-located `server/*.test.ts` would be silently skipped).
- Run a single file with `cd apps/web-platform && ./node_modules/.bin/vitest run test/durable-workspace-binding-resolver.test.ts` (NOT `bun test` — `apps/web-platform/bunfig.toml` blocks bun test discovery; NOT `npm run -w` — no root `workspaces` field).
- **Deterministic, LLM-free, no PROD writes** — pure in-process resolver + injected DB-read closure spy + `__test_only__` Map seam. No synthetic auth.users / conversations against any Supabase project (honors `hr-dev-prd-distinct-supabase-projects`).
- Mock convention: structural `SupabaseLike`-style chain mock (mirror `ws-deferred-creation.test.ts:48-64`) for the db-reader, or inject a bare `(userId) => Promise<string|null>` spy under shape A.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1** — `grep -c "No workspace binding for user" apps/web-platform/server/ws-handler.ts` returns **0** (both throw sites replaced by the durable resolver; the resolver may carry its own fail-loud message but NOT this literal).
- [ ] **AC2** — New test `test/durable-workspace-binding-resolver.test.ts` exists and `./node_modules/.bin/vitest run test/durable-workspace-binding-resolver.test.ts` passes; it includes the **Map-empty → DB-rehydrate → no throw** case (post-restart sim) as the load-bearing assertion.
- [ ] **AC3** — Fail-loud preserved: the resolver throws + fires `reportSilentFallback` exactly once on a genuinely-absent binding (DB null/absent or read error); a unit assertion confirms the return value is **not** `userId` on those branches (no solo-fallback re-introduced).
- [ ] **AC4** — Map-hit branch returns byte-identical to today and issues **zero** DB reads (spy asserts 0 calls) — hot path unchanged.
- [ ] **AC5** — `resolveUserWorkspaceBinding` is the **single** resolver both consumers call (`grep -c "resolveUserWorkspaceBinding" apps/web-platform/server/ws-handler.ts` ≥ 2; both consumer sites route through it).
- [ ] **AC6** — Slot/conversation workspace parity invariant holds: both `conversations.workspace_id` (insert) and the slot's `p_workspace_id` resolve through the same resolver (re-read the two edited blocks; confirm neither bypasses it).
- [ ] **AC7** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] **AC8** — Existing regression suites (Phase 3 list) pass unchanged.
- [ ] **AC9** — PR body uses **`Ref #5240`** (NOT `Closes`) — epic stays open for #2 / boot-rehydration / #4.

### Post-merge (operator)
- [ ] None. Pure code change against an already-provisioned surface; no migration, no new infra, no new secret. (`web-platform-release.yml` restarts the container on merge touching `apps/web-platform/**` — that IS the deploy.)

## Out of Scope (deferred — tracked under #5240, do NOT fold in)

- **Physical workspace re-provision / re-clone of a missing repo or worktree** (design item #2, FR status-map 🔴). A reconnected turn may resolve a valid workspace *id* and still land on a fresh filesystem; re-cloning is the separate #5240 follow-up. **Scope guard from the issue.**
- **Boot-time rehydration of the whole Map at process start** (the "rehydrate from DB on boot" half of design item #1). This plan rehydrates **lazily, per-consumer, on the empty-Map miss** — which fully satisfies AC4 ("no consumer throws after a reconnect") because the resolver never reaches the consumer with an empty binding when the DB has one. Eager boot rehydration is a strictly-additional optimization, not required for AC4. *(Decision: lazy is sufficient and simpler — YAGNI.)*
- **In-flight uncommitted-work preservation** (design item #4, FR status-map 🔴).
- **Cross-tenant `/workspaces` isolation boundary** — untouched. **Scope guard from the issue.**

## Domain Review

**Domains relevant:** Engineering (CTO) — assessed inline.

This is a backend binding-resolution change with no UI surface. **Product/UX Gate:** Mechanical UI-surface override did NOT fire — `## Files to Create` / `## Files to Edit` contain no path matching `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`. Product = **NONE**. No `.pen` required.

**CTO assessment (inline):** The change is a fail-loud durable resolver around an existing ephemeral Map. Two risk lenses:
1. **Cross-tenant write safety** — the resolver fails *closed and loud*, never returning a sibling or a blind `userId`. The DB read is RLS-self-scoped (`user_session_state_owner_select`). This is the load-bearing safety property given the value is written as `conversations.workspace_id`.
2. **Defense-relaxation check** — we are *removing* a throw (the empty-Map abort) but *replacing* it with a narrower throw (DB-also-absent). Net: the bound case that previously aborted now succeeds; the genuinely-unbound case still aborts. No defense is dissolved — the cross-tenant-write defense (resolve-to-real-binding-or-throw) is *strengthened* (now backed by the durable DB source, not just the ephemeral Map). No new ceiling needed.

## Observability

```yaml
liveness_signal:
  what: "resolver rehydrate-from-DB path exercised (Map-miss → DB-hit) — visible as the ABSENCE of new 'No workspace binding' aborts in Sentry post-deploy"
  cadence: per-consumer-invocation (on-demand, reconnect/restart-triggered)
  alert_target: Sentry (web-platform project)
  configured_in: existing Sentry integration (apps/web-platform/server/observability.ts)
error_reporting:
  destination: Sentry via reportSilentFallback (apps/web-platform/server/observability.ts:183)
  fail_loud: true  # case 3 (DB absent/null or read error) throws AND mirrors to Sentry; never silent solo-fallback
failure_modes:
  - mode: "DB read error during rehydrate"
    detection: reportSilentFallback fires with op=resolveUserWorkspaceBinding.db-read
    alert_route: Sentry web-platform
  - mode: "genuinely-unbound user (current_workspace_id null/absent)"
    detection: reportSilentFallback fires with op=resolveUserWorkspaceBinding.unresolvable; consumer throws honest retryable error
    alert_route: Sentry web-platform
logs:
  where: structured pino logs in ws-handler consumer catch + Sentry event extra {userId}
  retention: existing Better Stack / Sentry retention (no change)
discoverability_test:
  command: "rg 'op:.*resolveUserWorkspaceBinding' apps/web-platform/server/"
  expected_output: "op slug(s) present in the resolver's reportSilentFallback call(s); reachable from Sentry without ssh"
```

## Hypotheses

N/A — the failure mechanism is fully traced in code (empty process-local Map after restart/disconnect → consumer throw). No network-outage / SSH hypothesis class applies.

## Sharp Edges

- **Do NOT reuse `resolveCurrentWorkspaceId` directly** — its `?? userId` solo-fallback (`workspace-resolver.ts:217`) is exactly the silent solo-fallback #5256 removed; the durable resolver here is a fail-loud sibling. The db-reader closure returns `null` (not `userId`) so the fail-loud decision lives in one place.
- **Keep the registry dependency-light** — `agent-session-registry.ts:1-28` docblock exists to keep the module free of Supabase/SDK imports for unit-testability. Inject the DB-read closure (shape A) rather than importing `workspace-resolver`/Supabase into the registry.
- **Slot↔conversation `workspace_id` parity is load-bearing** (mig 059/093) — both must resolve through the *same* resolver or a null `p_workspace_id` re-triggers the 23502 the slot path closes. Confirm neither consumer bypasses the resolver after the edit.
- A plan whose `## User-Brand Impact` section is empty or placeholder will fail `deepen-plan` Phase 4.6 — this one is filled (threshold = single-user incident, CPO sign-off flagged).
- Test FILE path must match `test/**/*.test.ts` (node project, `vitest.config.ts:44`); a co-located `server/*.test.ts` is silently skipped. Use `./node_modules/.bin/vitest run`, never `bun test` or `npm run -w`.
