---
feature: feat-one-shot-concierge-prefill-approval-ui
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-02-fix-concierge-prefill-400-tool-approval-and-status-box-wrap-plan.md
brand_survival_threshold: single-user incident
status: ready-for-work
---

# Tasks — Concierge prefill-400 + tool-approval + status-box-wrap fix

## Phase 0 — Preconditions / root-cause grounding
- [ ] 0.1 Confirm `getSessionMessages(_sessionId, { dir? })` semantics in the installed SDK
  (`apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:518, 523-528`):
  `dir` omitted → searches all projects; sessions persist under
  `~/.claude/projects/<sanitized-cwd>/` (`:876, :3780`).
- [ ] 0.2 Confirm the guard `dir` value vs `buildAgentQueryOptions.cwd` value on both call sites
  (cc-dispatcher.ts:959, agent-runner.ts:1722). Record whether they byte-match.
- [ ] 0.3 Sentry: run the broadened query (per prior-plan Sharp Edge — wrapper titles swallow
  `prefill`) and read the `op:prefill-guard-empty-history` count; confirm the live error class
  is `invalid_request_error` + "assistant message prefill".
- [ ] 0.4 Reproduce the "every tool prompts" symptom from a transcript: classify (i) Concierge
  inline-engineering Bash vs (ii) 400-retry re-issuing gates vs (iii) genuine allowlist regression.

## Phase 1 — RED
- [ ] 1.1 `agent-prefill-guard.test.ts`: failing test — `getSessionMessages` returns `[]` for a
  known `resumeSessionId` → current guard passes `resume:` through (the false-negative).
- [ ] 1.2 `agent-runner-query-options.test.ts`: failing drift-guard — guard `dir` == SDK `cwd`
  on both call sites (or: guard probe resolves session without `dir`).
- [ ] 1.3 Failing test — a single guard fire / 400 does not re-issue >1 `review_gate` per Bash
  `tool_use_id` (no retry-storm).

## Phase 2 — GREEN: close the prefill-400 false-negative
- [ ] 2.1 (2a) In `agent-prefill-guard.ts` empty-history branch (lines 217-232): stop blindly
  passing `resume:` through; drop `resume:` (start fresh; runner rebinds session_id) while
  keeping the distinct `op:prefill-guard-empty-history` warn. Validate against the prior plan's
  empty-history note before flipping polarity.
- [ ] 2.2 (2b) Pick the smaller-blast-radius dir fix: (i) thread guard `dir` == SDK `cwd`, OR
  (ii) drop the `dir` arg so the probe searches all projects. Add the matching test.
- [ ] 2.3 Keep positive-match polarity (`last.type === "assistant"`) and the path-sanitized
  Sentry mirror (`sanitizeProbeError`). Confirm via test.

## Phase 3 — Tool-approval surface
- [ ] 3.1 Root-cause per 0.4; document (i)/(ii)/(iii) in PR body.
- [ ] 3.2 If (ii): audit `cleanupCcBashGatesForConversation` + `bashApprovalCache` revocation so
  a torn-down/400-retry turn does not leave dangling gates that re-prompt.
- [ ] 3.3 If (i): scope routing (cc-router should route engineering tasks to the legacy
  domain-leader path) — do NOT widen `safe-bash`. "Restore auto-approval" = restore the
  batched-approval cache hit-rate, not the allowlist regex.
- [ ] 3.4 Grep-verify NO new verb in `SAFE_BASH_VERBS` and NO metachar removed from
  `SHELL_METACHAR_DENYLIST` (safe-bash.ts).

## Phase 4 — Regression 2 (status-box no-wrap)
- [ ] 4.1 `message-bubble.tsx`: add `whitespace-nowrap` to the `ToolStatusChip` label span
  (24-30) and the leader-header span (193-195); give the routing-chip bubble a content-fit width
  (`w-fit`/`max-w-fit`) within the existing `max-w-[90%]` cap.
- [ ] 4.2 Confirm streaming/markdown body (line 269) keeps `whitespace-pre-wrap
  [overflow-wrap:anywhere]` (long content must still wrap).
- [ ] 4.3 Tests in `message-bubble-tool-status-chip.test.tsx` + `message-bubble-header.test.tsx`
  (vitest jsdom collects `test/**/*.test.tsx` — do NOT co-locate under components/).
- [ ] 4.4 Playwright screenshots: routing-chip state (`data-testid="routing-chip"`) AND a normal
  `tool_use` bubble — both on one line; long-content bubble still wraps.

## Phase 5 — Verify / ship
- [ ] 5.1 `tsc --noEmit` clean; full web-platform vitest green.
- [ ] 5.2 PR body: `Ref` the issue (not `Closes` if any post-merge operator verification);
  document Phase 3 root-cause + the chosen Phase 2 fix.
- [ ] 5.3 Post-merge (operator/automated): Sentry API query — zero new
  `invalid_request_error` + "assistant message prefill" events over 48h (verdict: count == 0).
