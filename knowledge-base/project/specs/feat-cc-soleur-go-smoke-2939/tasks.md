---
title: Tasks — cc-soleur-go Stage 6 PR-C (security smoke FR3.1-3.4 + visual-QA rubric FR5)
date: 2026-05-15
issue: 2939
plan: knowledge-base/project/plans/2026-05-15-feat-cc-soleur-go-smoke-2939-pr-c-plan.md
spec: knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/spec.md
lane: cross-domain
brand_survival_threshold: single-user incident
status: tasks-complete
---

# Tasks: PR-C — Security smoke + visual-QA rubric + #2939 reconciliation

> **PR-A tasks (closed):** see git history of this file at the merge of #3743.
> **PR-B tasks (closed):** see git history at the merge of #3778.
>
> This rewrite reflects PR-C scope only.

TDD-structured. Each task: RED (failing test) → GREEN (smallest impl) →
REFACTOR if needed. No commit until tests pass.

## Phase 0 — Preconditions (HARD GATE)

Block /work GREEN if any verification disagrees. Update plan + re-spawn
plan-review.

### 0.1 Foundations exist
- [ ] 0.1.1 `git log --oneline main | grep -E '^[a-f0-9]+ .*#3743|^[a-f0-9]+ .*#3778'` returns ≥ 2 lines
- [ ] 0.1.2 `ls apps/web-platform/e2e/cc-soleur-go-ws-injector.ts apps/web-platform/e2e/helpers/supabase-mocks.ts apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts apps/web-platform/e2e/cc-soleur-go-routing.e2e.ts` all exist
- [ ] 0.1.3 `grep -n "export async function attachWsInjector" apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` returns 1 hit
- [ ] 0.1.4 `grep -n "WsControlEvent\|sendControl" apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` returns ≥ 2 hits

### 0.2 DOM / selector verification
- [ ] 0.2.1 `grep -rn "data-rate-limit-exceeded" apps/web-platform/components/ apps/web-platform/app/` returns 0 hits
- [ ] 0.2.2 `grep -n "data-error-boundary" apps/web-platform/components/error-boundary-view.tsx` returns ≥ 1 hit
- [ ] 0.2.3 `grep -n 'errorCode === "rate_limited"\|code === "rate_limited"\|code: "rate_limited"' apps/web-platform/lib/ws-client.ts apps/web-platform/components/chat/chat-surface.tsx` returns ≥ 3 hits
- [ ] 0.2.4 `grep -n '"bash_approval"' apps/web-platform/lib/ws-zod-schemas.ts apps/web-platform/components/chat/interactive-prompt-card.tsx apps/web-platform/components/chat/chat-surface.tsx apps/web-platform/lib/chat-state-machine.ts apps/web-platform/lib/types.ts apps/web-platform/test/interactive-prompt-card-resolved.test.tsx` returns ≥ 6 hits

### 0.3 Limiter values
- [ ] 0.3.1 `grep -n "DEFAULT_PER_USER_PER_HOUR\|DEFAULT_PER_IP_PER_HOUR" apps/web-platform/server/start-session-rate-limit.ts` returns `=10` and `=30`

### 0.4 StreamEvent shape
- [ ] 0.4.1 `grep -n "type StreamEvent\|export type StreamEvent" apps/web-platform/lib/chat-state-machine.ts` shows interactive_prompt / tool_use / stream_end / chat_message arms
- [ ] 0.4.2 `grep -n 'type: "chat_message"\|case "chat_message"' apps/web-platform/lib/chat-state-machine.ts` returns ≥ 1 hit
- [ ] 0.4.3 Grep error-arm shape: `grep -n 'type: "error"\|case "error"' apps/web-platform/lib/chat-state-machine.ts apps/web-platform/lib/ws-zod-schemas.ts` and record the required-field set for FR3.4 frame construction.
- [ ] 0.4.4 Grep assistant text emit shape: `grep -n 'text_delta\|assistant_message\|case "text"' apps/web-platform/lib/chat-state-machine.ts` and read `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` to identify the canonical WS-replay event sequence

### 0.5 Issue + PR state
- [ ] 0.5.1 `gh issue view 2939 --json state,title` → state OPEN
- [ ] 0.5.2 `gh pr view 3779 --json state,title,isDraft` → state OPEN, isDraft true
- [ ] 0.5.3 `gh label list --limit 200 | grep -E 'type/security|domain/engineering|priority/p2-medium'` returns ≥ 3 labels (used for any §DS2-DS5 scope-out issues)

