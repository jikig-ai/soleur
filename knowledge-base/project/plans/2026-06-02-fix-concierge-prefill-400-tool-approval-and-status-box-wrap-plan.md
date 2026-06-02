---
title: "fix(chat): Concierge prefill-400 regression on resume + restore tool auto-approval + widen status box"
date: 2026-06-02
status: ready-for-work
type: bug-fix
issue: TBD
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
branch: feat-one-shot-concierge-prefill-approval-ui
prior_art:
  - knowledge-base/project/plans/2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md
related_prs: [4831, 4838, 4848, 4824, 3263, 3419, 3344]
---

# Fix Concierge prefill-400 on resume + tool-approval regression + status-box wrap

## TL;DR

Two regressions in the web Dashboard chat/Concierge flow after the chat-persistence
hardening (`#4831` workspace_id, `#4848`/`#4839` template_id NOT-NULL) and the chat-input
UI change (`#4838`):

**REGRESSION 1 (primary, server-side).** A Concierge-driven run (a) ends with raw
`API Error: 400 … "This model does not support assistant message prefill. The
conversation must end with a user message."`, and (b) prompts Approve/Deny on every
Bash call (`pwd && git rev-parse --is-bare-repository 2>/dev/null`,
`bash ./plugins/.../worktree-manager.sh cleanup-merged …`).

The 400 is a **regression of the `#3250`/`#3263` prefill guard** (plan
`2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md`). The guard
(`apps/web-platform/server/agent-prefill-guard.ts`) drops `resume:` when the persisted
SDK session ends on an `assistant` turn — but it probes the SDK session file via
`getSessionMessages(resumeSessionId, { dir: workspacePath })`, and on a **dir-mismatch or
absent session file** it falls into the empty-history branch which **passes `resume:`
through unchanged** (guard comment lines 217-232). The SDK then forwards the
assistant-terminated thread to `claude-sonnet-4-6`, which 400s. Two recent changes plausibly
re-opened the false-negative window: (i) `#4831`/`#4848` made the user/assistant message
INSERTs **throw** mid-turn on workspace_id/template_id failures, so turns now abort *after*
the SDK has streamed a partial assistant block but *before* the user-message row persists —
producing exactly the assistant-terminated persisted thread the guard must catch; (ii) the
`workspacePath` the guard passes as `dir` must equal the cwd the SDK persisted the session
under, or `getSessionMessages` returns `[]` (false negative → resume passes through → 400).

The Approve/Deny-on-every-Bash symptom is **partly working-as-designed and partly a
consequence of the failed turn**: the Concierge (cc-router) runs `claude-sonnet-4-6` on the
cc-soleur-go path where Bash routes through `canUseTool` + the `safe-bash` allowlist
(`#3344`). The two cited commands are genuinely NOT safe-bash (`&&`, `2>` redirect, and a
`bash <script>` verb not in the allowlist), so they have always routed to `review_gate`.
The regression the user perceives ("was working before") is that the Concierge is now
**attempting an engineering task inline** (worktree cleanup, bare-repo probing) on its own
cc-router surface instead of routing to a domain leader — and because the run 400s and is
retried, each retry re-issues the same gate prompts. Root-causing must determine whether the
fix is (a) restore the prior auto-approval surface for the Concierge's own
session-bootstrap commands, and/or (b) ensure the turn does not retry-storm after the 400.

**REGRESSION 2 (UI).** The "Soleur Concierge" header + "Working" badge + "Routing to the
right experts..." status box wraps its text onto multiple lines despite available
horizontal space. The status box is rendered by `MessageBubble`
(`apps/web-platform/components/chat/message-bubble.tsx`) via the routing chip at
`chat-surface.tsx:743-754` (`isClassifying` → `MessageBubble messageState="tool_use"
toolLabel="Routing to the right experts..."`). The bubble caps at `max-w-[90%]/md:max-w-[80%]`
with inner `min-w-0`; the `ToolStatusChip` label span (`message-bubble.tsx:24-30`) has no
`whitespace-nowrap`, so the short status string wraps inside the flexible bubble. Fix: let
the status chip and the leader header grow to their natural single-line width (e.g.
`whitespace-nowrap` on the chip span + header, `w-fit` on the bubble for the routing-chip
case) so short status text never wraps when space is available. This is a UI improvement, not
a `#4838`-caused defect — `#4838`/`#4832` only touched `chat-input.tsx`, `dashboard/page.tsx`,
`constants.ts`, not the bubble/surface.

