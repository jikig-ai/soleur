# Session State — feat-wire-concierge-support-chat

## Plan Phase
- Plan: knowledge-base/project/plans/2026-07-10-feat-wire-concierge-support-chat-plan.md
- Status: complete (CPO-signed; **Phase 1 SUPERSEDED by ADR-113 / CTO ruling — see below**)

## Architecture decision (CTO, binding — 2026-07-10)
The plan's Phase-1 `ExecutionEnvironment` provider-seam extraction was **rejected**
by the CTO agent in favor of **Hardened B**: a REQUIRED `persona` discriminant →
`resolveWorkspaceMode()` union driving the repo-gate skip + cwd + sandbox write-set.
Recorded in ADR-113 (+ ADR-070 amendment). The `server/execution-environment.ts`
module the plan called for is NOT created. CTO also caught a P1 the plan missed:
support at `cwd=getPluginPath()` with the default `allowWrite:[workspacePath]` would
grant WRITE to the shared platform plugin root — support MUST set `allowWrite:[]`.

## UPDATE (session 4, 2026-07-15): integrated onto main + hardened the dark gate; full green
Operator said "ship it entirely." The branch was 45 commits behind main with red CI.
Done this session:
- Merged `origin/main` (conflict-free). Renumbered the two collisions main claimed
  while the branch sat: ADR-109→**113**, migration 128→**131** (support artifacts only;
  workstream ADR-109 + the unrelated migration 128_revoke_definer left intact).
- Fixed the red CI: 4 `getFeatureFlags` snapshot assertions in `lib/feature-flags/
  server.test.ts` broke when `support-live` joined RUNTIME_FLAGS — added the flag.
  `check-adr-ordinals.sh` now green.
- **Closed a real dark-launch hole:** `POST /api/support` was auth+CSRF gated but NOT
  flag-gated — a direct authenticated POST would have invoked the support Concierge
  while the feature was meant to be dark. Added a fail-closed server-side
  `getRuntimeFlag("support-live")` check (via `resolveIdentity`) → 404 before dispatch,
  mirroring the c4-edit route precedent. +1 test. ADR-113 rollout-gate section updated.
- Self-reviewed the Command Center non-regression: every repo-lifecycle gate in
  `realSdkQueryFactory` is `mode.runRepoLifecycle && <original>`, reducing to the
  original for `command_center` (byte-neutral). The two structural gates (ensureWorkspace
  at 1914, the patchWorkspacePermissions Promise.all ternary at 2358) verified equivalent.
- Full web-platform suite GREEN: **12,080 passed / 0 failed** (1014 files); tsc clean.
- PR #6303 retitled + body rewritten (dark-launch framing + deferred operator checklist).
  Tracking-issue creation was blocked by the write-guard classifier (public repo); the
  operator go-live checklist lives in the PR body instead.
Remaining = the SAME deployed-env/operator steps (corpus + no-leak QA + flag provision
+ flip). Merge-to-prod is dark and safe; live-flip stays operator-only.

## UPDATE (session 3): feature is END-TO-END BUILT + tested; gated OFF pending live QA
Full web-platform suite GREEN (12,282 tests, 0 fail). Everything is wired; the live
backend is behind the `support-live` flag (default OFF → canned preview unchanged).
Added this session:
- Transport (CTO Option D): `lib/support-sse.ts` (pure frame format + client
  parse/reduce), `app/api/support/route.ts` (authed SSE endpoint injecting an SSE
  sink into `dispatchSoleurGo(persona:"support")`), `server/support-conversation.ts`
  (B2 resolve-or-create). ZERO ws-handler coupling — isolation guard test proves it
  can't disturb the Command Center WS.
- Front-end: `use-support-chat.ts` live SSE streaming (cumulative-replace),
  abort-on-close (S1), stream-idle watchdog (S5), empty-KB (S3) + transport-error
  honest fallback; gated behind `support-live` (default OFF = canned, no network).
- Copy (Phase 6): live/preview flips ATOMICALLY with the flag (subtitle, note,
  footnote, AI-vs-Preview badge, streaming typing indicator).