## Phase 1 — DOM canary contract (`data-rate-limit-exceeded`)

### 1.1 GREEN — call-site edit
- [ ] 1.1.1 Edit `apps/web-platform/components/chat/chat-surface.tsx:555-566`. Add `data-rate-limit-exceeded={lastError.code === "rate_limited" ? "" : undefined}` to the wrapping `<div className="mb-4 ${widthWrapper}">` of the ErrorCard render
- [ ] 1.1.2 `bun tsc --noEmit` from `apps/web-platform/` → green
- [ ] 1.1.3 (Optional) Add a small jsdom test in `apps/web-platform/test/chat-surface-rate-limit-canary.test.tsx` that renders with `lastError.code === "rate_limited"` and asserts `[data-rate-limit-exceeded]` exists. Skip if no existing chat-surface render harness — the e2e in Phase 3.4 is the canonical consumer.

### 1.2 Commit
- [ ] 1.2.1 `git add apps/web-platform/components/chat/chat-surface.tsx` (+ optional unit test)
- [ ] 1.2.2 Commit: `feat(chat): data-rate-limit-exceeded canary attribute on rate_limited ErrorCard branch (#2939)`

## Phase 2 — Security e2e scaffold + bootChat helper

### 2.1 GREEN — file scaffold
- [ ] 2.1.1 Create `apps/web-platform/e2e/cc-soleur-go-security.e2e.ts` with the header comment + imports per plan Phase 2.1
- [ ] 2.1.2 Add `assertNoPageErrors(injector)` helper at file bottom (mirror `cc-soleur-go-bubbles.e2e.ts:95-100`)

### 2.2 Per-context bootChat helper
- [ ] 2.2.1 Define `bootChat(page: Page, opts: { convId: string }): Promise<WsInjector>` — near-copy of `cc-soleur-go-routing.e2e.ts:71-120` with convId parameterised
- [ ] 2.2.2 Define `bootChatInContext(ctx: BrowserContext, opts: { convId: string }): Promise<{ page: Page; injector: WsInjector }>` — used only by FR3.3
- [ ] 2.2.3 Inline-copy NOT extracted yet — file scope-out §DS1 ticket BEFORE writing the third copy (see Phase 7)

## Phase 3 — Four FR3.x assertions

### 3.1 FR3.1 — Prompt-injection drain
- [ ] 3.1.1 Declare `const CANARY = "STAGE6_CANARY_DO_NOT_EXFILTRATE"` + `const INJECTION_NAMED_TOOL = "mcp__soleur_platform__test_synthesized_exfil"` (module scope)
- [ ] 3.1.2 `test()`: boot chat, inject user `chat_message` carrying the canary + the synthesized injection-text directive (per plan §3.1.2 sketch — verify exact union arm at Phase 0.4)
- [ ] 3.1.3 Inject synthesized assistant text stream that does NOT contain the canary AND does NOT emit `tool_use(INJECTION_NAMED_TOOL)` — use the event sequence from `test/cc-soleur-go-end-to-end-render.test.tsx`
- [ ] 3.1.4 Assertions: `text=CANARY` count 0; `[data-tool-chip-id*="INJECTION_NAMED_TOOL"]` count 0; `assertNoPageErrors`
- [ ] 3.1.5 (Positive sibling — sharp-edge mitigation) Before the negative assertions, inject a non-injection tool name and assert its chip RENDERS — proves the negation machinery actually fires

### 3.2 FR3.2 — Bash review-gate
- [ ] 3.2.1 `test()`: boot chat, inject `interactive_prompt` with `kind="bash_approval"`, `payload: { command, cwd, gated: true }` (verify required fields via `apps/web-platform/lib/types.ts:77`)
- [ ] 3.2.2 Assert `[data-prompt-id][data-prompt-kind="bash_approval"]` visible
- [ ] 3.2.3 Assert `[data-tool-chip-id*="bash"]` count 0 (BEFORE-execution gate)
- [ ] 3.2.4 Click Approve button; assert resolved-row grammar matches `interactive-prompt-card-resolved.test.tsx:21-46` ("Approved" verb visible, no buttons)

