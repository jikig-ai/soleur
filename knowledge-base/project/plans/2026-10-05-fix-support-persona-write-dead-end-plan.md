---
title: "fix: support-persona sessions dead-end on write-requiring tasks (no handoff to write-capable session)"
type: fix
date: 2026-10-05
slug: fix-support-persona-write-dead-end
branch: feat-one-shot-9539-support-persona-write-dead-end
issue: 9539
closes: 9539
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

Spec lacks valid `lane:` (no `spec.md` exists for this branch — one-shot pipeline entered at `plan`) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-05 (inline deepen-pass — this harness has no Task/subagent capability, so the skill's parallel agent fan-out ran as sequential inline verification; per-section review agents were NOT spawned — a `soleur:plan-review` pass on a capable runtime is recommended before `soleur:work`).
**Sections enhanced:** Mechanism search (cross-surface gate-leak confirmed live), Phase 3.1 (precise emit placement), Guard Contract (added — 2 guards, lint green), WS-path limitation (verified zero producers).
**Gates evaluated:** 4.5 network-outage — N/A (no SSH/network trigger); 4.55 downtime — N/A (standard code deploy, no infra/migration/router change); 4.6 User-Brand — PASS (threshold `none` + sensitive-path scope-out present); 4.7 Observability — PASS (5 fields, allowlisted `rg` probe, literal expected_output); 4.8 PAT — PASS (no hits); 4.9 UI-wireframe — PASS (zero glob-superset hits in Files to Edit/Create; prose-level "chat flow" reading documented in Domain Review); 4.10 Encryption — N/A (no store/connection); 4.11 Guard Contract — PASS (2 guards, `lint-guard-contract.py` rc=0); 4.12 Scope Check — PASS (1 unfenced section, all subsections, no unmapped rows).

### Key Improvements

1. Confirmed the support→WS review-gate leak is live today (runner dep-gate satisfied for all shared-runner dispatches) — Phase 2's Bash short-circuit is a real second-bug fix, not hardening.
2. Pinned the exact emit point: inside `enqueue`, before the terminal frame's own `controller.enqueue`.
3. Verified all cited issues/PRs live (#9539/#9534/#3820/#3242 open; #5848 merged; #1469 closed), all `knowledge-base/` refs resolve, all rule IDs active or migrated-active, markdownlint clean on plan + tasks.md.

### New Considerations Discovered

- `reduceSupportFrame`'s `stream` arm REPLACES `text` (verified `support-sse.ts`) — terminal-adjacent emit ordering is load-bearing, not stylistic.
- `SUPPORT_TERMINAL_FRAME_TYPES = {stream_end, session_ended, error}` — the handoff emit covers all three, including error termination after a recorded deny.

# fix: support-persona sessions dead-end on write-requiring tasks (no handoff to write-capable session)

## Overview

A support-persona Concierge session (the in-app support chat, `POST /api/support` + SSE transport, `persona: "support"` per ADR-113) that receives a write-requiring task — "run the one-shot pipeline", "fix my board page" — can only report the block in prose and stop. The read-only binding (`cwdSource: "plugin"`, `sandboxWrite: "none"`) is deliberate (ADR-113's P1 supply-chain read-only-escape denial) and is preserved unchanged. What is missing is an honest escalation path: a deterministic server-side signal that a write-requiring action was attempted, and a user-facing affordance that hands the task to a write-capable Command Center session (`/dashboard/chat/new?msg=<task>`, an already-shipping deep-link producer at `apps/web-platform/app/(dashboard)/dashboard/page.tsx` `handlePromptClick`) instead of a dead-end.

## Problem Statement / Motivation

Observed (issue #9539): a hosted support-persona session was asked to run the one-shot pipeline for a CRM UI change. The agent correctly refused writes — "file writes are disabled in this session … I did not work around that by writing files through the shell" — left an empty local branch, and dead-ended with no path forward. Two note-worthy details from the incident:

1. The refusal text did **not** contain the "Ask an agent" pointer that `SUPPORT_SYSTEM_DIRECTIVE` (`apps/web-platform/server/support-directive.ts`, `SUPPORT_SYSTEM_DIRECTIVE` const) already prescribes — model-fidelity-only guidance demonstrably dead-ends.
2. The stray `feat-one-shot-prospects-fullscreen-page` branch suggests `git branch <name>` ran. `SAFE_BASH_PATTERNS` (`apps/web-platform/server/safe-bash.ts`, the `^git\s+branch(?:\s+PATH_TOKEN)*$` entry) auto-approves `git branch <name>` (create) and `git branch -d|-D <name>` (delete) as "read-only" — a latent misclassification recommended as a follow-up issue (see Related findings).

The defect is one level up from the sandbox: the product has no channel for "this task needs a write-capable session — here's the button".

## Research Insights

### Premise Validation (Phase 0.6)

Every artifact the issue cites was verified against `origin/main` on 2026-10-05:

- `resolveWorkspaceMode` in `apps/web-platform/server/workspace-mode.ts` — exists; `persona: "support"` binds `{ runRepoLifecycle: false, cwdSource: "plugin", sandboxWrite: "none" }`; exhaustiveness `never`-throws on a garbage persona.
- `sandboxReadOnly` at `apps/web-platform/server/agent-runner-query-options.ts` (`const sandboxReadOnly = args.mode.sandboxWrite === "none"`), feeding `readOnly: sandboxReadOnly` into the sandbox options.
- `allowWrite` emission at `apps/web-platform/server/agent-runner-sandbox-config.ts` (`allowWrite: opts?.readOnly ? [] : [workspacePath]`).
- ADR-113 exists (`knowledge-base/engineering/architecture/decisions/ADR-113-support-persona-scoped-concierge.md`); its Decision makes the support read-only binding load-bearing, and its "Live rollout gate" section documents `POST /api/support` (SSE, `persona: "support"` hardcoded) decoupled from the CC WebSocket.
- Issue #9534 (open-web egress) is OPEN and unshipped — the "grant-column + RPC + toggle" pattern the issue's candidate 3 references does not exist on `main` yet.
- Dispatch facts verified directly: `ws-handler.ts` resolves `persona: context?.type === "support" ? "support" : "command_center"`; `app/api/support/route.ts` passes `persona: "support"`. The incident surface (dashboard support chat) hardcodes support — it is not a misclassification of an arbitrary task; the surface itself is persona-bound.

### Mechanism search (what already exists on `main`)

- `SUPPORT_SYSTEM_DIRECTIVE` already says "point them to 'Ask an agent' (the Command Center)" — prose only; the incident reply lacked it.
- The Skill-deny branch in `apps/web-platform/server/permission-callback.ts` (the `ctx.persona === "support" && toolName === "Skill"` block returning `deny` + relayable message) already denies non-allowlisted skills with a "use Ask an agent" message — again prose only, no affordance.
- `emitInteractivePrompt`/`pendingPrompts` exist for the CC path but emit over `defaultSendToClient` (the WS socket); on a support turn the per-request SSE sink is deliberately NOT captured by the process-singleton runner (`cc-dispatcher.ts` `getSoleurGoRunner(defaultSendToClient)` — "the runner's WS-emit closure is captured at first call"), and `reduceSupportFrame` in `apps/web-platform/lib/support-sse.ts` drops every frame type except `stream_start`/`stream`/`stream_end`/`session_ended`/`error`. **Deepen-pass verification:** the runner dep-gate `if (!pendingPrompts || !emitInteractivePrompt) return;` (`soleur-go-runner.ts`) is satisfied for ALL dispatches through the shared runner — so a non-safe `Bash` attempt in a support turn DOES emit a `review_gate` today, onto the WS sink, which either renders in an unrelated open Command Center chat or stalls to `REVIEW_GATE_TIMEOUT_MS`. The cross-surface leak is real, not hypothetical; it is what Phase 2 closes.
- Per-dispatch frames (`stream`/`stream_end`/`error`/…) flow through `dispatchSoleurGo`'s per-call `sendToClient` argument — the SSE sink the route wires as `(_uid, msg) => enqueue(msg)` — so `enqueue` is the right chokepoint for the handoff emit (deepen-pass verified against `app/api/support/route.ts`).
- `/dashboard/chat/new?msg=<text>` auto-sends a first message into a fresh Command Center conversation (`components/chat/chat-surface.tsx` `msgParam` → `runFirstRunSend`); `dashboard/page.tsx` `handlePromptClick` is a shipping producer.
- Canned (flag-OFF) support replies already embed markdown escape-hatch links via `MarkdownRenderer` (`canned-responder.ts`, `SUPPORT_KB_HREF` in `support-persona.ts`) — precedent for a link affordance.

### Property List (Phase 0.6b)

- **P1.** When a support-persona session attempts an engineering action (non-allowlisted `Skill` call, non-safe `Bash` command), the user is shown a one-click path to a write-capable session carrying the same task text — deterministically, not dependent on the model's prose.
- **P2.** When the model declines in prose without a denied tool call, the reply still names the concrete next step (directive-level fix).
- **P3.** `cwdSource: "plugin"` / `sandboxWrite: "none"` for `persona: "support"` is untouched; the offer never grants write inside a support session.
- **P4.** The affordance must not auto-run anything in a support context, must not leak across surfaces (no review-gate emitted to the WS for a support turn), and the handoff link must not depend on model-generated URL encoding.

### Cut List (Phase 0.6b)

- **Candidate 3 — opt-in write grant in support sessions** → buys no property P1–P4 buys cheaper; a write-capable support session is either (a) `cwdSource:"plugin"` + write = the exact ADR-113 P1 escape, or (b) `cwdSource:"workspace"` + write = a re-implemented `command_center`. The grant substrate (#9534) does not exist on `main`. **Cut: rejected on merit.**
- **Candidate 1 — silent intent-based dispatch re-routing** → the support surface is available to all `support`-flag users; auto-promoting write-intent messages into a write-capable dispatch would let prompt phrasing escalate a help-bubble turn into an engineering session — a new privilege-escalation axis — and still dead-ends repo-less users (`createConversation` throws "No connected repository"). The safe version of "routing" is a user-confirmed handoff = candidate 2. **Cut: rejected as silent auto-promotion; retained as the explicit user-clicked handoff.**
- **Prose-only fix (directive + deny-message copy)** → buys P2 only; incident proves prose alone dead-ends (P1 unmet). **Cut: insufficient alone; retained as one layer.**
- **New `interactive_prompt` kind + pendingPrompts plumbing** → buys P1 but requires WS-sink plumbing the support SSE path deliberately avoids, a response handshake the support panel cannot answer, and a `.tsx` render surface. Re-implementing pendingPrompts for one fire-and-forget card is over-mechanized; the terminal-frame emit + markdown render buys the same property for ~1/5 the plumbing. **Cut.**

### Institutional learnings applied

- `learnings/2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md` — terminal-frame discipline on the CC dispatch path; the handoff emit is anchored at the terminal-frame boundary for the same reason.
- `learnings/best-practices/2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md` (pattern in `test/permission-callback-support-skill-allowlist.test.ts`) — deny-path tests are deterministic unit tests, no SDK.
- ADR-070 — deny-with-message-not-silent-removal: the new Bash short-circuit keeps the deny + user-relayable message shape.
- ADR-113 / PR #5848 — the read-only invariant is load-bearing; no `allowWrite` change, ever, under `persona: "support"`.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (pipeline entered at `plan`); the issue body's claims were verified directly in Phase 0.6 — all held. No spec fiction to reconcile.

## Proposed Solution

A **deny-triggered handoff affordance** (issue candidate 2, confirmed on merit), amended by the 5-seat plan-review panel (see `## Plan Review Amendments` — every change below is a verified panel finding, not restatement):

1. **`server/support-escalation.ts` (new)** — a process-local per-conversation escalation flag: `recordSupportEscalation(conversationId, source)` / `consumeSupportEscalation(conversationId)` (consume-on-read, returns the `"skill"|"bash"` source for emit-log attribution) / `clearSupportEscalation(conversationId)`. Bounded `Map` with FIFO-evict at a fixed cap of 1000 (panel: "conversation-bounded" is false — `newConversation:true` re-mints rows, so the keyspace grows unboundedly). Set by the deny paths via a single `denySupport(ctx, source, logTag, message)` helper (log + record + deny in one call — every future support deny path gets record+telemetry for free); consumed at turn end by the SSE route.
2. **`permission-callback.ts`** — (a) the existing support Skill-deny branch records the escalation via `denySupport` before returning (its `deny-support-skill` log line gains the `conversationId` field — the observability join key); (b) a new support-persona short-circuit in the Bash branch: when `isBashCommandSafe` misses, support turns deny immediately with the relayable handoff message and record the escalation — instead of emitting a `review_gate`/`bash_approval`/`autonomous_disclosure` frame over `defaultSendToClient` (the WS socket); the same record fires on the `isBashCommandBlocked` deny for support (a blocklisted write attempt is still a write attempt); (c) a support deny in the `AskUserQuestion` branch (relayable "ask clarifying questions in your reply text") **without** an escalation record — a clarifying question is not an engineering attempt.
3. **`lib/support-sse.ts`** — the wire type stays support-local: `export type SupportSseMessage = WSMessage | { type: "support_handoff"; task: string; conversationId: string }`, and `formatSupportSseFrame` / `parseSupportSseChunks` / `reduceSupportFrame` widen to it. `lib/types.ts` and `lib/ws-zod-schemas.ts` are **deliberately untouched** — `ws-zod-schemas.ts:743-748` pins `WSMessage` ≡ `z.infer<wsMessageSchema>` bidirectionally (`_SchemaCoversForward`/`_SchemaCoversBackward`), so a bare union member without a zod arm is a compile error, and the frame can never legitimately ride the WS socket anyway. `SUPPORT_TERMINAL_FRAME_TYPES` moves/exports from here (single frame-taxonomy owner shared by route + reducer).
4. **`app/api/support/route.ts`** — inside `enqueue`, when `SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)` and `consumeSupportEscalation(conversationId)` returns a source, emit `{ type: "support_handoff", task, conversationId }` to the SSE stream **before** the terminal frame, inside the existing try/catch (an unguarded handoff enqueue could throw and skip the terminal frame itself; the stream is `ReadableStream<Uint8Array>` — `encoder.encode` applies). The intercept is extracted to a pure function `supportTerminalPrefixFrames(msg, escalation, task)` so ordering/vacuity is unit-testable without a route harness (fallback seam: the `vi.mock("@/server/cc-dispatcher")` pattern already at `test/support-route.test.ts`). `clearSupportEscalation(conversationId)` runs at stream open (before `dispatchSoleurGo`) AND at teardown — `resolveOrCreateSupportConversation` reuses the support conversation across POSTs and the route has no `cancel` handler, so a flag recorded by a zombie turn would otherwise be consumed by the next innocent turn; teardown clear logs `support-handoff-cleared-unconsumed` when it drops a live flag (distinguishes "flag orphaned" from "never recorded" in the deny→emit join).
5. **`lib/support-sse.ts` + `components/support/use-support-chat.ts`** — the `support_handoff` reducer case sets a separate `state.handoffMarkdown` field (never merged into `state.text` — the `stream` arm replaces `text` wholesale, and `fallback()` overwrites the bubble on `error`). The hook composes `state.text + state.handoffMarkdown` at patch time **including the `status === "error"` branch** — the previous shape emitted the frame on error-terminal turns and then discarded it before render. The markdown comes from a shared `buildSupportHandoffMarkdown(task)` (see item 6) using an angle-bracket destination `](/…<url>)` — `encodeURIComponent` leaves `!~*'()` literal and an unbalanced `)` truncates a bare destination. `use-support-chat.ts` is a `.ts` hook — the no-`.tsx` commitment is preserved.
6. **`server/support-directive.ts` + shared copy** — `SUPPORT_EXTRA_DISALLOWED_TOOLS` gains `"AskUserQuestion"`, `"TodoWrite"`, `"ExitPlanMode"` (all three emit WS-bound `review_gate`/`interactive_prompt` frames + never-consumable `pendingPrompts` entries on support turns today; schema-level removal is the file's established primary lever, the persona belt in item 2c is defense-in-depth for `AskUserQuestion`). `SUPPORT_SYSTEM_DIRECTIVE` is tightened to one-sentence boundary explanation + the canonical **"Ask an agent"** phrasing used by the command palette (`help-overlay.tsx`, `command-palette.tsx`) — one name for the destination across directive, both deny messages, and the link text. All four copy sites compose from `SUPPORT_AGENT_SESSION_HREF` / `buildSupportHandoffMarkdown(task)` exported from `lib/` (`support-persona.ts` already centralizes support copy on purpose). The link copy is verb-forward and honest about the action + precondition — e.g. "Send this task to an agent session (needs a connected repo) →" — because `?msg=` auto-sends a metered agent turn on click and repo-less users otherwise hit a relocated dead-end; the task string is code-point-aware truncated to 500 chars (`Array.from(message).slice(0,500).join("")` + `…` — `String.slice` can split a surrogate pair and `encodeURIComponent` then throws inside the reducer).

The deny paths are chosen as triggers because they are the precise points where a support turn *attempts* an engineering action — not a guess at intent from message text, which false-positives on legitimate "how do I fix X" support questions.

## Approach Evaluation (issue candidates)

| Candidate | Verdict | Why |
|---|---|---|
| 1. Dispatch routing fix (auto-promote write-intent messages to `command_center`) | Rejected as silent re-routing; survives only as the explicit user-clicked handoff | The support surface is persona-bound by design, not misclassified; auto-promotion adds a prompt-phrasing privilege-escalation axis for every `support`-flag user and still dead-ends repo-less users. |
| 2. Handoff affordance | **Chosen** | Preserves the ADR-113 boundary verbatim; deterministic triggers already exist at the deny sites; reuses the shipping `?msg=` deep-link; ~200 LoC. |
| 3. Opt-in write grant | Rejected | Needs the unbuilt #9534 grant substrate; a useful version degenerates to `command_center`; a plugin-root-scoped version re-opens the exact P1 escape ADR-113 closed. |
| Prose-only (directive/deny copy) | Insufficient alone; kept as layer | The incident reply demonstrates prose-only dead-ends even with the pointer already in the prompt. |

## Technical Considerations

- **Security boundary file.** `permission-callback.ts` is the tool-permission chokepoint. The diff adds deny-path behavior only — no allow path is touched, no tool becomes callable that wasn't, and `persona === "support"` branches remain default-deny. The Bash short-circuit *reduces* the reachable surface (a support turn can no longer emit a review-gate frame onto the WS).
- **Attack surface enumeration** (support write-axis, expanded post-review — the panel verified each entry against the worktree): (a) `Skill` calls outside `{kb-search}` — covered: deny + escalation record; (b) `Edit/Write/MultiEdit/NotebookEdit/Task/Agent` — already removed from schema via `SUPPORT_EXTRA_DISALLOWED_TOOLS`; (c) `Bash` non-allowlisted — covered: new short-circuit deny + record, which also closes the worse live bug: `deps.bashAutonomous`/`autonomousAckAt`/`isOwner` resolve unconditionally in `cc-dispatcher.ts` for support dispatches, so today a non-safe Bash on an autonomous acked workspace is **silently auto-allowed** (`permission-callback.ts:612-629` — executes inside `allowWrite:[]`), and on an un-acked owner it emits an `autonomous_disclosure` hold to the WS that **mutates workspace consent** when answered cross-surface; (d) `Bash` blocklisted (`isBashCommandBlocked`) — covered: deny + record (was an uncovered dead-end pre-amendment); (e) `AskUserQuestion` — `canUseTool` intercepts it unconditionally → `review_gate` to WS + `waiting_for_user` on the support row + a stall up to `REVIEW_GATE_TIMEOUT_MS` (5 min) vs the route's 120s cap and the client's 30s watchdog, then **auto-allows with a synthesized selection** on timeout — covered: schema removal + persona belt, no escalation record; (f) `TodoWrite`/`ExitPlanMode` — auto-allowed, emit `interactive_prompt`/`todo_write`/`plan_preview` to the WS via `emitInteractivePrompt` + never-consumable `pendingPrompts` entries — covered: schema removal; (g) `notifyOfflineUser` + `updateConversationStatus` — a support Bash gate today pushes a "Run Bash command?" notification and writes `waiting_for_user` on the support row — closed by the short-circuit (named so the fix's blast radius is fully claimed); (h) `Bash` safe-allowlisted write-shaped (`git branch <name>` / `-d`) — **gap, pre-existing on `main`**, the sandbox `allowWrite: []` still blocks the actual write; recommended as a follow-up issue, not silently fixed here (safe-bash changes hit the CC hot path and deserve their own review).
- **WS-path support turns.** `ws-handler.ts` maps `context?.type === "support"` to the support persona, but a deepen-pass grep confirms no client produces `context.type: "support"` over WS today (the support panel uses SSE exclusively; zero `type: "support"` producers under `components/`/`lib/`). The escalation flag set during a hypothetical WS support turn is simply never consumed — the bounded Map prevents a leak. Pinned by test (a WS-path support turn emits no `support_handoff`), not just documented.
- **Repo-less users.** Clicking the handoff link opens `/dashboard/chat/new?msg=<task>`; without a connected repo the CC surface fails honestly ("No connected repository"). The link copy should set that expectation. Optionally the frame could carry `repoConnected` — deferred (extra DB read per deny; the honest error already satisfies the acceptance note).
- **Message-length cap.** The `task` payload is truncated server-side (~500 chars) so the generated `?msg=` URL stays sane.
- **Emission ordering.** The handoff frame must precede the terminal frame in `enqueue` — the route closes the SSE response on terminal, and the client reducer's `stream` case replaces `text` wholesale, so an earlier emit could be overwritten by a subsequent `stream` frame.
- **ADR-113 amendment** is a deliverable of this plan (see Architecture Decision section).
- Client/server import boundary: `support-escalation.ts` is server-only; the reducer change is `lib/` (shared); `components/support/use-support-chat.ts` is a client `.ts` hook composing already-shared state — no `.tsx`, no new render surface (see Domain Review).

## Implementation Phases

### Phase 1 — detection + wire contract

1.1. `apps/web-platform/server/support-escalation.ts` (new): `recordSupportEscalation(conversationId: string, source: "skill" | "bash")`, `consumeSupportEscalation(conversationId: string): "skill" | "bash" | null` (consume-on-read; the source is logged at emit for deny→emit attribution), `clearSupportEscalation(conversationId: string)`; bounded `Map` with FIFO-evict at a fixed cap of 1000 — `newConversation:true` re-mints support conversations, so the keyspace is NOT conversation-bounded.
1.2. `apps/web-platform/lib/support-sse.ts`: `export type SupportSseMessage = WSMessage | { type: "support_handoff"; task: string; conversationId: string }`; widen `formatSupportSseFrame` / `parseSupportSseChunks` / `reduceSupportFrame` to it; move `SUPPORT_TERMINAL_FRAME_TYPES` here and export (route imports it). `lib/types.ts` + `lib/ws-zod-schemas.ts` untouched — the `_SchemaCovers` drift guard makes a bare `WSMessage` member a compile error.
1.3. `apps/web-platform/server/permission-callback.ts`: introduce `denySupport(ctx, source, logTag, message)` (logs `deny-support-<tag>` with `conversationId`, records the escalation, returns the deny); call it in the `ctx.persona === "support" && toolName === "Skill"` deny branch (`"skill"`); extend the deny `message` to the canonical "Ask an agent" phrasing. The existing `deny-support-skill` log line gains `conversationId`.
1.4. `permission-callback.ts` `AskUserQuestion` branch: `if (ctx.persona === "support")` → deny with relayable message ("this chat can't render interactive questions — ask the user directly in your reply text"), NO escalation record.
1.5. `server/support-directive.ts`: `SUPPORT_EXTRA_DISALLOWED_TOOLS` += `"AskUserQuestion"`, `"TodoWrite"`, `"ExitPlanMode"`.

### Phase 2 — Bash channel short-circuit

2.1. `permission-callback.ts` Bash branch: after the `isBashCommandSafe` allow (keep near-miss telemetry firing), add `if (ctx.persona === "support")` → `denySupport(ctx, "bash", "bash", <handoff message>)`. This MUST sit before the autonomous/cache/review-gate sequence — on an autonomous acked workspace a non-safe Bash in a support turn is today silently **auto-allowed** (`deps.bashAutonomous` resolves unconditionally in `cc-dispatcher.ts`; `permission-callback.ts:612-629`), and on an un-acked owner it emits an `autonomous_disclosure` hold to the WS that mutates workspace consent when answered. Also record via `denySupport` on the `isBashCommandBlocked` deny for support (blocklisted write attempts dead-end identically today).
2.2. `cc-dispatcher.ts` (optional micro-fix): gate `resolveBashAutonomous`/`resolveAutonomousAck`/`resolveIsWorkspaceOwner` on `mode.runRepoLifecycle` — support pays three meaningless workspace RPCs per turn for machinery the persona cannot use; feed fail-closed `false`/`null`/`false` (the same values they'd produce).

### Phase 3 — emission + render

3.1. `app/api/support/route.ts`: call `clearSupportEscalation(conversationId)` at stream open (before `dispatchSoleurGo`) — conversation reuse + absent `cancel` handler make this correctness, not hygiene. Inside `enqueue`, run the extracted pure `supportTerminalPrefixFrames(msg, consumedSource, task)` intercept: when `SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)` and a source was consumed, `controller.enqueue` the `support_handoff` frame BEFORE the terminal frame, inside the existing try/catch, with `encoder.encode`. Log `support-handoff-emitted` (`conversationId`, `source`). `task` = code-point-aware-truncated POST `message` (`Array.from(m).slice(0,500).join("")` + `…` when cut). In teardown, `clearSupportEscalation` + log `support-handoff-cleared-unconsumed` if a live flag was dropped.
3.2. `apps/web-platform/lib/support-sse.ts` + `components/support/use-support-chat.ts`: reducer `support_handoff` case → `{ ...state, handoffMarkdown: buildSupportHandoffMarkdown(task) }` (separate field; `state.text` untouched). The hook composes `state.text + "\n\n" + state.handoffMarkdown` at patch time — including the `status === "error"`/`fallback()` branch, which today overwrites the bubble wholesale. `buildSupportHandoffMarkdown(task)` lives in `lib/` (shared with directive + deny messages): angle-bracket destination `[<verb-forward copy with repo precondition>](</dashboard/chat/new?msg=<encoded>>)`, encoding = `encodeURIComponent` + `.replace(/[!'()*~]/g, c => "%" + c.charCodeAt(0).toString(16).toUpperCase())`.
3.3. `apps/web-platform/server/support-directive.ts` + `lib/support-persona.ts` copy: `SUPPORT_SYSTEM_DIRECTIVE` instructs one-sentence boundary explanation + the canonical "Ask an agent" surface name; export `SUPPORT_AGENT_SESSION_HREF`/`buildSupportHandoffMarkdown` from `lib/` so directive, Skill-deny message, Bash-deny message, and reducer all compose one phrase and one destination.

### Phase 4 — tests + ADR amendment

4.1. `apps/web-platform/test/support-handoff.test.ts` (new, matches the vitest node-env `include: ["test/**/*.test.ts"]` glob): deterministic unit tests (no SDK) — (a) support Skill deny records escalation + deny message names the agent surface; (b) support non-safe Bash denies without emitting any gate frame and records escalation; (b2) support Bash on `deps.bashAutonomous: true` + `isOwner` + acked posture still denies with zero gate/disclosure frames; (b3) blocklisted command (`sudo …`) on support records the escalation; (b4) `AskUserQuestion` on support denies without recording an escalation and with zero `deps.sendToClient` calls; (c) `command_center` persona unaffected on all paths; (d) `reduceSupportFrame` sets `handoffMarkdown` with the fully-encoded task (test vectors include `(` `)` `'` in the task and a surrogate-pair boundary); (e) `supportTerminalPrefixFrames` ordering: `support_handoff` precedes `stream_end`; (f) no flag → no frame (vacuity guard); (g) stale-flag: a flag recorded before stream-open clear produces no frame; (h) hook-level: a `support_handoff` + `error` frame sequence still renders the `?msg=` link (the F1 regression). Runner is vitest (`package.json` `scripts.test`; `bunfig.toml` `pathIgnorePatterns = ["**"]` disables `bun test`): verify with `cd apps/web-platform && ./node_modules/.bin/vitest run test/support-handoff.test.ts`.
4.2. Amend `ADR-113` — record the handoff-affordance decision and the rejected alternatives (silent re-routing, opt-in grant) in `## Alternatives Considered` / a short addendum; note the support-Bash gate short-circuit (closes silent auto-allow on autonomous acked workspaces + the WS `autonomous_disclosure` consent-mutation hold, not merely an unanswerable gate) and the `AskUserQuestion`/`TodoWrite`/`ExitPlanMode` schema-level removals.
4.3. Regression pin (existing suite must stay green): `resolveWorkspaceMode("support")` still returns `sandboxWrite: "none"`; support `allowWrite` emission still `[]`; `parseWSMessage`/`ws-zod-schemas.ts` untouched.
4.4. Add `server/support-escalation.ts` to `test/support-route-isolation.test.ts`'s file list (pin: it never imports `ws-handler`).
4.5. File the deferred follow-ups named in `## Related findings` (safe-bash `git branch` misclassification; `repoConnected` frame field; `?q=` dangling prefill param) as GitHub issues in the work phase — `wg-when-deferring-a-capability-create-a` requires the filing, not just a prose note.

## Files to Create

- `apps/web-platform/server/support-escalation.ts` — escalation flag registry + `denySupport` helper (~50 LoC)
- `apps/web-platform/test/support-handoff.test.ts` — deny/emit/render coverage (~180 LoC)

## Files to Edit

- `apps/web-platform/server/permission-callback.ts` — `denySupport` wiring: Skill-deny record + copy, Bash support short-circuit, blocklist-deny record, `AskUserQuestion` support belt (~60 LoC)
- `apps/web-platform/app/api/support/route.ts` — stream-open clear, terminal-frame handoff emit via `supportTerminalPrefixFrames`, teardown clear + log (~40 LoC)
- `apps/web-platform/lib/support-sse.ts` — `SupportSseMessage` union, exported `SUPPORT_TERMINAL_FRAME_TYPES`, reducer `support_handoff` case → `handoffMarkdown` (~40 LoC)
- `apps/web-platform/components/support/use-support-chat.ts` — compose `handoffMarkdown` at patch incl. error branch (~20 LoC; `.ts` hook — no `.tsx`)
- `apps/web-platform/server/support-directive.ts` — directive copy + 3 `SUPPORT_EXTRA_DISALLOWED_TOOLS` additions (~20 LoC)
- `apps/web-platform/lib/` shared copy module (new or into `support-persona.ts`/`support-sse.ts`) — `SUPPORT_AGENT_SESSION_HREF` + `buildSupportHandoffMarkdown` (~25 LoC)
- `apps/web-platform/server/cc-dispatcher.ts` — (optional) workspace-RPC trio gate on `mode.runRepoLifecycle` (~10 LoC)
- `knowledge-base/engineering/architecture/decisions/ADR-113-support-persona-scoped-concierge.md` — amendment (~40 LoC)

Deliberately absent: `lib/types.ts`, `lib/ws-zod-schemas.ts` (drift-guard — see Proposed Solution item 3), and no `components/**/*.tsx` — the affordance renders through the existing `MarkdownRenderer` as appended markdown; adding a dedicated card component is a possible later enhancement and would then trigger the BLOCKING UX gate (`wg-ui-feature-requires-pen-wireframe`).

## User-Brand Impact

- **If this lands broken, the user experiences:** today's status quo — a support reply that dead-ends on a write-requiring task with no next step — or a handoff link that navigates to `/dashboard/chat/new` where a repo-less user sees the existing honest "No connected repository" error. No silent breakage beyond the current failure mode.
- **If this leaks, the user's workflow is exposed via:** the `support_handoff` frame echoes the user's own message text back to the same authenticated user over their own SSE stream — no third-party surface, no persisted copy, no cross-user path. `?msg=` content is user-authored text re-delivered to its author.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** worst realistic outcome is a UI affordance that mis-renders or routes to an honest error — no data exposure, no money path, no cross-tenant reach.
- `threshold: none, reason:` the diff touches `server/permission-callback.ts` (a sensitive-path- adjacent security file) but only on deny paths — it never widens what a support session can do; the blast radius is a missing or malformed link.

## Observability

```yaml
liveness_signal:
  what: "structured deny+handoff log pair per support turn: `deny-support-skill` / `deny-support-bash` (permission-callback) paired with `support-handoff-emitted` (support route); a deny without a paired emit inside one turn is the anomaly"
  cadence: "per-event"
  alert_target: "ops log query on the host aggregator (Better Stack logs)"
  configured_in: "apps/web-platform/server/permission-callback.ts (deny log lines), apps/web-platform/app/api/support/route.ts (emit log line)"

error_reporting:
  destination: "Sentry web-platform via reportSilentFallback (existing helper — emit/enqueue failure mirrors there)"
  fail_loud: "support turn ends with an `error` frame or a reply that dead-ends while a `deny-support-*` log exists"

failure_modes:
  - mode: "deny recorded but handoff frame never emitted (registry miss / route ordering bug)"
    detection: "in-surface: the deny itself emits a structured `log.info({sec:true, decision:'deny-support-skill'|'deny-support-bash', conversationId})`; host-side emit logs `support-handoff-emitted` with the same conversationId (+ `source`) — join on it; absence = this mode. Scoped to denies followed by a terminal frame: a turn dying at SUPPORT_TURN_MAX_MS / client abort legitimately produces deny-without-emit — the `support-handoff-cleared-unconsumed` teardown log distinguishes 'flag orphaned' from 'never recorded'"
    alert_route: "ops log alert on deny-without-emit join (Better Stack query)"
  - mode: "frame emitted but client reducer drops/mis-renders it"
    detection: "unit test asserts the reducer appends the markdown link; enqueue failure is caught by the route's existing try/catch → reportSilentFallback"
    alert_route: "Sentry via reportSilentFallback"
  - mode: "support Bash attempt reaches the WS review-gate (regression of the short-circuit)"
    detection: "a `review_gate`/`bash_approval` frame emitted during a persona=support dispatch is logged by the new deny line AND asserted absent by test (b)"
    alert_route: "ops log query on `deny-support-bash` + CI test gate"

logs:
  where: "pino structured logs on the web host (journald/Better Stack ingest — existing pipeline)"
  retention: "existing platform log retention"

discoverability_test:
  command: "rg -n \"support_handoff\" apps/web-platform/lib/types.ts apps/web-platform/lib/support-sse.ts"
  expected_output: "support_handoff"
```

## Architecture Decision (ADR/C4)

This plan extends an existing architectural decision (the ADR-113 support-persona deny contract gains an escalation channel) and resolves the issue's three-way candidate fork — a decision worth recording so candidates 1 and 3 are not re-litigated.

- **ADR:** amend `ADR-113-support-persona-scoped-concierge.md` (not a new ADR — it owns the persona boundary). Add: (a) a short Decision addendum — "deny → escalate": support deny paths record a per-conversation escalation consumed by the SSE route into a `support_handoff` frame; (b) `## Alternatives Considered` entries for silent intent re-routing (rejected: prompt-phrasing privilege escalation + repo-less dead-end) and opt-in write grant (rejected: degenerates to command_center or re-opens the P1 escape); (c) note the support-Bash review-gate short-circuit (gates emitted over the WS are unanswerable on the SSE surface — removed, deny outcome unchanged).
- **C4 views:** **no C4 impact.** Rubric enumeration, checked against all three of `model.c4`/`views.c4`/`spec.c4` on 2026-10-05: (a) external human actors — the support-chat user is covered by the existing `founder`/`betaContact` actors, no new actor class; (b) external systems/vendors — none added (the frame rides the existing `dashboard -> api` SSE edge); (c) containers/data-stores — `platform.webapp.dashboard` and `platform.webapp.api` are already modeled, no new container or store; (d) access relationships — the handoff is an intra-dashboard navigation plus one new frame type on an existing container edge, below the C4 L2 granularity the model operates at.
- **Sequencing:** the ADR amendment lands in the same PR as the code (wg-architecture-decision-is-a-plan-deliverable).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A support-persona session that receives a write-requiring task must not dead-end with "re-enable file writes and I'll re-run" — it must either hand off or clearly explain the boundary." [issue #9539] | FR structure: Phases 1–3 (record → emit → render) + directive layer | mapped |
| 2 | "The read-only invariant on cwdSource: "plugin" / sandboxWrite: "none" is preserved (ADR-113); any relaxation is opt-in and workspace-scoped." [issue #9539] | No `workspace-mode.ts`/`allowWrite` edits; Phase 4.3 regression pin; Approach Evaluation rejects the grant candidate | mapped |
| 3 | "Option 2 is likely the right shape" + "Candidate fixes (not decided — needs brainstorm/triage)" [issue #9539] | Approach Evaluation table — all three candidates evaluated on merit | mapped |
| 4 | "Repro: ask a hosted Concierge/support session to run a code-change task that writes files; observe the dead-end." [issue #9539] | Test Scenarios S1–S4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `support-escalation.ts` registry | "when a support session detects a task that needs sandboxWrite: "workspace" … it offers "promote to a command-center session" instead of dead-ending" | asked (mechanism choice inferred from "handoff affordance") |
| `types.ts` `support_handoff` frame | same ask — the affordance needs a wire carrier | inferred — justification: the SSE stream is the only channel that reaches the support panel (ADR-113 transport ruling) |
| `route.ts` terminal emit | same ask | inferred — justification: `enqueue` is the single chokepoint where the SSE sink and the terminal boundary meet |
| `permission-callback.ts` Bash short-circuit | "a write-requiring task" class includes shell writes | inferred — justification: the existing path emits an unanswerable `review_gate` to the WS for a support turn; same dead-end class, safety-adjacent (gate on wrong surface) |
| `support-sse.ts` reducer case | "it offers" — client must render the offer | asked |
| `support-directive.ts` directive update | "clearly explain the boundary" | asked |
| ADR-113 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; the option fork is an architecture decision |
| `test/support-handoff.test.ts` | "observe the dead-end" → deterministic AC proof | inferred — justification: repo convention requires tests; deny paths need deterministic (non-LLM) invocation |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 8 | Estimated changed lines: ~300
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

Two open `code-review` issues mention planned paths:

- **#3242** (`tool_use` WS event lacks raw `name` field, mentions `lib/types.ts`): **acknowledge** — orthogonal; we add a new union member and do not touch `tool_use`.
- **#3820** (safe-bash allowlist extension, mentions `server/safe-bash.ts`): **acknowledge** — we do not edit `safe-bash.ts`; the discovered `git branch <name>`/`-D` misclassification found during planning is a recommended follow-up issue (see Related findings) since tightening the allowlist deserves its own review and #3820 is about *extending* it.

## Guard Contract

### Guard 1 — support-persona gate-frame short-circuit

**Property.** A `persona === "support"` dispatch never surfaces an interactive gate frame (`review_gate`, `bash_approval`, `autonomous_disclosure`, `interactive_prompt`, `todo_write`, `plan_preview`) onto the WS sink — for denied **and** auto-allowed tool actions (post-review widening: `AskUserQuestion`/`TodoWrite`/`ExitPlanMode` emit gate frames while being auto-allowed, so scoping the property to denied actions exempted the actual leaks). Every denied engineering action returns `deny` with a user-relayable message and records the escalation. (Gate frames route through `ccDeps.sendToClient: defaultSendToClient` — the WS socket — which a support-panel user can never answer.)

**Assembly.** Every tool-permission decision on every dispatch path flows through `createCanUseTool` in `apps/web-platform/server/permission-callback.ts` — the single SDK `canUseTool` chokepoint. Primary lever: `SUPPORT_EXTRA_DISALLOWED_TOOLS` schema removal (model cannot emit the tool — covers `AskUserQuestion`/`TodoWrite`/`ExitPlanMode`). Belt: the `ctx.persona === "support"` checks inside the Bash arm (after `isBashCommandSafe`, before the autonomous/cache/review-gate sequence), the blocklist-deny arm, and the `AskUserQuestion` arm (a model can emit a schema-removed tool). Its members are not enumerable; the coverage is structural — the persona branch sits on the one path all non-safe Bash commands must traverse.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the `ctx.persona === "support"` short-circuit | RED — support Bash test asserts `deny` + zero gate frames |
| 2 | Move the short-circuit above the `isBashCommandSafe` allow | RED — safe `kb-search`-shell commands get denied; support allowlist regressions fail |
| 3 | Emit the gate frame AND return deny (both fire) | RED — test asserts `deps.sendToClient` captured zero gate-shaped frames |
| 4 | `deps.bashAutonomous: true` + owner + acked posture, support persona | RED — test asserts `deny` + zero disclosure/allow — the short-circuit precedes the autonomous path |
| 5 | Drop the blocklist-deny `denySupport` call | RED — test asserts a `sudo …` attempt records the escalation |
| 6 | Record an escalation on the `AskUserQuestion` support deny | RED — test asserts zero frames AND no flag (a clarifying question must not mint a handoff) |

### Guard 2 — terminal-frame handoff emit is consume-gated

**Property.** A `support_handoff` frame is emitted on the support SSE stream if and only if a deny-path recorded an escalation during that turn — never unconditionally at turn end, never on a turn with no denied engineering attempt.

**Assembly.** The emit lives inside `enqueue` in `app/api/support/route.ts` — the single chokepoint every SSE frame passes — keyed on `SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)` AND `consumeSupportEscalation(conversationId)`. The record side has exactly two writers (the Skill-deny branch and the Bash short-circuit in `permission-callback.ts`); the consume side has exactly one reader.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Emit `support_handoff` unconditionally at terminal (drop the consume check) | RED — test (f): turn with no deny emits no frame |
| 2 | Emit AFTER the terminal frame (ordering flip) | RED — ordering test asserts handoff precedes `stream_end` |
| 3 | Record escalation but swallow the consume (flag never read) | RED — test (a/e): recorded deny must produce a frame |
| 4 | Drop the stream-open `clearSupportEscalation` | RED — test (g): a flag recorded by a prior zombie turn emits a spurious handoff on the next turn |

## Domain Review

**Domains relevant:** Engineering (persona/sandbox boundary), Product (support-surface UX), Support (the support-chat surface itself)

### Engineering

**Status:** reviewed (assessed inline — this harness has no subagent/Task capability; domain leaders were not spawned)
**Assessment:** touches the ADR-113 trust boundary on deny paths only; the new frame is server→client on an existing transport; blast radius is the support panel. The CTO-shape concerns (persona discriminant integrity, sandbox write-set) are preserved by construction — `resolveWorkspaceMode` and `allowWrite` emission are untouched and regression-pinned.

### Support (CCO lens)

**Status:** reviewed (inline)
**Assessment:** the change is a support-workflow improvement — a support session gains an honest escalation path rather than dead-ending. The dead-end message copy remains honest about scope.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (no subagent capability in this harness; the mechanical UI-surface glob scan found **zero** `components/**/*.tsx` / `app/**/page.tsx` paths in Files to Edit/Create — the affordance renders through the existing `MarkdownRenderer` via a `.ts`-only reducer change; tier set by the semantic rule "modifies existing user-facing surface content without adding new interactive surfaces")
**Skipped specialists:** `soleur:product:design:ux-design-lead` — not invoked; justified because no component/page file is touched and no new interactive surface is created (a markdown link inside an existing message body). If implementation later introduces a dedicated card component, the gate escalates to BLOCKING and a `.pen` wireframe becomes mandatory.
**Pencil available:** N/A (no UI surface)

#### Findings

- The affordance copy must be honest ("this chat is app help; an agent session can do this") and must not over-promise for repo-less users.

## Acceptance Criteria

- [ ] AC1: Given a support-persona dispatch, when the model invokes a non-allowlisted `Skill` (e.g. `one-shot`), then the SSE stream ends with a `support_handoff` frame (emitted before the terminal frame) and the rendered reply contains a `…/dashboard/chat/new?msg=…` link carrying the user's task text.
- [ ] AC2: Given a support-persona dispatch, when the model attempts a non-safe `Bash` command — including on an autonomous acked workspace (`bashAutonomous: true`) and including a blocklisted command — then `canUseTool` returns a deny with a user-relayable handoff message, `recordSupportEscalation` is called, and **no** `review_gate`/`bash_approval`/`autonomous_disclosure`/`interactive_prompt` frame is emitted for that turn.
- [ ] AC3: `resolveWorkspaceMode("support")` still returns `{ cwdSource: "plugin", sandboxWrite: "none" }`, `agent-runner-query-options.ts` still derives `sandboxReadOnly` for support, and `agent-runner-sandbox-config.ts` still emits `allowWrite: []` — existing support sandbox tests stay green. `lib/types.ts`/`ws-zod-schemas.ts` untouched (typecheck green).
- [ ] AC4: `command_center` dispatches are byte-neutral — no `support_handoff` frame, no behavior change in the Skill, Bash, or `AskUserQuestion` branches for `persona !== "support"`.
- [ ] AC5: `reduceSupportFrame` handles `support_handoff` by setting `state.handoffMarkdown` (leaving `state.text` untouched) with the fully-encoded `task`; the hook composes it into the rendered bubble — including on `error`-terminated turns, where `fallback()` previously discarded it. Unknown/other frame types remain ignored.
- [ ] AC6: A support turn with no deny event emits no `support_handoff` frame (anti-vacuity: the emit is consume-gated, not unconditional at terminal); a flag recorded by a prior zombie turn is cleared at stream open and produces no frame.
- [ ] AC7: ADR-113 carries the amendment recording the handoff decision and the rejected alternatives.
- [ ] AC8: The denied-skill deny message, the Bash deny message, the support directive, and the handoff link all use the canonical "Ask an agent" naming and compose from the shared `SUPPORT_AGENT_SESSION_HREF`/`buildSupportHandoffMarkdown`; the link copy names the action and the connected-repo precondition. **AC8 is the only coverage for prose-decline turns** (model refuses in text without a denied tool call — the #9539 incident's verbatim shape is a documented residual, see `## Related findings`).
- [ ] AC9: `AskUserQuestion` on a support turn denies with a relayable "ask in text" message and records no escalation; `AskUserQuestion`/`TodoWrite`/`ExitPlanMode` are absent from the support tool schema.

## Test Scenarios

- **S1:** Given `persona:"support"` and a `Skill` call for `one-shot`, when `createCanUseTool` runs, then it returns `deny`, calls `recordSupportEscalation(convId,"skill")`, and the route's `enqueue` emits `support_handoff` before `stream_end`.
- **S2:** Given `persona:"support"` and `Bash("git checkout -b x")` (non-allowlisted), when `canUseTool` runs, then it returns `deny` immediately — `deps.sendToClient` is never called with a `review_gate`/`bash_approval`/`autonomous_disclosure` frame. Same assertion under `bashAutonomous: true` + owner + acked posture (today's silent auto-allow path) and under a blocklisted command (`sudo ls`).
- **S3:** Given `persona:"command_center"`, when either path runs, then no escalation is recorded and no `support_handoff` frame is emitted (regression).
- **S4:** Given a `support_handoff` frame `{task:"run one-shot pipeline for my CRM page"}`, when `reduceSupportFrame` applies it, then `state.handoffMarkdown` carries a markdown link whose `msg` param is the percent-encoded task — incl. vectors with `(`/`)`/`'` and a surrogate-pair truncation boundary.
- **S5:** Given a support turn ending in `error` (not `stream_end`) with a recorded escalation, then the handoff frame precedes the error frame AND the rendered bubble still shows the link (hook composes `handoffMarkdown` into the error patch) — previously the frame was emitted then discarded.
- **S5b:** Given `persona:"support"` and an `AskUserQuestion` tool call, when `canUseTool` runs, then it denies with the ask-in-text message, zero `deps.sendToClient` calls, and no escalation recorded.
- **S6:** Live QA note (post-merge, deployed env): with `support-live` on, ask the support chat to run a build task; observe the handoff link under the reply and that clicking it opens a CC session pre-seeded with the task.

## Success Metrics

- Support sessions receiving write-requiring tasks render a handoff affordance on 100% of deny-triggered turns (assertable in tests; observable in logs via the deny→emit pair).
- Zero `review_gate`/`bash_approval`/`autonomous_disclosure` frames emitted during `persona:"support"` dispatches.

## Dependencies & Risks

- **Sequencing dependency:** the flag is set inside `canUseTool` (runs inside the SDK query) and consumed at the terminal frame in the route — both in-process, same conversation; no persistence, no race beyond single-process concurrency (consumed-on-read).
- **Risk — the motivating incident's verbatim shape does not trigger the affordance:** in the #9539 incident the model ran `git branch <name>` (auto-approved as safe — see Related findings) and declined writes in prose — no deny → no flag → no link. Replayed verbatim, the dead-end repeats, mitigated only by directive copy (AC8). Accepted residual per the acceptance note ("hand off OR clearly explain"); a persistent chrome-level escape row that would cover 100% of turns is a scope decision recorded in `specs/feat-one-shot-9539-support-persona-write-dead-end/decision-challenges.md` (User-Challenge — adds a `.tsx` surface → `wg-ui-feature-requires-pen-wireframe`).
- **Risk — `msg` URL length:** capped at ~500 chars server-side, code-point-aware truncation + ellipsis.
- **Risk — registry leak on abandoned turns:** bounded Map + clear at stream-open AND teardown (+ `support-handoff-cleared-unconsumed` log).
- **Risk — plan-level:** the WS-path support dispatch (`context.type === "support"`) does not emit the frame; no client produces that context today — documented limitation pinned by test.
- **Risk — cross-turn overlap:** two `send()`s on the reused support `conversationId` can overlap server-side (client aborts the fetch, the route has no `cancel`); a zombie turn's later deny records a flag the next turn consumes — mitigated by stream-open clear; documented limitation, not a regression (both messages are the user's own text).

## Related findings (recommended follow-up issues, not in scope — Phase 4.5 files them)

- `safe-bash.ts` `git branch` allowlist entry auto-approves `git branch <name>` (create), `git branch -d|-D <name>` (delete), and `git branch -m` (rename) as "read-only" — likely how the incident's stray branch was created. Sandboxed writes still fail for support at the FS layer, so this is a Command-Center-path mislabel more than a support leak. **Recommended follow-up issue:** tighten `^git\s+branch…` to read-only forms (`git branch` bare / `--list` / `-v*` / `--show-current`) and move create/delete/rename forms to the review-gate path. Not filed from the planning phase (scope: planning artifacts only); the implementing pipeline or a maintainer should file it.
- `repoConnected` field on the `support_handoff` frame — lets the link copy degrade honestly for repo-less users without an extra DB read per deny. Deferred; the honest "No connected repository" error satisfies the acceptance note.
- `?q=` prefill param produced by the command palette (`use-shortcuts.tsx`) has no consumer under `components/chat/` — a pre-existing dangling-param gap; a prefill-instead-of-autosend handoff variant could adopt it if one is ever wired.

## Plan Review Amendments (5-seat panel, 2026-10-05)

Panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer (eng), ux-design-lead, cto (named panel — relevance: user-facing flow + server boundary files; threshold `none`, no UI-glob hits). Standing check: all ACs deterministic, no concurrent-process dependence. Dispositions per `plan-review` classifier — all applied findings are **Mechanical**; the one **User-Challenge** is in `decision-challenges.md`.

**Applied (mechanical):** (1) `WSMessage` union member → support-local `SupportSseMessage` — `_SchemaCovers*` bidirectional drift guard made the plan un-compilable as written; (2) error-terminal handoff emitted-then-discarded → `handoffMarkdown` separate state field composed at patch incl. error branch; (3) `AskUserQuestion`/`TodoWrite`/`ExitPlanMode` WS-bound gate frames → schema removal + persona belt; (4) `bashAutonomous` silent auto-allow + `autonomous_disclosure` consent-mutation corrected in attack surface + pinned by test; (5) stale-flag cross-turn bleed → stream-open clear; (6) blocklist-deny records escalation; (7) `denySupport` helper consolidates log+record+deny; (8) copy centralized to `SUPPORT_AGENT_SESSION_HREF`/`buildSupportHandoffMarkdown`, canonical "Ask an agent" naming, repo-precondition honesty bound to AC8; (9) `encodeURIComponent` paren/surrogate edges → angle-bracket destination + `!~*'()` escaping + `Array.from` truncation; (10) registry = bounded Map FIFO-evict@1000, consume returns `source` for attribution; (11) `support_handoff` carries `conversationId`; (12) `deny-support-skill` log gains `conversationId`; (13) `support-handoff-cleared-unconsumed` teardown log + anomaly scoped to terminal-ful turns; (14) `SUPPORT_TERMINAL_FRAME_TYPES` exported from `support-sse.ts`; (15) `support-escalation.ts` added to route-isolation test list; (16) WS-path support limitation pinned by test; (17) optional `cc-dispatcher` RPC-trio gate on `runRepoLifecycle`; (18) `supportTerminalPrefixFrames` extracted pure for ordering/vacuity tests; (19) handoff enqueued inside existing try/catch with `encoder.encode`; (20) deferred follow-ups get filed in Phase 4.5.

**Noted but not blocking:** same-tab SPA nav via `support-panel.tsx` internal-link interceptor (better than the plan assumed — `router.push` + panel close, thread retained by shell-mounted launcher); `GENERIC_REPLY` never offers the escape hatch (subsumed by the `handoffMarkdown` compose; bare link in canned copy optional).

## Sharp Edges

- The `support_handoff` frame MUST be emitted before the terminal frame — the route closes the SSE stream on `stream_end`/`session_ended`/`error`.
- `reduceSupportFrame`'s `stream` case REPLACES `text`; the handoff lives in a separate `handoffMarkdown` state field so neither stream-replace nor `fallback()`-overwrite can discard it — do NOT merge it into `state.text`.
- `deps.sendToClient` in `ccDeps` is `defaultSendToClient` (the WS), NOT the per-request SSE sink — never emit support frames through it.
- Do not add a `components/**/*.tsx` file or edit — the mechanical UI-surface glob would force the BLOCKING UX gate and require a `.pen` wireframe; keep the affordance inside the `.ts` reducer/hook/markdown path.
- Do NOT add `support_handoff` to `WSMessage`/`wsMessageSchema` — the `_SchemaCovers` drift guard is bidirectional (`ws-zod-schemas.ts:743-748`); the frame is SSE-only and lives in the `SupportSseMessage` union.
- Keep the `task` payload server-derived (the POSTed user message), never model-generated — a model-built `msg` param is a URL-injection/encoding liability.

## References & Research

- Issue: #9539 (this fix), #9534 (adjacent open-web egress — grant substrate, unbuilt), #3820 (safe-bash extension scope-out), #3242 (types.ts overlap), #5848 (ro-bind shadow regression note)
- ADR-113 (support persona), ADR-093 (`getPluginPath()` read-only root), ADR-070 (deny-with-message contract), ADR-044 (active workspace)
- Code anchors: `resolveWorkspaceMode` (workspace-mode.ts); `sandboxReadOnly` (agent-runner-query-options.ts); `allowWrite` emission (agent-runner-sandbox-config.ts); `dispatchSoleurGo` persona threading (cc-dispatcher.ts, `resolveWorkspaceMode(args.persona)`); support Skill deny (`ctx.persona === "support" && toolName === "Skill"`, permission-callback.ts); `SUPPORT_TERMINAL_FRAME_TYPES`/`enqueue` (app/api/support/route.ts); `reduceSupportFrame` (lib/support-sse.ts); `SUPPORT_SYSTEM_DIRECTIVE`/`SUPPORT_EXTRA_DISALLOWED_TOOLS` (support-directive.ts); `handlePromptClick` `msg` producer (dashboard/page.tsx); `msgParam` consumer (chat-surface.tsx).
- Prior feature plan: `knowledge-base/project/plans/2026-07-10-feat-wire-concierge-support-chat-plan.md` (empty-KB escape-hatch precedent at its S3 note).
