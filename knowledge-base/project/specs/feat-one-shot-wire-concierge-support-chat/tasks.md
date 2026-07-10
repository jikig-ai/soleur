---
name: tasks-feat-one-shot-wire-concierge-support-chat
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-10-feat-wire-concierge-support-chat-plan.md
brand_survival_threshold: single-user incident
---

# Tasks: Wire the Concierge into the 24/7 support chat

Derived from `2026-07-10-feat-wire-concierge-support-chat-plan.md` (post 3-reviewer
pass: fable advisor + Kieran + architecture-strategist + spec-flow). Ships as one atomic
feature; all server wiring under `apps/web-platform/**`. Threshold: single-user incident
→ CPO sign-off + `user-impact-reviewer` at review.

## Phase 0 — Preconditions
- [ ] 0.1 `soleur:flag-list` — confirm `support` ON in prd (do not re-provision; stale `server.ts` comment).
- [ ] 0.2 `git grep -rln "realSdkQueryFactory\|dispatchSoleurGo" apps/web-platform/test/` → 19-file factory sweep.
- [ ] 0.3 Read the `routineAuthoring` hops + the dispatch write sites (`cc-dispatcher.ts:3087/3151/3169/3498/965`) + `handleResumeStream` (`ws-handler.ts:1458-1504`).
- [ ] 0.4 Read ADR-070/086/093; confirm `permission-callback.ts:883` Skill chokepoint + `:1020-1030` deny-with-message precedent + `:240` cwd-relative containment.
- [ ] 0.5 Confirm `conversations.repo_url` nullable (done); `agent-runner-sandbox-config.ts:213-221` ro-bind / allowWrite.

## Phase 1 — Two-axis ExecutionEnvironment seam (characterization-guarded)
- [ ] 1.1 Feathers characterization tests: snapshot the Command Center gate sequence (readiness→clone→lease→cwd→permission-patch) + the dispatch persistence writes; assert byte-neutral after refactor.
- [ ] 1.2 `server/execution-environment.ts`: `ExecutionEnvironment` (workspace) + `RepoWorkspaceProvider`/`ReadOnlyDocsProvider`; `ConversationStore` + `PersistedConversationStore`/`NullConversationStore`. Seam contract carries the always-on halves (narration MCP tools, always-on prompt sections, `applyPrefillGuard`, ack-posture register/release) + an INJECTED caller-owned AbortController; nests INSIDE the BYOK lease; convert cleanup to try/finally preserving `flushCcToolAttemptCollector` + ack-posture release.
- [ ] 1.3 Rewire `realSdkQueryFactory` + `dispatchSoleurGo` write sites to consume both providers; characterization tests green.
- [ ] 1.4 `persona` enum on dispatch/QueryFactory args; hop-audit comment enumerating BOTH axes (provider/persistence + skill-allowlist) and their distinct drop-failure modes.
- [ ] 1.5 `ws-handler.ts` — resolve `persona:"support"` from `chatContext.type`; auth-guard; select the support providers.

## Phase 2 — Conversation strategy (CTO decision B1 vs B2)
- [ ] 2.1 Decide B1 (ephemeral `NullConversationStore` + suppress support resume path) vs B2 (persisted repo-less `kind='support'` row — lower dispatch surgery, resolves reconnect, needs GDPR gate). Default lean: B2 unless a driver rejects the DB surface.
- [ ] 2.2 Support dispatch uses `ReadOnlyDocsProvider` (no readiness/clone/lease/permission-patch); keep BYOK lease + rate limiter; confirm no shared-bucket bypass/starve.
- [ ] 2.3 Handle the reconnect-replay cliff per the chosen strategy (suppress resume for B1; row-exists for B2).
- [ ] 2.4 Repo-free fail-loud defense-in-depth; file the persistence-follow-up deferral issue if B1.

## Phase 3 — Skill + tool scoping
- [ ] 3.1 `server/support-directive.ts`: `SUPPORT_SYSTEM_DIRECTIVE` (append) + `SUPPORT_SKILL_ALLOWLIST = {kb-search}` + anchored `soleur:` bare↔FQN normalizer.
- [ ] 3.2 Branch `buildSoleurGoSystemPrompt` to emit support routing (NOT `/soleur:go`) when `persona:"support"`; append the directive only in that mode (no conflict).
- [ ] 3.3 Default-deny skill allowlist in `createCanUseTool` (`isSafeTool` Skill branch): allow only normalized `kb-search`, else `{behavior:"deny", message}`. `CanUseToolDeps`/`CanUseToolContext` gains `persona`. Thread persona from `cc-dispatcher.ts:2677`.
- [ ] 3.4 Support `extraDisallowedTools` += `Edit,Write,MultiEdit,NotebookEdit,Task,Agent` (pinned, not inherited); KEEP `Bash`; every allow returns `{behavior:"allow", updatedInput: toolInput}`.

