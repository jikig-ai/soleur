# Tasks: feat-command-center-activity-ux

**Plan:** [`../../plans/2026-04-23-feat-command-center-activity-ux-plan.md`](../../plans/2026-04-23-feat-command-center-activity-ux-plan.md)
**Spec:** [`spec.md`](./spec.md)
**Issue:** #2861
**Draft PR:** #2860

## Phase 1: FR1 + FR2 — server-side label pipeline

### RED

- [ ] 1.1 Extend `apps/web-platform/test/build-tool-label.test.ts` with `"sandbox-path stripping"` describe block — host prefix, sandbox prefix, no workspacePath, idempotency, unmatched-leak → `reportSilentFallback({ feature: "command-center", op: "tool-label-scrub" })`.
- [ ] 1.2 Add `"Bash verb allowlist"` describe block — 11 allowlist verbs + 5 edge cases (`FOO=bar ls`, `bash -c "ls /tmp"`, `find . | head`, `sudo ls`, `$(ls)`). Unknown verbs assert `reportSilentFallback({ op: "tool-label-fallback", extra: { verb } })`.

### GREEN

- [ ] 1.3 Export named `SANDBOX_PATH_PATTERNS: RegExp[]` from `apps/web-platform/server/tool-labels.ts`.
- [ ] 1.4 Extend `stripWorkspacePath` to iterate `SANDBOX_PATH_PATTERNS` in addition to `workspacePath`. Call `reportSilentFallback` on remaining suspected-leak shape.
- [ ] 1.5 Add `mapBashVerb(command: string): string` helper with allowlist map, leading-env-assignment skip, and "Working…" fallback. Comment documents parser non-goals.
- [ ] 1.6 Wire `mapBashVerb` into `case "Bash"` of `buildToolLabel`, replacing `return \`Running: ${cleaned}\``.

## Phase 2: FR4 — `tool_progress` WS event + watchdog fix

### RED

- [ ] 2.1 Extend `apps/web-platform/test/chat-state-machine.test.ts` with `"tool_progress event"` describe block — `tool_use` → `tool_use` with timer reset, unknown leader inert, (post-Phase-4) `retrying` → `tool_use` with `retrying` cleared.
- [ ] 2.2 Add WS `onmessage` boundary test — unknown `type` does NOT throw, does NOT dispatch, calls `reportSilentFallback({ op: "ws-unknown-event", extra: { rawType } })`.
- [ ] 2.3 Create `apps/web-platform/test/tool-progress-forwarding.test.ts` — assert `sendToClient` shape, 5s debounce per `tool_use_id`, per-leader `AbortController` isolation.

### GREEN

- [ ] 2.4 Add `ToolProgressEvent` to WS `StreamEvent` discriminated union. Shape: `{ type: "tool_progress"; leaderId: DomainLeaderId; toolUseId: string; toolName: string; elapsedSeconds: number }`.
- [ ] 2.5 Add `else if (message.type === "tool_progress")` branch in `agent-runner.ts` message loop with `Map<tool_use_id, lastSentAt>` throttling to ≤ 1 WS emission / 5s per id.
- [ ] 2.6 Add `case "tool_progress":` branch in `applyStreamEvent` — timer reset when leader in `activeStreams`, inert no-op otherwise.
- [ ] 2.7 Add `KNOWN_TYPES` Set + 3-line guard at WS `onmessage` in `ws-client.ts`.

## Phase 3: FR3 — client-side assistant-text render scrub

### RED

- [ ] 3.1 Create `apps/web-platform/test/format-assistant-text.test.tsx` — fenced code preservation (standard, indented 4-space, nested triple-backtick, CRLF), inline backticks, URLs, `#NNNN` refs (line-start + mid-line), unknown-leak → `reportSilentFallback({ op: "asstext-scrub-fallthrough" })`, round-trip purity.

### GREEN

- [ ] 3.2 Create `apps/web-platform/lib/format-assistant-text.ts` exporting `formatAssistantText(raw, { reportFallthrough? })`. Tokenize by fence regex, import `SANDBOX_PATH_PATTERNS` from `tool-labels.ts`, apply only to non-fence segments.
- [ ] 3.3 Wire into `message-bubble.tsx` render path — `role === "assistant"` bubbles only; `<MarkdownRenderer content={formatAssistantText(content, { reportFallthrough })} />`.

## Phase 4: FR5 — retry lifecycle + pre-merge verify

### RED

- [ ] 4.1 Extend `chat-state-machine.test.ts` with `"applyTimeout retry lifecycle"` — first timeout → `retrying: true` + `timer reset`, second consecutive timeout → `"error"` with `toolLabel` preserved, `tool_progress` during `retrying` reverts to `"tool_use"`, server-emitted `error` bypasses `retrying` (narrowness).

### GREEN

- [ ] 4.2 Extend `ChatMessageBase` with `retrying?: boolean`. Modify `applyTimeout` for first-timeout → `retrying: true` + timer restart, second-timeout → `"error"` + timer clear. Extend `case "tool_progress":` to clear `retrying`.
- [ ] 4.3 Update `message-bubble.tsx`:
  - [ ] 4.3.1 `case "tool_use":` — if `message.retrying === true`, render amber "Retrying…" chip with `aria-live="polite"` + last `toolLabel` below.
  - [ ] 4.3.2 `case "error":` — red icon + `"Agent stopped responding after: <toolLabel ?? \"Working\">"` + "File an issue" link with session context (leaderId, conversationId, toolLabel). **No Retry button.**

### Pre-merge verification

- [ ] 4.4 Run `./node_modules/.bin/vitest run` from `apps/web-platform/` — baseline green.
- [ ] 4.5 Run `tsc --noEmit` from `apps/web-platform/` — clean.
- [ ] 4.6 Run `npx markdownlint-cli2 --fix` on changed `.md` files.
- [ ] 4.7 Dev-session dogfood — Command Center + long Grep over `knowledge-base/`, verify bubble stays live past 45s.
- [ ] 4.8 Capture PR screenshots: (a) long-running bubble stays live, (b) assistant text scrubbed, (c) forced-timeout error chip with File-issue link.
- [ ] 4.9 Run `/soleur:review` multi-agent review; resolve findings inline per `rf-review-finding-default-fix-inline`.
- [ ] 4.10 `/soleur:ship` — Changelog, semver label, mark PR ready, poll auto-merge.

## Post-merge (operator)

- [ ] M1 Post-deploy prod dogfood — `/command-center`, provoke >45s Grep, verify no "Agent stopped responding" chip.
- [ ] M2 Sentry breadcrumb inspection (48h window) — `feature: "command-center"` fallback hits trending DOWN; `ws-unknown-event` alert threshold `> 5/min sustained for 10+ min`.
- [ ] M3 Update #2225 comment noting this PR's new `tool_progress` branch also uses the loose `string` key, to be tightened alongside the rest when #2225 is scheduled.
