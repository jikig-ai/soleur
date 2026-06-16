---
title: "feat: Gate the legacy startAgentSession leader dispatch path on repo_status"
issue: 5399
type: enhancement
branch: feat-one-shot-gate-legacy-leader-repo-status
lane: cross-domain
created: 2026-06-16
requires_cpo_signoff: false
brand_survival_threshold: single-user incident
---

# feat: Gate the legacy `startAgentSession` leader dispatch path on `repo_status`

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-16
**Agents:** verify-the-negative grep pass (7/7 claims CONFIRMED), architecture-strategist,
silent-failure-hunter.

### Key improvements (all findings applied)

1. **F1 (HIGH, silent-failure):** Option A's gate sits ABOVE the outer `try` (`:930`), so a
   non-RuntimeAuthError throw from `getCurrentRepoStatus` (`current-repo-url.ts:126`) would escape
   uncaught (no Sentry, no client error). Added a fail-open try/catch around the gate read
   (`reportSilentFallback` + proceed) — AC11 + wiring test case 5. The cc-dispatcher precedent
   does NOT share this seam.
2. **P1 (architecture):** "before registerSession" was under-specified — the gate must sit ABOVE
   the supersede-abort (`getSession`/`abort` at `:876`), else a blocked dispatch kills the in-flight
   prior session before bailing. Pinned the insertion point + AC10.
3. **P1 (architecture):** documented the multi-leader `dispatchToLeaders` fan-out (`:2576/:2587`)
   N-emit behavior — accepted, not gated pre-fan-out (AC12).
4. **P2 (architecture):** use `hashUserId(userId)` in the breadcrumb for parity with
   cc-dispatcher.ts:3352 (avoid raw-userId-in-logs divergence).
5. **F2/F3 (silent-failure, MEDIUM):** breadcrumb now carries the sanitized `reason` for
   self-contained triage; the Observability `error_reporting` claim was made precise about the
   `users.repo_error` read's by-design silent fail-open carve-out.

### Verify-the-negative pass

All 7 load-bearing claims (getCurrentRepoStatus self-mints tenant; outer catch does
Sentry+failed-write; resolveSessionErrorCode returns undefined for RepoNotReadyError;
registerSession at ~:885 after supersede-abort at :876; all entry points funnel through
startAgentSession; evaluator fail-open; cc-dispatcher emit/skip shape) CONFIRMED with file:line
citations.

## Overview

#5395 (PR for the issue keyed as #5394 in code comments) added a server-authoritative
repo-readiness gate to the **Concierge / `/soleur:go`** dispatch path — the
`realSdkQueryFactory` choke point in `apps/web-platform/server/cc-dispatcher.ts`. It blocks a
dispatch whose active workspace `repo_status` is `cloning` or `error` BEFORE spawning the agent
or attempting a clone. That gate intentionally scoped to the Concierge surface and explicitly
deferred the **legacy leader path** as AC10 (the follow-up issue is this one, #5399).

The legacy leader path — `startAgentSession` (`apps/web-platform/server/agent-runner.ts:859`) —
is a co-equal, still-un-gated dispatch subsystem. It runs its OWN workspace-prep +
`ensureWorkspaceRepoCloned` (`~:1081`), reached from the ws-handler legacy `pendingLeader` branch
(`ws-handler.ts:2241`) AND from `sendUserMessage` (`agent-runner.ts:2793/2817/2833`, multi-leader
dispatch). `agent-runner.ts:1097` explicitly marks it "No outer `repo_status` gate" — a
deliberate pre-existing seam. A dispatch through this path against a `cloning`/`error` workspace
still reaches the repo-less / not-ready path (caught only by #5392's deterministic fail-loud
fallback, not prevented at the source).

**This plan** applies the same readiness gate to the legacy leader path, **reusing the primitives
that #5395 already shipped and tested** — `getCurrentRepoStatus` (`current-repo-url.ts:106`),
`evaluateRepoReadiness` + `RepoNotReadyError` (`repo-readiness.ts`). **No new predicate, no new
error class, no new copy.** The work is wiring: read `repo_status` before `startAgentSession`
spawns, evaluate readiness, and on `!ok` route an honest client message through the legacy path's
error surface with the Sentry-mirror SKIP (a `cloning`/`error` block is an expected transient
state, not an incident) and WITHOUT marking the conversation `failed` (a transient block must not
nuke a resumable conversation).

This is a pure code change against an already-provisioned surface: no new infrastructure, no UI,
no schema/migration, no new dependency. The gate reads an existing column.

## Premise Validation

All references in the issue were verified against `origin/main` at plan time:

- **#5399 is OPEN** (`gh issue view 5399`) — `closedByPullRequestsReferences: []`. Not stale; it
  is the legitimate AC10 follow-up filed by the source plan (`...block-dispatch...plan.md:270`).
- **#5392 is MERGED** (`fix(concierge): fail loud on repo-less workspace…`). The deterministic
  fail-loud fallback exists.
- **#5394 PR number does not resolve** (`gh pr view 5394` → "Could not resolve to a
  PullRequest"). The gate work merged as **PR #5395** (`gh pr view 5395` → MERGED,
  `feat(concierge): block dispatch until repo_status=ready…`, commit `867f77978`). Code comments
  cite "#5394" (the issue), the PR was #5395. Not a fabricated reference — issue-vs-PR number
  divergence, confirmed by both `gh pr view` and `git show origin/main`.
