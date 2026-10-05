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

A **deny-triggered handoff affordance** (issue candidate 2, confirmed on merit):

1. **`server/support-escalation.ts` (new)** — a process-local per-conversation escalation flag: `recordSupportEscalation(conversationId, source)` / `consumeSupportEscalation(conversationId)` (consume-on-read; bounded `Map`, mirrors the `bashApprovalCache`/`pendingPrompts` registry idiom already in this subsystem). Set by the deny paths; consumed at turn end by the SSE route.
2. **`permission-callback.ts`** — (a) the existing support Skill-deny branch records the escalation before returning its deny message; (b) a new support-persona short-circuit in the Bash branch: when `isBashCommandSafe` misses, support turns deny immediately with the relayable handoff message and record the escalation — instead of emitting a `review_gate`/`bash_approval` frame over `defaultSendToClient` (the WS socket), which a support-panel user cannot answer (a second, latent dead-end of the same class).
3. **`lib/types.ts`** — one `WSMessage` union member: `{ type: "support_handoff"; task: string }` (server→client only; `wsMessageSchema` validates inbound only).
4. **`app/api/support/route.ts`** — inside `enqueue`, when `SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)` and `consumeSupportEscalation(conversationId)` returns set, emit `{ type: "support_handoff", task: <this turn's message, capped ~500 chars> }` to the SSE stream **before** the terminal frame (the route closes on terminal, so order matters). Clear the flag on stream teardown for hygiene.
5. **`lib/support-sse.ts`** — `reduceSupportFrame` gains a `support_handoff` case appending a markdown affordance line to `state.text` (`[Continue this task in an agent session →](/dashboard/chat/new?msg=<encodeURIComponent(task)>)`). Rendering rides the existing `MarkdownRenderer` — deliberately **no `.tsx` change**.
6. **`support-directive.ts`** — tighten `SUPPORT_SYSTEM_DIRECTIVE`: when a request needs an engineering capability, answer in one sentence and include the bare link `[Open an agent session](/dashboard/chat/new)` (bare URL — no model-side query encoding). Small copy update to the Skill-deny message text naming the same surface.

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
- **Attack surface enumeration** (support write-axis): (a) `Skill` calls outside `{kb-search}` — covered: deny + escalation record; (b) `Edit/Write/MultiEdit/NotebookEdit/Task/Agent` — already removed from schema via `SUPPORT_EXTRA_DISALLOWED_TOOLS` (no deny event exists — the model cannot emit them; the directive covers the residual); (c) `Bash` non-allowlisted — covered: new short-circuit deny + record; (d) `Bash` safe-allowlisted write-shaped (`git branch <name>` / `-d`) — **gap, pre-existing on `main`**, the sandbox `allowWrite: []` still blocks the actual write; recommended as a follow-up issue, not silently fixed here (safe-bash changes hit the CC hot path and deserve their own review).
- **WS-path support turns.** `ws-handler.ts` maps `context?.type === "support"` to the support persona, but a deepen-pass grep confirms no client produces `context.type: "support"` over WS today (the support panel uses SSE exclusively; zero `type: "support"` producers under `components/`/`lib/`). The escalation flag set during a hypothetical WS support turn is simply never consumed — the bounded Map prevents a leak. Known limitation, not a bug.
- **Repo-less users.** Clicking the handoff link opens `/dashboard/chat/new?msg=<task>`; without a connected repo the CC surface fails honestly ("No connected repository"). The link copy should set that expectation. Optionally the frame could carry `repoConnected` — deferred (extra DB read per deny; the honest error already satisfies the acceptance note).
- **Message-length cap.** The `task` payload is truncated server-side (~500 chars) so the generated `?msg=` URL stays sane.
- **Emission ordering.** The handoff frame must precede the terminal frame in `enqueue` — the route closes the SSE response on terminal, and the client reducer's `stream` case replaces `text` wholesale, so an earlier emit could be overwritten by a subsequent `stream` frame.
- **ADR-113 amendment** is a deliverable of this plan (see Architecture Decision section).
- Client/server import boundary: `support-escalation.ts` is server-only; the reducer change is `lib/` (shared). `components/` is untouched by design (see Domain Review).

## Implementation Phases

### Phase 1 — detection + wire contract

1.1. `apps/web-platform/server/support-escalation.ts` (new): `recordSupportEscalation(conversationId: string, source: "skill" | "bash")`, `consumeSupportEscalation(conversationId: string): boolean`, `clearSupportEscalation(conversationId: string)`; bounded `Map` (evict oldest at N=1000, or keyspace is already conversation-bounded — pick the minimal form).
1.2. `apps/web-platform/lib/types.ts`: add `{ type: "support_handoff"; task: string }` to the `WSMessage` union, adjacent to the other server→client frame members.
1.3. `apps/web-platform/server/permission-callback.ts`: in the `ctx.persona === "support" && toolName === "Skill"` deny branch, call `recordSupportEscalation(ctx.conversationId, "skill")` before returning; extend the deny `message` to name the concrete next step.

