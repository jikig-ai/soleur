---
name: 2026-07-10-feat-wire-concierge-support-chat-plan
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: TBD
branch: feat-one-shot-wire-concierge-support-chat
worktree: .worktrees/feat-one-shot-wire-concierge-support-chat
adr: ADR-109 (provisional)
---

# Plan: Wire the Concierge into the 24/7 support chat (real agent-driven replies, support-scoped skills)

✨ **feature** · cross-cutting (frontend seam + server dispatch + skill-scoping + ADR/C4) · single-user-incident threshold

## Enhancement Summary

**Deepened:** 2026-07-10. Inputs: 4 parallel research agents (dispatch path, skill-scoping,
support UI, learnings) + scoped fable advisor consult (ADR-083) + 3-reviewer pass
(Kieran correctness, architecture-strategist, spec-flow) + installed-SDK verification.

**Key improvements over the first draft:**
1. **Provider-seam over a threaded boolean** (fable) — mode-leak becomes a compile-time type error.
2. **Two-axis seam** (architecture Finding 1) — `dispatchSoleurGo` hard-requires a persisted row at `cc-dispatcher.ts:3087` BEFORE streaming, so "ephemeral = no DB surgery" was false; corrected to a `ConversationStore` axis and a CTO B1(ephemeral)/B2(persisted-repo-less) decision.
3. **Corpus/internal-KB leak promoted to a ship-blocker** (architecture Finding 2) — `kb-search` over `knowledge-base/` would narrate the operator's confidential post-mortems/roadmap/ADRs to any end user; support search root must be hard-restricted to a curated corpus.
4. **SDK-native `skills` allowlist** (deepen, sdk.d.ts:3263-3265 @ `0.3.197`) — the intended primary scoping lever, currently unused; paired with a `canUseTool` deny-with-message defense-in-depth.
5. **Correctness fixes** (Kieran) — Edit/Write are NOT blocked by default (`CANONICAL_DISALLOWED_TOOLS` = WebSearch/WebFetch only), so support must pin `Edit,Write,MultiEdit,NotebookEdit,Task,Agent` in `disallowedTools`; keep Bash (kb-search needs it); bare↔FQN skill normalization; `help` dropped from the allowlist.
6. **User-flow states** (spec-flow) — persona-unresolved honest degrade, close-mid-turn abort, stream-idle watchdog, empty-KB state, refusal escape-hatch; ACs re-cast as invariants not proxies.

**New considerations discovered:** the dispatch-layer row dependency (not just ws-handler); the internal-KB confidentiality leak; the SDK-native `skills` lever; the reconnect-replay cliff; the ADR-070 grounding correction (deny-with-message-vs-silent-removal, precedent `permission-callback.ts:1020-1030`) + a required ADR-070 amendment.

**Verified live (deepen):** installed `@anthropic-ai/claude-agent-sdk` = `0.3.197`; `disallowedTools` docstring (sdk.d.ts:1327) confirms tools are "removed from the model's context"; `skills` main-session option exists (sdk.d.ts:3263-3265) and is unused in-repo; next-free ADR ordinal = **ADR-109** (fresh `origin/main`, highest = ADR-108).

## Overview