## Premise Validation

Checked (all on the worktree HEAD; today is 2026-06-02):

- **`#4831`** (deb0f1bb) merged — added a `conversations.workspace_id` SELECT inside
  `dispatchSoleurGo` (cc-dispatcher.ts:1465-1485), `saveMessage` (agent-runner.ts:437-471),
  and extended the `sendUserMessage` select (agent-runner.ts:2454-2481). All three now
  **throw** on read/INSERT failure. Confirmed present.
- **`#4848`** (7512ac6a) merged — `template_id: "default_legacy"` added to interactive INSERTs
  (visible in `sendUserMessage` at agent-runner.ts:2475). Confirmed.
- **`#4838`** (cfce2692) merged — touched only `chat-input.tsx`, `dashboard/page.tsx`,
  `constants.ts`, three test files. Did **NOT** touch `message-bubble.tsx` or
  `chat-surface.tsx`. So Regression 2 is NOT a `#4838` code change — it is a pre-existing
  layout characteristic the user wants improved. Confirmed via `git show cfce2692 --stat`.
- **`#4824`** (b31884f6, operator CC subscription oauth_token) merged but **gated OFF today**:
  `CC_OAUTH_EFFECTIVE_DATE = 2026-06-15` (byok-lease.ts:70) + kill-switch env + Flagsmith +
  requires an `anthropic_oauth` row. Today (2026-06-02) `getAgentCredential()` returns
  `scheme: "api_key"` → `buildAgentEnv` injects `ANTHROPIC_API_KEY` → model stays
  `claude-sonnet-4-6` (query-options.ts:130). **#4824 is NOT the active model-change cause.**
  Verified — rules out the "subscription model also rejects prefill" hypothesis for current prod.
- **Prefill guard / permission-callback / safe-bash had NO recent code changes**:
  `agent-prefill-guard.ts` last touched `#3419` (d0e648b5); `permission-callback.ts` last
  `#3608` (36e6e7cb); `safe-bash.ts` is `#3277`-era. So Regression 1 is a **runtime/state +
  persistence-interaction** regression, not a logic edit to those files. Verified via `git log`.
- **FLAG_CC_SOLEUR_GO retired** in `#3270` — cc-soleur-go runs unconditionally
  (ws-handler.ts:1316). The Concierge always uses `dispatchSoleurGo`. Verified.

No stale premise blocks the plan. The plan shape is **fix a regressed guard + a UI wrap**,
not build-from-scratch.

## User-Brand Impact

**If this lands broken, the user experiences:** A raw Anthropic `400 invalid_request_error`
string rendered verbatim inside the Concierge response bubble — the brand-visible front door
of `/soleur:go` — on a follow-up message after any mid-turn abort, container redeploy,
wall-clock fire, or message-persistence throw. Compounded by an Approve/Deny modal on every
Bash call, the user reads "Soleur is broken" within their first interaction. No recovery copy,
no retry button — the 400 renders into the bubble.

**If this leaks, the user's workflow is exposed via:** No data exposure. The exposure is a
trust collapse on first use; the prefill-guard probe error is already path-sanitized before
Sentry (`sanitizeProbeError`, agent-prefill-guard.ts:157-171), so no container-path leak.

**Brand-survival threshold:** `single-user incident` — inherited from the `#3250` prior plan;
the Concierge is the brand front door. CPO sign-off required at plan time;
`user-impact-reviewer` invoked at review time per `hr-weigh-every-decision-against-target-user-impact`.

## Research Reconciliation — Spec vs. Codebase