### Phase 2 — Bash channel short-circuit

2.1. `permission-callback.ts` Bash branch: after the blocklist deny and the `isBashCommandSafe` allow (keep near-miss telemetry firing), add `if (ctx.persona === "support")` → `recordSupportEscalation(ctx.conversationId, "bash")` + return `deny` with a user-relayable message ("this chat is read-only app help — continue in an agent session"). No `review_gate`/`autonomous_disclosure` frame may be emitted for support turns.

### Phase 3 — emission + render

3.1. `app/api/support/route.ts`: inside `enqueue` (the single per-frame chokepoint), when `SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)` and `consumeSupportEscalation(conversationId)` is true, `controller.enqueue(formatSupportSseFrame({ type: "support_handoff", task: message.slice(0, 500) }))` BEFORE the `controller.enqueue` of the terminal frame itself, and log `support-handoff-emitted` (structured, `conversationId` field) for the deny→emit observability pair. `message` is already in scope (the POST body, also passed as `userMessage` to the dispatch). Call `clearSupportEscalation(conversationId)` in the post-`turnComplete` teardown (`closed = true` block).
3.2. `apps/web-platform/lib/support-sse.ts`: `reduceSupportFrame` case `support_handoff` → `{ ...state, text: state.text + "\n\n" + SUPPORT_HANDOFF_MARKDOWN(task) }` where `SUPPORT_HANDOFF_MARKDOWN` builds `[Continue this task in an agent session →](/dashboard/chat/new?msg=${encodeURIComponent(task)})`; also handle the edge where `state.text` is empty (link stands alone).
3.3. `apps/web-platform/server/support-directive.ts`: update `SUPPORT_SYSTEM_DIRECTIVE` to instruct one-sentence boundary explanation + the bare `[Open an agent session](/dashboard/chat/new)` link.

### Phase 4 — tests + ADR amendment

4.1. `apps/web-platform/test/support-handoff.test.ts` (new, matches the vitest node-env `include: ["test/**/*.test.ts"]` glob): deterministic unit tests (no SDK) — (a) support Skill deny records escalation + deny message names the agent surface; (b) support non-safe Bash denies without emitting any gate frame and records escalation; (c) `command_center` persona unaffected on both paths; (d) `reduceSupportFrame` renders the handoff link with `encodeURIComponent` encoding; (e) `enqueue`-level ordering: `support_handoff` precedes `stream_end`; (f) no flag → no frame (vacuity guard). Runner is vitest (`package.json` `scripts.test`; `bunfig.toml` `pathIgnorePatterns = ["**"]` disables `bun test`): verify with `cd apps/web-platform && ./node_modules/.bin/vitest run test/support-handoff.test.ts`.
4.2. Amend `ADR-113` — record the handoff-affordance decision and the rejected alternatives (silent re-routing, opt-in grant) in `## Alternatives Considered` / a short addendum; note the support-Bash gate short-circuit.
4.3. Regression pin (existing suite must stay green): `resolveWorkspaceMode("support")` still returns `sandboxWrite: "none"`; support `allowWrite` emission still `[]`.

## Files to Create

- `apps/web-platform/server/support-escalation.ts` — escalation flag registry (~40 LoC)
- `apps/web-platform/test/support-handoff.test.ts` — deny/emit/render coverage (~120 LoC)

## Files to Edit

- `apps/web-platform/lib/types.ts` — `support_handoff` union member (~3 LoC)
- `apps/web-platform/server/permission-callback.ts` — Skill-deny record; Bash support short-circuit (~40 LoC)
- `apps/web-platform/app/api/support/route.ts` — terminal-frame handoff emit + flag hygiene (~25 LoC)
- `apps/web-platform/lib/support-sse.ts` — reducer case + markdown builder (~25 LoC)
- `apps/web-platform/server/support-directive.ts` — directive + copy (~15 LoC)
- `knowledge-base/engineering/architecture/decisions/ADR-113-support-persona-scoped-concierge.md` — amendment (~30 LoC)

Deliberately absent: no `components/**/*.tsx` — the affordance renders through the existing `MarkdownRenderer` as appended markdown; adding a dedicated card component is a possible later enhancement and would then trigger the BLOCKING UX gate (`wg-ui-feature-requires-pen-wireframe`).

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
    detection: "in-surface: the deny itself emits a structured `log.info({sec:true, decision:'deny-support-skill'|'deny-support-bash', conversationId})`; host-side emit logs `support-handoff-emitted` with the same conversationId — join on it; absence = this mode"
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