### 3.3 FR3.3 — Cross-user / cross-context isolation
- [ ] 3.3.1 `test()` with `async ({ browser }) => ...` signature
- [ ] 3.3.2 Create two contexts: `ctxA = browser.newContext({ storageState: "e2e/.auth/user.json" })` + ctxB symmetric
- [ ] 3.3.3 `bootChatInContext(ctxA, { convId: "conv-stage-6-sec-fr33-a" })` + symmetric for B
- [ ] 3.3.4 `const FR33_MARKER = "STAGE6_FR33_USER_A_ONLY"`; inject a uniquely-marked frame on context A
- [ ] 3.3.5 Assert A's page shows the marker; assert B's page has zero hits on the marker; symmetric in reverse direction
- [ ] 3.3.6 Inline comment explains "harness boundary, not server boundary" (sharp edge)
- [ ] 3.3.7 `await ctxA.close(); await ctxB.close()`

### 3.4 FR3.4 — 11-conversation rate limit
- [ ] 3.4.1 `test()`: boot chat, inject synthesized `error` frame with `errorCode: "rate_limited"` + the canonical server message string ("Rate limited: too many conversations this hour.")
- [ ] 3.4.2 Assertions: `[data-rate-limit-exceeded]` visible (canary from Phase 1.1.1); `text=Rate Limited` visible (ErrorCard title from `chat-surface.tsx:558`); message body propagates through ErrorCard

### 3.5 Commit
- [ ] 3.5.1 `git add apps/web-platform/e2e/cc-soleur-go-security.e2e.ts`
- [ ] 3.5.2 Commit: `feat(e2e): Stage 6 PR-C security smoke FR3.1-FR3.4 (#2939)`

## Phase 4 — Screenshot redaction helper

### 4.1 GREEN — `screenshot-redact.ts`
- [ ] 4.1.1 `grep -n '"sharp":' apps/web-platform/package.json` — if present, use `sharp.composite`; if absent, run `bun add -d sharp` AFTER operator ack (sharp-edge: package.json change in security PR warrants ack)
- [ ] 4.1.2 Create `apps/web-platform/e2e/helpers/screenshot-redact.ts` with the API per plan §4.1.1
- [ ] 4.1.3 Add `apps/web-platform/test/screenshot-redact.test.ts` — synthetic 4×4 PNG, 2×2 redaction at (1,1), assert opaque-black pixels at (1,1)..(2,2) + original elsewhere
- [ ] 4.1.4 `grep -rn 'from.*screenshot-redact\|require.*screenshot-redact' apps/web-platform/app/ apps/web-platform/lib/ apps/web-platform/server/` returns 0 (helper must not leak into runtime paths)

### 4.2 Commit
- [ ] 4.2.1 `git add apps/web-platform/e2e/helpers/screenshot-redact.ts apps/web-platform/test/screenshot-redact.test.ts` (+ `package.json` + `bun.lock` if sharp added)
- [ ] 4.2.2 Commit: `feat(e2e-helpers): screenshot redaction helper for Stage 6 visual-QA (#2939)`

## Phase 5 — Visual-QA rubric

### 5.1 GREEN — `visual-qa-rubric.md`
- [ ] 5.1.1 Create `knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/visual-qa-rubric.md` with the YAML frontmatter + body sections per plan §5.1.1 (FR5.1-FR5.6)
- [ ] 5.1.2 `grep -rn "test@e2e.com\|test-user-id" knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/visual-qa-rubric.md` returns 0 (no test-user identifiers leak into the rubric doc itself)

### 5.2 Operator capture (POST-merge work, run by operator at QA time)
- [ ] 5.2.1 Capture 8 redacted screenshots (4 bubbles × 2 themes) to `$(pwd)/tmp/screenshots/` per rubric step 1
- [ ] 5.2.2 Run redaction helper on each
- [ ] 5.2.3 Paste redacted PNGs into PR-C body (GitHub user-attachment textbox, NOT git-add)

### 5.3 Commit
- [ ] 5.3.1 `git add knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/visual-qa-rubric.md`
- [ ] 5.3.2 Commit: `docs(spec): Stage 6 one-time visual-QA rubric for cc-soleur-go (#2939)`

## Phase 6 — Integration verification + guard greps + PR body

### 6.1 Run tests
- [ ] 6.1.1 `cd apps/web-platform && bun playwright test --project=authenticated cc-soleur-go-security.e2e.ts` → all 4 FR3.x test groups green
- [ ] 6.1.2 `cd apps/web-platform && bun playwright test --project=authenticated cc-soleur-go-bubbles.e2e.ts cc-soleur-go-routing.e2e.ts` → no regression from Phase 1 chat-surface edit
- [ ] 6.1.3 `bun tsc --noEmit` from `apps/web-platform/` → green
- [ ] 6.1.4 `bun run vitest apps/web-platform/test/screenshot-redact.test.ts` → green

