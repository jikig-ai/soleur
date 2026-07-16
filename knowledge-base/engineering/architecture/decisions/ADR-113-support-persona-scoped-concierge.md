# ADR-113: Support-persona scoped Concierge — required-persona discriminant, `WorkspaceMode` derivation, repo-gate + sandbox-write bypass, skill/tool scope

- **Status:** adopting (feat-wire-concierge-support-chat — scoping core + discriminant + migration landed; repo-gate/sandbox wiring, ws-handler support-conversation creation, front-end streaming, product-help corpus, and live QA are sequenced within the same atomic feature branch)
- **Date:** 2026-07-10
- **Deciders:** Operator (CPO sign-off at plan time — single-user-incident threshold; chose full plan + B2 persistence + curate-corpus-now); **CTO agent (binding ruling on the repo-gate mechanism — this ADR supersedes the plan's Phase 1)**. Domain: Engineering (CTO), Product (CPO).
- **Related:** ADR-070 (two-tier fail-open / deny-with-message-not-silent-removal — reconciled below), ADR-093 (`getPluginPath()` boot-validated read-only cwd chokepoint), ADR-086/#6046 (`context_queries` web port), ADR-044 (active-workspace resolver), `agent-runner-query-options.ts` (the typed-field/derivation idiom this follows), `routine-authoring-directive.ts` (the trusted system-prompt-append precedent), plan `knowledge-base/project/plans/2026-07-10-feat-wire-concierge-support-chat-plan.md`.

> **Ordinal.** Resolved to **113** at merge-time (2026-07-15): while this branch sat, `origin/main` claimed 109 (workstream-issue-writes), 110, 111, and 112, so the original provisional 109 was renumbered to the next-free 113 (highest on `origin/main` = ADR-112). Re-verify against `origin/main` if the merge is deferred again.

## Context

The 24/7 in-app support chat (`components/support/*`, PR #5741) shipped as an interface-only shell: it renders a canned "live support coming soon" reply from the synchronous seam `getSupportReply()` in `canned-responder.ts`. The `support` flag is live for all prd users (Flagsmith 220580 + Doppler `FLAG_SUPPORT=1`). The operator wants the bubble to actually answer, routed through the **existing production Concierge** (`dispatchSoleurGo` → `realSdkQueryFactory` → `@anthropic-ai/claude-agent-sdk query()`), scoped to support-appropriate skills — NOT a parallel runner.

Two hard problems, both verified in code:

1. **The Concierge is deeply repo-coupled.** `realSdkQueryFactory` runs a repo-readiness gate → git-clone self-heal → worktree write-lease → `patchWorkspacePermissions` → bwrap `cwd = workspacePath`, and `createConversation` throws "No connected repository" when `repo_url` is null. A support user is frequently repo-less (a brand-new user asking "how do I…") — reusing the path as-is breaks support for the users who most need it.
2. **There is no skill-level gate today.** The whole soleur plugin (95 skills) is mounted and the `Skill` tool is blanket-allowed via `isSafeTool`. Scoping to support requires an actual gate.

## Decision

Run the Concierge under a **required `persona` discriminant** (`"command_center" | "support"`) that resolves ONCE into a discriminated `WorkspaceMode` union; derive the repo-gate skip, the cwd, and the **sandbox write-set** from that one value.

1. **`server/workspace-mode.ts` — the single pure module.** `resolveWorkspaceMode(persona): WorkspaceMode` returns `{ persona, runRepoLifecycle, cwdSource, sandboxWrite }` bound together at construction, with an exhaustive `never` default that THROWS on a garbage/cast value. Support = `{ runRepoLifecycle:false, cwdSource:"plugin", sandboxWrite:"none" }`; Command Center = `{ true, "workspace", "workspace" }`. Because one function builds the union, a docs cwd can never pair with a non-empty write-set (the P1 escape below) and a repo-less mode can never keep the readiness/clone/lease gates.

2. **`persona` is REQUIRED (non-optional) on the dispatch interfaces** (`DispatchSoleurGoArgs` → runner `DispatchArgs` → `QueryFactoryArgs`). The two leak axes have OPPOSITE safe defaults — a support turn's danger is *gaining* repo/write; a Command Center turn's danger is *losing* gates — so there is no safe default. Required-and-non-optional makes a dropped hop a **missing-required-field compile error** at every construction site, recovering the compile-time guarantee on both axes.

3. **Repo-gate bypass in place (not extraction).** Gate `evaluateRepoReadiness`, the clone self-heal, `acquireAndHoldWorktreeLease`, and (in the `Promise.all`) `patchWorkspacePermissions` behind `if (mode.runRepoLifecycle)`; under support run `applyPrefillGuard` alone. The outermost BYOK-lease frame, the injected `AbortController`, the `try/catch` cleanup (`flushCcToolAttemptCollector` + ack-posture release), the `soleur_platform` MCP server, and the `effectiveSystemPrompt` concat are left **physically untouched** — targeted conditionals, not a restructuring of the revenue-critical Command Center path.

4. **`cwd` + sandbox write-set derived from `mode`.** `cwd = getPluginPath()` for support (the boot-validated read-only platform docs root, ADR-093); `allowWrite = []` for support (**P1 fix** — otherwise `cwd = getPluginPath()` with the default `allowWrite:[workspacePath]` would grant WRITE to the shared platform plugin root, a supply-chain read-only-escape).

5. **Skill/tool scope (three layers).** (a) SDK-native `Options.skills = ["kb-search"]` (PRIMARY — hides every other skill from the model's context); (b) `createCanUseTool` default-deny for `persona:"support"` — a `Skill` ∉ `{kb-search}` (bare↔`soleur:`-FQN normalized) denies with a user-relayable message; (c) `disallowedTools ⊇ {Edit,Write,MultiEdit,NotebookEdit,Task,Agent}` (Bash KEPT — kb-search shells out behind the read-only safe-bash gate).

6. **Support prompt.** `buildSoleurGoSystemPrompt` short-circuits to the Soleur Support prompt when `persona:"support"` — it does NOT emit the Command Center `/soleur:go` routing line (a downstream append cannot un-say it) and ignores artifact/sticky-workflow scoping.

7. **Persistence = B2 (operator-decided).** A real `conversations` row with `kind='support'` (migration 131) + null `repo_url`, so `dispatchSoleurGo`'s persisted-row requirements (ownership probe, workspace_id read, messages FK) are satisfied without dispatch-persistence surgery, and the reconnect-replay cliff is resolved naturally.

## ADR-070 reconciliation

The support scope uses two mechanisms ADR-070 governs: (a) the `createCanUseTool` default-deny returns a **graceful `{behavior:"deny", message}` the model relays** — NOT the silent phase-scope deny ADR-070 forbids; (b) the `disallowedTools` removal of Edit/Write/MultiEdit/NotebookEdit/Task/Agent is a silent removal, but is acceptable — and NOT the additive-hint-only violation ADR-070 forbids — because those are tools a support user NEVER legitimately needs, so their removal breaks no valid flow. A one-paragraph amendment to ADR-070 records this carve-out.

## Rejected alternatives

- **Plan's Phase-1 `ExecutionEnvironment` provider-seam extraction** (two composition roots so mode-leak is a compile error). **Rejected by the CTO ruling.** Its safety claim rests on characterization tests that snapshot the *options object*, but its real risk (lease/abort/cleanup ordering in the outermost braided frame at `cc-dispatcher.ts:1648/2402/2709/2721/2727`) lives OUTSIDE that object and is not runtime-validatable by the implementing agent; it lands silently on the paying-customer Command Center path. It eliminates only 1 of the 2 documented leak axes (the plan concedes the skill-scope axis stays a runtime value); its own design keeps 3 braided constructs on the always-on side, so the two-provider boundary is not clean; and it introduces a pattern foreign to a subsystem that already has a proven typed-field/derivation idiom. **This ADR supersedes the plan's Phase 1** and deletes the planned `server/execution-environment.ts` module. Surfaced to the operator/CPO (this record + the PR body) rather than silently substituted, per the single-user-incident threshold.
- **Naive optional `persona` + scattered `if(persona==="support")` branches.** Rejected: optional silently defaults on a dropped hop; independent gate-vs-cwd branches can drift; and it does not force the sandbox write-set to track the cwd, leaving the P1 plugin-root write escape latent.
- **B1 ephemeral (`NullConversationStore`).** Rejected by the operator in favor of B2 — B1 needs MORE dispatch surgery (skip 5 write sites) and loses the support thread on a brief disconnect.
- **`kb-search` over the internal `knowledge-base/`.** Rejected as a ship-blocker — it would narrate the operator's confidential post-mortems/roadmap/ADRs to any end user. Support reads ONLY a curated product-help corpus, search-root-restricted (Phase 4).

## Transport (CTO ruling #2 — Option D: dedicated SSE, WS untouched)

The support chat is a global bubble overlay; a concurrent conversation to the
Command Center. But the WS transport is single-per-user (`ws-handler.ts`
`supersedeExistingUserSocket` closes any second per-user socket), so support cannot
open its own `useWebSocket` without dropping the CC agent session. **Ruling:
support streams over a dedicated `POST /api/support` + Server-Sent-Events response,
sharing ZERO runtime with the WS.** It reuses `dispatchSoleurGo`'s INJECTED
`sendToClient` — the route hands it an SSE-writing sink and passes `persona:"support"`.
`supersedeExistingUserSocket` and the `sessions` map are untouched (the whole point).
An **isolation guard test** asserts the support route + hook import neither, so a
future edit can't re-introduce the CC-supersession risk. Rejected: A (multiplex — edits
the shared router, unverifiable), B (per-channel socket key — rewrites the exact CC-
protecting line), C (on-demand WS that supersedes CC — drops the paying agent session,
no auto-reconnect). New: `lib/support-sse.ts` (pure frame format + client parse/reduce),
`server/support-conversation.ts` (B2 resolve-or-create), `app/api/support/route.ts`.

### Transport completion semantics (correction, 2026-07-15 — live-QA finding)

Reusing `dispatchSoleurGo`'s injected sink hid a lifetime mismatch that only
surfaced live: `dispatchSoleurGo` **resolves as soon as the turn's SDK query is
started** — the runner consumes it on a fire-and-forget task (`void consumeStream`
in `soleur-go-runner.ts`), so `onText`/`stream` frames arrive AFTER the dispatch
promise settles. The Command Center's WS sink is process-lived, so this is invisible
there; but the SSE stream is per-REQUEST, and the route originally closed the
`ReadableStream` in a `finally` right after `await dispatchSoleurGo(...)` — i.e.
BEFORE the first token. Every support turn therefore ran to completion server-side
(LLM called, usage + reply persisted) while the client received an empty stream and
fell back to canned. **Fix:** the route holds the SSE open until a TERMINAL frame
(`stream_end`/`session_ended`/`error`) or a hard cap (`SUPPORT_TURN_MAX_MS`), not on
the dispatch promise; regression test in `support-route.test.ts` emits frames AFTER
the dispatch mock resolves. Corollary fix: `getSoleurGoRunner` is a process singleton
whose captured sink feeds only `emitInteractivePrompt` — the support dispatch now
passes the process-stable `defaultSendToClient` (a no-op for CC, since its
`sendToClient` IS `defaultSendToClient`) instead of the per-request SSE sink, so the
singleton never captures a request-scoped closure and the "re-init with different
sendToClient" guard no longer fires per support turn. Unit-mock dispatch tests missed
both because they resolved the injected sink synchronously.

## Live rollout gate (`support-live` flag)

The live backend is gated behind a NEW `support-live` runtime flag, default OFF: while
OFF the bubble shows the canned interface-preview reply (no network); the copy flips
live/preview atomically with the flag. **The gate is enforced server-side, not only in
the front-end:** `POST /api/support` re-checks `getRuntimeFlag("support-live", …)` (via
the fail-closed `resolveIdentity`) and returns 404 while OFF, BEFORE resolving a
conversation or invoking `dispatchSoleurGo`. This is load-bearing — the route is
authenticated-reachable independently of the React flag, so without the server check a
direct POST would invoke the support Concierge (and its kb-search read surface) while the
feature is meant to be dark. So a dark merge genuinely keeps the backend inert: the code
ships to prod but the endpoint 404s until an operator flips the flag. `support-live` must
NOT be flipped ON until a
DEPLOYED-env QA confirms (a) a repo-less user gets a real corpus-grounded streamed reply
and (b) NO internal-`knowledge-base/` content leaks. The sandbox `denyReadExtra` obscures
`<root>/knowledge-base` from the read-only support session as tool-level defense-in-depth,
but the broad read surface (`--ro-bind / /` + Bash) means live no-leak verification is the
gating precondition, not code alone. A curated product-help corpus at the support cwd
(`getPluginPath()`-relative `knowledge-base/`) is the remaining content prerequisite so
`kb-search` grounds answers instead of dead-ending.

## Consequences

- Command Center path is byte-neutral (the `command_center` branch preserves gate order, `cwd=workspacePath`, `allowWrite=[workspacePath]`).
- A dropped persona hop is a compile error; a garbage value throws; a support turn cannot gain repo write (sandbox `allowWrite:[]`) nor the 95-skill surface (SDK `skills` + canUseTool default-deny).
- Minimum test set (CTO): `resolveWorkspaceMode` unit (impossible-state + never-throw), support repo-gate-bypass, **support sandbox write-set empty**, CC non-regression characterization, end-to-end persona threading into `CanUseToolDeps`, skill-allowlist deny (bare+FQN), `disallowedTools` membership, and the ws-handler honest-degrade wire boundary.
