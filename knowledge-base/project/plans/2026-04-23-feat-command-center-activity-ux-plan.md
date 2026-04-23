# feat: Command Center activity UX — verb labels, path scrub, heartbeat forwarding, retry lifecycle

**Date:** 2026-04-23
**Issue:** #2861
**Brainstorm:** [`2026-04-23-command-center-activity-ux-brainstorm.md`](../brainstorms/2026-04-23-command-center-activity-ux-brainstorm.md)
**Spec:** [`../specs/feat-command-center-activity-ux/spec.md`](../specs/feat-command-center-activity-ux/spec.md)
**Branch:** `feat-command-center-activity-ux`
**Worktree:** `.worktrees/feat-command-center-activity-ux/`
**Draft PR:** #2860

---

## Overview

Five tightly-coupled changes to the web-platform Command Center, shipped as one PR:

1. **FR1 — Verb-based activity labels.** Bash allowlist → "Exploring project structure" / "Searching code" / etc. Unknown verbs → "Working…". Never emit raw command.
2. **FR2 — Sandbox-path stripping.** Canonical regex table covering host (`/workspaces/<uuid>/…`) and sandbox (`/tmp/claude-<uid>/-workspaces-<uuid>/…`) prefixes. `reportSilentFallback` on any unmatched suspected-leak shape — this is the success metric.
3. **FR3 — Assistant-text client-side render scrub.** New pure helper `formatAssistantText(raw)`. Render-time only; `conversation_messages` stores verbatim so cost tracking, SDK replay, and Sentry breadcrumbs remain source-of-truth.
4. **FR4 — `tool_progress` WS event (the real fix for "Agent stopped responding").** SDK emits `SDKToolProgressMessage` as a top-level message type with `tool_use_id`, `tool_name`, `elapsed_time_seconds`. `agent-runner.ts` does not forward these today. Forward (server-side debounced to ≤ 1/5s per `tool_use_id`); reducer resets the 45s per-leader stuck timer without changing bubble state.
5. **FR5 — Single auto-retry with visible "Retrying…" before terminal error.** Bubble gains `retrying?: boolean`. First timeout → `retrying` + `aria-live="polite"` + timer restart. Second consecutive timeout → `error` with last known activity label + File-issue link. Incoming `tool_progress` during `retrying` cancels the retry and transitions back to `tool_use`. Trigger narrow: stuck-timeout path only.

Out of scope (from brainstorm Non-Goals): agent-emitted progress notes (approach B), #2853 single-leader routing, #2854 Command Center → `/soleur:go` delegation, tool-level retry, WS protocol versioning, schema changes to `conversation_messages`.

---

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| FR4: "reducer default branch returns state unchanged (RED test)" | `applyStreamEvent` switch is **exhaustive** over a TS discriminated union — no default branch; TS enforces exhaustiveness at build time. An unknown runtime event simply doesn't match any `case` and drops inertly. | Add a 3-line inline type check at the WS `onmessage` site: `if (!KNOWN_TYPES.has(msg?.type)) { reportSilentFallback(...); return; }`. No zod, no schema, no reducer widening. |
| FR2: canonical sandbox path is `/tmp/claude-<uid>/-workspaces-<uuid>/…` | Not hardcoded anywhere in repo; SDK manages bwrap mounts internally. | Lock the regex from the user's screenshots + SDK docs as best-inference. `reportSilentFallback` on any `/workspaces/\|/tmp/claude-` path-shape that didn't match a known pattern is the observability safety net. |
| TR2: insertion site "`agent-runner.ts` around lines 880-940" | Actual stream branch lines 888-930. `SDKToolProgressMessage` is a **top-level** `message.type` variant, NOT nested inside `stream_event`. | Add peer `else if (message.type === "tool_progress")` branch at the top of the message loop. Extract `tool_use_id`, `tool_name`, `elapsed_time_seconds`. |
| FR5: "last known activity label" on error chip | `message-bubble.tsx` `"error"` render branch shows static "Agent stopped responding" — no access to `toolLabel` even though it exists on the message object. | Thread `toolLabel` into the error render branch: `"Agent stopped responding after: <toolLabel ?? \"Working\">"`. File-issue link only; no Retry button (per plan-review: no non-functional affordances). |
| FR3 scope: preserve code fences, backticked identifiers, URLs, `#NNNN` refs | `message-bubble.tsx` renders `content` via `MarkdownRenderer` (markdown-aware). Scrub runs before markdown parsing. | Tokenize by fenced-code regex into (fence, non-fence) segments; apply path-prefix regex only to non-fence segments. URLs and `#NNNN` refs are not path-shaped so they pass through. Edge cases (indented fences, nested triple-backticks, CRLF) covered by RED tests. |

