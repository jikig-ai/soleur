---
title: "feat(concierge): block dispatch until repo_status=ready"
issue: 5394
branch: feat-one-shot-block-dispatch-until-repo-status-ready
date: 2026-06-16
semver: minor
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat(concierge): block dispatch until `repo_status=ready` (close the connect-repo race at the source)

Closes #5394.

## Overview

Follow-up to #5392 (merged, commit `c79ca1fd7`). That PR made a repo-less Concierge
workspace **fail loud** with an honest "not ready, try again" message at the skill +
`worktree-manager.sh` layer instead of flailing for ~40 tool calls. This issue closes the
race **at the source** so a Concierge session never starts against a `cloning`/`error`
workspace in the first place — making #5392's deterministic fallback rarely fire.

Two layers:

- **Layer A — server dispatch readiness gate (load-bearing backstop).** Before spawning a
  leader workflow, read the active workspace's `repo_status` and short-circuit on
  `cloning` (honest "still being set up" message) / `error` (setup-failed + reconnect
  message); `ready` proceeds normally into the existing self-heal. This covers UI **and**
  API/agent consumers (AC1's "server-authoritative" requirement).
- **Layer B — chat composer "setting up" state.** While `cloning`, disable the chat
  composer and show a "Setting up your repository…" state with an elapsed indicator,
  auto-transitioning to `ready` on the next poll without a manual refresh; on `error`,
  show a reconnect CTA to Settings → Repository.

This is a `single-user incident` brand-survival feature: it sits on the **dispatch hot
path** (`cc-dispatcher` / `ws-handler`). A wrong gate predicate that fires on `ready`
would block every founder's every turn; a gate that mis-reads `cloning` as `ready` would
re-open the exact flailing window #5392 patched. CPO sign-off required at plan time;
`user-impact-reviewer` runs at review time.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "The chat surface already reads `repo_status` via `/api/repo/status`." | The chat surface (`chat-surface.tsx`, `chat-input.tsx`) does **NOT** read repo status at all today — its composer is gated only on the WebSocket `status !== "connected"`. `/api/repo/status` is polled only by the connect-repo onboarding page (`app/(auth)/connect-repo/page.tsx:333-372`, 2 s × 60). `useActiveRepo` (`hooks/use-active-repo.ts`) fetches `/api/workspace/active-repo` (returns `repoStatus` from `workspaces.repo_status`) on **mount + window focus only**, no interval. | Layer B must **add** a repo-status signal to the chat composer. Reuse `useActiveRepo` (same `workspaces.repo_status` source as Layer A — avoids the `users`-vs-`workspaces` divergence below) and **add a while-`cloning` interval poll** so AC4's "auto-transition without manual refresh" holds. Do not invent a second `/api/repo/status` consumer in chat. |
| Gate reads "the active workspace's `repo_status`". | Two physical sources exist post-ADR-044: `/api/repo/status` reads **`users.repo_status`**; `getCurrentRepoUrl` + `/api/workspace/active-repo` read **`workspaces.repo_status`** (via tenant client + `resolveCurrentWorkspaceId`). The setup route writes BOTH on every transition (`users` at `route.ts:125/197/308`; mirrored to `workspaces` via `mirrorRepoColsToSoloWorkspace` at `:154/212/319`). For a solo founder `workspace_id === user.id`, so they converge; for a future team/shared workspace they can diverge. | Gate reads **`workspaces.repo_status`** (the ADR-044 source of truth, same row `getCurrentRepoUrl` already resolves) so it stays correct for shared workspaces and matches the BYOK/active-repo read model. Extend `getCurrentRepoUrl` to also return `repo_status`/`repo_error` from the same `.maybeSingle()` rather than adding a second round-trip. |
| Gate inserts at `realSdkQueryFactory` "and/or the ws-handler turn-accept path". | Factory throw → re-thrown by runner (`soleur-go-runner.ts:2546`) → caught at `dispatchSoleurGo` (`cc-dispatcher.ts:3277`). The generic `else` branch (`:3347`) emits a HARDCODED message and clears `session_id` (`:3363`). The runner's factory catch (`:2541`) and the dispatch catch (`:3284`) BOTH Sentry-mirror — so throwing on a benign `cloning` would emit Sentry noise on every cloning-window turn. | **Hybrid, primary in ws-handler.** Put the user-facing short-circuit in the ws-handler chat case (`ws-handler.ts:2346`, before `dispatchSoleurGoForConversation`) where it can `sendToClient({type:"error",message})` + `break` with **no throw, no Sentry noise, no session_id clobber**. Keep a **factory-level backstop** (`cc-dispatcher.ts` after `getCurrentRepoUrl` `:1532`) for non-WS / API / agent consumers, using **typed error classes** (`RepoSetupInProgressError`, `RepoSetupFailedError`) with dedicated `else if` branches at `:3328`-style so (a) the message is honest per-branch, (b) `session_id` is NOT cleared, (c) the Sentry mirrors skip these expected classes. |
| Setup route line refs `:125,166,197/213,308/320`. | All confirmed verbatim: `:125` cloning update, `:166` background `provisionWorkspaceWithRepo` (not awaited), `:197/213` ready, `:308/319` error. | No setup-route change needed (out of scope: synchronous clone-await). The route is read-only context for the gate. |

## User-Brand Impact

**If this lands broken, the user experiences:** a gate predicate inverted or mis-keyed
(reads `users.repo_status` for a shared workspace whose `workspaces.repo_status` is
`ready`, or treats `ready` as not-ready) → **every chat turn is blocked** behind a
"setting up" message that never clears, with the composer permanently disabled. The
founder cannot use Soleur at all.

**If this leaks, the user's workflow is exposed via:** `repo_error` is surfaced to the
client in the `error` branch. The setup route already JSON-wraps + `sanitizeGitStderr`-es
the error payload (`route.ts:301-305`) and `/api/repo/status` allowlist-validates the
code (`status/route.ts:113-118`); the gate MUST consume the **sanitized** message
(reuse `parseErrorPayload` shape), never raw stderr / absolute paths.

**Brand-survival threshold:** single-user incident.

> `threshold: single-user incident` → CPO sign-off required at plan time;
> `user-impact-reviewer` runs at review time (review/SKILL.md conditional-agent block).

## Implementation Phases

Phase order is load-bearing (`2026-05-10-plan-phase-order-load-bearing`): the
status-reader contract (Phase 1) ships before its consumers (Phases 2-3).

### Phase 0 — Preconditions (verify, do not code)

- `grep -n "repo_status" apps/web-platform/server/current-repo-url.ts` → confirm it does
  NOT yet read `repo_status` (it selects only `repo_url`).
- `grep -n "else if (err instanceof" apps/web-platform/server/cc-dispatcher.ts` → confirm
  the `:3328` typed-branch ladder shape the new branches mirror.
- Read `apps/web-platform/server/byok-lease.ts:192-201` (`MissingByokKeyError`) → the
  error-class export pattern to mirror.
- `grep -nE "reportSilentFallback|mirrorWithDebounce" apps/web-platform/server/soleur-go-runner.ts apps/web-platform/server/cc-dispatcher.ts` → confirm both Sentry mirror sites
  (`soleur-go-runner.ts:2541`, `cc-dispatcher.ts:3284`) so the skip-list edit covers both.
- Confirm vitest config include globs: `grep -nE "include|happy-dom|node" apps/web-platform/vitest.config.ts` → unit = `test/**/*.test.ts` (node), component = `test/**/*.test.tsx` (happy-dom). Tests land under `apps/web-platform/test/`, flat.
- `command -v ./node_modules/.bin/vitest` from `apps/web-platform`.

### Phase 1 — Status reader contract (server)

1. **Extend `getCurrentRepoUrl` → add `getCurrentRepoStatus`** (sibling in
   `apps/web-platform/server/current-repo-url.ts`). Same tenant client +
   `resolveCurrentWorkspaceId` + `workspaces` row; widen the `.select("repo_url")` to
   `.select("repo_url, repo_status, repo_error")` and return
   `{ repoUrl, repoStatus, repoError }`. `repoStatus: "cloning" | "error" | "ready" | "not_connected"` (coerce `null` → `"not_connected"`). Preserve the existing
   transient-null/`RuntimeAuthError` fail-closed semantics (a null read → treat as
   `not_connected`, NOT as a block — fail-OPEN on a transient read error so a tenant-mint
   blip never blocks a `ready` founder; document this trade-off explicitly).
   - **Why fail-open on read-error:** a `ready` founder hitting a transient tenant-JWT
     blip must NOT be blocked; the worst case of fail-open is the `cloning`/`error`
     workspace falls through to #5392's deterministic fallback — exactly the safety net
     this issue layers on top of. Fail-closed here would convert a read blip into a hard
     block on a working repo (the inverted-gate brand-survival failure above).
2. **Error classes** in a small new module `apps/web-platform/server/repo-readiness.ts`
   (or co-located): `RepoSetupInProgressError extends Error` and
   `RepoSetupFailedError extends Error { readonly sanitizedReason: string }`. Plus a pure
   `evaluateRepoReadiness(status, repoError): { ok: true } | { ok: false; code: "cloning" | "error"; message: string }` that produces the **exact AC copy**:
   - `cloning` → `"Your repository is still being set up — it'll be ready in a moment."`
   - `error` → ``Repository setup failed: ${sanitizedReason}. Reconnect in Settings → Repository.`` (reason via the `parseErrorPayload` shape from `status/route.ts:102`; reuse, don't re-derive).
   - `ready` / `not_connected` → `{ ok: true }` (a `not_connected` workspace is NOT
     blocked here — it flows to the existing repo-less path / #5392 fallback; this gate is
     specifically the cloning/error race, per the issue).
   Keep `evaluateRepoReadiness` pure so the unit test (AC7) drives it without a DB.

### Phase 2 — Layer A gate (dispatch backstop)

3. **ws-handler primary short-circuit** (`apps/web-platform/server/ws-handler.ts`,
   chat case, immediately BEFORE the `dispatchSoleurGoForConversation` call at `:2355`,
   inside the `routing.kind !== "legacy"` branch). Resolve
   `getCurrentRepoStatus(userId)` → `evaluateRepoReadiness`. On `!ok`:
   `sendToClient(userId, { type: "error", message, ...(code === "error" ? { errorCode: "repo_setup_failed" } : {}) })` then `break` — **no dispatch, no agent spawn**. This is
   the clean, throw-free, Sentry-noise-free path for the WS founder.
   - Place it so it does NOT short-circuit the legacy `sendUserMessage` path unless that
     path also needs it — scope to the Concierge (`routing.kind !== "legacy"`) dispatch,
     which is the surface #5394 targets.
4. **Factory backstop** (`apps/web-platform/server/cc-dispatcher.ts`, in
   `realSdkQueryFactory` immediately AFTER `repoUrl` resolves at `:1532-1533`, and
   **BEFORE** `ensureWorkspaceDirExists`/`ensureWorkspaceRepoCloned` at `:1634/1657`).
   Read status (reuse the same row — fold `repo_status,repo_error` into the existing
   `getCurrentRepoUrl` resolution if it's converted, else a parallel read in the
   `Promise.all`). `evaluateRepoReadiness`; on `cloning` throw `RepoSetupInProgressError`,
   on `error` throw `RepoSetupFailedError(sanitizedReason)`. This covers API/agent
   consumers that bypass the ws-handler (AC1 "server-authoritative").
   - **AC6 placement invariant:** the gate sits BEFORE `ensureWorkspaceRepoCloned`, so a
     `ready` status flows UNCHANGED into the existing self-heal (`ensureWorkspaceRepoCloned`
     no-ops when `.git` present, re-clones when absent) and the `worktree_enter_failed` +
     `reprovisionOutcome` reclaim path (`cc-dispatcher.ts:2628+/3148`) is untouched. The
     gate only fires on `cloning`/`error`, never on `ready` — so the "ready but `.git`
     gone mid-session" reclaim case is provably not regressed (it never reaches a
     `cloning`/`error` branch). Add an AC asserting `ready` → no early-return.
5. **Dispatch catch branches** (`apps/web-platform/server/cc-dispatcher.ts:3328`
   ladder). Add `else if (err instanceof RepoSetupInProgressError)` →
   `sendToClient({type:"error", message: err.message})` (the cloning copy) and
   `else if (err instanceof RepoSetupFailedError)` →
   `sendToClient({type:"error", message: err.message, errorCode: "repo_setup_failed"})`.
   Both branches MUST sit ABOVE the generic `else` so they short-circuit the
   `session_id`-clearing path (`:3363`) — a cloning/error block is transient and must NOT
   nuke a resumable session.
6. **Sentry-mirror skip** for the two expected classes. At
   `soleur-go-runner.ts:2541` and `cc-dispatcher.ts:3284`, guard the mirror with
   `if (!(err instanceof RepoSetupInProgressError || err instanceof RepoSetupFailedError))`
   — a `cloning` window is an expected benign state, not an incident. (Per
   `cq-silent-fallback-must-mirror-to-sentry`: these are user-facing honest messages, NOT
   silent fallbacks, so skipping the mirror is correct — but emit a structured `logger.info`
   breadcrumb instead so the rate is still observable without Sentry noise. See
   `## Observability`.)

### Phase 3 — Layer B (chat composer "setting up" state)

7. **Repo-status signal into chat.** Extend `useActiveRepo` (or a thin
   `useRepoSetupState` wrapper) to **poll on an interval WHILE `repoStatus === "cloning"`**
   (reuse the connect-repo cadence: 2 s, self-stopping on `ready`/`error`/`not_connected`;
   clear interval on unmount). Keep mount+focus revalidation. Single source =
   `workspaces.repo_status` (matches Layer A). Coalesce via the existing module-level
   `inFlight` latch so the chat mount does not multiply fetches with the nav badge.
8. **ChatInput composer gate** (`apps/web-platform/components/chat/chat-input.tsx`):
   add `repoSetupState?: "cloning" | "error" | null` prop; fold into the existing
   `disabled = rawDisabled || workflowEnded` → also disabled when
   `repoSetupState === "cloning"`. Placeholder → `"Setting up your repository…"` while
   cloning. Render a slim inline indicator above the textarea with an **elapsed timer**
   (mm:ss since cloning observed) — reuse the copy/voice from
   `components/connect-repo/setting-up-state.tsx`; the elapsed timer is new (that
   component is step-based, not time-based) so add a tiny `useElapsed(sinceMs)` helper.
9. **Error-state reconnect CTA** (`chat-input.tsx` or a small
   `components/chat/repo-setup-banner.tsx`): when `repoSetupState === "error"`, show a
   compact banner — message + a `Reconnect in Settings → Repository` link to
   `/dashboard/settings` (the `ProjectSetupCard` there already owns all repo states).
   Mirror `failed-state.tsx` CTA voice; do NOT reuse the full onboarding `FailedState`
   (too heavy for an inline composer banner).
10. **Wire `chat-surface.tsx`** to read the polled state and pass `repoSetupState` to
    `<ChatInput>`. Auto-transition: when the poll flips to `ready`, the prop clears →
    composer re-enables + placeholder restores, no manual refresh (AC4).

### Phase 4 — Tests (AC7)

- **Dispatch-gate unit** (`apps/web-platform/test/repo-readiness.test.ts`, node project):
  drive `evaluateRepoReadiness` per branch — `cloning` → `{ok:false, code:"cloning", message: <exact copy>}` (AC1), `error` → `{ok:false, code:"error", message includes sanitizedReason + "Reconnect in Settings → Repository"}` (AC2), `ready` → `{ok:true}` (AC3), `not_connected` → `{ok:true}` (not blocked). Plus a focused test that the
  factory/ws-handler gate, given `cloning`/`error`, calls `sendToClient` and does NOT call
  the dispatch/spawn (mock the dispatcher) — keep the LLM/agent OFF the assertion path
  (`2026-04-19-llm-sdk-security-tests-need-deterministic-invocation`).
- **AC6 regression**: a `ready`-status test asserting the gate returns `{ok:true}` and the
  factory proceeds to `ensureWorkspaceRepoCloned` (mock it; assert it is reached) — proving
  the reclaim/self-heal path is not short-circuited.
- **UI transition** (`apps/web-platform/test/chat-input-repo-setup.test.tsx`, component
  project, happy-dom): render `<ChatInput repoSetupState="cloning">` → composer disabled +
  "Setting up your repository…" placeholder + elapsed indicator present (AC4 start state);
  rerender with `repoSetupState={null}` (ready) → composer re-enabled, default placeholder
  (AC4 auto-transition). `repoSetupState="error"` → reconnect CTA to `/dashboard/settings`
  present (AC5). Follow the `test/connect-repo-page.test.tsx` fetch-mock + `waitFor`
  pattern for any poll-driven variant; prefer driving the transition via prop rerender to
  keep the LLM/timer off the assertion path.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `repo_status === "cloning"`: dispatch returns the exact message
  `"Your repository is still being set up — it'll be ready in a moment."` and spawns no
  agent. Verified server-authoritatively (ws-handler short-circuit + factory backstop;
  unit test asserts no dispatch/spawn call).
- **AC2** — `repo_status === "error"`: dispatch returns
  ``Repository setup failed: <sanitized repo_error>. Reconnect in Settings → Repository.``
  with `errorCode: "repo_setup_failed"`; no agent spawned.
- **AC3** — `repo_status === "ready"`: dispatch proceeds normally; `evaluateRepoReadiness`
  returns `{ok:true}`; factory reaches `ensureWorkspaceRepoCloned`. No regression.
- **AC4** — Chat composer shows the "Setting up your repository…" disabled state with an
  elapsed indicator while `cloning`, and auto-transitions to the enabled normal state on
  the next poll returning `ready` (no manual refresh). Component test drives both states.
- **AC5** — On `error`, the composer shows a reconnect CTA linking to
  `/dashboard/settings` (Settings → Repository).
- **AC6** — Reclaim case (status `ready` but `.git` gone mid-session) still falls through
  to the existing `worktree_enter_failed` self-heal + `reprovisionOutcome` honest reclaimed
  message AND #5392's `worktree-manager.sh` fail-loud guard — proven by the gate firing
  ONLY on `cloning`/`error` (never `ready`) and sitting BEFORE `ensureWorkspaceRepoCloned`.
- **AC7** — Tests: dispatch-gate unit per `repo_status` branch (cloning/error/ready +
  not_connected) and the UI "setting up → ready" transition + error-CTA test, all green via
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/repo-readiness.test.ts test/chat-input-repo-setup.test.tsx`.
- **AC8** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (exhaustiveness
  rails on the new error branches + the `WSMessage` `errorCode` widening if any).
- **AC9** — `repo_error` reaches the client only via the sanitized `parseErrorPayload`
  shape; no raw stderr / absolute path in the `error` message (grep the gate code for raw
  `repo_error` interpolation; assert it routes through the sanitizer).

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering

**Status:** carry-forward (CTO lens applied inline at plan time)
**Assessment:** Dispatch hot path; the load-bearing risks are (a) inverted/mis-sourced
predicate blocking `ready` founders, (b) Sentry noise from throw-as-control-flow on the
expected `cloning` state, (c) `session_id` clobber on a transient block. All three are
addressed by the hybrid ws-handler-primary + typed-factory-backstop design with mirror-skip
and above-the-generic-`else` branch ordering. Defense-relaxation rule N/A (no defense
removed; a new gate is ADDED). The gate mirrors a SQL-/skill-layer concept (#5392 fail-loud)
at the dispatch layer — its load-bearing sub-value is **observability + happy-path
correctness the skill-layer guard can't provide** (skill guard fires only after the agent
spawns; this prevents the spawn), documented per
`2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate`.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed (pipeline) — BLOCKING because Layer B adds a new user-facing chat
composer state (disabled "setting up" + elapsed indicator + error CTA). Per
`wg-ui-feature-requires-pen-wireframe`, a `.pen` wireframe for the composer "setting up"
and "error" states is required; `ux-design-lead` is a non-skippable producer at /work
Phase 2.5 if not produced here.
**Agents invoked:** cpo, spec-flow-analyzer, ux-design-lead (to run in the plan pipeline's
Phase 2.5 / deepen-plan)
**Skipped specialists:** none
**Pencil available:** TBD — resolve at Phase 2.5 (`pencil-setup --auto`)

#### Findings
The composer states reuse existing onboarding voice (`setting-up-state.tsx`,
`failed-state.tsx`); the elapsed timer is the only net-new UI primitive. Keep the inline
banner light — full `FailedState` is too heavy for the composer. CPO sign-off gates the
`single-user incident` threshold.

## Observability

```yaml
liveness_signal:
  what: "structured logger.info breadcrumb 'repo-readiness gate: blocked' emitted on each cloning/error short-circuit (ws-handler + factory), tagged {code, userIdHash}"
  cadence: per-blocked-dispatch
  alert_target: "Better Stack log query (rate of code=error blocks) — no alert on code=cloning (expected/benign); alert if code=error rate spikes"
  configured_in: "apps/web-platform/server/ws-handler.ts + cc-dispatcher.ts (logger.info), Better Stack saved search"
error_reporting:
  destination: "Sentry — ONLY for unexpected gate failures (status-read throw that is NOT a RuntimeAuthError); RepoSetupInProgressError/RepoSetupFailedError are EXCLUDED from the mirror (expected user-facing states)"
  fail_loud: "a status-read error that is not the known transient class still mirrors to Sentry via the existing reportSilentFallback in getCurrentRepoUrl"
failure_modes:
  - mode: "gate blocks a ready founder (inverted/mis-sourced predicate)"
    detection: "Better Stack: code=cloning|error block rate against a workspace whose /api/repo/status shows ready; unit AC3/AC6 guard pre-merge"
    alert_route: "log spike query"
  - mode: "Sentry noise from cloning-window throws"
    detection: "Sentry event rate for RepoSetupInProgressError (should be ZERO post-skip)"
    alert_route: "Sentry saved search = 0 expected"
  - mode: "error branch leaks raw stderr"
    detection: "AC9 grep + sanitizer routing"
    alert_route: "pre-merge gate"
logs:
  where: "Better Stack (pino → structured), Sentry for unexpected only"
  retention: "Better Stack default"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/repo-readiness.test.ts test/chat-input-repo-setup.test.tsx"
  expected_output: "all tests pass; cloning→blocked message, error→reconnect message, ready→ok, UI setting-up→ready transition"
```

## Out of Scope

- Awaiting the clone synchronously inside `/api/repo/setup` (large repos → timeouts). Keep
  the background clone + `repo_status` polling.
- Real-time clone progress percentage — `cloning`/`ready`/`error` states suffice; the
  elapsed timer is wall-clock, not clone-progress.
- Changing the `users` vs `workspaces` repo-column dual-write (ADR-044 owns that
  decommission). The gate reads `workspaces.repo_status` (the source of truth) and Layer B
  aligns to it; `/api/repo/status` (users-backed) is left untouched.

## Open Code-Review Overlap

Four open `code-review` issues body-match files this plan edits — all **Acknowledge**
(orthogonal concerns, own cycles; this plan does NOT touch their surfaces):

- #3243 `arch: decompose cc-dispatcher.ts into focused modules` — module decomposition of
  the whole file; the gate adds a small block + catch branches, no decomposition. Acknowledge.
- #3242 `review: tool_use WS event lacks raw name field` — `tool_use` frame shape; unrelated
  to the readiness gate. Acknowledge.
- #3374 `review: emit slot_reclaimed WS frame` — ledger-divergence recovery frame; the AC6
  reclaim path is read-only context here (not modified). Acknowledge.
- #2191 `refactor(ws): clearSessionTimers helper + timer jitter` — ws-handler session-timer
  refactor; the gate adds a chat-case short-circuit, not timer logic. Acknowledge.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder will fail
  `deepen-plan` Phase 4.6. This section is filled (threshold `single-user incident`).
- **Do not source the gate from `users.repo_status`** (the `/api/repo/status` route's
  source) — for a shared/team workspace it diverges from `workspaces.repo_status`. Read
  `workspaces.repo_status` via the same `getCurrentRepoUrl` row.
- **Order the new dispatch-catch branches ABOVE the generic `else`** at
  `cc-dispatcher.ts:3347` — the generic else clears `session_id` (`:3363`); a transient
  cloning/error block must not nuke a resumable session.
- **Skip the Sentry mirror for the two expected error classes at BOTH sites**
  (`soleur-go-runner.ts:2541` AND `cc-dispatcher.ts:3284`) — missing either re-introduces
  noise on every cloning-window turn.
- **Fail-OPEN on a status-read error** (transient tenant-mint blip → treat as `ready`/proceed,
  NOT block) — a `cloning`/`error` workspace then still hits #5392's fallback, but a `ready`
  founder is never blocked by a read blip.
- Component test path MUST be `apps/web-platform/test/*.test.tsx` (happy-dom project) — a
  co-located `components/**/*.test.tsx` is silently never run by the vitest include globs.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, never
  `npm run -w` (no root `workspaces` field).

## PR Body Reminder

Use `Closes #5394` in the PR body (not the title).
