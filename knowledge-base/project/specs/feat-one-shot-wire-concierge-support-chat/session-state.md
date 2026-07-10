# Session State — feat-wire-concierge-support-chat

## Plan Phase
- Plan: knowledge-base/project/plans/2026-07-10-feat-wire-concierge-support-chat-plan.md
- Status: complete (CPO-signed; **Phase 1 SUPERSEDED by ADR-109 / CTO ruling — see below**)

## Architecture decision (CTO, binding — 2026-07-10)
The plan's Phase-1 `ExecutionEnvironment` provider-seam extraction was **rejected**
by the CTO agent in favor of **Hardened B**: a REQUIRED `persona` discriminant →
`resolveWorkspaceMode()` union driving the repo-gate skip + cwd + sandbox write-set.
Recorded in ADR-109 (+ ADR-070 amendment). The `server/execution-environment.ts`
module the plan called for is NOT created. CTO also caught a P1 the plan missed:
support at `cwd=getPluginPath()` with the default `allowWrite:[workspacePath]` would
grant WRITE to the shared platform plugin root — support MUST set `allowWrite:[]`.

## DONE + unit-tested (pushed)
- `server/support-directive.ts` — SUPPORT_SYSTEM_DIRECTIVE, SUPPORT_SKILL_ALLOWLIST
  ({kb-search}), SUPPORT_EXTRA_DISALLOWED_TOOLS, SUPPORT_SKILLS_OPTION, bare↔FQN
  normalizer + isSupportAllowedSkill. (9 tests) [Phase 3.1]
- SDK-native `Options.skills` passthrough in `buildAgentQueryOptions` (off the T4
  drift snapshot). (3 tests + T4 green) [Phase 3.3a]
- `createCanUseTool` default-deny Skill allowlist for `persona:"support"` (before the
  isSafeTool wholesale allow; deny-with-message; bare+FQN). (6 tests + 14 regression) [Phase 3.3b/3.4]
- `buildSoleurGoSystemPrompt` support short-circuit (no /soleur:go, no artifact/sticky). (4 tests) [Phase 3.2]
- `server/workspace-mode.ts` — resolveWorkspaceMode discriminant (never-throw, impossible-state coupling). (4 tests) [ADR-109 T1]
- `persona` threaded (optional today — MUST upgrade to REQUIRED per CTO) through
  DispatchSoleurGoArgs → runner DispatchArgs → QueryFactoryArgs; consumed for SDK
  skills scope + createCanUseTool persona + support disallowed-tools. tsc clean.
- Migration 128 `conversations.kind` discriminator (B2 repo-less support rows) + down.
- ADR-109 + ADR-070 amendment.

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