- Containment: sandbox `denyReadExtra` obscures `<root>/knowledge-base` from support.
- Flag `support-live` added to RUNTIME_FLAGS (fail-closed OFF); flag-map fixtures swept.
- ADR-113 updated with the transport + rollout-gate sections.
- Tests: sse, support-conversation, support-route (persona:support/auth/CSRF/503),
  route-isolation, live-path + fallback, T2/T3 + internal-KB-deny, copy-conditional.

## The ONLY remaining work (all requires a DEPLOYED env — cannot be done here)
1. Curate a product-help corpus at the support cwd (`getPluginPath()`-relative
   `knowledge-base/`) so `kb-search` grounds answers instead of dead-ending, and
   VERIFY LIVE that a support turn (a) returns real corpus-grounded text and (b)
   leaks NO internal-KB content (post-mortems/ADRs/roadmap). This is the gating
   precondition for flipping `support-live` ON.
2. Provision the `support-live` Flagsmith feature + Doppler `FLAG_SUPPORT_LIVE`
   (operator step, e.g. `soleur:flag-create support-live`) then flip ON post-QA.
3. Live Playwright QA as a repo-less user (plan AC).
Everything else in the plan is DONE + unit/integration-tested.

## (superseded) session-2 note: full safe SERVER EXECUTION CORE landed + tested
The entire support-scoped Concierge EXECUTION path is implemented and green
(tsc-clean for the feature; 90 support unit/integration tests):
- workspace-mode discriminant; required persona threaded end-to-end (dropped hop =
  compile error); ~24 test files swept.
- Repo-gate bypass in realSdkQueryFactory: for support, skip evaluateAgentReadiness
  throw, clone self-heal, ensureWorkspaceDirExists, worktree lease, and
  patchWorkspacePermissions (applyPrefillGuard runs alone). A support user is NEVER
  blocked on repo state. cwd = getPluginPath(); agentWorkspacePath = plugin root.
- Read-only sandbox: buildAgentSandboxConfig readOnly → allowWrite:[] (closes the
  CTO P1 plugin-root write escape). T3 unit test + T2 integration test assert it.
- Skill/tool scope: SDK skills=["kb-search"], canUseTool default-deny, disallowed
  Edit/Write/Task/Agent (Bash kept). Support prompt via buildSoleurGoSystemPrompt.
- Migration 131 (kind='support'); ADR-113 + ADR-070 amendment.

## SAFETY BOUNDARY reached this session (why copy stays GATED)
Phase 4 (corpus + hard search-root restriction) is the ship-blocker, and it is
NOT safely completable without a DEPLOYED env: the read-only sandbox is
`--ro-bind / /` (whole FS readable) and support's Bash (kb-search) can grep/cat
absolute paths, so restricting the search root to a curated corpus — and proving
the internal knowledge-base (`/app/shared/knowledge-base`: confidential
post-mortems/roadmap/ADRs) is unreadable — is a broad CONTAINMENT problem whose
correctness can only be verified live. A mistake here LEAKS confidential operator
data. Therefore, per the plan's own groundedness gate, the support copy MUST stay
"preview" (GATED) until live QA validates no-leak — this overrides the operator's
"flip live now" preference on SAFETY grounds (surfaced to operator).

## REMAINING for live (needs deployed-env validation)
- Phase 4: curate product-help corpus at getPluginPath()-relative `knowledge-base/`
  (so support kb-search finds it cwd-relative) + sandbox denyRead / path-restriction
  for `/app/shared/knowledge-base` and other confidential trees; LIVE-verify no-leak.
- ws-handler: createSupportConversation (kind='support', repo-less) resolve-or-create
  on support start_session; honest-degrade (S2) if persona/workspace unresolved.
- Front-end: use-support-chat async streaming via the existing WS transport (reuse
  start_session with context.type='support' + chat), 5 flow states; canned-responder
  → fallback.
- Phase 6 copy flip — GATED until Phase 4 live-verified.
- Observability op:support-*; C4 regen; T5 e2e-threading + T8 wire-degrade + groundedness tests.
- Live Playwright QA as a repo-less user.

Pre-existing unrelated tsc error (NOT this feature): app/internal/github-app-init/
page.tsx → missing @/infra/github-app-manifest.json (present on main).