### Guard 1 — support-persona Bash gate short-circuit

**Property.** A `persona === "support"` dispatch never surfaces an interactive gate frame (`review_gate`, `bash_approval`, `autonomous_disclosure`, `interactive_prompt`) for a denied tool action — every denied Bash command returns `deny` with a user-relayable message and records the escalation. (Gate frames route through the runner's process-captured `emitInteractivePrompt` — the WS sink — which a support-panel user can never answer.)

**Assembly.** Every tool-permission decision on every dispatch path flows through `createCanUseTool` in `apps/web-platform/server/permission-callback.ts` — the single SDK `canUseTool` chokepoint. The guard is the `ctx.persona === "support"` check inside the Bash arm, positioned after the `isBashCommandSafe` allow and before the autonomous/cache/review-gate sequence. Its members are not enumerable (any non-safe command string a support turn can emit); the coverage is structural — the persona branch sits on the one path all non-safe Bash commands must traverse.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the `ctx.persona === "support"` short-circuit | RED — support Bash test asserts `deny` + zero gate frames |
| 2 | Move the short-circuit above the `isBashCommandSafe` allow | RED — safe `kb-search`-shell commands get denied; support allowlist regressions fail |
| 3 | Emit the gate frame AND return deny (both fire) | RED — test asserts `deps.sendToClient` captured zero gate-shaped frames |

### Guard 2 — terminal-frame handoff emit is consume-gated

**Property.** A `support_handoff` frame is emitted on the support SSE stream if and only if a deny-path recorded an escalation during that turn — never unconditionally at turn end, never on a turn with no denied engineering attempt.

**Assembly.** The emit lives inside `enqueue` in `app/api/support/route.ts` — the single chokepoint every SSE frame passes — keyed on `SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)` AND `consumeSupportEscalation(conversationId)`. The record side has exactly two writers (the Skill-deny branch and the Bash short-circuit in `permission-callback.ts`); the consume side has exactly one reader.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Emit `support_handoff` unconditionally at terminal (drop the consume check) | RED — test (f): turn with no deny emits no frame |
| 2 | Emit AFTER the terminal frame (ordering flip) | RED — ordering test asserts handoff precedes `stream_end` |
| 3 | Record escalation but swallow the consume (flag never read) | RED — test (a/e): recorded deny must produce a frame |

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
- [ ] AC2: Given a support-persona dispatch, when the model attempts a non-safe `Bash` command, then `canUseTool` returns a deny with a user-relayable handoff message, `recordSupportEscalation` is called, and **no** `review_gate`/`bash_approval`/`autonomous_disclosure` frame is emitted for that turn.
- [ ] AC3: `resolveWorkspaceMode("support")` still returns `{ cwdSource: "plugin", sandboxWrite: "none" }`, `agent-runner-query-options.ts` still derives `sandboxReadOnly` for support, and `agent-runner-sandbox-config.ts` still emits `allowWrite: []` — existing support sandbox tests stay green.
- [ ] AC4: `command_center` dispatches are byte-neutral — no `support_handoff` frame, no behavior change in the Skill or Bash branches for `persona !== "support"`.
- [ ] AC5: `reduceSupportFrame` handles `support_handoff` by appending a markdown link with `encodeURIComponent`-encoded `task`; unknown/other frame types remain ignored.
- [ ] AC6: A support turn with no deny event emits no `support_handoff` frame (anti-vacuity: the emit is consume-gated, not unconditional at terminal).
- [ ] AC7: ADR-113 carries the amendment recording the handoff decision and the rejected alternatives.
- [ ] AC8: The denied-skill deny message and the support directive each name the concrete next surface ("Ask an agent" / agent session link), so a model relaying either conveys an actionable path.

## Test Scenarios

- **S1:** Given `persona:"support"` and a `Skill` call for `one-shot`, when `createCanUseTool` runs, then it returns `deny`, calls `recordSupportEscalation(convId,"skill")`, and the route's `enqueue` emits `support_handoff` before `stream_end`.
- **S2:** Given `persona:"support"` and `Bash("git checkout -b x")` (non-allowlisted), when `canUseTool` runs, then it returns `deny` immediately — `deps.sendToClient` is never called with a `review_gate`/`bash_approval`/`autonomous_disclosure` frame.
- **S3:** Given `persona:"command_center"`, when either path runs, then no escalation is recorded and no `support_handoff` frame is emitted (regression).
- **S4:** Given a `support_handoff` frame `{task:"run one-shot pipeline for my CRM page"}`, when `reduceSupportFrame` applies it, then `state.text` ends with a markdown link whose `msg` param is the percent-encoded task.
- **S5:** Given a support turn ending in `error` (not `stream_end`) with a recorded escalation, then the handoff frame still precedes the error frame (all terminal types are covered).
- **S6:** Live QA note (post-merge, deployed env): with `support-live` on, ask the support chat to run a build task; observe the handoff link under the reply and that clicking it opens a CC session pre-seeded with the task.

## Success Metrics

- Support sessions receiving write-requiring tasks render a handoff affordance on 100% of deny-triggered turns (assertable in tests; observable in logs via the deny→emit pair).
- Zero `review_gate`/`bash_approval`/`autonomous_disclosure` frames emitted during `persona:"support"` dispatches.

## Dependencies & Risks

- **Sequencing dependency:** the flag is set inside `canUseTool` (runs inside the SDK query) and consumed at the terminal frame in the route — both in-process, same conversation; no persistence, no race beyond single-process concurrency (consumed-on-read).
- **Risk — model relays deny verbatim but no deny fires:** covered by the directive layer (P2) — residual dead-end possible for prose-only declines; acceptable per the acceptance note ("hand off OR clearly explain").
- **Risk — `msg` URL length:** capped at ~500 chars server-side.
- **Risk — registry leak on abandoned turns:** bounded Map + clear-on-teardown.
- **Risk — plan-level:** the WS-path support dispatch (`context.type === "support"`) does not emit the frame; no client produces that context today — documented limitation.

## Related findings (recommended follow-up issues, not in scope)

- `safe-bash.ts` `git branch` allowlist entry auto-approves `git branch <name>` (create), `git branch -d|-D <name>` (delete), and `git branch -m` (rename) as "read-only" — likely how the incident's stray branch was created. Sandboxed writes still fail for support at the FS layer, so this is a Command-Center-path mislabel more than a support leak. **Recommended follow-up issue:** tighten `^git\s+branch…` to read-only forms (`git branch` bare / `--list` / `-v*` / `--show-current`) and move create/delete/rename forms to the review-gate path. Not filed from the planning phase (scope: planning artifacts only); the implementing pipeline or a maintainer should file it.

## Sharp Edges

- The `support_handoff` frame MUST be emitted before the terminal frame — the route closes the SSE stream on `stream_end`/`session_ended`/`error`.
- `reduceSupportFrame`'s `stream` case REPLACES `text`; a handoff rendered mid-stream would be wiped by later `stream` frames — the terminal-adjacent emit ordering is load-bearing.
- `deps.sendToClient` in `ccDeps` is `defaultSendToClient` (the WS), NOT the per-request SSE sink — never emit support frames through it.
- Do not add a `components/**/*.tsx` file or edit — the mechanical UI-surface glob would force the BLOCKING UX gate and require a `.pen` wireframe; keep the affordance inside the `.ts` reducer/markdown path.
- The new WSMessage member is server→client only; do not add it to `wsMessageSchema` (inbound validation) or the CC chat state machine. Widening a discriminated union: do NOT enumerate exhaustiveness sites by grep — after the `types.ts` edit, run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; every TS2322 "not assignable to never" is a rail to widen (sharp edge: the compiler is the canonical enumerator).
- Keep the `task` payload server-derived (the POSTed user message), never model-generated — a model-built `msg` param is a URL-injection/encoding liability.

## References & Research

- Issue: #9539 (this fix), #9534 (adjacent open-web egress — grant substrate, unbuilt), #3820 (safe-bash extension scope-out), #3242 (types.ts overlap), #5848 (ro-bind shadow regression note)
- ADR-113 (support persona), ADR-093 (`getPluginPath()` read-only root), ADR-070 (deny-with-message contract), ADR-044 (active workspace)
- Code anchors: `resolveWorkspaceMode` (workspace-mode.ts); `sandboxReadOnly` (agent-runner-query-options.ts); `allowWrite` emission (agent-runner-sandbox-config.ts); `dispatchSoleurGo` persona threading (cc-dispatcher.ts, `resolveWorkspaceMode(args.persona)`); support Skill deny (`ctx.persona === "support" && toolName === "Skill"`, permission-callback.ts); `SUPPORT_TERMINAL_FRAME_TYPES`/`enqueue` (app/api/support/route.ts); `reduceSupportFrame` (lib/support-sse.ts); `SUPPORT_SYSTEM_DIRECTIVE`/`SUPPORT_EXTRA_DISALLOWED_TOOLS` (support-directive.ts); `handlePromptClick` `msg` producer (dashboard/page.tsx); `msgParam` consumer (chat-surface.tsx).
- Prior feature plan: `knowledge-base/project/plans/2026-07-10-feat-wire-concierge-support-chat-plan.md` (empty-KB escape-hatch precedent at its S3 note).