The support chat UI (`components/support/*`) shipped as an **interface-only shell**
(PR #5741): sending a message renders the user's bubble plus a **canned "live support
coming soon" reply** produced by the synchronous seam
`getSupportReply()` in `components/support/canned-responder.ts`. The `support` flag is
**live for all prd users** (Flagsmith feature 220580 + Doppler `FLAG_SUPPORT=1`,
2026-06-30). The operator now wants the bubble to actually answer.

This plan replaces the canned seam with a **real, agent-driven reply** that routes
support messages through the **existing production Concierge** (`cc-soleur-go`:
`dispatchSoleurGo` → `realSdkQueryFactory` → `@anthropic-ai/claude-agent-sdk`
`query()`), **without building a parallel runner** — and scopes that Concierge session
to **support-appropriate skills only** (KB search / help / product-navigation; NOT the
95-skill engineering surface). It flips `support-persona.ts` copy from preview to live,
wires streaming/error/observability the way `cc-dispatcher` does, and keeps the
`support` flag semantics intact.

The two hard problems (both confirmed by codebase research, see Reconciliation):

1. **The existing cc path is deeply repo/workspace-coupled.** `createConversation`
   (`ws-handler.ts:900`) **throws "No connected repository" when `repo_url` is null**,
   and `realSdkQueryFactory` runs a repo-readiness gate → git-clone self-heal →
   worktree write-lease → bwrap `cwd = workspacePath` (`cc-dispatcher.ts:1686-2636`).
   A "how do I use the app" support user is frequently **repo-less** (brand-new user)
   — exactly the person who most needs help. Reusing the path as-is means support
   **breaks for the users who need it most**. The plan introduces a **`supportMode`**
   that bypasses the repo-coupled gates and runs the Concierge read-only.

2. **There is no skill-level gate today.** The whole soleur plugin (95 skills) is
   mounted (`agent-runner-query-options.ts:255`) and the `Skill` tool is blanket
   auto-allowed (`permission-callback.ts` `isSafeTool` branch). The only real levers
   are the **system prompt** (a mode-scoped trusted append pattern already exists —
   `ROUTINE_AUTHORING_DIRECTIVE`) and a **new skill-name allowlist in
   `createCanUseTool`**. Scoping to support requires both.

**Approach (recommended — updated after the scoped strong-model consult, ADR-083):**
reuse the `SoleurGoRunner`/`realSdkQueryFactory` **engine** and the WebSocket transport
unchanged, but do **not** thread a `supportMode` *boolean* that disables safety gates
inside the hottest shared path (a 5-hop boolean any hop can drop/invert is exactly the
mode-leak shape that produces a single-user incident). Instead, **extract the
repo-lifecycle concerns** (`evaluateRepoReadiness`, clone self-heal, worktree lease,
bwrap `cwd`, `patchWorkspacePermissions`) behind a single **`ExecutionEnvironment`
(workspace-provider) seam** with **two composition roots**: the existing **repo
provider** (Command Center) and a new **read-only docs provider** (support,
`cwd = getPluginPath()` docs root). The support entry point *cannot construct* repo
gates and the normal entry *cannot omit* them → **mode-leak becomes a compile-time type
error, not a flag-hygiene bug.** A thin `persona: "support"` entry selects the docs
provider + the support prompt + the support skill allowlist. Scope tools+skills via a
support system-prompt directive + a **default-deny** `canUseTool` skill allowlist
(`{kb-search}` only — `help` enumerates the engineering command surface so it is
excluded; new plugin skills are safe-by-default via default-deny). Front-end drives off the
same cumulative WS `stream` protocol.

**Conversation-persistence strategy (CORRECTED after architecture review — Finding 1):**
`dispatchSoleurGo` itself hard-requires a persisted `conversations` row at
`cc-dispatcher.ts:3087` (`updateConversationFor expectMatch:true` throws "Conversation
not found" **before any frame streams**), `:3151` (SELECT workspace_id), and
`:3169`/`:3498` (messages FK INSERTs). So "ephemeral = no DB surgery" was **wrong** —
ephemeral requires MORE dispatch surgery (skip 5 write sites), not less. Resolve as a
**two-axis composition seam**: extend the seam beyond workspace/repo to also abstract
**conversation persistence** — a `ConversationStore` with a `PersistedConversationStore`
(Command Center, today's behavior) and a `NullConversationStore` (support: synthetic id,
no ownership probe, `workspace_id` sourced from `user_session_state`, no `messages`/
`turn_summary` writes). Support = `ReadOnlyDocsProvider` + `NullConversationStore`, so
**mode-leak stays a compile-time type error on BOTH axes**. The lower-surgery
alternative — persist a minimal **repo-less support row** (`repo_url` is nullable `text`,
verified; add a `kind` discriminator to keep support rows out of DSAR/normal queries) —
is the CTO decision recorded in Alternatives (it needs LESS dispatch surgery but reopens
a bounded DB/RLS/DSAR surface). The three biggest plan-review items: (1) the corpus/leak
blocker (Phase 4, below), (2) the two-axis seam contract, (3) streaming-vs-await.

## Research Reconciliation — Task/Spec claims vs. Codebase reality

Placed between Overview and Implementation Phases per the plan skill (spec-fiction guard).

| Claim (task / shipped spec / code comment) | Reality (verified on this branch) | Plan response |
|---|---|---|
| "Make the seam async / return a `Promise<string>` and await it — that one caller plus this file are the entire swap surface." (`canned-responder.ts` header) | A real Concierge reply is **streamed** (cumulative `stream` frames), not a single final string. A `Promise<string>` captures only the final text and loses live streaming/tool-progress. The seam under-specifies streaming. | Evolve the seam beyond `Promise<string>`: `use-support-chat.ts` subscribes to streamed frames (cumulative-replace, like `ws-client.ts`). Keep `canned-responder.ts` as the **flag-off / error fallback**, not the live path. Documented as a decision for plan-review. |
| "Tests to touch: `canned-responder.test.ts`." | Blast radius is **3 test files**: `canned-responder.test.ts` (async), `support-panel.test.tsx:62` asserts `expect(fetchSpy).not.toHaveBeenCalled()` — **must invert** for a live backend, `support-launcher.test.tsx` (mount/context). | Update all three + add new server tests + sweep the **19 factory test consumers** (see Sharp Edges). |
| `feature-flags/server.ts:61-64` comment: "Default OFF for all roles until the support backend lands." | Stale. Memory + task confirm **Doppler `FLAG_SUPPORT=1` in dev+prd** and Flagsmith `support` (220580) ON for all since 2026-06-30 — the bubble is **already live in prd** (canned). | Do NOT re-provision the flag. Update the stale comment. Verify live state at /work via `soleur:flag-list` (read-only) before relying on it — do not trust the code comment. |
| `createConversation` can persist a support conversation. | `ws-handler.ts:900-905` **throws "No connected repository"** when `getCurrentRepoUrl(user.id)` is null (app-level; `repo_url` column itself is nullable `text`). AND `dispatchSoleurGo` requires a persisted row at `cc-dispatcher.ts:3087`/`:3151`/`:3169`/`:3498`. | Two-axis seam: support = `NullConversationStore` (B1, ephemeral) OR a `kind='support'` repo-less row (B2). **Never a sentinel `context_path`.** CTO decision — see Alternatives + Phase 2. |
| `SupportLauncher` has the context to call a backend. | `SupportLauncher` is **context-free** — no `userId`/`orgId`/`conversationId`, no auth hook (`support-launcher.tsx`; agent report). | Thread identity/conversation context in (auth is available at `(dashboard)/layout.tsx`; support conversation id resolved on open). |
| System-prompt directives can hang off `agent-runner`. | The support chat is a **leaderless conversation**; learning `2026-06-16-leaderless-conversation-system-prompt-seam-is-cc-dispatcher-not-agent-runner.md` proves the seam is **cc-dispatcher**, not agent-runner. A directive on agent-runner silently never fires. | Append the support directive in the **cc-dispatcher factory path** (`effectiveSystemPrompt`, `cc-dispatcher.ts:2350-2384`) + `soleur-go-runner buildSoleurGoSystemPrompt`. |

No spec fiction beyond the above — every reuse anchor (`dispatchSoleurGo`,
`realSdkQueryFactory`, `buildAgentQueryOptions`, `createCanUseTool`, the WS `stream`
protocol, `MarkdownRenderer`) exists on this branch.

## User-Brand Impact

**If this lands broken, the user experiences:** a support bubble that **errors,
hangs, or answers wrong** — strictly worse than the honest "coming soon" preview it
replaces. Concretely: a repo-less new user opens support, asks "how do I create a
routine?", and gets a `RepoNotReadyError` / "No connected repository" failure or a
silent spinner (the exact repo-coupling this plan bypasses). Or the scoped Concierge
**escapes its persona** and runs an engineering skill (`/soleur:one-shot`) or a
write tool against the user's workspace from a "help" chat.

**If this leaks, the user's data / workspace is exposed via:** a support session that
(a) reads or narrates **another tenant's** context into the reply (cross-tenant
prose leak — the narration redaction probe scrubs paths/secret-shapes, NOT another
tenant's text), or (b) writes/edits the user's connected repo from a support chat the
user believed was read-only, or (c) persists support-conversation content into an
exportable/DSAR-visible record without disclosure.

**Cross-tenant reframe (spec-flow S7):** the ephemeral session + `cwd = getPluginPath()`
shared product-docs root means **no tenant data is in the support session's reach** —
this structurally removes the cross-tenant-prose leak vector, turning the system-prompt
"never name another tenant" prohibition into defense-in-depth rather than the sole
control. Do NOT give the support session read access to any per-user workspace path.

**Brand-survival threshold:** single-user incident (inherited from the support-interface
plan `brand_survival_threshold: single-user incident`; carried forward, not re-authored).
→ `requires_cpo_signoff: true` (frontmatter). CPO sign-off required at plan time before
`/work`; `user-impact-reviewer` runs at review time (review skill conditional-agent block).

## Implementation Phases

> Phase order is load-bearing: the **contract-declaring** server surface (supportMode
> dispatch + skill scope) must exist and be **flag/mode-gated closed** before the
> front-end flips copy to "live" — never declare a support contract the dispatch layer
> doesn't deliver (learning `2026-05-07-foundations-pr-must-not-declare-downstream-contracts.md`).
> This ships as **one atomic feature** (no interim window where the UI promises live
> support the backend can't answer). All server wiring lives under `apps/web-platform/**`
> so the merge triggers the `web-platform-release.yml` image rebuild — a `plugins/`-only
> change would NOT deploy (learning `2026-07-02-merged-is-not-deployed-on-concierge-instrument-dont-ask.md`).

### Phase 0 — Preconditions (grep/verify against installed code, not memory)
1. `soleur:flag-list` (read-only) — confirm `support` = ON in prd Flagsmith + Doppler `FLAG_SUPPORT=1` (do not re-provision; do not trust the stale `server.ts` comment).
2. `git grep -rln "realSdkQueryFactory\|dispatchSoleurGo" apps/web-platform/test/` → **19 files** (list in Sharp Edges). Every new import/arg on the factory must add an inert default mock to each.
3. Read the `routineAuthoring` 5-hop threading (`ws-handler.ts:1281` → `cc-dispatcher.ts:2934` DispatchArgs → `:2362` prompt-append → `:4047` runner pass → `soleur-go-runner.ts:974/1046/2536`). `supportMode` mirrors this exactly; enumerate the hops in a call-site comment so a dropped hop (→ silently-inert directive) is auditable.
4. Read ADR-070 (two-tier fail-open), ADR-086/#6046 (context-queries web port), ADR-093 (`getPluginPath()` chokepoint + `assertTrustedPluginPath`). The support skill-deny is a **product-persona deny-with-message** (graceful; model relays it) — distinct from ADR-070's forbidden *silent* phase-scope deny. Reconcile in ADR-109.
5. `sed -n '878,890p' permission-callback.ts` — confirm the `isSafeTool(toolName)` Skill allow branch is the chokepoint for the skill-name allowlist.

### Phase 1 — `ExecutionEnvironment` seam + support entry (no threaded safety-disabling boolean)
1. Extract the repo-lifecycle concerns currently inline in `realSdkQueryFactory` (`cc-dispatcher.ts:1627-2636`) — `evaluateRepoReadiness`, `probeGitWorktreeShape`/`ensureWorkspaceRepoCloned` self-heal, `acquireAndHoldWorktreeLease`, `patchWorkspacePermissions`, and the `cwd` resolution — behind a single **`ExecutionEnvironment` (workspace-provider) interface**. Implement **two providers**: `RepoWorkspaceProvider` (today's behavior, exact refactor — no behavior change for the Command Center path) and `ReadOnlyDocsProvider` (support: `cwd = getPluginPath()` docs root; provides NO worktree lease, NO clone, NO readiness gate — it *cannot* construct them). This is a characterization-test-guarded refactor of the hot path (see Legacy-code note in Sharp Edges).
   **Seam-contract scope (architecture Finding 3 — do NOT under-cut the boundary):** the refactor must NOT capture or duplicate the **cross-cutting** concerns braided through the same block. Explicitly:
   - **BYOK lease is the outermost frame** (`resolveKeyOwnerThenLease` `:1648→:2769`; credential at `:1674`, consumed `:2641`). The provider must run **nested inside** the lease scope (support keeps key zeroization/delegation).
   - **AbortController** (`:2402`) is **caller-owned and injected** into the provider, never owned by it (the repo lease's heartbeat-lost callback calls `controller.abort()` `:2600`).
   - **Cleanup is `try/catch` (`:2709-2768`), not `try/finally`**, and co-releases the worktree lease with two XC releases: `flushCcToolAttemptCollector` (`:2721`) and the ack-posture cell delete (`:2727`). Extracting the lease must re-plumb its error-path release WITHOUT dropping the two XC releases; convert to `try/finally` if needed.
   - **Three braided constructs** stay with the always-on half, not the repo provider: the `soleur_platform` MCP server (`:2308`, merges always-on narration + flag-gated C4 tools); the `effectiveSystemPrompt` concat (`:2350-2385`, interleaves always-on NARRATION/GH_403 with repo-conditional directives); and the `Promise.all` (`:2320`, couples `patchWorkspacePermissions` (repo) with `applyPrefillGuard` (XC)). The `ReadOnlyDocsProvider` must still RECEIVE the always-on halves (narration tools, always-on prompt sections, `applyPrefillGuard`, ack-posture register/release, injected AbortController).
   - The **ack-posture cell** (`:1807` register → `:2727` release) is XC but buried deepest in the repo block — the concern most likely to be miscategorized as repo state and lost on the support path; name it explicitly in the seam contract.
2. A thin **support entry** selects `ReadOnlyDocsProvider`. Prefer a `persona: "support"` discriminant carried on the dispatch context (resolved in `ws-handler.ts` from a `chatContext.type === "support"`), which the dispatch uses to pick the provider + the support system-prompt + the support skill allowlist. The persona value is a small enum, not a scattered boolean; the provider choice is the single branch point.
3. Guard: `persona:"support"` has NO effect unless the caller is an authenticated user (auth enforced by the ws-handler `auth` frame + middleware). A flag-flip alone MUST NOT open support behavior server-side without the persona being set (multi-agent review probe).
4. Because mode-leak is now a **type error** (a repo turn gets `RepoWorkspaceProvider` by construction; a support turn gets `ReadOnlyDocsProvider`), the 5-hop `routineAuthoring`-style boolean threading is avoided. The `persona` still threads to the prompt/skill-scope, but disabling safety gates is NOT expressible on the repo path.

### Phase 2 — Conversation strategy (CTO decision B1 vs B2) + repo-free execution
**Decide B1 (ephemeral via `NullConversationStore`) vs B2 (persisted repo-less row)** —
the fable consult favored ephemeral to dodge RLS/DSAR, but architecture Finding 1 shows
`dispatchSoleurGo` itself requires a persisted row at 5 write sites, so **ephemeral is
NOT "no DB surgery"** (it needs the store abstracted through the seam AND resume
suppressed) and **B2 may be the lower-surgery, more-robust v1**. Whichever is chosen:
**reject the sentinel `context_path` variant outright** — a magic `context_path` in a
table every downstream reader (RLS, DSAR, repo-readiness queries) assumes is repo-backed
leaks forever; B2 uses a `kind='support'` discriminator + nullable `repo_url` instead.
1. Because support is ephemeral, `createConversation` (`ws-handler.ts:886-942`) is **not
   called** on the support path — the `getCurrentRepoUrl` null-throw at `:900` is never
   reached. **BUT `dispatchSoleurGo` itself requires a persisted row (architecture
   Finding 1)** at `cc-dispatcher.ts:3087` (`updateConversationFor expectMatch:true` —
   throws BEFORE streaming), `:3151` (SELECT workspace_id), `:3169`/`:3498` (messages FK
   INSERTs), and `insertTurnSummary` `:965`. So the ephemeral path routes these through a
   `NullConversationStore` (part of the two-axis seam): synthetic id, no ownership probe,
   `workspace_id` sourced from `user_session_state` (not the conversations SELECT), and
   NO `messages`/`turn_summary` writes. The WS transport, `sendToClient` (userId-keyed,
   `:658`), `streamReplayBuffer`, and both rate limiters need ZERO change (they treat
   `conversationId` as an opaque key). Reject the naive "createConversation not called →
   done" framing — the dispatch-layer row dependency is the real work.
   **Reconnect-replay cliff (architecture Finding 5):** `handleResumeStream`
   (`ws-handler.ts:1458-1504`) SELECTs `conversations WHERE id=…` before replay; a
   synthetic id → empty `stream_replay{incomplete}` → the client refetches empty
   persisted history, silently losing the whole support thread on a brief disconnect.
   Either **suppress the resume path for support** or **choose the persisted-repo-less
   row** (which resolves this naturally — the row exists). This is a decisive point in
   favor of persisted-repo-less; weigh in Alternatives.
2. `realSdkQueryFactory` support path = the `ReadOnlyDocsProvider` from Phase 1: no
   readiness gate, no clone, no worktree lease, no permission patch. Keep BYOK/credential
   lease (`:1648`) and rate limiting (support turns share/observe the cc rate limiter —
   review probe: confirm support cannot bypass or starve the shared bucket).
3. `cwd = getPluginPath()` product-docs root — trusted, boot-validated `/app/` path
   (ADR-093), sandbox-**read-only** (`--ro-bind / /`; only `workspacePath` is in
   `allowWrite`, `agent-runner-sandbox-config.ts:213-221`). It exists and is readable
   (the "cwd doesn't exist in the namespace" worry is misfounded); the real constraint is
   that any tool WRITING into cwd hits EROFS — fine for read-only `kb-search`, and a
   permanent constraint on the persona (architecture Finding 5). NEVER the untrusted
   workspace copy. Note this cwd points at the internal Soleur repo KB — see Phase 4:
   the support search root must be hard-restricted to the curated corpus, not this whole
   tree.
4. Repo-free fail-loud: if a support query somehow reaches a repo op, it fails loud with
   a support-appropriate message, not flail (learning
   `2026-06-15-concierge-no-repo-workspace-must-fail-loud-not-flail.md`). Defense-in-depth
   (support skills/tools already exclude repo work).

### Phase 3 — Skill + tool scoping (support persona)
1. **Support system-prompt directive** — new `SUPPORT_SYSTEM_DIRECTIVE` constant (server-side, trusted; mirror `routine-authoring-directive.ts:16-36`), **appended** to `effectiveSystemPrompt` in the cc-dispatcher factory path (`cc-dispatcher.ts:2350-2384`) when `persona:"support"`. Content: "You are Soleur Support. Answer how-do-I / navigation questions from the knowledge base and product docs. Use only `kb-search`. Never edit code, never run engineering workflows (plan/work/ship/deploy/one-shot), never touch a repository. If asked to do engineering work, explain that this is app-help support and point to the relevant app area / Command Center." **Routing-line replacement is a SEPARATE mechanism** (Kieran review #5): an *append* cannot un-say the baseline `/soleur:go` routing line already baked into `buildSoleurGoSystemPrompt` (`soleur-go-runner.ts:1291`) — so **branch `buildSoleurGoSystemPrompt`** to emit the support routing instead of `/soleur:go` when `persona:"support"`. Do not rely on the append to "replace" it (both would coexist and conflict).
2a. **SDK-native `skills` allowlist (PRIMARY lever — deepen finding, sdk.d.ts:3263-3265, installed SDK `0.3.197`).** The Agent SDK main-session `Options` has an unused-in-codebase `skills?: string[]` field: *"When provided, only skills whose names match an entry are loaded into the main session system prompt... Omit to load every discovered skill."* Setting `skills: ["kb-search"]` for `persona:"support"` **removes all other skills from the model's context** (they are never advertised) — a far cleaner scope than advertising 95 and denying at call-time, and the SDK's intended mechanism (passing `'Skill'` to `allowedTools` is deprecated *in favor of* this option per sdk.d.ts:1307). Thread a `skills?: string[]` option through `buildAgentQueryOptions` (new passthrough field) → set it on the support path. **ADR-070 note:** this is a context-reduction (surface shrink) on a NON-fail-open layer, so it MUST be paired with 2b below (a model that emits a non-loaded skill would otherwise hit the silent unknown-tool failure ADR-070 forbids).
2b. **Default-deny skill allowlist in `createCanUseTool` (defense-in-depth for the emit-a-non-loaded-skill case)** (`permission-callback.ts`, the `isSafeTool` Skill branch ~`:883`) — the genuinely new gate that keeps ADR-070 satisfied when 2a shrinks the surface. When the dispatch persona is `support`, a `Skill` call is allowed **only** if the invoked skill ∈ `SUPPORT_SKILL_ALLOWLIST` (`{ kb-search }`; **drop `help`** — it enumerates the full engineering command surface, not support-appropriate); **everything else denies** (default-deny — a new plugin skill is safe-by-default) **with a clear `message`** ("Support can only use app-help") — a graceful `{behavior:"deny", message}` the model relays (established shape at `permission-callback.ts:912-913`), NOT a silent rejection (ADR-070 reconciliation). **Bare↔FQN normalization (Kieran review #2):** the model-controlled `.skill` field can arrive `soleur:`-prefixed; anchored-strip `soleur:` before the `∈ SUPPORT_SKILL_ALLOWLIST` check (mirror `context-queries-hook.ts` Gate #1 / `phase-surface-hook.ts`) — else `soleur:kb-search` false-denies the happy path. Assert BOTH forms in the unit test. `CanUseToolDeps` gains a `persona`/allowlist input (thread from the factory at `cc-dispatcher.ts:2677`).
3. **`disallowedTools` — hard-remove the write/fan-out surface (Kieran review #1, HIGH).** Edit/Write are **NOT** blocked by default — `CANONICAL_DISALLOWED_TOOLS` is only `["WebSearch","WebFetch"]` (`agent-runner-query-options.ts:53`) and Edit/Write are gated only by cwd-relative `isPathInWorkspace(filePath, ctx.workspacePath)` (`permission-callback.ts:240`). Under support's `cwd = getPluginPath()`, a `Write` to a path *under* the plugin root would pass containment and be **allowed** — the exact "read-only surface that isn't" leak. So `persona:"support"` `extraDisallowedTools` MUST explicitly include **`Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Task`, `Agent`** (do not rely on the cc-router's `CC_PATH_DISALLOWED_TOOLS` inheritance — pin it on the support path). **ADR-070 reconciliation (architecture Finding 4):** this silent `disallowedTools` removal is acceptable here — and NOT the "additive-hint only" violation ADR-070 forbids — because the harm ADR-070 enumerates is a *silent unknown-tool failure for a tool the paying user legitimately needs*; Edit/Write/Task/Agent are tools a support user NEVER legitimately needs, so their removal breaks no valid flow. **State this justification explicitly in ADR-109** (do not slip it in). **KEEP `Bash` (Kieran review #3):** `kb-search` shells out via Bash (`grep`, `kb-search-cache.sh`) behind the existing `resolveCcBashGate` read-only allowlist — removing Bash disables the only real support capability. WebSearch/WebFetch already in the canonical list.
4. Allow-branch shape: every `canUseTool` allow returns `{ behavior: "allow" as const, updatedInput: toolInput }` explicitly (learning `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md`).

### Phase 4 — Support answer source (HARD PRECONDITION — confidential-KB leak, architecture Finding 2)
**This is a ship-blocker, not an open question.** `kb-search` searches `knowledge-base/`,
which is **entirely operator-internal** (`project/learnings`, `project/plans`,
`project/specs`, `engineering/operations` post-mortems, ADRs, finance/legal/marketing).
"How do I create a routine?" over that corpus returns Inngest internals, the routines
WORM-cascade + credit-exhaustion **post-mortems**, implementation plans, the roadmap, and
ADRs — a support Concierge scoped to `kb-search` would **narrate the operator's
confidential engineering KB, incident history, and roadmap to any end user.** That is
worse than the cross-tenant vector and it is the feature's CORE question. Under
`cwd = getPluginPath()` (= `/app/shared/plugins/soleur`, the Soleur repo KB baked into
the image) the in-scope KB is Soleur's own internal repo KB. **Two mandatory parts,
both before the copy flips live:**
1. **Curate a real end-user product-help corpus** (how-to / navigation docs) — likely
   derived from the marketing docs under `plugins/soleur/docs/pages/*.njk` (which
   `kb-search` does NOT scan today) into a dedicated support-help artifact set.
2. **Hard-restrict the support search root** so support `kb-search` (or a support-only
   read tool) can read ONLY the curated product-help corpus and **CANNOT** read
   `knowledge-base/` internal domains. Enforce at the tool/root level, not by prompt.
If the corpus cannot be curated in this PR, the Phase 6 copy flip is **gated** (do not
promise live answers over an unrestricted internal KB). Options for the corpus source
(assess in deepen-plan):
- (a) Curated support docs under the platform-deployed root (`getPluginPath()`), read-only, sandbox-readable — recommended; pair with the ADR-086 `context_queries` web port (`context-queries-hook.ts`, #6046) so the support skill declaratively pulls the right product-help artifacts.
- (b) Model answers from system-prompt product knowledge + the 3 starter-chip answers only (no KB read) — simplest, but brittle/hallucination-prone.
The plan's v1 recommendation: (a), scoped to a small curated product-help corpus.
**Groundedness gate (spec-flow S3):** the corpus is a HARD prerequisite for the copy
flip — a support persona scoped to `{kb-search}` + told "answer from the KB" over an
**empty** corpus dead-ends every user. So Phase 4 either **seeds the minimal corpus in
this PR** (so the driven "how do I create a routine?" answer is grounded in a real
artifact) OR the Phase 6 copy flip is **gated** so it does not promise answers the KB
cannot ground. Do NOT ship live copy over an empty corpus.

### Phase 5 — Front-end: live streaming seam
1. `use-support-chat.ts` — `send()` becomes **async + streaming-aware**: append the user message, open/reuse the support transport, subscribe to cumulative `stream` frames (replace-not-append, matching `ws-client.ts`; learning `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md`), track `pending`/`streaming`/`error` state (none exists today). Attach an explicit `.catch()` on any fire-and-forget dispatch (learning `2026-03-20-fire-and-forget-promise-catch-handler.md`).
2. Transport — reuse the WS path (`useWebSocket`-style) with the support conversation id. The support UI deliberately did NOT reuse `ChatSurface`/`useWebSocket` (they were backend-coupled); this phase adds a **minimal support WS client** or a scoped reuse of `useWebSocket` for the support conversation. (Weigh vs an SSE/HTTP transport in Alternatives.)
3. `canned-responder.ts` — demoted to the **flag-off / transport-error fallback** (keep the KB escape-hatch link). No longer the live path.
4. `support-message.tsx` — already renders support-side via `MarkdownRenderer`; add a streaming/typing indicator and an **error bubble + retry** affordance (neither exists today). Keep the internal-link interception (`support-panel.tsx handleReplyLinkClick`).
5. Thread identity/conversation context into `SupportLauncher` → `use-support-chat` (userId from auth, support conversation id on open).

**Front-end flow states (folded from spec-flow review — these are the user-facing invariants, not proxies):**
- **Close/reopen mid-turn (S1):** define panel-close semantics = **abort-on-close** — closing the panel aborts the in-flight support dispatch (`abort_turn` on the support conversation id) so no Concierge turn streams to nowhere burning Anthropic cost (per-session cost attribution, commit `20a0cae7a`). State must NOT unmount-and-orphan: hold support chat state at a session-level provider (survives close/reopen) OR explicitly clear on close; the synthetic conversation id must not silently regenerate mid-turn and lose/duplicate the partial reply.
- **Persona-unresolved dishonest-degrade (S2, highest severity):** because Phase 1.2 selects the provider *from* the persona, a dropped `persona` hop defaults to `RepoWorkspaceProvider` → the `getCurrentRepoUrl` null-throw (`ws-handler.ts:900`) → "No connected repository" — the *exact repo-less dead-end this plan exists to kill*, now under the flipped "always on" copy. The `canned-responder` fallback (Phase 5.3) MUST also cover **persona-unresolved / repo-error-under-support**, not only flag-off/transport-error. Defense-in-depth: a support conversation id reaching the repo path must surface the honest fallback, never `RepoNotReadyError` under live copy.
- **Out-of-scope refusal next-step (S4):** a *successful-but-refused* live turn (model declines "fix my code", or a skill-deny fires) must still surface the KB escape-hatch / a redirect affordance ("open Command Center for engineering work") — the escape hatch currently lives only in the flag-off/error fallback. No live dead-end.
- **Client stall watchdog + retry idempotency (S5):** add a client **stream-idle timeout** (no frames for N seconds → error+retry bubble) — a mid-stream stall (WS open, frames stop, no error event) is the "silent spinner" the User-Brand Impact warns of; the server "freeze" op has no client counterpart today. Define retry semantics: discard the partial, do NOT resend a duplicate assistant bubble.
- **Empty-KB result state (S3):** a "`kb-search` returned nothing" outcome needs a live empty-state with the escape-hatch/escalation link — not a hallucinated answer or a bare "I couldn't find that" dead-end.

### Phase 6 — Persona copy flip (`support-persona.ts`)
Flip preview → live (keep honest guardrails where still true — e.g. "AI assistant, may be wrong"):
- `SUPPORT_GREETING` — from "I can help you find your way around the app — ask me anything, or pick a question below" (already fine) → keep, drop any preview framing.
- `SUPPORT_PREVIEW_NOTE` — from "This is a preview — live support chat is coming soon. Replies below are samples for now." → live framing (e.g. "I'm an AI assistant — I can help you navigate Soleur. I may not be perfect; for anything I can't answer, browse your knowledge base.").
- `SUPPORT_COMPOSER_FOOTNOTE` — from "Responses are previews for now." → live (e.g. "Answers are AI-generated.").
- `SUPPORT_PANEL_SUBTITLE` — from "Preview · live chat coming soon" → live (e.g. "AI app help · always on").
- Remove the "PREVIEW" badge on support replies (`support-message.tsx`) OR relabel (decide with copywriter/CPO). Update `feature-flags/server.ts` stale comment.

### Phase 7 — Observability (5-field schema; see `## Observability`)
1. Distinct `op: "support-*"` slugs on every un-recovered support path via `reportSilentFallback`/`mirrorWithDebounce` (so the operator confirms the code path executes on the Concierge surface via Sentry — learning `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`; blind-surface probe below).
2. Gate error-level reporting on **final** recoverability, not first failure (learning `2026-06-05-report-error-on-final-recoverability-not-first-failure.md`): a transient KB-search timeout → `info` breadcrumb; only an un-recovered support freeze → Sentry.
3. In-sandbox discriminating probe (blind surface): the support dispatch runs in the same bwrap sandbox; emit a structured event (`supportMode`, `skillDenied`, `repoGateBypassed`) so a wrong-layer/wrong-mode diagnosis is decidable from one Sentry event.

### Phase 8 — Tests
1. Rewrite `test/components/support/canned-responder.test.ts` — `getSupportReply` is now the **async fallback**; assert its fallback/error-path contract (still returns the KB escape hatch), not the old "coming soon" live behavior.
2. Invert `test/components/support/support-panel.test.tsx:51-64` — the live path **does** call the transport; replace `expect(fetchSpy).not.toHaveBeenCalled()` with an assertion that the support send dispatches a backend call (mock the transport). Keep the markdown-render + internal-link-interception assertions.
3. `test/components/support/support-launcher.test.tsx` — flag-gating still holds; add identity/context threading assertions.
4. New server tests: `supportMode` repo-gate bypass (mirror `cc-dispatcher-repo-gate.test.ts`), skill-name allowlist deny-with-message in `createCanUseTool`, support system-prompt directive appended only in supportMode.
5. **Factory cold-start sweep** — every new import/arg on `realSdkQueryFactory` adds an inert default to the **19** factory test consumers (Phase 0 list); the full-suite `vitest run` exit gate is the backstop (learning `2026-06-03-dispatcher-factory-new-import-sweep-all-exercising-test-files.md`).
6. Typecheck/test commands: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and `./node_modules/.bin/vitest run <path>` (NOT `npm run -w`; NOT bun test — `bunfig.toml` ignores). Test file paths must match `vitest.config.ts` `include:` (`test/**/*.test.ts(x)`).

### Phase 9 — ADR-109 + C4 (see `## Architecture Decision`)
Author ADR-109 (support-persona scoped Concierge mode + repo-gate bypass + skill
allowlist), reconciling ADR-070 (graceful deny-with-message ≠ silent phase deny) and
ADR-093 (`getPluginPath()` read-only cwd). Update the three `.c4` model files per the
completeness enumeration below; regenerate `model.likec4.json`
(`bash scripts/regenerate-c4-model.sh`) and run the C4 validation tests.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] A repo-less authenticated user can open support, ask a how-do-I question, and receive a **streamed, agent-generated, corpus-grounded** reply (no "No connected repository" / `RepoNotReadyError`). The AC asserts groundedness (the driven answer cites/derives from a real product-help artifact), not merely "a reply arrived" (spec-flow S3).
- [ ] **SDK `skills` allowlist (loaded layer):** in `persona:"support"`, the SDK `Options.skills` passed to `query()` is `["kb-search"]` (only that skill is loaded into the main-session prompt); asserted on the built options object.
- [ ] **canUseTool (denied layer, defense-in-depth):** in `persona:"support"`, a `Skill` call for any skill ∉ `{kb-search}` is **denied with a user-relayable message**; `kb-search` is allowed in **both** bare (`kb-search`) and FQN (`soleur:kb-search`) forms. Deterministic `createCanUseTool` unit test (not an LLM prompt — learning `2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md`).
- [ ] **disallowedTools (absent layer):** in `persona:"support"`, `options.disallowedTools` includes `Edit, Write, MultiEdit, NotebookEdit, Task, Agent, WebSearch, WebFetch` — asserted as a `disallowedTools`-membership post-condition (NOT a canUseTool proxy; Kieran #1/#4). `Bash` is present (kb-search needs it).
- [ ] **Integration threading:** a real support dispatch threads `persona` all the way into `CanUseToolDeps` (not just the unit-constructed deps) — else a dropped hop allows all 95 skills while the unit test stays green (Kieran #2 / spec-flow S6).
- [ ] No repo clone / worktree lease / `patchWorkspacePermissions` runs on a support turn (assert via the `ReadOnlyDocsProvider` — the support entry cannot construct them).
- [ ] **No internal-KB leak (architecture Finding 2, ship-blocker):** a support turn's search root is hard-restricted to the curated product-help corpus and **cannot** read `knowledge-base/` internal domains (learnings/plans/specs/post-mortems/ADRs/legal). Assert: a driven "how do I create a routine?" reply contains NO internal-KB content (post-mortem text, ADR ordinals, roadmap). If the corpus is not curated in this PR, the copy flip is gated OFF.
- [ ] **Dispatch persistence (architecture Finding 1):** a support turn does not throw at `cc-dispatcher.ts:3087` (`updateConversationFor`) and writes no `messages`/`turn_summary` rows (NullConversationStore) OR persists exactly one repo-less `kind='support'` row (B2) — asserted, not assumed.
- [ ] **Reconnect (architecture Finding 5):** a brief disconnect mid-support-turn does not silently drop the thread — either resume is suppressed for support (documented) or the persisted row makes replay work.
- [ ] The support routing is emitted by a branched `buildSoleurGoSystemPrompt` (not `/soleur:go`) **only** when `persona:"support"`, and `SUPPORT_SYSTEM_DIRECTIVE` is appended only in that mode (unit test on the prompt builder; the two do not conflict).
- [ ] **Persona-unresolved honest degrade (spec-flow S2):** with `support` flag ON but `persona` unresolved server-side, a repo-less user sees the honest `canned-responder` fallback, **never** `RepoNotReadyError`/"No connected repository" under live copy.
- [ ] **Copy flip verified as invariant, not proxy (spec-flow S6):** `grep -niE 'preview|coming soon|sample' components/support/**` (widened beyond `support-persona.ts`, incl. the `support-message.tsx` PREVIEW badge) returns only intentional live copy; AND a **positive** assertion that the "AI-generated, may be wrong" disclosure string is **present** and persistently visible (you must not pass by deleting the disclosure). Stale `feature-flags/server.ts` comment updated.
- [ ] Front-end: `send()` is async, shows a pending/streaming indicator, renders cumulative-replace streamed markdown, shows an error+retry bubble on transport failure **and on a stream-idle timeout** (spec-flow S5), and closing the panel mid-turn **aborts** the dispatch (no orphaned streaming turn — spec-flow S1). A refused/out-of-scope live turn still surfaces the KB escape-hatch (spec-flow S4). `support-panel.test.tsx` fetch-not-called assertion is inverted.
- [ ] All 3 support test files updated + new server tests pass; the 19 factory test consumers still pass under `vitest run` (full-suite exit gate).
- [ ] `## Observability` block present with support `op:` slugs; every un-recovered support server path mirrors to Sentry; discoverability test is ssh-free.
- [ ] `support` flag NOT re-provisioned; behavior is inert when the flag is off (fallback copy) and when `supportMode` is not set server-side.
- [ ] ADR-109 authored (reconciles ADR-070 + ADR-093); the three `.c4` files updated per the completeness enumeration; `model.likec4.json` regenerated; C4 validation tests green.
- [ ] `tsc --noEmit` + `vitest run` green; `grep -rnE '#[0-9a-fA-F]{3,6}' components/support/` returns nothing (token-only styling preserved).

### Post-merge (operator / automatable)
- [ ] After deploy, drive the support bubble end-to-end via Playwright (repo-less test user), confirm a real streamed reply, and confirm the `op:support-*` Sentry markers fire (learning: merged ≠ deployed; verify code path executes on the Concierge surface). Automatable — bake into `/work` post-deploy verification or `/ship`, not a manual operator step.

## Observability

```yaml
liveness_signal:
  what: "support turn dispatched + streamed (info-level pino line, op:support-turn) per support conversation"
  cadence: "per support message"
  alert_target: "Better Stack log volume; Sentry issue-rate on op:support-* error slugs"
  configured_in: "apps/web-platform/server/cc-dispatcher.ts (supportMode branch) via createChildLogger + reportSilentFallback"
error_reporting:
  destination: "Sentry via reportSilentFallback / mirrorWithDebounce (per-userId+errorClass 5-min debounce)"
  fail_loud: "un-recovered support dispatch failure mirrors to Sentry with op:support-dispatch-failed; transient KB-search timeout stays info-level (final-recoverability gating)"
failure_modes:
  - mode: "support dispatch throws before SDK query (auth/BYOK/factory)"
    detection: "outer .catch on the fire-and-forget dispatch → reportSilentFallback op:support-dispatch-failed"
    alert_route: "Sentry issue-alert (mirror existing cc-dispatcher issue-alerts.tf pattern)"
  - mode: "model attempts a non-allowlisted skill in supportMode"
    detection: "createCanUseTool deny path emits op:support-skill-denied (info; count, not page) with the skill name"
    alert_route: "Better Stack breadcrumb; Sentry only if deny-rate spikes"
  - mode: "repo-gate bypass wrongly skipped a gate a non-support turn needed"
    detection: "in-sandbox structured event {supportMode, repoGateBypassed} discriminates support vs non-support in one event"
    alert_route: "Sentry op:support-mode-leak if repoGateBypassed=true on a non-support conversation"
logs:
  where: "pino child logger 'cc-dispatcher' with op:support-* slugs; Better Stack"
  retention: "existing web-platform log retention"
discoverability_test:
  command: "Sentry API query for op:support-dispatch-failed over last 24h after a Playwright-driven support turn (no ssh)"
  expected_output: "zero un-recovered errors on the happy path; the driven failure fixture surfaces exactly one op:support-dispatch-failed event"
```

Affected-surface note (blind bwrap sandbox / cc-dispatcher readiness path per plan
Phase 2.9.2): the support dispatch runs on the same operator-blind Concierge sandbox;
`failure_modes` above name **in-surface** probes (emitted from the dispatch), and the
structured event's fields (`supportMode`/`skillDenied`/`repoGateBypassed`) discriminate
the competing root causes (wrong-mode vs wrong-layer vs skill-escape) in one event.

## Architecture Decision (ADR/C4)

Detected: a new **substrate/trust-boundary mode** (support-persona scoped Concierge),
a **resolver/dispatch change** (repo-coupled gates bypassed under a mode flag), and a
**new cross-cutting deny surface** on the web SDK `canUseTool` layer — all
architectural. ADR is a deliverable of THIS plan, not a follow-up.

### ADR
Author **ADR-109 (provisional ordinal — re-verify next-free vs origin/main at ship;
`/ship` ADR-Ordinal Collision Gate owns the final number)**: "Support-persona scoped
Concierge mode — repo-gate bypass + skill-name allowlist + graceful deny." Its
`## Decision` + `## Alternatives Considered` records: reuse the `SoleurGoRunner`/
`realSdkQueryFactory` engine (no parallel runner); **extract repo-lifecycle behind an `ExecutionEnvironment`
provider seam with two composition roots** (repo vs read-only-docs) so a support turn
*cannot construct* repo gates and a normal turn *cannot omit* them (mode-leak =
compile-time type error) — chosen over a threaded gate-disabling `supportMode` boolean;
support runs read-only with `cwd = getPluginPath()` product-docs root; **ephemeral v1
(no conversation/message persistence)**; skill scope via support system-prompt + a
**default-deny** `canUseTool` skill allowlist. **Reconcile ADR-070 (corrected per architecture Finding 4):** ground the compatibility
NOT in "persona-scope ≠ phase-scope" (that trips ADR-070's literal "additive-hint only"
line, which bans hard-deny on the `canUseTool`/`disallowedTools` *layer*, not on the
phase *axis*) but in **deny-with-relayable-`message` vs silent removal** — ADR-070's only
enumerated harm is a *silent "unknown tool" failure for a paying user*. Decisive
precedent: `permission-callback.ts:1020-1030` **already hard-denies unrecognized tools
with a message** on `canUseTool` and predates ADR-070 without being flagged. So
"additive-hint only" constrains phase-scoping surface reduction, not authorization
denials with feedback. **Add a one-paragraph amendment to ADR-070 itself** (it binds the
deferred #5772 web-`disallowedTools` implementer). Separately justify the silent
`disallowedTools` removal of Edit/Write/Task/Agent (never legitimately needed in support
→ no ADR-070 harm). **Reconcile ADR-093:** the read-only support `cwd` uses the trusted
`getPluginPath()` root, never the untrusted workspace copy.

### C4 views
Per the completeness mandate, READ all three `.c4` files
(`model.c4`, `views.c4`, `spec.c4`) — done at plan time. Enumeration:
- **External human actors:** the support user IS the existing `founder` actor
  (`model.c4:8`) — no new actor.
- **External systems/vendors:** Anthropic (`claude`, `model.c4:224`) already modeled —
  no new vendor. No new inbound/outbound integration.
- **Containers/data stores:** support reuses the `engine` (cc-soleur-go) container and
  `webapp`/`dashboard`. **v1 is ephemeral — NO data store touched** (no
  `conversations`/`messages` rows). The `founder -> webapp` + `webapp -> engine`
  (WebSocket, `model.c4:291`) edges already exist — no new store, no new edge.
- **Access-relationship change:** the one genuinely new architectural fact is a
  **support-scoped, read-only, skill-restricted mode** of the `founder → engine`
  interaction. This is a *mode/trust-scope* on an existing edge, not a new element.
  **Plan response:** add a one-line annotation/note to the `webapp -> engine` edge (or
  the `dashboard` container description) recording the support-scoped read-only mode,
  so the C4 does not mislead a future engineer into thinking every dashboard→engine
  turn is the full repo-coupled Concierge. This is the minimal correct edit; NOT "no
  C4 impact." After editing, regen `model.likec4.json` + run
  `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
ADR-109 is authored now describing the target state; it ships in this feature's
lifecycle (no deferral).

## Domain Review

**Domains relevant:** Product, Support, Engineering (+ Legal/GDPR touchpoint).

### Engineering (CTO)
**Status:** to be spawned at plan time (architecture fork is significant).
**Assessment (planner pre-read, post scoped-advisor consult):** decisions (a) and (b)
are now resolved — (a) an `ExecutionEnvironment` provider seam with two composition
roots (mode-leak = type error), NOT a threaded gate-disabling boolean; (b) ephemeral v1
(no DB rows, no sentinel `context_path`). Residual for CTO: (i) confirm the provider-seam
refactor of `realSdkQueryFactory` is characterization-test-guarded and behavior-neutral
for the Command Center path; (ii) confirm support turns cannot bypass/starve the shared
cc rate-limit bucket; (iii) confirm the skill-name `canUseTool` gate is the right layer
(it is the only place a prompt-level scope can be *enforced*, not requested).

### Support (CCO)
**Status:** to be spawned at plan time.
**Assessment (planner pre-read):** persona/tone, escalation path when the AI can't
answer (KB escape hatch must remain), and whether "AI-generated, may be wrong" framing
is honest + on-brand.

### Product/UX Gate
**Tier:** advisory (modifies existing support UI — adds streaming/loading/error states
and flips copy; **no new pages or components**; wireframes already approved 2026-06-30,
committed at `knowledge-base/product/design/support/support-chat-interface.pen`). Pipeline/headless context → auto-accept the
advisory UX per the plan skill's ADVISORY pipeline arm; copywriter recommended for the
persona copy flip (Phase 6). Record CPO sign-off (required by threshold).
**Decision:** auto-accepted (pipeline); copywriter + CPO to review copy at plan/review time.

## GDPR / Compliance touchpoint

Trigger (a): a **new processing activity using an LLM on operator/user-session-derived
data** (support messages → Anthropic). If support conversations are **persisted** and
exportable (DSAR/Article 30), a disclosure + processing-activity entry may be needed.
`/soleur:gdpr-gate` to run against this plan at plan/deepen time. Mitigation baked in:
the narration/summary redaction path already scrubs paths/secret-shapes; cross-tenant
prose prohibition is in the support system-prompt directive (Phase 3). The
**ephemeral** conversation strategy sidesteps most of this (no persisted category) and
is the safer default if persistence has no strong product justification.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **A′. `ExecutionEnvironment` provider seam + support entry (CHOSEN)** — reuse WS + `dispatchSoleurGo` + `realSdkQueryFactory` engine; extract repo-lifecycle behind an interface with two composition roots (repo vs read-only-docs); support entry picks the docs provider. | Chosen (scoped-advisor consult). Honors "reuse, no parallel runner"; keeps one engine; **mode-leak is a compile-time type error**, not a flag-hygiene risk. Refactor of the hot path guarded by characterization tests. |
| ~~A. Threaded `supportMode` boolean disabling gates in the shared factory~~ | **Rejected** — a 5-hop boolean disabling safety gates in the hottest path is the mode-leak shape that produces a single-user incident (any hop drops/inverts it; nothing but runtime discipline stops a support call acquiring a worktree lease or a normal call skipping the readiness gate). |
| **B1. Ephemeral via `NullConversationStore` (two-axis seam)** | Keeps the DB clean, but architecture Finding 1 shows `dispatchSoleurGo` requires a persisted row at 5 write sites (`:3087`/`:3151`/`:3169`/`:3498`/`:965`) — so ephemeral needs the store abstracted through the seam (MORE dispatch surgery than first claimed) AND must suppress the reconnect-replay path (Finding 5). Mode-leak stays a type error. |
| **B2. Persisted repo-less support row (`repo_url` nullable + `kind` discriminator) — RE-WEIGH as likely v1** | **Lower dispatch surgery** — `dispatchSoleurGo` works unchanged because the row exists; only `createConversation`'s app-level repo throw is relaxed + a `kind` column keeps support rows out of DSAR/normal queries. Resolves the reconnect-replay cliff for free. Cost: a bounded, honest DB/RLS/DSAR surface (mitigate with `kind` + retention + GDPR gate). **CTO decision B1-vs-B2** — the plan's earlier "ephemeral is less work" claim was wrong; persisted-repo-less may be the simpler AND more robust v1. Never a sentinel `context_path` (RLS/DSAR readers assume repo-backed). |
| **C. Lighter SSE/HTTP one-shot query** (`POST /api/support/message` → scoped SDK query → SSE) instead of WS | Deferred, low-leverage. Task says "stream the same way cc-dispatcher does" (WS); reuse the existing transport unchanged for v1. A transport swap is independently shippable later. |
| **D. Keep the `Promise<string>` seam literally (await final text, no streaming)** | Rejected as the live UX — loses streaming/tool-progress the task explicitly asks for. Retained only as the flag-off/error fallback (`canned-responder.ts`). |
| **E. Scope skills via system-prompt only (no `canUseTool` gate)** | Rejected — a prompt cannot hard-stop `Skill(soleur:one-shot)`; at single-user threshold the persona restriction must be enforced, not requested (learning: guardrails key on observed side-effects, not cooperative signals). Gate is **default-deny allowlist** so new plugin skills are safe-by-default. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this one is filled (threshold: single-user incident).
- **Factory cold-start sweep (19 files):** `agent-runner-helpers.test.ts`, `agent-runner-query-options.test.ts`, `cc-dispatcher-cost.test.ts`, `cc-dispatcher-prefill-guard.test.ts`, `cc-dispatcher-real-factory.test.ts`, `cc-dispatcher-repo-gate.test.ts`, `cc-dispatcher-session-id-writer.test.ts`, `cc-dispatcher-tool-progress-forwarding.test.ts`, `cc-dispatcher-warm-presandbox-mkdir.test.ts`, `cc-dispatcher-warm-reclone-await.test.ts`, `cc-dispatcher.test.ts`, `cc-effective-installation.test.ts`, `cc-mcp-tier-allowlist.test.ts`, `cc-reprovision.test.ts`, `test/helpers/cc-dispatcher-harness.ts`, `test/setup-node.ts`, `ws-handler-cc-session-id-wiring.test.ts`, `ws-handler-disconnect-grace-owning-host-guard.test.ts`, `ws-handler-grace-abort-cc-parity.test.ts`. Any new factory import/arg defaults inert in each; `vitest run` is the backstop.
- **Provider-seam refactor is on the hottest path:** the `ExecutionEnvironment` extraction touches `realSdkQueryFactory` — guard with characterization tests (Feathers) BEFORE refactoring: snapshot the Command Center path's gate sequence (readiness → clone → lease → cwd) and assert byte-for-byte unchanged behavior for `RepoWorkspaceProvider`. The refactor is the risk; the support provider is additive.
- **`persona` threading — TWO independent axes (architecture Finding 5):** a dropped hop has DIFFERENT failure modes per axis. (1) **Provider/persistence axis:** a dropped hop defaults to `RepoWorkspaceProvider` → the `getCurrentRepoUrl` null-throw → repo-less user dead-ends under live copy (spec-flow S2). (2) **Skill-allowlist axis (`canUseTool`):** the gate is persona-gated on top of the existing `isSafeTool` *unconditional* Skill allow — so a dropped persona hop THERE means support **silently regains the entire 95-skill engineering surface** (an over-capability ESCAPE, not merely "loud"). Enumerate BOTH axes in the hop-audit comment; the integration AC (persona reaches `CanUseToolDeps`) guards axis 2.
- **Reconnect-replay cliff:** `handleResumeStream` (`ws-handler.ts:1458-1504`) SELECTs `conversations` by id; a synthetic (ephemeral) id → empty replay → silent thread loss on a brief disconnect. Suppress resume for support OR use persisted-repo-less (row exists).
- **ADR-070 trap:** enforce the support skill scope via `canUseTool` **deny-with-message** (graceful, model relays), NOT via removing skills from context or a silent deny — the latter is the silent unknown-tool failure ADR-070 forbids on the web SDK layer.
- **Leaderless seam:** the directive MUST hang off cc-dispatcher's `effectiveSystemPrompt`, not agent-runner (learning 2026-06-16).
- **Deploy trigger:** all server wiring under `apps/web-platform/**` (triggers `web-platform-release.yml`); a `plugins/`-only change would not deploy.
- **Cumulative streaming:** reuse the WS `stream` cumulative-replace protocol; do not invent a support-only delta protocol.
- **C4:** editing `.c4` requires `bash scripts/regenerate-c4-model.sh` + committing `model.likec4.json`, else CI `test-scripts` c4-model-freshness fails (not caught by tsc/vitest).
- **ADR ordinal:** ADR-109 is provisional; re-verify next-free vs origin/main at ship. If renumbered, sweep this plan + tasks.md + specs for the old ordinal in the same edit.

## Open Code-Review Overlap

None found at plan time (no open `code-review` issue enumerated against
`components/support/*`, `cc-dispatcher.ts`, `permission-callback.ts`, or
`ws-handler.ts` for this scope). Re-run the overlap grep at `/work` once the final
`Files to Edit` list is frozen.

## Files to Edit

Server (all `apps/web-platform/`):
- `server/cc-dispatcher.ts` — extract repo-lifecycle behind the `ExecutionEnvironment` seam in `realSdkQueryFactory`; `persona` on `DispatchSoleurGoArgs`; support directive in `effectiveSystemPrompt`; support `op:` observability.
- (new) `server/execution-environment.ts` — the two-axis seam: `ExecutionEnvironment` (workspace) interface + `RepoWorkspaceProvider`/`ReadOnlyDocsProvider`, AND `ConversationStore` interface + `PersistedConversationStore`/`NullConversationStore` (if B1 chosen). Contract must carry the always-on halves + injected AbortController (Phase 1 seam-contract scope).
- `server/cc-dispatcher.ts` (dispatch write sites `:3087`/`:3151`/`:3169`/`:3498`/`:965`) — route through the `ConversationStore` (B1) so support skips the ownership probe + message writes; OR relax nothing here and persist a repo-less row upstream (B2).
- `server/soleur-go-runner.ts` — `persona` on dispatch/QueryFactory args; support-vs-`/soleur:go` prompt branch in `buildSoleurGoSystemPrompt`.
- `server/ws-handler.ts` — resolve `persona:"support"` from context; select the support (ephemeral, no `createConversation`) path; thread through `dispatchSoleurGoForConversation`.
- `server/permission-callback.ts` — default-deny support skill allowlist (deny-with-message) in the `isSafeTool` Skill branch; `CanUseToolDeps` gains `persona` input.
- `server/agent-runner-query-options.ts` — support `extraDisallowedTools` (Task/Agent[/Bash]); (no change to plugin-mount — stays `getPluginPath()`).
- `server/routine-authoring-directive.ts` sibling — new `support-directive.ts` (`SUPPORT_SYSTEM_DIRECTIVE`, `SUPPORT_SKILL_ALLOWLIST = {kb-search}`, bare↔FQN normalizer).
- Support answer corpus (Phase 4) — new curated product-help artifacts + a hard search-root restriction so support `kb-search` cannot read `knowledge-base/` internal domains.
- `lib/feature-flags/server.ts` — update the stale "default OFF / backend not landed" comment.
- `soleur-go-runner.ts buildSoleurGoSystemPrompt` — branch to emit support routing (not `/soleur:go`) when `persona:"support"`.
- `knowledge-base/engineering/architecture/decisions/ADR-070-*.md` — one-paragraph amendment (deny-with-message ≠ additive-hint-only).
- Migration: none for B1 (ephemeral); a `kind` discriminator + nullable-repo_url relax for B2. GDPR gate on B2.

Front-end:
- `components/support/use-support-chat.ts` — async streaming `send()`, pending/error state, `.catch()`.
- `components/support/canned-responder.ts` — demote to flag-off/error fallback.
- `components/support/support-persona.ts` — live copy flip.
- `components/support/support-message.tsx` — streaming/typing indicator, error+retry bubble, PREVIEW badge decision.
- `components/support/support-launcher.tsx` / `support-panel.tsx` — thread identity + support conversation id; wire the transport.
- (new) a minimal support WS client hook (or scoped reuse of `useWebSocket`).

Tests:
- `test/components/support/canned-responder.test.ts`, `support-panel.test.tsx`, `support-launcher.test.tsx` (update).
- New: `test/cc-dispatcher-support-mode.test.ts` (repo-gate bypass + directive), `test/permission-callback-support-skill-allowlist.test.ts`.
- The 19 factory consumers (inert-default sweep).

Architecture:
- `knowledge-base/engineering/architecture/decisions/ADR-109-*.md` (new).
- `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4}` + regenerated `model.likec4.json`.

## Files to Create
- `apps/web-platform/server/execution-environment.ts` (interface + `RepoWorkspaceProvider` + `ReadOnlyDocsProvider`)
- `apps/web-platform/server/support-directive.ts`
- `apps/web-platform/test/execution-environment.test.ts` (provider behavior parity)
- `apps/web-platform/test/cc-dispatcher-support-mode.test.ts`
- `apps/web-platform/test/permission-callback-support-skill-allowlist.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-109-support-persona-scoped-concierge-mode.md`
- (v1) a minimal support WS client hook (front-end). No Supabase migration in v1 (ephemeral).