| Claim (from feature description) | Reality (codebase HEAD) | Plan response |
| --- | --- | --- |
| "web platform lives under `web-platform/`" | It lives under **`apps/web-platform/`**. | All paths in this plan use `apps/web-platform/`. |
| "messages array sent to model ends with assistant (prefill) — fix the message-array construction" | The platform does NOT hand-build the messages array; the **Agent SDK** rebuilds it from the persisted `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` when `resume:` is set. The only Soleur lever is the **prefill guard** that drops `resume:` (remediation (a) from the `#3250` plan). | Fix targets the guard's false-negative (dir-mismatch / empty-history pass-through), not a hand-built array. |
| "permission-mode regression — tools previously auto-approved now all prompt" | `permissionMode` defaults to `"default"` (query-options.ts:131) — unchanged. The cited commands were never safe-bash auto-approved (`&&`/redirect/`bash <script>`). | Root-cause whether the Concierge is now emitting inline-engineering Bash it should route, and/or the 400 retry re-issues gates. Restore prior surface only after confirming what "previously auto-approved" meant. |
| "regression introduced by `#4838` (chat input UI)" | `#4838` did not touch the bubble/surface. | Regression 2 is a UI improvement to `message-bubble.tsx`/`chat-surface.tsx`, decoupled from `#4838`. |
| "`#4831` broke message-history construction" | `#4831` did not change `resumeSessionId` derivation (still `activeSession?.sessionId ?? conv.session_id ?? undefined`, agent-runner.ts:2505). It DID add mid-turn throwing INSERTs that can leave the SDK session assistant-terminated. | Plan treats `#4831` as the *trigger amplifier* (more abort-mid-stream turns), not the array builder. |

## Reproduction (must run at /work Phase 1, before any fix)

The 400 is non-deterministic (depends on a persisted assistant-terminated session). Establish a
deterministic repro at the guard boundary, with the LLM removed from the assertion path
(per the LLM-SDK-security-test Sharp Edge — natural-language prompts are non-deterministic):

1. **Guard false-negative repro (unit).** Stub `getSessionMessages` to return `[]` for a
   known `resumeSessionId` (the dir-mismatch / absent-file case). Assert the current guard
   returns `{ safeResumeSessionId: <id> }` (passes resume through) — this is the bug. Then
   assert the empty-history branch's chosen remediation (see Phase 2) drops resume OR routes
   to a safe path. Reuse the `cc-dispatcher-real-factory.test.ts` mock harness +
   `agent-prefill-guard.test.ts` scaffold.
2. **dir-arg correctness probe.** Assert (in a runner-integration test, mocked SDK) that the
   `workspacePath` passed to `applyPrefillGuard` on BOTH paths equals the cwd
   `buildAgentQueryOptions` sets as `cwd:` (query-options.ts:129) and that the SDK persists
   under `<encoded(cwd)>` — i.e. the guard's `dir` and the SDK's `cwd` are the same value.
   A divergence here is the false-negative root cause.
3. **Sentry signal confirmation.** Before treating zero `op:prefill-guard-empty-history` hits
   as "guard healthy", run a representative broadened Sentry query (per the prior plan's Sharp
   Edge — `Error: Claude Code returned an error result:` wrappers swallow `prefill` substrings).
   Confirm the live error class matches `invalid_request_error` + `assistant message prefill`
   AND check the `prefill-guard-empty-history` op count — a non-zero count proves the
   dir-mismatch path is the live trigger.

## Implementation Phases

> Phase order is load-bearing: harden the guard (contract) BEFORE touching the dispatch
> retry / approval surface (consumer), and do the UI fix independently. RED before GREEN.

### Phase 1 — RED: reproduce both server regressions deterministically
- Add failing unit tests in `apps/web-platform/test/agent-prefill-guard.test.ts` for the
  empty-history false-negative (Repro 1) and the dir-arg invariant (Repro 2).
- Add a failing assertion that on a guard fire, the dispatch does NOT retry-storm gate prompts
  (drive `realSdkQueryFactory` / runner with a mocked SDK that 400s once, assert single gate
  emission per Bash, not N).
- Files: `apps/web-platform/test/agent-prefill-guard.test.ts`,
  `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` (extend),
  `apps/web-platform/test/agent-runner-*.test.ts` (legacy-path guard parity).