---

## Hypotheses → Verified Root Causes

- **H1 (verified): "Agent stopped responding" = 45s client watchdog starvation during long tool execution.** `STUCK_TIMEOUT_MS=45_000` in `ws-client.ts:70`; `applyTimeout` in `chat-state-machine.ts:239` fires when no stream activity arrives. `tool_use` fires once (model issues call); tool execution can exceed 45s silently. SDK emits `SDKToolProgressMessage` heartbeats — `agent-runner.ts` does not forward them. Fix: FR4.
- **H2 (verified): path leak = sandbox vs host path mismatch.** `stripWorkspacePath` (`tool-labels.ts:27-29`) only matches `workspacePath` host form; the model quotes the sandbox-mapped form. Fix: FR2.
- **H3 (verified): assistant-text leaks raw paths with zero post-processing.** `agent-runner.ts:908-919` streams `block.text` verbatim. Fix: FR3.

---

## Domain Review

**Domains relevant:** Engineering, Product (carried forward from brainstorm `## Domain Assessments`)

### Engineering (CTO — carried forward)

**Status:** reviewed
**Assessment:** Server-side SDK interception is the right site for label derivation; client-render-time scrub preserves verbatim storage invariant; root cause is client-watchdog starvation (not a #2843 bypass). Boundary-level inline type-check at WS `onmessage` is sufficient — zod is overkill for one new event type.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (narrow scope — modifies existing `message-bubble.tsx`, creates no new `components/**/*.tsx` file)
**Agents invoked:** cpo (via brainstorm)
**Skipped specialists:** ux-design-lead (small affordance additions), copywriter (standard web copy)
**Pencil available:** N/A

**Findings:** heuristic label is the floor (never raw); Retrying indicator uses `aria-live="polite"`; File-issue link is the user's functional escape hatch; success metric is raw-path leak count trending to zero via `reportSilentFallback` breadcrumbs.

---

## Open Code-Review Overlap

1 open scope-out touches files this plan edits:

- **#2225 (P3/chore):** `refactor(chat): tighten activeStreams key type and derive activeLeaderIds via useMemo`. Touches `chat-state-machine.ts` + `ws-client.ts`.
  - **Disposition: Acknowledge.** This plan adds a new reducer branch (`tool_progress`) and a `retrying` boolean on bubbles — it does NOT change the `activeStreams` key type or touch `activeLeaderIds` derivation. Orthogonal. #2225 remains open.

---

## Implementation Phases

### Phase 1 — FR1 + FR2: server-side label pipeline (RED → GREEN)

**TDD gate applies (`cq-write-failing-tests-before-implementation`).**

- **T1.1 RED — sandbox-path stripping:** extend `apps/web-platform/test/build-tool-label.test.ts` with a new describe block. Table-driven cases: host `/workspaces/<uuid>/…` → stripped; sandbox `/tmp/claude-<uid>/-workspaces-<uuid>/…` → stripped; no workspacePath → unchanged; idempotency (double-scrub = single-scrub); unmatched suspected-leak shape (path starts with `/workspaces/` or `/tmp/claude-` but doesn't match canonical regex) → `reportSilentFallback` called with `{ feature: "command-center", op: "tool-label-scrub" }`.
- **T1.2 RED — Bash verb allowlist:** table-driven matrix covering: `ls` → "Exploring project structure"; `find` / `rg` / `grep` → "Searching code"; `cat` → "Reading file"; `git <sub>` → "Checking git <sub>"; `gh <sub>` → "Querying GitHub"; `npm`/`bun`/`pnpm` → "Running package command"; `doppler` → "Fetching secrets"; `terraform` → "Running Terraform"; unknown → "Working…". **Edge cases:** `FOO=bar ls` (strip env assignment); `bash -c "ls /tmp"` → unknown (verb is `bash`, not `ls`); `find . | head` → `find` matches; `sudo ls` → unknown; `$(ls)` → unknown. Unknown-verb cases assert `reportSilentFallback` with `{ feature: "command-center", op: "tool-label-fallback", extra: { verb } }`.
- **T1.3 GREEN:** in `apps/web-platform/server/tool-labels.ts`:
  - Export a named `SANDBOX_PATH_PATTERNS: RegExp[]` with the canonical regex table (`/tmp/claude-\d+/-workspaces-[0-9a-f-]{36}/?` + companions). Export this array so the client-side scrub (Phase 3) can reuse it.
  - Extend `stripWorkspacePath` to iterate `SANDBOX_PATH_PATTERNS` in addition to the workspacePath prefix. If a suspected-leak shape remains after stripping, call `reportSilentFallback`.
  - Add `mapBashVerb(command: string): string` helper. Parse the first token after skipping leading env assignments. Look up in allowlist map; return "Working…" on miss. Document parser non-goals as a brief code comment (doesn't handle `bash -c`, pipelines, sudo, subshells — fallback is safe).
  - Wire `mapBashVerb` into `case "Bash"` branch of `buildToolLabel`, REPLACING `return \`Running: ${cleaned}\``.

**Acceptance:** `./node_modules/.bin/vitest run test/build-tool-label.test.ts` green.

### Phase 2 — FR4: `tool_progress` WS event + watchdog fix (RED → GREEN)

- **T2.1 RED — reducer branch:** extend `apps/web-platform/test/chat-state-machine.test.ts` with `"tool_progress event"` describe block. Assertions:
  - `tool_progress` event for a leader with bubble state `"tool_use"` → `messages` unchanged (same reference), `timerAction === { type: "reset", leaderId }`.
  - `tool_progress` for an unknown leader (no matching bubble) → `messages` unchanged, no `timerAction` (inert no-op).
  - `tool_progress` for a leader in `"retrying"` (Phase 4 prerequisite) → bubble transitions back to `"tool_use"`, `retrying` cleared, `timerAction === { type: "reset", leaderId }`. (Add this assertion after Phase 4 lands; initial Phase 2 test covers only `tool_use` → `tool_use`.)
- **T2.2 RED — WS unknown-type drop:** add a test at the WS `onmessage` boundary asserting: feeding a raw message with unknown `type` does NOT throw, does NOT dispatch to the reducer, and calls `reportSilentFallback({ feature: "command-center", op: "ws-unknown-event", extra: { rawType } })`.
- **T2.3 RED — server-side forwarding + debounce:** new file `apps/web-platform/test/tool-progress-forwarding.test.ts`. Mock SDK iterator yielding a `SDKToolProgressMessage`. Assert:
  - `sendToClient` is called with `{ type: "tool_progress", leaderId, toolUseId, toolName, elapsedSeconds }`.
  - Multiple heartbeats for the same `tool_use_id` within 5s → only the first forwards (debounce). The 6th second heartbeat forwards again.
  - Per-leader `AbortController` isolation: two leaders, abort one, assert the other's heartbeat still forwards.
- **T2.4 GREEN — types:** add `ToolProgressEvent` to the WS `StreamEvent` discriminated union. Shape: `{ type: "tool_progress"; leaderId: DomainLeaderId; toolUseId: string; toolName: string; elapsedSeconds: number }`.
- **T2.5 GREEN — agent-runner:** add `else if (message.type === "tool_progress")` branch at the top of the message loop in `agent-runner.ts`. Extract `tool_use_id`, `tool_name`, `elapsed_time_seconds`. Maintain a `Map<tool_use_id, lastSentAt: number>` to throttle to ≤ 1 WS emission per 5s per tool_use_id. Call `sendToClient` when throttle allows. No `streamStartSent` guard — inert bubble no-op on the client is acceptable.
- **T2.6 GREEN — state machine:** add `case "tool_progress":` branch in `applyStreamEvent`. If `activeStreams` has the `leaderId`, return `{ messages: prev, activeStreams: unchanged, timerAction: { type: "reset", leaderId } }`. Otherwise return state unchanged with no timerAction.
- **T2.7 GREEN — WS boundary:** in `ws-client.ts` (or the `onmessage` handler file), add `const KNOWN_TYPES = new Set(["stream_start", "stream", "stream_end", "tool_use", "tool_progress", "review_gate", "error", "session_ended", ...])`. Guard: `if (!KNOWN_TYPES.has(msg?.type)) { reportSilentFallback(...); return; }`. 3 lines.

**Acceptance:** All Phase 2 tests green. Manual verify: run a long `rg` over `knowledge-base/` in a dev Command Center session — bubble stays in `tool_use` past 45s, no "Agent stopped responding" chip.

### Phase 3 — FR3: client-side assistant-text render scrub (RED → GREEN)

- **T3.1 RED:** new file `apps/web-platform/test/format-assistant-text.test.tsx`. Cases:
  - Path stripping outside code fences (standard case).
  - Fenced code block preservation: ```` ```…``` ```` preserved byte-for-byte even if it contains a sandbox path.
  - Indented 4-space code blocks: preserved.
  - Nested triple-backticks: preserved.
  - Inline backticked identifiers: preserved.
  - URLs (http://, https://): preserved.
  - `#NNNN` references at line-start and mid-line (per `cq-prose-issue-ref-line-start`): preserved.
  - CRLF line endings: handled correctly.
  - Unknown suspected-leak pattern (matches `/workspaces/\|/tmp/claude-` but no canonical pattern) → `reportSilentFallback` mock called with `{ feature: "command-center", op: "asstext-scrub-fallthrough" }`.
  - Round-trip: raw input → formatted output does NOT mutate the raw (purity).
- **T3.2 GREEN:** create `apps/web-platform/lib/format-assistant-text.ts` exporting `formatAssistantText(raw: string, opts?: { reportFallthrough?: (shape: string) => void }): string`. Implementation:
  - Tokenize by fenced-code regex + indented-code-block detection into (fence, non-fence) segments.
  - Import `SANDBOX_PATH_PATTERNS` from `tool-labels.ts` (server-exported, tree-shaken for client use).
  - Apply path-prefix regex only to non-fence segments.
  - `reportFallthrough` closure invoked on any remaining `/workspaces/\|/tmp/claude-` shape in non-fence segments.
  - Pure function — no IO on happy path. `reportFallthrough` is the only IO and is optional.
- **T3.3 GREEN:** wire into `message-bubble.tsx` render path — `<MarkdownRenderer content={formatAssistantText(content, { reportFallthrough: report })} />` where `report` calls `reportSilentFallback`. Scope: only `role === "assistant"` bubbles. User-role messages render verbatim.

**Acceptance:** Phase 3 tests green. Manual verify in dev: agent message referencing a sandbox path renders scrubbed; Supabase `conversation_messages` row content = verbatim.

### Phase 4 — FR5: retry lifecycle + pre-merge verification

- **T4.1 RED — retry transitions:** extend `chat-state-machine.test.ts` with `"applyTimeout retry lifecycle"`:
  - First `applyTimeout(leaderId)` on bubble in `"tool_use"` → bubble gains `retrying: true`, state stays `"tool_use"` (visual chip switches via render), `timerAction === { type: "reset", leaderId }` (restart 45s watchdog).
  - Second consecutive `applyTimeout(leaderId)` (bubble has `retrying: true`) → bubble transitions to `"error"`, `retrying` cleared, `toolLabel` preserved, `timerAction === { type: "clear", leaderId }`.
  - `tool_progress` event for a leader with `retrying: true` (covered by Phase 2 T2.1 addendum) → bubble transitions back to `"tool_use"`, `retrying` cleared.
  - Server-emitted `error` event (not a stuck-timeout) on a bubble in `"tool_use"` → transitions directly to `"error"` WITHOUT passing through `retrying` (narrowness invariant).
- **T4.2 GREEN — state machine:** extend `ChatMessageBase` with `retrying?: boolean`. Modify `applyTimeout` to read `retrying`, transition first-timeout → `retrying: true` with timer restart, second-timeout → `"error"` with timer clear. Extend `case "tool_progress":` in `applyStreamEvent` to clear `retrying` when present.
- **T4.3 GREEN — message-bubble:** update render:
  - `case "tool_use":` — if `message.retrying === true`, show amber "Retrying…" chip with `aria-live="polite"` announcement + last `toolLabel` below in neutral text. Otherwise existing `ToolStatusChip`.
  - `case "error":` — show red icon + `"Agent stopped responding after: <toolLabel ?? \"Working\">"`. Append a "File an issue" link populated with session context (leaderId, conversationId, last toolLabel). **No Retry button** — the File-issue link is the functional escape hatch.
- **T4.4 Pre-merge verification checklist:**
  - Run `./node_modules/.bin/vitest run` from `apps/web-platform/` — baseline ~2322 passing + ~11 skipped at plan time; must remain green.
  - Run `tsc --noEmit` from `apps/web-platform/` — clean.
  - Run `npx markdownlint-cli2 --fix` on all changed `.md` files.
  - Dev-session dogfood: open Command Center, run a long Grep/Read over `knowledge-base/`, verify bubble stays live past 45s.
  - Screenshot set for PR body: (a) long-running bubble stays live; (b) assistant text references a path and renders scrubbed; (c) forced-timeout error chip with File-issue link.

**Acceptance:** All tests green. Manual verify + screenshots captured.

---

## Files to Edit

- `apps/web-platform/server/tool-labels.ts` — FR1 + FR2
- `apps/web-platform/server/agent-runner.ts` — FR4 forwarding + debounce
- `apps/web-platform/lib/chat-state-machine.ts` — FR4 + FR5 reducer branches
- `apps/web-platform/lib/ws-client.ts` — FR4 `KNOWN_TYPES` boundary guard, `ToolProgressEvent` type addition
- `apps/web-platform/components/chat/message-bubble.tsx` — FR3 render scrub + FR5 UI
- `apps/web-platform/test/build-tool-label.test.ts` — FR1 + FR2 tests
- `apps/web-platform/test/chat-state-machine.test.ts` — FR4 + FR5 reducer tests

## Files to Create

- `apps/web-platform/lib/format-assistant-text.ts` — FR3 pure helper
- `apps/web-platform/test/format-assistant-text.test.tsx` — FR3 tests
- `apps/web-platform/test/tool-progress-forwarding.test.ts` — FR4 agent-runner test

---

## Test Strategy

- **Unit-level RED tests run FIRST** per `cq-write-failing-tests-before-implementation`.
- **Test runner:** `./node_modules/.bin/vitest run` from `apps/web-platform/` (per `cq-in-worktrees-run-vitest-via-node-node`).
- **jsdom constraint (`cq-jsdom-no-layout-gated-assertions`):** assert DOM structure + `data-*` hooks, not layout values.
- **Fake timers** for retry lifecycle use manual `setTimeout`, NOT `AbortSignal.timeout` per `cq-abort-signal-timeout-vs-fake-timers`.
- **Module-scope stubs** per `cq-vitest-setup-file-hook-scope`: `reportSilentFallback` stubbed at module scope; cleanup in `afterAll`.
- **Observability assertion** in every fallback-path test: `reportSilentFallback` called with correct `feature`/`op` tags. This is load-bearing for the FR2/FR3/FR4 success metric.

---

## Acceptance Criteria

### Pre-merge (PR)

- [x] No raw sandbox or host workspace path appears in any Command Center activity bubble label under the tested tool matrix (Read/Edit/Write/Bash/Grep/Glob + 11 Bash verb cases + 5 edge cases).
- [x] No raw sandbox or host workspace path appears in rendered assistant-text output (8 representative shapes including fenced code, indented code, nested fences, CRLF, URLs, `#NNNN`). `conversation_messages` row content = verbatim model output.
- [ ] Long-running Grep or Bash call exceeding 45s does NOT flip the bubble to `error` state while heartbeats flow (manual verify + screenshot).
- [x] First stuck-timeout transitions to `retrying` (visible "Retrying…" + `aria-live="polite"` + 45s watchdog restart). A matching `tool_progress` during `retrying` reverts to `"tool_use"`. A second consecutive stuck-timeout transitions to `error` with last activity label + File-issue link.
- [x] Server-emitted `error` events (not stuck-timeout) transition to `"error"` directly WITHOUT passing through `retrying` (narrowness invariant).
- [x] Unknown WS event types are dropped via `KNOWN_TYPES.has()` guard with `reportSilentFallback({ feature: "command-center", op: "ws-unknown-event" })`. No exception, no state mutation.
- [x] `reportSilentFallback` fires on each fallback path: unknown Bash verb (`op: "tool-label-fallback"`), unmatched sandbox prefix (`op: "tool-label-scrub"`), unscrubbed assistant-text leak (`op: "asstext-scrub-fallthrough"`), unknown WS event (`op: "ws-unknown-event"`). All tagged `feature: "command-center"`.
- [x] `SDKToolProgressMessage` forwarding is debounced to ≤ 1 emission / 5s per `tool_use_id` (verified in T2.3 test).
- [x] All existing tests continue to pass (baseline ~2322 passing + ~11 skipped). Post-plan: 2404 passing + 11 skipped.
- [x] `tsc --noEmit` clean.
- [ ] `/soleur:review` multi-agent review passes.

### Post-merge (operator)

- [ ] Post-deploy dogfood verify: `/command-center` on prod, provoke a >45s Grep, confirm no "Agent stopped responding".
- [ ] Sentry breadcrumb inspection (48h post-deploy): `feature: "command-center"` fallback hits for `tool-label-fallback` / `tool-label-scrub` / `asstext-scrub-fallthrough` trend DOWN. Alert threshold on `ws-unknown-event`: > 5/min sustained for 10+ minutes after deploy settles indicates true server/client skew (short post-deploy burst is expected).

---

## Alternative Approaches Considered

| Approach | Chosen? | Why |
|---|---|---|
| **A+B: heuristic labels + agent-emitted progress notes (brainstorm approach B)** | No, B dropped | System-prompt compliance is probabilistic with no prior data; #2854 may subsume B. Deterministic A ships today; B revisited only if A proves insufficient. |
| **Server-side assistant-text scrub at stream time** | No | Corrupts `conversation_messages`, cost tracking, SDK replay, Sentry breadcrumbs. Violates verbatim-storage invariant. |
| **zod schema at WS boundary** | No | Reducer is already exhaustive TS. Inline `KNOWN_TYPES.has()` check + `reportSilentFallback` is 3 lines and zero new dependency. |
| **Retry button wired as non-functional placeholder** | No | Shipping UI that doesn't do anything is worse UX than no button. File-issue link is the functional escape hatch. Handler wiring is a future scope if demand surfaces. |

---

## Risks

1. **Bash verb parser edge cases** (`bash -c`, pipelines, `sudo`, subshells) fall through to "Working…". This is the correct safe default; `reportSilentFallback` instruments the rate. If prod data shows a hot pattern, add it to the allowlist in a follow-up (single-line change). No risk of leaking raw command — fallback is "Working…", not the raw string.
2. **Sandbox-path regex false positives on legitimate user content.** Scrub scoped to `role === "assistant"` bubbles only; user-role messages render verbatim (T3.3 invariant).

---

## Research Insights

- **SDK `SDKToolProgressMessage` is a top-level `SDKMessage` union variant**, NOT nested in `stream_event`. Shape: `{ type: 'tool_progress'; tool_use_id: string; tool_name: string; parent_tool_use_id: string | null; elapsed_time_seconds: number; task_id?: string; uuid: UUID; session_id: string }`. Source: `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:2504-2513`. Verified 2026-04-23.
- **Current reducer is exhaustive** — boundary-level `KNOWN_TYPES.has()` guard handles forward-compat without widening the discriminated union.
- **`reportSilentFallback` signature:** `(err, { feature, op?, extra?, message? })` from `apps/web-platform/server/observability.ts:82-103`.
- **Community discovery:** no trust-qualifying artifact implements Claude Agent SDK heartbeat forwarding, tool-call heuristic labeling, or sandbox path scrubbing. Soleur-specific infrastructure confirmed.
- **Governing AGENTS.md rules:** `cq-silent-fallback-must-mirror-to-sentry`, `cq-write-failing-tests-before-implementation`, `cq-in-worktrees-run-vitest-via-node-node`, `cq-abort-signal-timeout-vs-fake-timers`, `cq-jsdom-no-layout-gated-assertions`, `cq-vitest-setup-file-hook-scope`, `cq-prose-issue-ref-line-start`, `cq-union-widening-grep-three-patterns` (applies when `ToolProgressEvent` joins `StreamEvent`).
- **PR #2843 (commit `be0378ce`)** addressed adjacent stream-lifecycle idempotency. This plan does not re-examine those paths.
