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

- **Layer A — server dispatch readiness gate (load-bearing backstop).** A **single gate**
  inside `realSdkQueryFactory` (the Concierge dispatch choke point) reads the active
  workspace's `repo_status` before spawning, and short-circuits on `cloning` (honest
  "still being set up" message) / `error` (setup-failed + reconnect message); `ready`
  proceeds normally into the existing self-heal. Because the factory runs on BOTH the cold
  first-message and warm follow-up Concierge paths, one gate is server-authoritative for
  the whole Concierge surface. **Scope:** this issue gates the Concierge / `/soleur:go`
  surface; the pre-existing un-gated legacy-leader path (`startAgentSession`,
  `agent-runner.ts:1097`) is a separate deliberate seam — a follow-up issue (filed at
  plan time) tracks gating it.
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
| Gate reads "the active workspace's `repo_status`". | Two physical sources exist post-ADR-044: `/api/repo/status` reads **`users.repo_status`**; `getCurrentRepoUrl` + `/api/workspace/active-repo` read **`workspaces.repo_status`** (via tenant client + `resolveCurrentWorkspaceId`). The setup route writes BOTH on every transition (`users` at `route.ts:125/197/308`; mirrored to `workspaces` via `mirrorRepoColsToSoloWorkspace` at `:154/212/319`). For a solo founder `workspace_id === user.id`, so they converge; for a future team/shared workspace they can diverge. | Gate reads **`workspaces.repo_status`** (the ADR-044 source of truth, same row `getCurrentRepoUrl` already resolves) so it stays correct for shared workspaces. Extend `getCurrentRepoUrl`'s `.select` to also return `repo_status` from the same row (no extra round-trip). **NOTE — write-ordering lag (architecture review P1):** the setup route writes `users` FIRST, mirrors to `workspaces` SECOND, so on the `ready` transition there's a sub-ms window where `workspaces` still says `cloning`. Skew direction is **stale-blocking, not stale-spawning** (the safe direction — one false-blocked turn that self-clears on the founder's retry / next 2 s Layer-B poll). Accepted; documented in Sharp Edges. |
| `repo_error` source row. | **`repo_error` is NOT mirrored to `workspaces`** (`server/workspace-repo-mirror.ts:6` — "`repo_error`, `health_snapshot` stay on `users` and are NOT mirrored"; the error mirror at `route.ts:319` writes only `repo_status:"error"`). So `workspaces.repo_error` is **always NULL** (zero writers). The sanitized payload lives on **`users.repo_error`** (written via `sanitizeGitStderr` at `route.ts:303`). `parseErrorPayload` (the JSON-unwrap + code-allowlist) is **module-private** in `status/route.ts:102` (not exported). | The gate reads `repo_status` from `workspaces` (source of truth) but the **error reason from `users.repo_error`** (the only row that holds it). **Extract `parseErrorPayload` into a shared exported module** (e.g. alongside `sanitizeGitStderr` in `server/git-auth.ts`, which already references it) so BOTH `status/route.ts` and the gate consume one sanitizer — no inline re-derivation (closes the leak-class + blank-reason bug user-impact review FINDING 1/2 flagged). At-rest value is already sanitized; the gate just unwraps it. |
| Gate inserts at `realSdkQueryFactory` "and/or the ws-handler turn-accept path"; "covers UI + API/agent consumers". | **Two co-equal dispatch subsystems exist** (architecture review P0): (a) the **Concierge / `/soleur:go`** path (ws-handler chat case → `dispatchSoleurGoForConversation` → `dispatchSoleurGo` → `realSdkQueryFactory`); (b) the **legacy leader** path `startAgentSession` (`agent-runner.ts:858`) — its OWN workspace-prep + `ensureWorkspaceRepoCloned` (`:1081`), reached from the ws-handler legacy `pendingLeader` branch (`:2236`) and `sendUserMessage`, and explicitly flagged "No outer `repo_status` gate" (`:1097`). The factory throw is re-thrown by the runner (`soleur-go-runner.ts:2546`) → caught at `dispatchSoleurGo` (`:3277`); the generic `else` (`:3347`) clears `session_id` (`:3363`); both `:2541` + `:3284` Sentry-mirror. There are **two** `dispatchSoleurGoForConversation` call sites: `:2221` (first message) and `:2355` (follow-up). | **Scope #5394 to the Concierge surface; gate at the factory (the Concierge choke point) ONLY; file a follow-up for the legacy path.** The simplest design (code-simplicity review): a **single gate** inside `realSdkQueryFactory` (after `getCurrentRepoUrl` `:1532`, before `ensureWorkspaceRepoCloned`) throwing **one** typed class `RepoNotReadyError { code: "cloning"\|"error", errorCode? }`, caught by **one** new `else if` branch ABOVE the generic `else` (preserves `session_id`), with **one** `instanceof` skip-clause at each of the two Sentry-mirror sites. This is server-authoritative for the WHOLE Concierge path (cold first-message at `:2221` AND follow-up at `:2355` both funnel through the factory) — so the redundant ws-handler short-circuit is **dropped**. AC1 is rescoped to "no Concierge agent spawned"; the legacy `startAgentSession` gap is filed as follow-up #TBD (it predates this issue and `agent-runner.ts:1097` marks it a deliberate seam). |
| Setup route line refs `:125,166,197/213,308/320`. | All confirmed verbatim: `:125` cloning update, `:166` background `provisionWorkspaceWithRepo` (not awaited), `:197/213` ready, `:308/319` error. | No setup-route change needed (out of scope: synchronous clone-await). The route is read-only context for the gate. |
| `errorCode: "repo_setup_failed"` wire contract. | `WSMessage` "error" variant already has optional `errorCode?: WSErrorCode` (`lib/types.ts:458`); the `WSErrorCode` union (`:140`) does NOT yet include `repo_setup_failed`. `ws-client.ts` switches on `msg.errorCode`. | Widen the `WSErrorCode` union with `"repo_setup_failed"` and sweep consumers per `cq-union-widening-grep-three-patterns` / `hr-type-widening-cross-consumer-grep` (`git grep errorCode lib/ components/` — confirm `ws-client.ts` either handles or safely falls through). No `WSMessage`-shape change. |

## User-Brand Impact

**If this lands broken, the user experiences:** a gate predicate inverted or mis-keyed
(reads `users.repo_status` for a shared workspace whose `workspaces.repo_status` is
`ready`, or treats `ready` as not-ready) → **every chat turn is blocked** behind a
"setting up" message that never clears, with the composer permanently disabled. The
founder cannot use Soleur at all.

**If this leaks, the user's workflow is exposed via:** the `error`-branch reason string. The
sanitized payload is written **at rest** to `users.repo_error` (`route.ts:303`, via
`sanitizeGitStderr` + JSON-wrap) — so the primary leak is closed at the write boundary. The
gate consumes that already-sanitized value through the **extracted, shared** `parseErrorPayload`
(no inline re-derivation), so a legacy plain-stderr row is unwrapped through the same allowlist.
Residual exposure is contained; the gate adds no new raw-stderr surface.

**Brand-survival threshold:** single-user incident.

> `threshold: single-user incident` → CPO sign-off required at plan time;
> `user-impact-reviewer` runs at review time (review/SKILL.md conditional-agent block).

## Implementation Phases

Phase order is load-bearing (`2026-05-10-plan-phase-order-load-bearing`): the
status-reader contract (Phase 1) ships before its consumers (Phases 2-3).

Design simplified post-review (code-simplicity + architecture): **one** gate (factory),
**one** error class, **one** catch branch; legacy-path coverage filed as a follow-up.

### Phase 0 — Preconditions (verify, do not code)

- `grep -n "repo_status\|repo_error" apps/web-platform/server/current-repo-url.ts` → confirm
  it selects only `repo_url` today.
- `sed -n '3328,3371p' apps/web-platform/server/cc-dispatcher.ts` → confirm the typed-branch
  ladder + the generic `else` `session_id` clear at `:3363` the new branch must sit above.
- Read `apps/web-platform/server/byok-lease.ts:192-201` (`MissingByokKeyError`) → error-class
  pattern (`extends Error`, `this.name = ...`).
- `grep -nE "reportSilentFallback|mirrorWithDebounce" apps/web-platform/server/soleur-go-runner.ts apps/web-platform/server/cc-dispatcher.ts` → confirm both Sentry mirror sites
  (`soleur-go-runner.ts:2541`, `cc-dispatcher.ts:3284`).
- `grep -n "repo_error" apps/web-platform/server/workspace-repo-mirror.ts` → confirm
  `repo_error` is NOT mirrored to `workspaces` (so the reason must come from `users`).
- `grep -n "parseErrorPayload\|WSErrorCode" apps/web-platform/app/api/repo/status/route.ts apps/web-platform/lib/types.ts` → confirm `parseErrorPayload` is module-private (must be
  extracted) and `WSErrorCode` lacks `repo_setup_failed` (must be widened).
- Confirm vitest include globs (`grep -nE "include|happy-dom|node" apps/web-platform/vitest.config.ts`): unit `test/**/*.test.ts` (node), component `test/**/*.test.tsx` (happy-dom).
  Tests land under `apps/web-platform/test/`, flat. `command -v ./node_modules/.bin/vitest`.
- `gh label list --limit 200 | grep -E "^(domain/engineering|chore)\b"` → confirm labels
  for the legacy-path follow-up issue exist (substitute if not).

### Phase 1 — Status reader contract (server)

1. **Extract the sanitizer.** Move `parseErrorPayload` from `status/route.ts:102` (currently
   module-private) into a shared exported module — co-locate with `sanitizeGitStderr` in
   `apps/web-platform/server/git-auth.ts` (which already references it). Update
   `status/route.ts` to import it. One sanitizer, two consumers (the route + the gate);
   no inline re-derivation in the gate (closes the leak-class FINDING 2).
2. **Extend `getCurrentRepoUrl` → return status too** (`apps/web-platform/server/current-repo-url.ts`). Widen the existing `.select("repo_url")` to `.select("repo_url, repo_status")` on
   the SAME `workspaces` row, and the **error reason from `users.repo_error`** (the only row
   that holds it — see Reconciliation; a tiny `.from("users").select("repo_error").eq("id", userId)` read, OR fold into the existing `Promise.all` in the factory so it is not a new
   sequential await on the hot path). Add `getCurrentRepoStatus(userId): Promise<{ repoStatus: "cloning"|"error"|"ready"|"not_connected"; repoError: string | null }>`
   reusing the same resolver. Preserve the transient-null/`RuntimeAuthError` semantics:
   a null status read coerces to `not_connected` → **fail-OPEN** (never block a `ready`
   founder on a tenant-mint blip; worst case a `cloning`/`error` workspace falls through to
   #5392's fallback — the safety net this issue layers on top of).
3. **One error class + pure evaluator** in `apps/web-platform/server/repo-readiness.ts`:
   - `class RepoNotReadyError extends Error { constructor(readonly code: "cloning" | "error", message: string, readonly errorCode?: "repo_setup_failed") { super(message); this.name = "RepoNotReadyError"; } }` (mirrors the `MissingByokKeyError` shape; one class
     because both states are handled identically — emit `{type:"error", message, errorCode?}`
     + skip-mirror — so they are data, not type, per code-simplicity review).
   - Exported copy **constants** (so the gate and the test import the SAME string — no drift):
     `REPO_CLONING_MSG = "Your repository is still being set up — it'll be ready in a moment."`
     and a builder `repoErrorMsg(reason) = ``Repository setup failed: ${reason}. Reconnect in Settings → Repository.``` (reason via the extracted `parseErrorPayload`).
   - Pure `evaluateRepoReadiness(status, repoError): { ok: true } | { ok: false; code: "cloning" | "error"; message: string; errorCode?: "repo_setup_failed" }`:
     `cloning` → `{ok:false, code:"cloning", message: REPO_CLONING_MSG}`;
     `error` → `{ok:false, code:"error", message: repoErrorMsg(parseErrorPayload(repoError).errorMessage ?? "setup failed"), errorCode:"repo_setup_failed"}`;
     `ready` / `not_connected` → `{ ok: true }` (a `not_connected` workspace is NOT blocked —
     it flows to the existing repo-less path / #5392 fallback; this gate is the cloning/error
     race). Pure → the AC7 unit test drives it DB-free.

### Phase 2 — Layer A gate (single, in the factory)

4. **The gate** (`apps/web-platform/server/cc-dispatcher.ts`, in `realSdkQueryFactory`
   AFTER `repoUrl` resolves at `:1532-1533`, **BEFORE** `ensureWorkspaceDirExists`/`ensureWorkspaceRepoCloned` at `:1634/1657`). Resolve `repo_status` (fold
   `repo_status` into the existing `getCurrentRepoUrl` row resolution in the `Promise.all`
   at `:1515-1533` so it adds ZERO round-trips). `const r = evaluateRepoReadiness(status, repoError); if (!r.ok) throw new RepoNotReadyError(r.code, r.message, r.errorCode);`.
   The factory is the choke point for BOTH the cold first-message (`ws-handler.ts:2221`) and
   warm follow-up (`:2355`) Concierge dispatch — so this single site is server-authoritative
   for the whole Concierge surface. No ws-handler short-circuit (dropped per code-simplicity).
   - **AC6 placement invariant:** the gate sits BEFORE `ensureWorkspaceRepoCloned`
     (`:1657`, which no-ops when `.git` present per `ensure-workspace-repo.ts:142`, re-clones
     when absent) and fires only on `cloning`/`error` (never `ready`). A `ready` status flows
     UNCHANGED into the self-heal + the `worktree_enter_failed`/`reprovisionOutcome` reclaim
     path (`cc-dispatcher.ts:2628+/3148`). The "ready but `.git` gone mid-session" reclaim is
     provably un-regressed (it never reaches a `cloning`/`error` branch). The gate keys on
     `repo_status`, NOT `.git` presence — no race with a mid-session reclaim (different state).
5. **One dispatch catch branch** (`cc-dispatcher.ts:3328` ladder, **ABOVE** the generic
   `else` at `:3347`): `else if (err instanceof RepoNotReadyError) { sendToClient(userId, { type: "error", message: err.message, ...(err.errorCode ? { errorCode: err.errorCode } : {}) }); }`. Above the generic `else` so it does NOT hit the `session_id`-clearing path
   (`:3363`) — a transient cloning/error block must not nuke a resumable session.
6. **Sentry-mirror skip** at BOTH `soleur-go-runner.ts:2541` AND `cc-dispatcher.ts:3284`:
   guard each mirror with `if (!(err instanceof RepoNotReadyError))`. A cloning/error window
   is an expected benign state, not an incident. **No precedent** — `MissingByokKeyError`/
   `KeyInvalidError` ARE mirrored today (precedent research flagged this as novel); the
   distinction is that those are real failures while a cloning window is an expected
   transient state. Per `cq-silent-fallback-must-mirror-to-sentry`: these are user-facing
   honest messages, NOT silent fallbacks — emit a structured `logger.info` breadcrumb
   instead so the rate stays observable without Sentry noise (see `## Observability`).
7. **Widen the wire contract.** Add `"repo_setup_failed"` to the `WSErrorCode` union
   (`lib/types.ts:140`); sweep consumers per `cq-union-widening-grep-three-patterns`
   (`git grep -n "errorCode" lib/ws-client.ts components/`) and confirm `ws-client.ts`
   either handles the new code or safely falls through (no silent half-wire).

### Phase 3 — Layer B (chat composer "setting up" state)

8. **Repo-status signal into chat — extend `useActiveRepo` in place** (it ALREADY returns
   `repoStatus` from the `workspaces`-backed `/api/workspace/active-repo`). Add a
   `setInterval` (2 s) inside its existing `useEffect`, guarded by `data?.repoStatus === "cloning"`, cleared on unmount and self-stopping once status leaves `cloning`
   (`ready`/`error`/`not_connected`). Keep mount+focus revalidation and the module-level
   `inFlight` coalescing latch (no fetch multiplication with the nav badge). **No new
   `useRepoSetupState` wrapper** (it would wrap a hook to add ~5 lines — net negative).
9. **ChatInput composer gate** (`apps/web-platform/components/chat/chat-input.tsx`):
   add `repoSetupState?: "cloning" | "error" | null` prop; fold into the existing
   `disabled = rawDisabled || workflowEnded` → also disabled when `repoSetupState === "cloning"`. Placeholder → `"Setting up your repository…"` while cloning. Above the textarea,
   a slim inline indicator: spinner + `"Setting up your repository…"` (voice from
   `setting-up-state.tsx`). **Elapsed indicator (lightweight):** the issue's parenthetical
   "elapsed indicator" — use the existing static copy `"This usually takes less than a minute."`
   from `setting-up-state.tsx` (satisfies "indicator" with zero new code). **No `useElapsed`
   mm:ss ticking timer** (gold-plating: per-second re-render on a blocked composer for a
   number the founder can't act on — clone progress is out of scope, per code-simplicity).
10. **Error-state reconnect CTA — inline in `chat-input.tsx`** (NOT a new
    `repo-setup-banner.tsx`): when `repoSetupState === "error"`, render a compact inline
    line above the textarea — text + a `<Link href="/dashboard/settings">Reconnect in Settings → Repository</Link>` (the `ProjectSetupCard` there owns all repo states). Mirror
    `failed-state.tsx` CTA voice; ~4-5 lines of JSX, no new file.
11. **Wire `chat-surface.tsx`** to read `repoStatus` from `useActiveRepo` and pass
    `repoSetupState` (mapping `"cloning"`/`"error"` through, else `null`) to `<ChatInput>`.
    Auto-transition: when the poll flips to `ready`, the prop clears → composer re-enables +
    placeholder restores, no manual refresh (AC4).

### Phase 4 — Tests (AC7)

Per test-design review, the pure evaluator alone tests the predicate, not the wiring. Test
BOTH the evaluator AND the factory-throw seam, plus the poll, the Sentry-skip, and the wire
contract.

- **Pure evaluator** (`apps/web-platform/test/repo-readiness.test.ts`, node): drive
  `evaluateRepoReadiness` per branch — `cloning` → `{ok:false, code:"cloning", message: REPO_CLONING_MSG}` (AC1, assert against the imported constant), `error` →
  `{ok:false, code:"error", errorCode:"repo_setup_failed", message contains the sanitized reason + "Reconnect in Settings → Repository"}` (AC2), `ready` → `{ok:true}` (AC3),
  `not_connected` → `{ok:true}`. **Fail-open case:** a `null`/transient status (coerced to
  `not_connected`) → `{ok:true}` (the inverted-gate brand-survival case). **Sanitization (AC9
  as assertion, not grep):** `evaluateRepoReadiness("error", "<raw stderr with /abs/path>")`
  → message routes through the extracted `parseErrorPayload`/`sanitizeGitStderr`, contains no
  `/`-absolute path or raw stderr.
- **Factory-throw seam** (`apps/web-platform/test/cc-dispatcher-repo-gate.test.ts`, node):
  (a) factory given `cloning`/`error` THROWS `RepoNotReadyError` BEFORE reaching
  `ensureWorkspaceRepoCloned` (spy on it; assert NOT reached + no agent/query spawned) — the
  AC1 "no spawn" proof, LLM off the assertion path
  (`2026-04-19-llm-sdk-security-tests-need-deterministic-invocation`). (b) the dispatch catch
  routes `RepoNotReadyError` to a branch that does NOT call `clearCcSessionId`/
  `onSessionIdPersisted(null)` (the session-survival Sharp Edge — a re-order below the generic
  `else` must fail this). (c) `error` payload carries `errorCode:"repo_setup_failed"`; cloning
  payload does NOT.
- **Sentry-mirror skip** (same file): spy on `mirrorWithDebounce` (`cc-dispatcher.ts:3284`)
  and `reportSilentFallback` (`soleur-go-runner.ts:2541`); a `RepoNotReadyError` → ZERO mirror
  calls (the Observability "should be ZERO" failure mode); an unrelated error → one call
  (positive control).
- **AC6 regression** (same file): a `ready`-status factory test asserting the gate does NOT
  early-return and `ensureWorkspaceRepoCloned` IS reached (mocked) — proving the
  reclaim/self-heal path is not short-circuited.
- **Poll controller** (`apps/web-platform/test/use-active-repo-poll.test.ts`, node, or
  `.test.tsx` if RTL `renderHook`): `vi.useFakeTimers()` + sequenced fetch mock
  (`cloning`→`cloning`→`ready`): assert (a) the interval fires while `cloning`, (b) it
  self-stops on `ready` (no fetch after), (c) `clearInterval` on unmount (no fetch after
  unmount), (d) the `inFlight` latch coalesces a mount+focus double-fetch. This is the actual
  AC4 controller (the connect-repo-page poll pattern); no LLM involved, so fake timers are the
  faithful test — not a prop-rerender proxy.
- **UI view** (`apps/web-platform/test/chat-input-repo-setup.test.tsx`, component, happy-dom):
  `<ChatInput repoSetupState="cloning">` → composer disabled + "Setting up your repository…"
  placeholder + the static "less than a minute" indicator present (AC4 view); rerender with
  `repoSetupState={null}` → composer re-enabled, default placeholder (AC4 view transition);
  `repoSetupState="error"` → reconnect CTA `<Link>` to `/dashboard/settings` present (AC5).
  Prop-rerender is correct HERE (testing the View; the Controller is covered by the poll test
  above).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `repo_status === "cloning"`: the Concierge dispatch (factory gate) throws
  `RepoNotReadyError("cloning", REPO_CLONING_MSG)`; the client receives `{type:"error", message: "Your repository is still being set up — it'll be ready in a moment."}` and **no
  agent/query is spawned** (factory throws before `ensureWorkspaceRepoCloned`). Scope:
  Concierge / `/soleur:go` surface (the legacy `startAgentSession` path is the follow-up).
- **AC2** — `repo_status === "error"`: dispatch returns
  ``Repository setup failed: <sanitized reason from users.repo_error>. Reconnect in Settings → Repository.`` with `errorCode: "repo_setup_failed"`; no agent spawned. The reason is
  non-empty (sourced from `users.repo_error`, NOT the always-NULL `workspaces.repo_error`).
- **AC3** — `repo_status === "ready"`: dispatch proceeds normally; `evaluateRepoReadiness`
  returns `{ok:true}`; the factory reaches `ensureWorkspaceRepoCloned` (asserted). No regression.
- **AC4** — Chat composer shows the disabled "Setting up your repository…" state (placeholder
  + inline "less than a minute" indicator) while `cloning`, and **auto-transitions** to the
  enabled normal state on the next 2 s `useActiveRepo` poll returning `ready` (no manual
  refresh). The poll controller test (fake timers) proves the transition; the View test proves
  the rendered states.
- **AC5** — On `error`, the composer shows a reconnect CTA `<Link>` to `/dashboard/settings`
  (Settings → Repository).
- **AC6** — Reclaim case (status `ready` but `.git` gone mid-session) still falls through
  to the existing `worktree_enter_failed` self-heal + `reprovisionOutcome` honest reclaimed
  message AND #5392's `worktree-manager.sh` fail-loud guard — proven by the factory test that
  `ready` reaches `ensureWorkspaceRepoCloned` and the gate fires ONLY on `cloning`/`error`.
- **AC7** — Tests green: pure evaluator (per branch + fail-open + sanitization), factory-throw
  seam (no-spawn + session-survival + payload errorCode), Sentry-mirror skip, poll controller
  (fake timers), and UI view — via
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/repo-readiness.test.ts test/cc-dispatcher-repo-gate.test.ts test/use-active-repo-poll.test.ts test/chat-input-repo-setup.test.tsx`.
- **AC8** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (the `WSErrorCode`
  union widening + the new catch branch).
- **AC9** — The `error`-branch message routes through the **extracted, shared**
  `parseErrorPayload` + `sanitizeGitStderr`; no raw stderr / absolute path leaks (asserted by
  the pure-evaluator sanitization test, not a grep).
- **AC10** — A follow-up issue is filed (Concierge legacy-leader path `startAgentSession`
  un-gated; `agent-runner.ts:1097`) with a re-evaluation note, per `wg-when-deferring-a-capability-create-a`. PR body uses `Ref #<follow-up>`.

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering

**Status:** reviewed (architecture-strategist + code-simplicity + user-impact + test-design
agents ran at deepen-plan)
**Assessment:** Dispatch hot path; the load-bearing risks are (a) inverted/mis-sourced
predicate blocking `ready` founders — addressed by reading `workspaces.repo_status` +
fail-OPEN on read error; (b) Sentry noise from throw-as-control-flow on the expected
`cloning` state — addressed by the dual-site mirror-skip; (c) `session_id` clobber —
addressed by the catch branch sitting above the generic `else`. Architecture review found
the original "covers all consumers" claim **false** (the legacy `startAgentSession` path is
a co-equal un-gated dispatch subsystem) → rescoped to the Concierge surface with a filed
follow-up (AC10). Code-simplicity review collapsed the hybrid two-site gate to **one** factory
gate + **one** error class. User-impact review found `workspaces.repo_error` is **never
written** → reason re-sourced from `users.repo_error` + the sanitizer extracted/shared.
Defense-relaxation rule N/A (a new gate is ADDED). The gate's load-bearing sub-value over
#5392's skill-layer guard: it prevents the spawn (the skill guard only fires AFTER the agent
spawns), per `2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate`.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed — BLOCKING because Layer B adds a new user-facing chat composer state
(disabled "setting up" + error CTA). `.pen` wireframe **produced and committed** this pass
(`wg-ui-feature-requires-pen-wireframe` satisfied).
**Agents invoked:** ux-design-lead (wireframe produced); architecture-strategist,
code-simplicity-reviewer, user-impact-reviewer, test-design-reviewer (deepen-plan review)
**Skipped specialists:** none
**Pencil available:** yes — committed
`knowledge-base/product/design/concierge/chat-composer-repo-setup-states.pen` (commit
`d8b60d3b5`), three states (cloning-disabled / error-reconnect / ready-enabled) +
screenshots.

#### Findings
The composer states reuse existing onboarding voice (`setting-up-state.tsx`,
`failed-state.tsx`). The mm:ss elapsed timer was **cut** as gold-plating (code-simplicity) —
the static "less than a minute" copy satisfies the issue's "elapsed indicator" parenthetical.
Inline error CTA (not a new banner component). CPO sign-off gates the `single-user incident`
threshold.

## Observability

```yaml
liveness_signal:
  what: "structured logger.info breadcrumb 'repo-readiness gate: blocked' emitted at the single factory gate on each cloning/error block, tagged {code, userIdHash}"
  cadence: per-blocked-dispatch
  alert_target: "Better Stack log query (rate of code=error blocks) — no alert on code=cloning (expected/benign); alert if code=error rate spikes"
  configured_in: "apps/web-platform/server/cc-dispatcher.ts realSdkQueryFactory (logger.info), Better Stack saved search"
error_reporting:
  destination: "Sentry — ONLY for unexpected gate failures; RepoNotReadyError is EXCLUDED from both mirror sites (expected user-facing state)"
  fail_loud: "a status-read error that is not the known transient class still mirrors to Sentry via the existing reportSilentFallback in getCurrentRepoUrl"
failure_modes:
  - mode: "gate blocks a ready founder (inverted/mis-sourced predicate)"
    detection: "Better Stack: code=cloning|error block rate against a workspace whose /api/workspace/active-repo shows ready; unit AC3/AC6 + fail-open test guard pre-merge"
    alert_route: "log spike query"
  - mode: "Sentry noise from cloning-window throws"
    detection: "Sentry event rate for RepoNotReadyError (should be ZERO post-skip; spy test asserts zero mirror calls)"
    alert_route: "Sentry saved search = 0 expected"
  - mode: "error branch leaks raw stderr / blank reason"
    detection: "pure-evaluator sanitization test (AC9) + AC2 non-empty-reason assertion (reason from users.repo_error)"
    alert_route: "pre-merge gate"
logs:
  where: "Better Stack (pino → structured), Sentry for unexpected only"
  retention: "Better Stack default"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/repo-readiness.test.ts test/cc-dispatcher-repo-gate.test.ts test/use-active-repo-poll.test.ts test/chat-input-repo-setup.test.tsx"
  expected_output: "all pass; cloning→blocked msg + no-spawn, error→reconnect msg + errorCode, ready→reaches ensureWorkspaceRepoCloned, zero Sentry mirror, poll auto-transition, UI states"
```

## Out of Scope

- Awaiting the clone synchronously inside `/api/repo/setup` (large repos → timeouts). Keep
  the background clone + `repo_status` polling.
- Real-time clone progress percentage — `cloning`/`ready`/`error` states suffice; the
  composer indicator is a static "less than a minute" line, not a clone-progress meter.
- Changing the `users` vs `workspaces` repo-column dual-write (ADR-044 owns that
  decommission). The gate reads `workspaces.repo_status` (source of truth) + `users.repo_error`
  (the only row holding the sanitized reason); `/api/repo/status` (users-backed) is untouched.
- **Gating the legacy `startAgentSession` leader path** (`agent-runner.ts:1097`, a co-equal
  un-gated dispatch subsystem reached from the ws-handler legacy branch + `sendUserMessage`).
  Pre-existing deliberate seam; tracked by the AC10 follow-up issue. #5394 scopes to the
  Concierge / `/soleur:go` surface.

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
- **Source `repo_status` from `workspaces` but the error REASON from `users.repo_error`.**
  `workspaces.repo_error` is NEVER written (not mirrored — `workspace-repo-mirror.ts:6`); the
  sanitized payload lives only on `users.repo_error` (`route.ts:303`). Reading `repo_error`
  from `workspaces` yields a blank reason (user-impact FINDING 1). Do NOT source `repo_status`
  from `users` either — for a shared/team workspace it diverges from `workspaces.repo_status`.
- **Extract `parseErrorPayload` before consuming it.** It is module-private in
  `status/route.ts:102` — the gate cannot import it as-is (user-impact FINDING 2). Move to a
  shared exported module; one sanitizer, two consumers. No inline re-derivation.
- **Order the new `RepoNotReadyError` catch branch ABOVE the generic `else`** at
  `cc-dispatcher.ts:3347` — the generic else clears `session_id` (`:3363`); a transient
  cloning/error block must not nuke a resumable session. A test asserts the branch does NOT
  call `clearCcSessionId`.
- **Skip the Sentry mirror for `RepoNotReadyError` at BOTH sites** (`soleur-go-runner.ts:2541`
  AND `cc-dispatcher.ts:3284`) — missing either re-introduces noise on every cloning-window
  turn. This is a NOVEL pattern (existing `MissingByokKeyError`/`KeyInvalidError` ARE mirrored)
  — a spy test asserts zero mirror calls.
- **Fail-OPEN on a status-read error** (transient tenant-mint blip → coerce to
  `not_connected`/proceed, NOT block) — a `cloning`/`error` workspace then still hits #5392's
  fallback, but a `ready` founder is never blocked by a read blip. A test exercises the
  `null`-read → `{ok:true}` path.
- **Write-ordering lag is acceptable (stale-blocking, not stale-spawning).** The setup route
  writes `users` then mirrors to `workspaces`, so on the `ready` transition there's a sub-ms
  window where `workspaces` still says `cloning`. The skew false-blocks one turn (self-clears
  on retry / next 2 s poll); it never spawns against a not-ready repo. Do not add a re-check.
- **Single factory gate, NOT a ws-handler site.** The factory is the choke point for both the
  cold first-message (`ws-handler.ts:2221`) and follow-up (`:2355`) Concierge dispatch — one
  gate is server-authoritative for the Concierge surface. A ws-handler short-circuit would be
  redundant (dropped per code-simplicity review).
- **Widen `WSErrorCode` with `repo_setup_failed` + sweep consumers** (`ws-client.ts`) per
  `cq-union-widening-grep-three-patterns` — the `WSMessage.errorCode` field already exists; the
  union literal does not.
- Component test path MUST be `apps/web-platform/test/*.test.tsx` (happy-dom) / `*.test.ts`
  (node) — a co-located `components/**/*.test.tsx` is silently never run by the vitest globs.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, never
  `npm run -w` (no root `workspaces` field).

## PR Body Reminder

Use `Closes #5394` in the PR body (not the title). Add `Ref #<legacy-path-follow-up>` for the
AC10 deferred-scope issue (legacy `startAgentSession` gate). Reference the committed wireframe
`knowledge-base/product/design/concierge/chat-composer-repo-setup-states.pen`.