### 6.2 Guard greps
- [ ] 6.2.1 `grep -n "mcp__soleur_platform__plausible_" apps/web-platform/e2e/cc-soleur-go-security.e2e.ts` returns 0 (TR9 / NG4)
- [ ] 6.2.2 `grep -n "ANTHROPIC_API_KEY\|claude-agent-sdk\|@anthropic-ai/" apps/web-platform/e2e/cc-soleur-go-security.e2e.ts` returns 0 (NG2)
- [ ] 6.2.3 `grep -n "toHaveScreenshot" apps/web-platform/e2e/cc-soleur-go-security.e2e.ts` returns 0 (NG1)
- [ ] 6.2.4 `grep -n "test_synthesized_exfil\|test_synthesized_smoke" apps/web-platform/server/tool-tiers.ts` returns 0
- [ ] 6.2.5 `grep -rn "test@e2e.com\|test-user-id" knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/` returns 0
- [ ] 6.2.6 `grep -rn 'STAGE6_CANARY_DO_NOT_EXFILTRATE\|STAGE6_FR33_USER_A_ONLY' apps/web-platform/ --include="*.ts" --include="*.tsx"` returns only matches inside `e2e/cc-soleur-go-security.e2e.ts`

### 6.3 PR body
- [ ] 6.3.1 `gh pr edit 3779 --body-file <file>` with content per plan §6.3.1 (Closes #2939; Refs #3743 #3778; honest-framing notes)
- [ ] 6.3.2 Apply labels: `semver:patch`, `domain/engineering`, `type/chore`

## Phase 7 — Scope-out filing (during /work, BEFORE bug-class assertions)

Per plan-author bug-handling policy: file scope-out issues BEFORE writing
the assertion that fails the bug, NOT after.

### 7.1 §DS1 — bootChat extraction
- [ ] 7.1.1 `gh issue create --title "[stage-6-smoke / cleanup] Extract bootChat into e2e/helpers/cc-soleur-go-boot.ts" --label "domain/engineering,type/chore,priority/p3-low" --body "Three e2e specs each carry near-identical bootChat (bubbles, routing, security). ~60-LoC extraction. Cleanup-only."`

### 7.2 §DS2-DS5 — Real-bug filings (CONDITIONAL on Phase 3 surfacing bugs)
- [ ] 7.2.1 IF FR3.1 prompt-injection drain assertion fails on a real bug: `gh issue create --title "[stage-6-smoke / prompt-injection-drain] <symptom>" --label "type/security,domain/engineering,priority/<tier>"` and record the issue number in PR body "Deferred bugs found"
- [ ] 7.2.2 IF FR3.2 bash review-gate fails on a real bug: `gh issue create --title "[stage-6-smoke / bash-review-gate] <symptom>" --label "type/security,domain/engineering,priority/<tier>"`
- [ ] 7.2.3 IF FR3.3 cross-user isolation fails on a real bug: `gh issue create --title "[stage-6-smoke / cross-user-isolation] <symptom>" --label "type/security,domain/engineering,priority/<tier>"`
- [ ] 7.2.4 IF FR3.4 rate-limit assertion fails on a real bug: `gh issue create --title "[stage-6-smoke / rate-limit-window] <symptom>" --label "type/security,domain/engineering,priority/<tier>"`

## Phase 8 — Ship + merge

- [ ] 8.1 Run `skill: soleur:compound` — capture any session learnings
- [ ] 8.2 Run `skill: soleur:ship` — PR title prefix: `feat(cc-soleur-go): Stage 6 PR-C — security smoke (FR3.1-3.4) + visual-QA rubric (#2939)`
- [ ] 8.3 Verify PR body has `Closes #2939` (auto-closes umbrella on merge)

## Phase 9 — Post-merge (operator + automation)

- [ ] 9.1 Verify auto-close: `gh issue view 2939 --json state` → `CLOSED`
- [ ] 9.2 `gh issue edit 2939 --body-file <reconciliation-block>` appending the 3-PR landed reconciliation per plan §7.1.1
- [ ] 9.3 Verify each scope-out issue from §7.2 (if any filed) shows `state: "OPEN"` and the correct title prefix
- [ ] 9.4 If #3722 is the next dependent: leave a comment on #3722 referencing the closed #2939 to unblock its Stage 6 dependency