- **Cited primitives all exist on `origin/main`:** `evaluateRepoReadiness` + `RepoNotReadyError`
  + `RepoReadiness` + `REPO_CLONING_MSG` + `repoErrorMsg` in
  `apps/web-platform/server/repo-readiness.ts`; `getCurrentRepoStatus` at
  `apps/web-platform/server/current-repo-url.ts:106` returning
  `{ repoStatus: string, repoError: string | null }`.
- **Cited legacy-path sites all exist verbatim:** `startAgentSession` at `agent-runner.ts:859`;
  `ensureWorkspaceRepoCloned` call inside the `.git`-absent block at `~:1081`; "No outer
  `repo_status` gate" marker at `~:1097`; ws-handler `pendingLeader` → `startAgentSession` at
  `ws-handler.ts:2241`.
- **Mechanism is not in a rejected-alternatives ADR table:** the source plan's Reconciliation
  table explicitly RECOMMENDS extending the same gate to the legacy path as a follow-up — this
  plan executes that recommendation; it is not re-litigating a rejected design.

No external premises remain unvalidated.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on `origin/main` | Plan response |
| --- | --- | --- |
| "read `repo_status` via `getCurrentRepoStatus` before `startAgentSession` spawns" | `getCurrentRepoStatus(userId)` does its OWN `getFreshTenantClient(userId)` (`current-repo-url.ts:113`) — it does NOT depend on the in-callback `sessionTenant` or the BYOK lease. | The gate CAN run at the **top of `startAgentSession`, before `resolveKeyOwnerThenLease`** (Option A below), so a not-ready dispatch never even acquires the BYOK lease. This is a cleaner placement than cc-dispatcher's (which is inside the lease body because it parallelizes the read into an existing `Promise.all`). |
| "route through the legacy path's error surface" | The legacy outer catch (`agent-runner.ts:2475-2514`) ends in a generic `else` that `Sentry.captureException(err)` AND `updateConversationStatusIfActive(..., "failed")`. `resolveSessionErrorCode` (`:110`) returns `undefined` for `RepoNotReadyError`. | The honest message + `errorCode` must be emitted via a branch that SKIPS both the Sentry mirror and the failed-status write, reading `err.errorCode` directly (mirrors cc-dispatcher catch B at `:3422`). |
| "single point of gating" | `startAgentSession` is the single function reached by BOTH ws-handler `pendingLeader` (`:2241`) and `sendUserMessage`'s three call sites (`:2793/2817/2833`). | A single gate inside (or at the top of) `startAgentSession` is server-authoritative for the ENTIRE legacy-leader surface — no per-caller wiring needed. |
| `repo_status` lives on `users` (legacy SOLO column) | Post-ADR-044 it is read from `workspaces` (source of truth) by `getCurrentRepoStatus`; the sanitized reason comes from `users.repo_error`. | Reuse `getCurrentRepoStatus` verbatim — it already encodes the ADR-044 source-of-truth split, so an invited member on a shared `cloning` workspace is gated correctly (the #4543 divergence is not re-created). |

## User-Brand Impact

**If this lands broken, the user experiences:** a leader/CPO chat turn dispatched against a
still-`cloning` or `error`'d repository — the same flailing / dead-end "No Git repository" symptom
the Concierge gate already closes — OR (false-positive) a `ready` founder's leader turn wrongly
blocked with "your repository is still being set up." The pure evaluator is **fail-open** (only
`cloning`/`error` block; a read blip → `not_connected` → `{ ok: true }`), so the false-positive
mode is bounded to a genuine `cloning`/`error` state.

**If this leaks, the user's workflow / data is exposed via:** the error-branch message embeds the
repo-setup failure reason. The reason is sanitized at rest (`/api/repo/setup` → `sanitizeGitStderr`)
AND re-sanitized defensively inside `evaluateRepoReadiness` (`repo-readiness.ts` `error` branch,
via `parseErrorPayload` + `sanitizeGitStderr`), so a legacy plain-stderr row cannot leak an
absolute path / raw stderr. This plan reuses that path unchanged — no new leak surface.

**Brand-survival threshold:** `single-user incident`. A single founder hitting a broken dispatch
on the leader surface is a brand-visible incident; the source gate was filed at the same
threshold. Inherited from the source plan's framing (#5395).

Per the threshold-driven requirement: `single-user incident` normally adds `requires_cpo_signoff:
true`. Here the approach was already framed and CPO-acked at the source-gate brainstorm/plan
(#5395), and this follow-up reuses the identical primitives + design with zero net-new decision
surface — `requires_cpo_signoff: false`, with the rationale recorded here. `user-impact-reviewer`
WILL run at review time (review-skill conditional-agent block fires on the `single-user incident`
threshold).

## Design

### The gate

```ts
// apps/web-platform/server/agent-runner.ts — the FIRST statement of
// startAgentSession, ABOVE the supersede-abort `const existing = getSession(...)`
// (:876) and ABOVE registerSession (:885). LOAD-BEARING ordering: the gate must
// precede the supersede-abort so a blocked not-ready dispatch does NOT abort the
// user's in-flight prior session before bailing (architecture review P1).
//
// #5399 — legacy-leader repo-readiness gate (follow-up to #5395 AC10).
// getCurrentRepoStatus self-mints its tenant client, so this runs without
// the BYOK lease — a cloning/error workspace never acquires a key, never
// spawns an agent, never attempts a clone. Server-authoritative for the
// WHOLE legacy surface (ws-handler pendingLeader :2241 + sendUserMessage
// :2793/:2817/:2833 + dispatchToLeaders fan-out :2576/:2587 all funnel
// through startAgentSession).
//
// FAIL-OPEN WRAPPER (silent-failure review F1, HIGH): this gate sits ABOVE the
// outer `try` (:930), so a non-RuntimeAuthError throw from getCurrentRepoStatus
// (the bare `throw err` at current-repo-url.ts:126 — e.g. a non-auth runtime
// blip) would otherwise escape uncaught (no Sentry, no client error, no
// failed-status). The cc-dispatcher precedent does NOT share this seam (its read
// is inside an existing try). Wrap the read in a fail-open try/catch that mirrors
// to Sentry and PROCEEDS (degrade to the existing repo-less / #5392 path) rather
// than dead-ending the dispatch.
let repoReadiness: RepoReadiness;
try {
  const { repoStatus, repoError } = await getCurrentRepoStatus(userId);
  repoReadiness = evaluateRepoReadiness(repoStatus, repoError);
} catch (err) {
  // Unexpected status-read throw at this pre-try call site — mirror and
  // fail OPEN (proceed). Never block a dispatch on a readiness-read blip.
  reportSilentFallback(err, {
    feature: "agent-runner",
    op: "repo-readiness-gate.read",
    extra: { userId, conversationId },
  });
  repoReadiness = { ok: true };
}
if (!repoReadiness.ok) {
  // Honest client message; SKIP Sentry (expected transient/benign, not an
  // incident); do NOT mark the conversation failed (a cloning/error block
  // must not nuke a resumable conversation). Info breadcrumb keeps the rate
  // observable in Better Stack (alert on a code=error spike, never cloning).
  // Carry the sanitized message so the Better Stack line is self-contained for
  // triage (silent-failure review F2 — the reason is sanitized by the evaluator,
  // no leak). Use hashUserId for log parity with cc-dispatcher.ts:3352 (F-P2).
  log.info(
    {
      feature: "agent-runner",
      op: "repo-readiness-gate",
      code: repoReadiness.code,
      userIdHash: hashUserId(userId),
      conversationId,
      leaderId,
      reason: repoReadiness.message,
    },
    "repo-readiness gate: blocked legacy-leader dispatch (repo not ready)",
  );
  sendToClient(userId, {
    type: "error",
    message: repoReadiness.message,
    ...(repoReadiness.errorCode ? { errorCode: repoReadiness.errorCode } : {}),
  });
  return; // no lease, no agent, no clone
}
```

This wrapper needs imports `RepoReadiness` from `./repo-readiness`, `reportSilentFallback`
(already imported at `agent-runner.ts:70`), and `hashUserId` (verify import — it is used by
cc-dispatcher; confirm the same helper is importable in agent-runner at /work time, else fall back
to the existing `userId` field shape but document the divergence).

### Placement decision — pre-lease early-return (Option A, recommended)

Two placements were considered; this is a genuine architectural choice for plan-review to weigh.

- **Option A — gate as the FIRST statement of `startAgentSession`, ABOVE the supersede-abort
  (`const existing = getSession(...)` at `:876`) and ABOVE `registerSession` (`:885`),
  early-`return`ing on `!ok` (RECOMMENDED).** `getCurrentRepoStatus` self-mints its tenant client,
  so the read does not need the lease or the in-callback `sessionTenant`/`workspacePath`. Gating
  here means a not-ready dispatch acquires **no BYOK lease**, fetches **no credential**, spawns
  **no agent**, attempts **no clone**, and (load-bearing) does **not abort the user's in-flight
  prior session** — the faithful "close the race at the source" intent. The honest message +
  Sentry-skip are emitted inline (no throw), so the existing outer catch is untouched. Costs/risks
  the implementer MUST handle: (1) the gate sits ABOVE the outer `try` (`:930`), so the
  `getCurrentRepoStatus` read MUST be wrapped in its own fail-open try/catch (a non-RuntimeAuthError
  throw at `current-repo-url.ts:126` would otherwise escape uncaught — silent-failure review F1,
  HIGH); (2) it must `return` (not `throw`) so the lease body never runs; (3) it must sit above
  `getSession`/`abort` at `:876`, not merely above `registerSession`, so a blocked turn never
  mutates session state (architecture review P1).

- **Option B — gate inside the lease callback, after `workspacePath = resolveActiveWorkspacePath`
  (`:1004`) and before `ensureWorkspaceDirExists`/`.git`-absent reprovision, throwing
  `RepoNotReadyError`; add a new `else if (err instanceof RepoNotReadyError)` branch in the outer
  catch (`:2475`) ABOVE the generic `else`.** This mirrors cc-dispatcher exactly (one throw, one
  catch branch). Cost: the BYOK lease is acquired and a credential fetched before the gate fires
  (wasted work for a known-not-ready dispatch), and the catch branch must additionally skip the
  `updateConversationStatusIfActive(..., "failed")` write — which the cc-dispatcher catch does not
  have to think about (it has no failed-status write in that ladder).

### Multi-leader fan-out (legacy-path-specific behavior)

`sendUserMessage`'s multi-leader branch calls `dispatchToLeaders` (`agent-runner.ts:~2550`),
which fans out to `startAgentSession` at `:2576` and `:2587` — one closure per leader. Because the
gate lives INSIDE `startAgentSession`, every leader's dispatch is gated (good — full coverage), but
a single not-ready multi-leader dispatch will emit **N identical `{ type: "error" }` frames** (one
per leader). The Concierge path has no such fan-out, so this is a legacy-path-specific behavior the
"single point" framing glosses (architecture review P1). **Disposition: accept the N-emit** — it is
not a correctness bug (each frame is the honest message), the client already renders error toasts
idempotently for a given conversation, and gating once before fan-out would re-introduce a second
gate site the source plan deliberately rejected. AC10 documents the accepted behavior; do NOT add a
pre-fan-out gate.

**Recommendation: Option A.** It is cheaper (no lease/credential for a not-ready dispatch),
matches the source-gate intent more faithfully ("before spawn/clone"), and avoids threading a new
branch through the most delicate part of the runner (the outer catch that also clears
session_id-adjacent state and marks conversations failed). The Sentry-skip + no-failed-write are
satisfied by construction (the early return never reaches either). The trade-off — a second
client-emit path that does not share the catch ladder — is acceptable because the emit is a single
`sendToClient` reusing the exact shape cc-dispatcher catch B uses.

### Why no new test for the evaluator

`evaluateRepoReadiness`'s branches (`cloning` / `error` / fail-open default) are already fully
covered by `apps/web-platform/test/repo-readiness.test.ts`. This plan adds only a **wiring** test
for the legacy path (the gate read → block → honest emit → Sentry-skip → no-spawn), mirroring the
existing `agent-runner-reprovision.test.ts` mock harness which already mocks `@sentry/nextjs`
(`captureException`), `../server/ws-handler` (`sendToClient`), and `../server/current-repo-url`.

## Files to Edit

- `apps/web-platform/server/agent-runner.ts` — add the gate (Option A: top of `startAgentSession`
  before `registerSession`/`resolveKeyOwnerThenLease`, early-return on `!ok`). Imports: verify
  whether `getCurrentRepoStatus` is already in the existing `./current-repo-url` import line
  (`getCurrentRepoUrl` is) and extend it rather than duplicate; add `evaluateRepoReadiness` from
  `./repo-readiness`. Under Option A the early-return path does not throw the class, so
  `RepoNotReadyError` import is **not** required — include it only if Option B is chosen at /work
  time.
- (Option B only, if chosen) `apps/web-platform/server/agent-runner.ts` outer catch (`:2475`) —
  new `else if (err instanceof RepoNotReadyError)` branch above the generic `else`, emitting
  `err.message` + `err.errorCode`, skipping Sentry + the failed-status write.

## Files to Create

- `apps/web-platform/test/agent-runner-repo-readiness-gate.test.ts` — wiring test (vitest, node
  project; path matches the `test/**/*.test.ts` include glob in `vitest.config.ts`). Mirrors
  `agent-runner-reprovision.test.ts` hoisted-mock harness (which already mocks `@sentry/nextjs`,
  `../server/ws-handler`, `../server/current-repo-url`). Cases:
  1. `getCurrentRepoStatus` → `{ repoStatus: "cloning", repoError: null }`: asserts `sendToClient`
     receives `{ type: "error", message: REPO_CLONING_MSG }` (no `errorCode`); `query` (SDK) NOT
     called; `captureException` NOT called; conversation NOT marked failed.
  2. `getCurrentRepoStatus` → `{ repoStatus: "error", repoError: <sanitized JSON payload> }`:
     asserts `sendToClient` message matches `repoErrorMsg(...)` AND carries
     `errorCode: "repo_setup_failed"`; `query` NOT called; `captureException` NOT called.
  3. `getCurrentRepoStatus` → `{ repoStatus: "ready", repoError: null }`: gate is a no-op — the
     existing dispatch path proceeds (assert the gate's `sendToClient` error-emit is NOT fired;
     downstream mocks may short-circuit the rest of the session).
  4. `getCurrentRepoStatus` → `{ repoStatus: "not_connected", repoError: null }` (fail-open
     default): gate is a no-op (same as case 3) — proves a not-connected workspace flows
     unchanged into the existing repo-less / #5392 path.
  5. `getCurrentRepoStatus` mock REJECTS (throws a non-RuntimeAuthError): the gate's fail-open
     try/catch fires — `reportSilentFallback` is called with
     `op: "repo-readiness-gate.read"`, the gate does NOT emit an error frame, and dispatch
     PROCEEDS (no dead-end). Verifies AC11 (the F1 fix).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — A leader dispatch (`startAgentSession`) against a `cloning` active workspace spawns NO
  agent: `query`/SDK is not invoked, no clone is attempted, and the client receives
  `{ type: "error", message: REPO_CLONING_MSG }`. Verified by the new wiring test case 1.
- **AC2** — A leader dispatch against an `error` active workspace emits
  `{ type: "error", message: repoErrorMsg(<sanitized reason>), errorCode: "repo_setup_failed" }`
  and spawns no agent. Verified by wiring test case 2.
- **AC3** — A `cloning`/`error` block does NOT mirror to Sentry: `Sentry.captureException` is not
  called on the gate path. Verified by wiring test cases 1 + 2 asserting the mock is not called.
- **AC4** — A `cloning`/`error` block does NOT mark the conversation `failed`
  (`updateConversationStatusIfActive(..., "failed")` not invoked on the gate path) — a transient
  block must not nuke a resumable conversation. Verified by the wiring test (mock assertion).
- **AC5** — A `ready` and a `not_connected` workspace are no-ops for the gate: the gate's
  error-emit does not fire and dispatch proceeds. Verified by wiring test cases 3 + 4.
- **AC6** — No new predicate / error class / copy is introduced: `git diff origin/main --
  apps/web-platform/server/repo-readiness.ts apps/web-platform/server/current-repo-url.ts` is
  empty (the primitives are reused, not modified). Verified by `git diff --stat`.
- **AC7** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- **AC8** — `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-repo-readiness-gate.test.ts test/repo-readiness.test.ts` passes (the new wiring test + the unchanged evaluator suite).
- **AC9** — The gate is the single point covering all legacy-leader entry points:
  `git grep -n "startAgentSession(" apps/web-platform/server` confirms the ws-handler
  `pendingLeader` call (`ws-handler.ts:2241`), the three `sendUserMessage` call sites
  (`agent-runner.ts:2793/2817/2833`), AND the `dispatchToLeaders` fan-out sites
  (`agent-runner.ts:2576/2587`) all route through the gated function — no per-caller wiring is
  added.
- **AC10** — The gate sits ABOVE `const existing = getSession(...)` (`agent-runner.ts:~876`) and
  ABOVE `registerSession` (`~:885`): a blocked dispatch must not abort the in-flight prior session
  or register a dangling session. Verified by Phase 0 reading + a test assertion that a `cloning`
  block does NOT call `getSession`/`registerSession` (mock assertion) — or, minimally, a code
  review check that no session-mutating call precedes the gate.
- **AC11** — The gate read is fail-open on an unexpected throw: if `getCurrentRepoStatus` rejects
  (non-RuntimeAuthError), the gate mirrors via `reportSilentFallback`
  (`op: "repo-readiness-gate.read"`) and PROCEEDS (does not block, does not dead-end). Verified by a
  wiring test case 5: `getCurrentRepoStatus` mock rejects → dispatch proceeds + `reportSilentFallback`
  called + no error frame emitted by the gate.
- **AC12** — A not-ready multi-leader dispatch (`dispatchToLeaders`) emits one error frame per
  leader (accepted N-emit). Documented, not gated pre-fan-out. (Behavioral note; no new test
  required beyond AC1/AC2 which already cover the single-leader emit.)

### Post-merge (operator)

- None. Pure code change; the `web-platform-release.yml` pipeline restarts the container on merge
  to main touching `apps/web-platform/**` (path-filtered `on.push`), so the merge itself is the
  deploy. No migration, no Doppler change, no Terraform.

## Observability

```yaml
liveness_signal:
  what: "structured logger.info breadcrumb on every gate block (op=repo-readiness-gate, code=cloning|error)"
  cadence: "per blocked legacy-leader dispatch"
  alert_target: "Better Stack — alert on a code=error spike; NEVER alert on cloning (expected transient)"
  configured_in: "apps/web-platform/server/agent-runner.ts (gate block) + existing pino->Better Stack log pipeline"
error_reporting:
  destination: "Sentry — INTENTIONALLY SKIPPED for RepoNotReady blocks (expected transient/benign, not an incident); the underlying repo-setup error was already mirrored at the /api/repo/setup write boundary. An UNEXPECTED throw from the gate read (non-RuntimeAuthError, current-repo-url.ts:126) IS mirrored via the gate's own fail-open try/catch (reportSilentFallback op=repo-readiness-gate.read) — the F1 fix, NOT skipped."
  fail_loud: "the gate is fail-open (read blip / unexpected throw -> proceed, never block). Precise carve-out: the STATUS read (workspaces.repo_status) mirrors a DB error via reportSilentFallback inside getCurrentRepoStatus (already shipped); the REASON read (users.repo_error, current-repo-url.ts:159-163) fails open to generic copy WITHOUT a mirror BY DESIGN — accepted because it only degrades message specificity, never readiness. AC6 forbids touching that file, so this carve-out is stated, not fixed."
failure_modes:
  - mode: "false-positive block of a ready founder"
    detection: "evaluateRepoReadiness is fail-open by construction (only cloning/error block); a code=cloning breadcrumb for a user whose workspaces.repo_status is ready would indicate a status-read consistency bug"
    alert_route: "Better Stack breadcrumb rate (code=cloning) cross-referenced against repo_status; no Sentry page (would flood)"
  - mode: "status-read DB error"
    detection: "getCurrentRepoStatus reportSilentFallback (op=read-current-repo-status) — already shipped in #5395"
    alert_route: "Sentry (existing)"
  - mode: "leaked raw stderr in error-branch message"
    detection: "message is built by evaluateRepoReadiness via parseErrorPayload + sanitizeGitStderr (unchanged); covered by repo-readiness.test.ts AC9"
    alert_route: "n/a — sanitized at rest + re-sanitized in the evaluator; no new surface"
logs:
  where: "pino structured logs -> Better Stack (existing web-platform log pipeline)"
  retention: "existing Better Stack retention (no change)"
discoverability_test:
  command: "curl -s deploy.soleur.ai/hooks/deploy-status (deploy health) + Better Stack query feature=agent-runner op=repo-readiness-gate"
  expected_output: "post-merge: deploy healthy; on a real cloning-window leader dispatch, a code=cloning breadcrumb appears in Better Stack with NO corresponding Sentry event"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a server-side dispatch-gating change reusing
already-shipped primitives. No UI surface (the client receives an existing `{ type: "error" }` WS
message shape with an existing `errorCode`; no new component, page, or flow). No
Files-to-Edit/Create path matches the UI-surface term list (`components/**`, `app/**/page.tsx`,
etc.) — the mechanical Product/UX override does not fire. No engineering-architecture decision
beyond the Option A/B placement (surfaced for plan-review). Infrastructure: none (Phase 2.8 skip —
edits only `apps/web-platform/server/` + `apps/web-platform/test/`). GDPR/compliance: the gate
reads an existing `repo_status` column and reuses the already-audited sanitization path; no new
regulated-data processing (Phase 2.7 skip — the (a)-(d) expansion triggers also do not fire: no
new LLM processing, no new cron/distribution surface; brand-survival threshold is inherited from
#5395, not net-new).

## Open Code-Review Overlap

Two open `code-review` issues mention `agent-runner.ts` in their bodies; both **acknowledged**
(different concern — neither touches the dispatch-gate / `startAgentSession` entry path this plan
edits):

- **#3454** (`review: expose pdf_metadata as agent-callable MCP tool`) — PDF-metadata MCP tool
  surface, unrelated to repo-readiness gating. Stays open.
- **#3242** (`review: tool_use WS event lacks raw name field for agent consumers`) — WS `tool_use`
  event shape, unrelated to the dispatch gate. Stays open.

No open issue touches `repo-readiness.ts` or the readiness-gate code path. No fold-in needed.

## Risks & Mitigations

- **Risk (silent-failure review F1, HIGH): Option A's gate sits ABOVE the outer `try` (`:930`), so
  an unexpected throw from `getCurrentRepoStatus` escapes uncaught.** `getCurrentRepoStatus`
  fails-open only for `RuntimeAuthError` (`current-repo-url.ts:116-125`) and `statusRes.error`
  (`:147-153`); any OTHER throw hits the bare `throw err` at `:126` and propagates UP — past the
  new pre-`try` gate, out of `startAgentSession` entirely. The user gets no error frame, the
  conversation is not marked failed, and Sentry may or may not see it depending on the caller's
  await handling. The cc-dispatcher precedent does NOT share this seam (its read is inside an
  existing `try`). **Mitigation (in the gate snippet above):** wrap the gate read in its own
  fail-open try/catch — mirror via `reportSilentFallback` (`op: "repo-readiness-gate.read"`) and
  set `repoReadiness = { ok: true }` (proceed; degrade to the existing repo-less / #5392 path).
  AC11 + wiring test case 5 verify it.
- **Risk (architecture review P1): Option A's early `return`/blocked dispatch must not abort the
  in-flight prior session or leave a dangling registered one.** `startAgentSession` runs a
  supersede-abort (`const existing = getSession(...)` at `:876`) then `registerSession` at `:885`.
  If the gate sits BELOW `:876`, a blocked not-ready dispatch first kills the user's running prior
  turn, then bails — leaving the conversation with no active session and no replacement.
  **Mitigation:** place the gate as the FIRST statement of `startAgentSession`, ABOVE `:876` (not
  merely above `registerSession`). /work Phase 0 MUST read `agent-runner.ts:870-890` and pin the
  exact insertion point (immediately after the JSDoc/param list); AC10 asserts no session-mutating
  call precedes the gate. (Load-bearing — see Sharp Edges.)
- **Risk: extra DB read on the leader hot path.** `getCurrentRepoStatus` adds one tenant-mint +
  two parallel selects per leader dispatch. The cc-dispatcher path parallelized it into an
  existing `Promise.all`; the legacy path has no such pre-lease `Promise.all`, so under Option A it
  is a sequential await at the top of `startAgentSession`. **Mitigation:** the read is fail-open
  and gates BEFORE the (heavier) lease acquisition + agent spawn, so net latency for a `ready`
  dispatch is one extra round-trip before work that already does several. Acceptable; note in the
  PR body. Do NOT attempt to fold it into a `Promise.all` with the lease — the lease body resolves
  `workspaceId` internally and the gate must precede the lease.
- **Risk: `RepoNotReadyError` import unused under Option A.** Under the recommended early-return
  design the class is not thrown, so importing it would be a dead import (lint/tsc noise). Import
  only `evaluateRepoReadiness` — the message + `errorCode` come from the evaluator's return value,
  so `REPO_CLONING_MSG`/`repoErrorMsg` are not needed at the gate site either. Verify imports at
  /work time.
- **Risk: `getCurrentRepoStatus` already imported?** `agent-runner.ts` imports `getCurrentRepoUrl`
  from `./current-repo-url` (used in the reprovision block). Verify whether `getCurrentRepoStatus`
  is already in that import statement; extend it rather than adding a duplicate import line.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above.)
- **Option A ordering is load-bearing.** The gate must sit ABOVE `const existing = getSession(...)`
  (`:876`) — not merely above `registerSession` (`:885`). Placing it between the two still kills
  the in-flight prior session before bailing. The cc-dispatcher gate did not face this because it
  lives inside the factory, not at a session-registration boundary. /work Phase 0 must read
  `agent-runner.ts:870-890` and pin the exact insertion point.
- **Option A introduces a pre-`try` uncaught-throw seam the cc-dispatcher precedent lacks.** The
  gate read sits above the outer `try` (`:930`); a non-RuntimeAuthError throw from
  `getCurrentRepoStatus` (`current-repo-url.ts:126`) would escape uncaught (no Sentry, no client
  error). The gate snippet's fail-open try/catch is NOT optional — it is the F1 fix. Do not drop
  it as "defensive boilerplate."
- **Do not add a new error-branch to the outer catch under Option A.** The early-return design
  intentionally bypasses the catch ladder (which marks conversations failed + clears session
  state). Adding both the early return AND a catch branch would double-handle the block. Choose
  ONE placement (A or B) at /work time and implement only that one.
- **`resolveSessionErrorCode` returns `undefined` for `RepoNotReadyError`** (`agent-runner.ts:110`).
  Under Option B, the catch branch must read `err.errorCode` directly (mirroring cc-dispatcher
  catch B at `cc-dispatcher.ts:3422`), NOT rely on `resolveSessionErrorCode`. Under Option A this
  is moot (the evaluator's `errorCode` is spread directly).
- **Reuse `getCurrentRepoStatus`, not a fresh `users.repo_status` read.** A naive inline
  `users.repo_status` select would re-create the #4543 invited-member divergence the source plan
  fixed — `repo_status` lives on `workspaces` post-ADR-044. `getCurrentRepoStatus` encodes the
  correct source-of-truth split; do not bypass it.

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| **Option B (throw `RepoNotReadyError` inside the lease body + new catch branch)** | Acquires the BYOK lease + fetches a credential before the gate fires (wasted work for a known-not-ready dispatch); threads a new branch through the delicate outer catch that also marks conversations failed. Recommended fallback only if Option A's pre-`registerSession` ordering proves infeasible. |
| **Gate in the ws-handler `pendingLeader` branch (`:2241`)** | Misses the `sendUserMessage` multi-leader entry points (`:2793/2817/2833`). Not server-authoritative for the whole legacy surface. The source plan explicitly dropped the redundant ws-handler short-circuit in favor of the single choke point. |
| **Make the gate `throw` and rely on the existing generic `else`** | The generic `else` mirrors to Sentry AND marks the conversation failed — exactly the two behaviors a transient `cloning`/`error` block must avoid. Would page on every cloning-window turn and nuke resumable conversations. |
| **Add a new predicate / error subtype for the legacy path** | Violates the issue's explicit "reuse existing primitives — no new predicate" constraint. The pure evaluator + error class already cover both states and are tested. |

## Out of Scope

- Synchronous clone-await / clone-progress reporting (the source plan's out-of-scope; the gate
  shows a static "still being set up" message, not a progress bar).
- Any change to `repo-readiness.ts`, `current-repo-url.ts`, or `/api/repo/setup` (reused
  unchanged — AC6 enforces an empty diff).
- Decommissioning the legacy `startAgentSession` path (the issue's re-evaluation note: if the
  path is later retired, close that as a separate obsolescence task).
