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

5. **Skill/tool scope (three layers).** (a) SDK-native `Options.skills = ["kb-search"]` (PRIMARY — hides every other skill from the model's context); (b) `createCanUseTool` default-deny for `persona:"support"` — a `Skill` ∉ `{kb-search}` (bare↔`soleur:`-FQN normalized) denies with a user-relayable message; (c) `disallowedTools ⊇ {Edit,Write,MultiEdit,NotebookEdit,Task,Agent}` (Bash KEPT — kb-search shells out behind the read-only safe-bash gate). *[Premise falsified 2026-10-06 — the allowlist never admitted those commands; see the premise correction under `## ADR-070 reconciliation`. Bash stays kept, now as the deny+escalate tripwire only.]*

6. **Support prompt.** `buildSoleurGoSystemPrompt` short-circuits to the Soleur Support prompt when `persona:"support"` — it does NOT emit the Command Center `/soleur:go` routing line (a downstream append cannot un-say it) and ignores artifact/sticky-workflow scoping.

7. **Persistence = B2 (operator-decided).** A real `conversations` row with `kind='support'` (migration 131) + null `repo_url`, so `dispatchSoleurGo`'s persisted-row requirements (ownership probe, workspace_id read, messages FK) are satisfied without dispatch-persistence surgery, and the reconnect-replay cliff is resolved naturally.

## ADR-070 reconciliation

The support scope uses two mechanisms ADR-070 governs: (a) the `createCanUseTool` default-deny returns a **graceful `{behavior:"deny", message}` the model relays** — NOT the silent phase-scope deny ADR-070 forbids; (b) the `disallowedTools` removal of Edit/Write/MultiEdit/NotebookEdit/Task/Agent is a silent removal, but is acceptable — and NOT the additive-hint-only violation ADR-070 forbids — because those are tools a support user NEVER legitimately needs, so their removal breaks no valid flow. A one-paragraph amendment to ADR-070 records this carve-out.

**Premise correction (2026-10-06, #9559).** Decision item 5(c) recorded "Bash KEPT — kb-search shells out behind the read-only safe-bash gate". The premise was false: the safe-bash allowlist never admitted kb-search's documented commands (`git grep`, `grep -Fxq`, `bash <script>` — `git grep` is not an allowlisted git verb, `grep`/arg-bearing `bash` are deliberately excluded, and `$`/quoting trips the metachar denylist before any pattern runs), and the deployed plugin root is not a git worktree so `git grep` cannot run there regardless. The support kb-search path is therefore Read/Grep/Glob-only over the committed corpus (`plugins/soleur/knowledge-base/`), auto-approved read tools under `cwd = getPluginPath()`. Bash stays OUT of `SUPPORT_EXTRA_DISALLOWED_TOOLS` — unchanged — but its role is now only the deny+escalation tripwire for engineering-shaped attempts, not a kb-search transport.

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

## Decision addendum (2026-10-05, #9539): deny → handoff escalation channel

A write-requiring task dispatched into a support turn used to dead-end: the deny
message relayed "file writes are disabled" with no path to a write-capable
session. The boundary stays — `sandboxWrite:"none"`, `allowWrite:[]`,
`cwdSource:"plugin"` are unchanged — but every *engineering-intent deny* now
records a per-conversation escalation, and the support route emits a
`support_handoff` SSE frame (`{task, conversationId, repoConnected?}`, task
server-derived from the POSTed message, ≤500 code points) immediately BEFORE
the terminal frame. `repoConnected?` is recorded at deny time, sourced from the
`repoUrl` resolution `realSdkQueryFactory` already performs
(`readCurrentRepoUrlResult`, zero extra reads — `degraded` emits `undefined`
rather than a false "not connected"); it stays optional so dep-less deny
contexts (unit tests and any future unwired deps path) keep the
pre-widening frame shape — the legacy `agent-runner.ts` deps construction
never sets `persona: "support"`, so it cannot reach a support deny at all
and is NOT such a producer.
The client stores it in a separate `handoffMarkdown` state field so
`stream`-replace and error-fallback cannot discard it, and renders an
"Ask an agent →" deep link to `/dashboard/chat/new?msg=<task>`.

Mechanism:

- `server/support-escalation.ts` — bounded FIFO registry +
  `denySupport` (structured `deny-support-{skill,bash,tool}` log + permission-decision
  log + record + user-relayable deny, one authoring point). Escalation sources:
  `skill` (non-allowlisted Skill), `bash` (blocklist or non-safe command),
  `tool` (every other denied engineering surface).
- `permission-callback.ts` — deny-with-record covers ALL engineering-intent
  surfaces: Skill-deny, BOTH Bash deny sites (blocklist, plus a short-circuit
  after the safe-allowlist + near-miss telemetry and BEFORE
  `bashAutonomous`/cache/review-gate), write-class file tools (`Write`/`Edit`/
  `MultiEdit`/`NotebookEdit`), outside-workspace file denies, `Agent`, platform
  tools, and deny-by-default. The Bash short-circuit also closes two latent
  leaks: on an acked autonomous workspace a non-safe command was silently
  auto-ALLOWED, and on an un-acked owner path a WS-bound `autonomous_disclosure`
  hold could be cross-surface-acked. `AskUserQuestion`/`TodoWrite`/
  `ExitPlanMode` get persona-deny belts WITHOUT an escalation record (a UX
  signal is not an engineering attempt) and join
  `SUPPORT_EXTRA_DISALLOWED_TOOLS`.
- `soleur-go-runner.ts` — `bridgeInteractivePromptIfApplicable` returns early
  for `persona === "support"`: the bridge fires on tool_use *sighting* (before
  `canUseTool`), so it is the chokepoint belt keeping `interactive_prompt`
  frames + answerable `pendingPrompts` entries off the WS sink even if a model
  emits a schema-removed tool.
- `cc-dispatcher.ts` — support dispatches filter `allowedTools` against
  `SUPPORT_EXTRA_DISALLOWED_TOOLS` (auto-approve bypasses `canUseTool`, so the
  overlap would defeat both schema removal and the belts), and the entire C4
  surface — `edit_c4_diagram` registration, `platformToolNames` entry, and
  `c4PromptAddendum` — is gated off support (the tool commits to the user's
  repo via the installation token, a real write outside `allowWrite:[]`).
- `app/api/support/route.ts` — consume-on-read at the terminal boundary
  (exactly-once, never unconditional), `clearSupportEscalation` at stream open
  (zombie-turn stale flag) and teardown, a per-conversation busy guard (409 to
  a second POST while a turn is in-flight — the sticky conversation + warm
  Query rebind would otherwise cross-attribute the escalation flag), and
  `support-handoff-emitted` / `support-handoff-cleared-unconsumed` /
  `support-handoff-emit-failed` / `support-escalation-evicted` markers for the
  deny→emit join.
- `lib/support-handoff.ts` — canonical label/href/encoded-link builder +
  `SUPPORT_AGENT_SESSION_HINT` (the plain-text pointer all deny messages
  compose from — model-relayed prose and the rendered link cannot drift).
- The handoff frame is a support-local `SupportSseMessage` member, NOT a
  `WSMessage` member — the bidirectional `_SchemaCovers` drift pin makes a bare
  member a compile error, and the frame can never legitimately arrive on the WS.
  `lib/types.ts` / `ws-zod-schemas.ts` are untouched; the CC dispatch path is
  byte-neutral.

Known residuals (tracked, not silently accepted): the GH-token
mint/askpass/egress surface is not persona-gated (#9558); a zombie turn
recording a deny *during* a successor turn's window is the remaining
flag-attribution edge after the busy guard (a per-dispatch key cannot reach
the per-Query `canUseTool` ctx without new plumbing). Resolved by this
addendum's follow-up PR: the `git branch` write-forms auto-approve hole
(#9555 — allowlist tightened to read-only arms) and the kb-search shell-out
false-positive handoff (#9559 — support path is Read/Grep/Glob-only; see the
premise correction under `## ADR-070 reconciliation`).

## Alternatives Considered (this addendum)

- **Silent intent re-routing** (server sniffs the task for engineering intent and
  re-routes the turn to the command_center dispatch). Rejected: a prompt-phrasing
  privilege axis on a security boundary — a crafted "engineering-sounding"
  support message would gain the repo-write surface the persona exists to deny;
  and repo-less support users would dead-end in a different place (the CC
  dispatch requires a connected repo).
- **Opt-in support write grant** (e.g. let the support session write to the
  user's workspace on request). Rejected for this change: it re-opens the
  plugin-root write-escape class the `allowWrite:[]` pin exists to close, and
  needs a consent/ack substrate that does not exist on the SSE surface. The
  handoff link is the honest interim path to a session that already has the
  write surface wired.
- **`WSMessage` union member + shared reducer.** Rejected by the drift guard and
  by transport semantics — see above.