### Phase 2 — GREEN: close the prefill-400 false-negative
Two candidate fixes; choose at /work based on Phase 1 evidence (prefer the smaller):
- **2a (default — empty-history is unsafe on resume).** In `agent-prefill-guard.ts`, change the
  empty-history branch (lines 217-232) so a non-empty `resumeSessionId` that yields `[]` does
  **not** blindly pass `resume:` through. Today it passes through (comment: "Anthropic accepts
  empty conversation + new user message"). But an *absent/rotated* session file means the SDK
  may still hold server-side state that ends on assistant. Safer: **drop `resume:` on
  empty-history too** (start fresh; the runner rebinds `session_id` from the first streamed
  message — same recovery as the assistant-terminated branch), keeping the distinct
  `prefill-guard-empty-history` warn op for observability. Verify against the prior plan's
  "empty-history short-circuit refinement" note before flipping polarity.
- **2b (dir correctness).** If Phase 1 proves the `dir`/`cwd` divergence, fix the
  `workspacePath` threaded into `applyPrefillGuard` to equal `buildAgentQueryOptions.cwd`
  exactly on both call sites (cc-dispatcher.ts:959, agent-runner.ts:1722). Add a drift-guard
  assertion in `agent-runner-query-options.test.ts` that the guard's `dir` and the SDK `cwd`
  are sourced from the same value.
- Keep the positive-match polarity (`last.type === "assistant"`) — do not regress to a
  negative match.

### Phase 3 — Tool-approval surface: root-cause then restore prior auto-approval
- Determine empirically (Phase 1 + transcript) whether "every tool prompts" is: (i) the
  Concierge emitting inline-engineering Bash it should route to a domain leader, (ii) the 400
  retry re-issuing the same `review_gate` per Bash, or (iii) a genuine regression in the
  safe-bash/`bashApprovalCache` surface.
- If (ii): ensure a guard fire / 400 does not re-drive the tool loop — the turn should reset
  cleanly (the runner rebinds session_id; no replay of pending gates). Audit
  `cc-dispatcher.ts` `cleanupCcBashGatesForConversation` + the `bashApprovalCache` revocation
  so a torn-down turn does not leave dangling gates that re-prompt on the retry.
- If (i): this is a routing-prompt-content concern (the cc-router should route engineering
  tasks to the legacy domain-leader path where the workflow's own toolset auto-runs) — scope
  carefully; do NOT widen `safe-bash` to auto-approve `bash <script>` or compound/`&&`/redirect
  commands (that would re-open the `#3344` cascade and the confused-deputy surface). Restoring
  "prior auto-approval" means restoring the prior *batched-approval cache hit-rate*
  (`bashApprovalCache.grant` after one batched Approve), not loosening the allowlist regex.
- Files: `apps/web-platform/server/cc-dispatcher.ts`,
  `apps/web-platform/server/permission-callback.ts` (read-only audit unless (iii) is proven),
  `apps/web-platform/server/safe-bash.ts` (do NOT edit unless a proven allowlist gap).

### Phase 4 — Regression 2: widen the status box / stop status wrap
- In `apps/web-platform/components/chat/message-bubble.tsx`: add `whitespace-nowrap` to the
  `ToolStatusChip` label span (line 24-30) and to the leader-header span (line 193-195) so
  the single-line status never wraps; for the routing-chip case give the bubble a content-fit
  width (`w-fit` / `max-w-fit` within the existing `max-w-[90%]` cap) so it grows to its
  natural width when horizontal space is available.
- Verify the fix does not regress long-content assistant bubbles (which must still wrap) —
  scope `whitespace-nowrap` to the `tool_use`/status chip + header, NOT the streaming/markdown
  body (`message-bubble.tsx:269` keeps `whitespace-pre-wrap [overflow-wrap:anywhere]`).
- Visual verification in BOTH the routing-chip state (`isClassifying`) AND a normal in-flight
  `tool_use` bubble via Playwright MCP screenshots (per the "verify both toggle states"
  Sharp Edge — the wrap can differ by bubble subtree).
- Files: `apps/web-platform/components/chat/message-bubble.tsx`; tests under
  `apps/web-platform/test/` (e.g. `message-bubble.test.tsx`, `command-center.test.tsx`,
  any `routing-chip` testid assertion). Existing homes:
  `apps/web-platform/test/message-bubble-tool-status-chip.test.tsx`,
  `apps/web-platform/test/message-bubble-header.test.tsx`,
  `apps/web-platform/test/command-center.test.tsx`.

## Files to Edit
- `apps/web-platform/server/agent-prefill-guard.ts` — empty-history branch (Phase 2a).
- `apps/web-platform/server/cc-dispatcher.ts` — guard `dir` source + gate retry/cleanup (Phase 2b/3).
- `apps/web-platform/server/agent-runner.ts` — legacy-path guard `dir` parity (Phase 2b).
- `apps/web-platform/server/agent-runner-query-options.ts` — `cwd`/`dir` drift-guard (Phase 2b, if needed).
- `apps/web-platform/components/chat/message-bubble.tsx` — `whitespace-nowrap` + `w-fit` (Phase 4).
- Tests: `apps/web-platform/test/agent-prefill-guard.test.ts`,
  `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`,
  `apps/web-platform/test/agent-runner-query-options.test.ts`,
  `apps/web-platform/test/message-bubble-tool-status-chip.test.tsx` +
  `apps/web-platform/test/message-bubble-header.test.tsx` (existing files — the right home
  for the Regression-2 no-wrap assertions; vitest jsdom project collects `test/**/*.test.tsx`,
  so a co-located `components/**/*.test.tsx` would be silently skipped).

## Files to Create
- None expected (extend existing test files). If a new test file is needed, place it under
  `apps/web-platform/test/**` to satisfy the vitest `include:` glob (`test/**/*.test.ts(x)`);
  co-located `components/**/*.test.tsx` is silently skipped.

## Open Code-Review Overlap

None — to be confirmed at /work by querying `gh issue list --label code-review --state open`
for the file paths above.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO/UX).

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Server-side regression in a load-bearing recovery primitive (prefill guard).
The fix must not regress the positive-match polarity, must keep the path-sanitized Sentry
mirror, and must keep the guard's `dir` argument equal to the SDK `cwd`. The retry/gate-cleanup
audit (Phase 3) touches the cc Bash review-gate registry — verify `cleanupCcBashGatesForConversation`
revokes the `bashApprovalCache` on teardown so a 400-retry does not re-prompt. No new
infrastructure, no new secrets, no migration — pure code change on an already-provisioned surface.

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline ADVISORY — modifies an existing component, adds no new
user-facing surface or flow)
**Skipped specialists:** none
**Pencil available:** N/A — no new UI surface (CSS-only width/wrap change to an existing
component; mechanical UI-surface override does not force BLOCKING because no new
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` file is created).

#### Findings
Regression 2 is a non-wrapping/width tweak to the existing Concierge status chip — ADVISORY.
Visual verification via Playwright screenshots is required at /work (both routing-chip and
tool_use states). The "Routing to the right experts..." copy is unchanged (no copywriter gate).

## Infrastructure (IaC)

Skip — no new infrastructure, server, service, secret, vendor, or persistent runtime process.
Pure code change against the already-provisioned web-platform surface.

## Observability

```yaml
liveness_signal:
  what: Sentry warn op `op:prefill-guard` / `op:prefill-guard-empty-history` fire-rate (cc-concierge + agent-runner features)
  cadence: per guard fire (event-driven)
  alert_target: Sentry issue stream, feature=cc-concierge / agent-runner
  configured_in: apps/web-platform/server/agent-prefill-guard.ts (warnSilentFallback calls)
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (path-sanitized)
  fail_loud: true — the prefill 400, if it still leaks, surfaces as an Anthropic invalid_request_error event; the guard fires emit distinct warn ops
failure_modes:
  - mode: guard false-negative (empty-history passes resume → 400)
    detection: count of `invalid_request_error` + "assistant message prefill" events > 0 after fix
    alert_route: Sentry feature=cc-concierge
  - mode: dir/cwd divergence (getSessionMessages returns [])
    detection: `op:prefill-guard-empty-history` count > 0 for known resumeSessionIds
    alert_route: Sentry op:prefill-guard-empty-history
  - mode: gate retry-storm after 400
    detection: multiple `review_gate` emissions per single Bash tool_use_id within one turn
    alert_route: Sentry feature=cc-dispatcher op:review-gate (audit at /work)
logs:
  where: structured pino logs (createChildLogger) + Sentry breadcrumbs
  retention: per existing Sentry/log retention (unchanged)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-prefill-guard.test.ts"
  expected_output: all guard tests pass, including the new empty-history-drops-resume + dir-invariant assertions
```

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — A unit test proves the guard drops `resume:` (or routes to the chosen safe path)
  when `getSessionMessages` returns `[]` for a known `resumeSessionId` (the false-negative
  that leaks the 400). RED→GREEN.
- [ ] AC2 — A drift-guard test asserts the `dir` passed to `applyPrefillGuard` equals the
  `cwd` `buildAgentQueryOptions` sets, on BOTH the cc-dispatcher and agent-runner call sites.
- [ ] AC3 — The guard retains positive-match polarity (`last.type === "assistant"`) and the
  path-sanitized Sentry mirror — verified by an existing/extended test, not just inspection.
- [ ] AC4 — A test proves a single guard fire / 400 does not re-issue more than one
  `review_gate` per Bash `tool_use_id` (no retry-storm of approval prompts).
- [ ] AC5 — Phase 3 root-cause documented in the PR body: which of (i)/(ii)/(iii) explains
  "every tool prompts", and the exact fix. `safe-bash.ts` allowlist regex is NOT loosened to
  auto-approve `bash <script>`/compound/redirect commands (grep-verified: no new verb in
  `SAFE_BASH_VERBS`, no metachar removed from `SHELL_METACHAR_DENYLIST`).
- [ ] AC6 — Regression 2: Playwright screenshots show the "Soleur Concierge" header +
  "Routing to the right experts..." status box on ONE line when horizontal space is available,
  in BOTH the routing-chip (`data-testid="routing-chip"`) and a normal `tool_use` bubble.
  Long-content assistant bubbles still wrap (no regression to body wrapping).
- [ ] AC7 — `tsc --noEmit` clean; full web-platform vitest green.

### Post-merge (operator)
- [ ] AC8 — After deploy, Sentry shows zero new `invalid_request_error` + "assistant message
  prefill" events on the cc-concierge / agent-runner features over the following 48h
  (read-only Sentry API query; deterministic verdict: count == 0). Automation: query Sentry
  API per `hr-no-dashboard-eyeball-pull-data-yourself`.

## Risks & Mitigations
- **R1 — flipping the empty-history branch to drop resume could discard a legitimately
  resumable fresh session.** Mitigation: the runner rebinds `session_id` from the first
  streamed message on a fresh start (documented recovery in the `#3250` plan); the distinct
  warn op preserves observability. Validate against the prior plan's empty-history note before
  flipping.
- **R2 — widening `safe-bash` to silence prompts would re-open the `#3344` PDF-cascade /
  confused-deputy surface.** Mitigation: Phase 3 explicitly forbids loosening the allowlist;
  "restore auto-approval" = restore the batched-approval cache hit-rate, not the regex.
- **R3 — Agent SDK `getSessionMessages` surface drift.** Mitigation: pinned via existing guard
  tests; `dir`/`cwd` invariant test (AC2) catches a cwd-encoding change.
- **R4 — `whitespace-nowrap` on the wrong element could clip long status labels off-screen.**
  Mitigation: scope to the status chip + header only; keep the bubble's `max-w-[90%]` cap so a
  pathologically long label still wraps at the cap; Playwright verify both states.

## Sharp Edges
- The platform does NOT hand-build the Anthropic `messages` array — the Agent SDK rebuilds it
  from the persisted `.jsonl` on `resume:`. The ONLY Soleur lever is the prefill guard's
  decision to forward or drop `resume:`. Do not look for a `messages: [...]` construction site.
- The guard's `dir` argument MUST equal the SDK `cwd`, or `getSessionMessages` silently
  returns `[]` (false negative → 400). This is the highest-suspicion root cause.
- `bash ./plugins/.../worktree-manager.sh …` and `pwd && git rev-parse … 2>/dev/null` are NOT
  safe-bash by design (`bash <script>` verb, `&&`, `2>` redirect all fail
  `SHELL_METACHAR_DENYLIST`). They have prompted since `#3344`. Do NOT "fix" by adding them to
  the allowlist.
- `#4824` oauth is gated to 2026-06-15 + flag + kill-switch + `anthropic_oauth` row — inactive
  today; do not chase a subscription-model prefill hypothesis for current prod.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is
  `single-user incident` with `requires_cpo_signoff: true`.
- Verify the vitest `include:` glob before choosing any new test file path — co-located
  `components/**/*.test.tsx` is silently skipped; tests live under `test/**`.