## Phase 4 — Support answer corpus (HARD PRECONDITION — internal-KB leak blocker)
- [ ] 4.1 Curate an end-user product-help corpus (how-to/navigation), likely from `plugins/soleur/docs/pages/*.njk`.
- [ ] 4.2 Hard-restrict the support search root so support `kb-search` (or a support-only read tool) CANNOT read `knowledge-base/` internal domains. Enforce at tool/root level, not prompt.
- [ ] 4.3 If corpus not curated in this PR → gate the Phase 6 copy flip OFF (do not promise live answers over internal KB).

## Phase 5 — Front-end streaming seam + flow states
- [ ] 5.1 `use-support-chat.ts`: async streaming `send()` (cumulative-replace), pending/streaming/error state, `.catch()`.
- [ ] 5.2 Minimal support WS client hook (or scoped `useWebSocket`) with identity + support conversation id.
- [ ] 5.3 `canned-responder.ts` → fallback for flag-off / transport-error / **persona-unresolved** (S2) — never `RepoNotReadyError` under live copy.
- [ ] 5.4 `support-message.tsx`: streaming/typing indicator; error+retry bubble on transport failure AND stream-idle timeout (S5); empty-KB state with escape-hatch (S3); refusal keeps escape-hatch (S4); PREVIEW badge removed.
- [ ] 5.5 Close-mid-turn = abort-on-close (S1); no duplicate bubble on retry; state survives close/reopen without orphaning the turn.

## Phase 6 — Persona copy flip (gated on Phase 4)
- [ ] 6.1 `support-persona.ts`: flip greeting/preview-note/composer-footnote/panel-subtitle to live; keep persistent "AI-generated, may be wrong" disclosure.
- [ ] 6.2 Update stale `feature-flags/server.ts` comment; copywriter/CPO review copy.

## Phase 7 — Observability
- [ ] 7.1 `op:support-*` slugs on every un-recovered support path; final-recoverability gating.
- [ ] 7.2 In-sandbox structured event ({persona, skillDenied, repoGateBypassed}) discriminating root causes in one event.

## Phase 8 — Tests
- [ ] 8.1 Rewrite `canned-responder.test.ts` (async fallback incl. persona-unresolved).
- [ ] 8.2 Invert `support-panel.test.tsx:62` fetch-not-called; keep markdown/link assertions.
- [ ] 8.3 `support-launcher.test.tsx` + identity/context threading.
- [ ] 8.4 New: `execution-environment.test.ts`, `cc-dispatcher-support-mode.test.ts` (repo-gate bypass + dispatch-persistence skip/row + directive), `permission-callback-support-skill-allowlist.test.ts` (deterministic; bare+FQN; deny-with-message; integration persona→CanUseToolDeps).
- [ ] 8.5 Inert-default sweep into all 19 factory consumers; `vitest run` exit gate.
- [ ] 8.6 Groundedness assertion: driven "how do I create a routine?" reply has NO internal-KB content.
- [ ] 8.7 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` + `./node_modules/.bin/vitest run` (node `.test.ts` + jsdom `.test.tsx` projects).

## Phase 9 — ADR-109 + ADR-070 amendment + C4
- [ ] 9.1 Author ADR-109 (two-axis seam, ephemeral/persisted decision, default-deny allowlist; ground ADR-070 in deny-with-message-vs-silent-removal `:1020-1030`; justify Edit/Write/Task/Agent disallow; reconcile ADR-093). Re-verify next-free ordinal at ship.
- [ ] 9.2 One-paragraph amendment to ADR-070 (binds #5772 implementer).
- [ ] 9.3 Edit `model.c4`/`views.c4` (annotate support-scoped read-only mode); `bash scripts/regenerate-c4-model.sh`; commit `model.likec4.json`; `c4-code-syntax.test.ts` + `c4-render.test.ts` green.

## Post-merge (automatable)
- [ ] P.1 Playwright-drive support as a repo-less user post-deploy; confirm a real grounded streamed reply + `op:support-*` Sentry markers fire; confirm NO internal-KB content in replies. Bake into `/work` post-deploy verify or `/ship`.