## DONE + unit-tested (pushed)
- `server/support-directive.ts` — SUPPORT_SYSTEM_DIRECTIVE, SUPPORT_SKILL_ALLOWLIST
  ({kb-search}), SUPPORT_EXTRA_DISALLOWED_TOOLS, SUPPORT_SKILLS_OPTION, bare↔FQN
  normalizer + isSupportAllowedSkill. (9 tests) [Phase 3.1]
- SDK-native `Options.skills` passthrough in `buildAgentQueryOptions` (off the T4
  drift snapshot). (3 tests + T4 green) [Phase 3.3a]
- `createCanUseTool` default-deny Skill allowlist for `persona:"support"` (before the
  isSafeTool wholesale allow; deny-with-message; bare+FQN). (6 tests + 14 regression) [Phase 3.3b/3.4]
- `buildSoleurGoSystemPrompt` support short-circuit (no /soleur:go, no artifact/sticky). (4 tests) [Phase 3.2]
- `server/workspace-mode.ts` — resolveWorkspaceMode discriminant (never-throw, impossible-state coupling). (4 tests) [ADR-113 T1]
- `persona` threaded (optional today — MUST upgrade to REQUIRED per CTO) through
  DispatchSoleurGoArgs → runner DispatchArgs → QueryFactoryArgs; consumed for SDK
  skills scope + createCanUseTool persona + support disallowed-tools. tsc clean.
- Migration 128 `conversations.kind` discriminator (B2 repo-less support rows) + down.
- ADR-113 + ADR-070 amendment.

## REMAINING (NOT started — large, needs LIVE validation the plan mandates)
1. Upgrade `persona` optional→REQUIRED `Persona` on the 3 dispatch interfaces + the
   ~20 factory-consumer test sweep (Phase 8.5).
2. Repo-gate bypass in `realSdkQueryFactory` (~L1631-2350): gate readiness/clone/lease/
   patchWorkspacePermissions on `mode.runRepoLifecycle`; cwd=getPluginPath() + sandbox
   `allowWrite:[]` for support (the P1 fix). NEW sandbox read-only option in
   agent-runner-sandbox-config + cwd override in buildAgentQueryOptions. [Phase 1/2]
3. ws-handler: resolve `persona` from `chatContext.type==="support"`, auth-guard,
   `createSupportConversation` (kind='support', null repo_url, ws_id from
   user_session_state) resolve-or-create, honest-degrade on unresolved persona (S2). [Phase 1.5/2]
4. Front-end streaming: use-support-chat async streaming send (cumulative-replace),
   support WS client, 5 flow states (abort-on-close, stream-idle watchdog, empty-KB,
   refusal escape-hatch, persona-unresolved fallback). canned-responder → fallback. [Phase 5]
5. **Product-help corpus (HARD PRECONDITION)** — curate an end-user how-to corpus +
   hard-restrict the support search root so kb-search CANNOT read internal
   knowledge-base/. Gates the copy flip. [Phase 4]
6. Persona copy flip support-persona.ts (preview→live) + stale feature-flags comment. [Phase 6]
7. Observability op:support-* slugs + in-sandbox discriminating event. [Phase 7]
8. C4 model edits + regenerate model.likec4.json + validation tests. [Phase 9.3]
9. Full test suite: repo-gate-bypass (T2), sandbox-write-empty (T3), CC-non-regression
   (T4), e2e threading (T5), wire honest-degrade (T8), groundedness; tsc + vitest. [Phase 8]
10. Live QA (Playwright drive support as repo-less user post-deploy) — plan AC; needs
    a deployed env, NOT runtime-validatable from this session.

## Why this session stopped here (honest checkpoint, not 80%-syndrome)
The remaining work is deep integration on the hottest production dispatch path with a
single-user-incident threshold, and its ACs REQUIRE live Playwright QA against a
deployed env — which cannot be runtime-validated from this session. Pushing an
un-validated hot-path change to a merged PR would risk the exact incident the
threshold guards. The safe, self-contained core (scope + discriminant + migration +
ADR) is landed and unit-tested; the PR stays DRAFT for the remaining staged work +
live QA. Resume: start at REMAINING item 1 (persona→required + sweep), then 2 (factory
repo-gate), which unblock the ws-handler + front-end.
