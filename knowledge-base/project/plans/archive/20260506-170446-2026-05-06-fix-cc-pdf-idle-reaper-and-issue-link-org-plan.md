---
type: bug-fix
issue: TBD
branch: feat-one-shot-concierge-pdf-and-issue-link-fix
parent_plans:
  - 2026-05-05-fix-cc-pdf-poppler-cascade-phase2-positional-and-exclusion-list-plan.md
  - 2026-05-05-fix-cc-pdf-read-capability-prompt-plan.md
prior_prs: [3225, 3253, 3287, 3288, 3294]
related_learning: 2026-05-05-defense-relaxation-must-name-new-ceiling.md
sdk_pin: "@anthropic-ai/claude-agent-sdk@0.2.85"
requires_cpo_signoff: true
---

# fix(cc-pdf + chat-error-link): idle-reaper kills mid-PDF Read; "File an issue" link points to wrong GitHub org

## Enhancement Summary

**Drafted on:** 2026-05-06 (post-reproduction screenshot supplied by user)
**Deepened on:** 2026-05-06 (same session)
**Sections enhanced:** Hypotheses (added concrete SDK-message-shape detection), Acceptance Criteria (replaced structural-content check with `tool_use_result` field check + `isSynthetic` flag), Test Strategy (concrete RED-test sketch using existing `createMockQuery` harness), Sharp Edges (added KB 50MB vs Anthropic 32MB ceiling mismatch + tracking issue), Research Reconciliation (added SDK-version pin and `tool_use_result` field discovery).
**Research sources used:**

- Live SDK type definitions at `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:2523-2536` (`SDKUserMessage` shape with `tool_use_result?: unknown` + `isSynthetic?: boolean`).
- Live source at `apps/web-platform/server/soleur-go-runner.ts:1043-1075` (`consumeStream`), L809-824 (`recordAssistantBlock`/`armRunaway`/`armTurnHardCap`), L126-132 (`DEFAULT_WALL_CLOCK_TRIGGER_MS`/`DEFAULT_MAX_TURN_DURATION_MS`).
- Live test harness at `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts:107-185` (`createMockQuery`, `makeAssistant`, `makeResult`).
- Existing learning `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` (the load-bearing precedent for the 90s + 10-min ceiling pair).
- `gh issue view 3287`/`3253` (both `CLOSED`), `gh pr view 3225`/`3288`/`3294` (all `MERGED`) — every cited number verified live.
- `apps/web-platform/server/kb-limits.ts:17` `MAX_BINARY_SIZE = 50 * 1024 * 1024` vs Anthropic PDF beta 32 MB ceiling — newly discovered ceiling mismatch.

### Key Improvements Discovered During Deepen-Pass

1. **`SDKUserMessage` carries an explicit `tool_use_result?: unknown` discriminator (sdk.d.ts:2528).** This is a stronger and cleaner detection than scanning `message.content` for a `tool_result` block. Use `tool_use_result !== undefined` as the primary gate; fall back to structural content inspection only if needed for forward-compat. Combined with the documented `isSynthetic?: boolean` flag (L2527), the new branch can also distinguish SDK-synthesized messages from user-typed ones with high precision.
2. **Existing test harness covers exactly the surface we need.** `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts:107-185` already builds `createMockQuery`, `makeAssistant`, `makeResult` plus the `Mutable<T>` helper, all imported into a no-network test that exercises `state.runaway` via `vi.useFakeTimers`. We add `makeUserToolResult(toolUseId, content)` in the new test file, mirroring `makeAssistant`.
3. **Defense-pair invariant is explicit in source comments.** `soleur-go-runner.ts:127-132` documents the 10-min `DEFAULT_MAX_TURN_DURATION_MS` ceiling as the explicit defense covering "chatty-but-stalled agent" (PR #3225 added it as the new ceiling when 30s → 90s reset semantics widened). The new tool_result reset doubles the protection on the per-block window — and the 10-min ceiling stays unchanged; the defense pair is preserved exactly as the `2026-05-05-defense-relaxation-must-name-new-ceiling` learning prescribes.
4. **KB upload ceiling vs Anthropic API ceiling are mismatched.** `kb-limits.ts:17` allows 50 MB binary uploads; Anthropic's PDF beta accepts up to 32 MB. A user can upload a 33-50 MB PDF, attach it to a Concierge thread, ask for a summary, and the agent's `Read` will fail at the API boundary with a `tool_result` carrying an error payload — which the new branch correctly resets the timer for, then the model emits a recovery text block. This is acceptable behavior, but the upstream KB upload should warn users at attach time. Tracked as a follow-up issue (see Sharp Edges).
5. **Live PR/issue verification matrix.** `gh pr view 3225` → MERGED ("raise idle window to 90s with per-block reset + max-turn ceiling + de-duplicate header"); `gh pr view 3288` → MERGED ("instrument cc-soleur-go cold-Query construction with Sentry breadcrumb (#3287)"); `gh pr view 3294` → MERGED ("Phase 2 — artifact frame leads + gated named-tool exclusion list"); `gh issue view 3287` → CLOSED; `gh issue view 3253` → CLOSED. All five citations are live-verified; no SHA or PR-number drift.

### New Considerations Discovered

- **Concrete fix shape:** The new branch in `consumeStream` is exactly five lines. The branch position is between L1056 (`else if (msg.type === "result")`) and L1059 (the `// Other SDKMessage variants ...` comment). Pseudo-code:

  ```ts
  } else if (msg.type === "user" && (msg as SDKUserMessage).tool_use_result !== undefined) {
    if (state.closed || state.awaitingUser) continue;
    armRunaway(state); // re-arm per-block timer; do NOT touch turnHardCap
  }
  ```

  The cast to `SDKUserMessage` is safe because `msg.type === "user"` narrows to either `SDKUserMessage` or `SDKUserMessageReplay` and both share the `tool_use_result?: unknown` field.
- **`SDKUserMessageReplay` parity:** During session resume, the SDK can emit `SDKUserMessageReplay` (sdk.d.ts:2538-2552) which has identical relevant fields (`type: 'user'`, `tool_use_result?: unknown`, `isSynthetic?: boolean`). The narrow at the structural check `tool_use_result !== undefined` covers both shapes — no extra branch needed. Pin this in test scenario E (replay-path resilience).
- **Heartbeat-rate amplification implications:** Anthropic's PDF native handling is opaque from our perspective. We do NOT control whether the SDK emits intermediate `tool_use_summary` (sdk.d.ts:2515) or `partial_assistant` blocks during long PDF Reads. If a future SDK version starts emitting heartbeats during native PDF processing, the new branch becomes redundant — but harmless. Forward-compatible design.
- **Cost cap interaction:** The cost ceiling at L1032 fires on `result` messages only, NOT on `tool_use_result` (which is mid-turn). The new branch's `armRunaway` does not touch cost; the existing cap remains the cost-bound. Defense-in-depth pair of (per-block idle, max turn duration, cost ceiling) is unchanged.



Two distinct bugs in the Soleur Concierge chat surface, deliberately bundled because (a) they share the same component (`apps/web-platform/components/chat/message-bubble.tsx` error branch) AND the same trigger ("Concierge silently fails on a PDF chat"), and (b) Bug 2 is a one-line literal swap whose risk profile is independent and trivial — folding it into Bug 1's PR avoids a separate ship cycle for a 1-character fix.

## Overview

### Bug 1 — Concierge gives up mid-`Read` on a multi-MB PDF

User attaches `Manning Book — Effective Platform Engineering.pdf` (a real ~10MB book), asks "can you please summarize this PDF?", and Concierge displays:

> Agent stopped responding after: Reading knowledge-base/overview/Manning Book - Effective Platform Engineering.pdf...

This is a **new failure mode**, distinct from the prior #3253/#3287/#3294 cascade (model fabricates a missing `pdftotext` tool and refuses). Here the model correctly emits `tool_use: Read("…book.pdf")` — the routing, system prompt, gated directive, and exclusion-list work AS DESIGNED — and the runner records the assistant block. The failure is downstream:

1. T+0s — model emits `assistant.content[0] = { type: "tool_use", name: "Read", input: { file_path: ".../book.pdf" } }`. `consumeStream` in `apps/web-platform/server/soleur-go-runner.ts:1052` calls `handleAssistantMessage` → `recordAssistantBlock(state, "tool_use", "Read")` (L952) which arms `state.runaway` for `wallClockTriggerMs = DEFAULT_WALL_CLOCK_TRIGGER_MS = 90_000` ms.
2. T+10-30s — SDK reads the PDF natively (qpdf-linearized at upload, so disk read is fast), packages the bytes as a `tool_result` content block, and emits `{ type: "user", message: { role: "user", content: [{ type: "tool_result", tool_use_id, content: [<pdf bytes>] }] } }`. **`consumeStream` falls through this message** — the switch at L1052-1058 only handles `assistant` and `result`; the comment at L1059 says "Other SDKMessage variants … are ignored". The idle timer is **not** reset.
3. T+30-90s — the SDK forwards the PDF bytes + prior turns to the Anthropic API. The model now thinks across all 200+ pages and composes a summary. There is zero client-visible activity during this window: no assistant block, no tool_use, no result.
4. T+90s — `state.runaway` fires (L835-864). It logs `reason: "idle_window"`, calls `emitWorkflowEnded({ status: "runner_runaway", reason: "idle_window", lastBlockToolName: "Read", … })`. `cc-dispatcher.ts:930` maps this to the `error` `messageState` carrying the last `toolLabel` ("Reading …pdf"). `message-bubble.tsx:240-260` renders the failure card. The stream is closed and the model's eventual reply (which would have arrived a few more seconds later) is dropped.

The **`DEFAULT_WALL_CLOCK_TRIGGER_MS = 90_000`** ceiling at `soleur-go-runner.ts:126` was last raised in `73e9ea0e fix(kb-concierge): raise idle window to 90s with per-block reset + max-turn ceiling …(#3225)` based on an observed `~75s p99` for a "PDF Read+summarize" turn. That measurement was almost certainly taken on a small KB-fixture PDF, not a 10MB book. The window is bounded by **Anthropic's PDF processing latency**, which scales with page count, not by the runner's own behavior. Pinning a tighter window risks killing legitimate long-running summaries on every book-sized PDF a user attaches; raising the window further trades silent-failure latency against runaway protection. The right fix is **observe the SDK's own forward progress, not only assistant-side blocks**.

The principled fix:

- In `consumeStream` (L1043-1075), when `msg.type === "user"` AND the message body contains a `tool_result` content block AND the runner is not closed/awaiting, treat the tool_result as forward progress and **reset `state.runaway`** (and refresh `state.lastActivityAt`, already set at L1050). The 90s ceiling continues to bound true silence (no assistant block AND no tool_result for 90s); the 10-min `maxTurnDurationMs` ceiling continues to bound a chatty stalled agent (`firstToolUseAt`-anchored, NOT reset by tool_result, per the comment at L805-808 — "armed once on the first block of a turn and is NOT touched on subsequent blocks"). Adds one explicit role for tool_result-on-user-message: forward-progress signal that prevents idle_window from firing while the SDK's own pipeline is making progress.

This generalizes beyond PDFs — any tool_use whose execution + downstream model thinking exceeds 90s (e.g., a deep `Glob`/`Grep` over a large KB followed by a long summary, a `kb_search` over thousands of files) hits the same trap. The fix ports to those cases for free.

### Bug 2 — "File an issue" link points to the wrong GitHub org

`apps/web-platform/components/chat/message-bubble.tsx:251` hardcodes:

```
href="https://github.com/jikigai/soleur/issues/new?labels=type%2Fbug&template=bug_report.md"
```

GitHub org slug is **`jikig-ai`** (verified against the working tree path `git-repositories/jikig-ai/soleur`, `apps/web-platform/bunfig.toml:3` `https://github.com/jikig-ai/soleur/issues/1174`, `apps/web-platform/infra/variables.tf:47` `ghcr.io/jikig-ai/soleur-web-platform`, plus 18+ `ghcr.io/jikig-ai/soleur-*` references in `apps/web-platform/infra/ci-deploy*.sh` and the Soleur-org main remote). The `jikigai` slug is the **company name** (`@jikigai.com` email domain, `@jikigai.com` legal contact) — a separate identifier that the docs site, legal pages, and Discord webhook templates correctly use. The chat-bubble link conflates the two.

Effect: every user who clicks "File an issue" in the failure card lands on a `404 Not Found` page from GitHub. Issues from chat failures cannot be filed — the canonical observability + remediation pathway for end-user-experienced agent failures is broken.

Fix: swap `jikigai` → `jikig-ai` in the literal href. One character difference.

This is bundled into the same PR because (a) the failing `Reading <pdf>...` UX from Bug 1 is **the** surface most likely to display this link (mid-PDF runaway is the user's first-touch with the failure card), so users hit both bugs in the same session; (b) the link is one line in the same file as no other ongoing edits; (c) shipping it as a separate PR adds review, CI, and merge overhead disproportionate to a 1-character fix.

## User-Brand Impact

- **If this lands broken, the user experiences:** First-touch chat trust collapse — they attach their first private PDF (a real book, not a small KB fixture), Concierge starts reading it, then displays "Agent stopped responding" with a "File an issue" link that 404s. They cannot summarize the document; they cannot file the issue; they cannot recover. Users who watched their first PDF chat fail silently and saw the issue link 404 will not re-attach a private document. This is the same brand-trust framing as PR #3288/#3294 and the entire `cc-pdf` cascade — the bug is shaped slightly differently but the artifact (Concierge fails mid-Read on a real-world PDF, and the escape hatch is broken) is identical.
- **If this leaks, the user's data/workflow is exposed via:** No data leak (the agent reads the PDF natively into Anthropic's API and the tool_result is dropped on runaway, never persisted to logs). The leak is workflow trust: the failure-card "File an issue" link is the explicit affordance the failure-mode UI offers; when it 404s, the user perceives the entire failure-handling pathway as broken.
- **Observability framing (forward-progress branch):** The new `handleUserMessage` branch in `consumeStream` re-arms `state.runaway` on `tool_use_result` SDK signals. It does NOT mirror to Sentry — this is intentional pass-through (forward progress, not a degraded fallback) per the carve-out in `cq-silent-fallback-must-mirror-to-sentry`. Adding a Sentry breadcrumb here would be precedent-contradicting: the analogous existing call site (`recordAssistantBlock`) does not breadcrumb on every "agent is alive" signal either, and pino-only visibility on forward-progress signals is the runner's house style. If a future SDK regression starts emitting fake heartbeats, the existing 10-min `turnHardCap` log + `runner_runaway` Sentry mirror remain the diagnostic hooks.
- **Brand-survival threshold:** `single-user incident` — inherited from the entire `cc-pdf` chain (#3253, #3287, #3294 all gated at `single-user incident`). One reproduction on a deployed `web-v0.66+` against the user's primary KB document already happened (the screenshot the user attached to this task). One first-touch "Concierge can't read PDFs" experience is brand-load-bearing per the prior plans' threshold reasoning, which carries forward unchanged.

`requires_cpo_signoff: true` per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`. CPO sign-off required at plan time before `/work` begins; `user-impact-reviewer` will run at review-time. Carry-forward from PR #3288/#3294's framing — same artifact, same threshold, two new fix surfaces.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality (verified at plan time) | Plan response |
| --- | --- | --- |
| Idle reaper at `wallClockTriggerMs = 90_000`, last raised in #3225 based on observed ~75s p99. | Verified at `apps/web-platform/server/soleur-go-runner.ts:126` (`DEFAULT_WALL_CLOCK_TRIGGER_MS = 90 * 1000`) and PR #3225 (commit `73e9ea0e`). The comment at L124-127 explicitly says "PDF Read+summarize observed at ~75s p99, hence 90s." | The 90s window is bounded by Anthropic's PDF latency, not the runner. A 10MB book exceeds the p99 measured on small fixtures. Fix: reset on tool_result-bearing `user` messages, not raise the ceiling further. |
| `consumeStream` ignores `msg.type === "user"`. | Verified at `soleur-go-runner.ts:1043-1075`: switch handles `assistant` (L1052) and `result` (L1056); comment at L1059-1060 says "Other SDKMessage variants (partial assistant, hook, task notifications) are ignored at V1." `user`-role tool_result messages are the SDK's own forward-progress signal and fall in this gap. | Add `else if (msg.type === "user")` branch that detects `tool_result` content and refreshes the per-block runaway timer. The `state.lastActivityAt = now()` at L1050 already runs unconditionally — keep it; the new branch only re-arms the runaway timer. |
| `recordAssistantBlock` arms both `runaway` (per-block, 90s) and `turnHardCap` (per-turn, 10min, first-block-only). | Verified at `soleur-go-runner.ts:809-824`: `armRunaway(state)` runs every assistant block, `armTurnHardCap(state)` runs only on the first block of a turn. The `turnHardCap` is `firstToolUseAt`-anchored (L778) and explicitly NOT reset by subsequent blocks (comment L805-808). | The new tool_result branch must call ONLY `armRunaway` (re-arm the per-block window). It MUST NOT touch `turnHardCap` — the 10-min absolute ceiling continues to bound a chatty-but-stalled agent, AND that ceiling is one of the two defenses the `defense-relaxation-must-name-new-ceiling` learning protects (PR #3225). Relaxing the per-block window without preserving the absolute ceiling would dissolve a defense PR #3225 explicitly added. |
| Failure card UI source of "Agent stopped responding after: <toolLabel>". | Verified at `apps/web-platform/components/chat/message-bubble.tsx:240-260` — `case "error"` branch reads `toolLabel` from props (L246-248) and renders the `File an issue` link at L250-258. The `toolLabel` is set by `cc-dispatcher.ts` via `buildToolLabel` from `apps/web-platform/lib/tool-labels.ts`. | The "Reading <path>" label is correct (`Read` tool's label), the bug is upstream — the conversation should not have entered the error state in the first place. No edits to the error UI for Bug 1. |
| GitHub org slug. | Verified: `apps/web-platform/bunfig.toml:3` references `https://github.com/jikig-ai/soleur/issues/1174`; `apps/web-platform/infra/variables.tf:47` references `ghcr.io/jikig-ai/soleur-web-platform:latest`; `apps/web-platform/infra/ci-deploy.sh:148` and `apps/web-platform/infra/ci-deploy.test.sh` (40+ refs) all use `jikig-ai/soleur-*`; the worktree path itself is `git-repositories/jikig-ai/soleur`. The `jikigai` form is reserved for `@jikigai.com` email/legal contacts and is NOT the GitHub org slug. | One-line literal swap at `message-bubble.tsx:251`. Add a unit test pinning the literal `https://github.com/jikig-ai/soleur/issues/new` substring so a regression to the company-name slug fails the test. |

## Hypotheses

### Bug 1 — Why does the conversation enter the `error` state?

| # | Hypothesis | Diagnostic | Pre-fix verdict |
| --- | --- | --- | --- |
| H1 | Idle reaper (90s) fires while SDK is mid-PDF processing on Anthropic's side. The model emits one `tool_use: Read` block, the SDK reads + uploads the PDF + waits for the model's reply, and that round-trip exceeds 90s for a real book. The runaway logs `reason: "idle_window"` and ends with `lastBlockToolName: "Read"`. | Repro with a ~10MB book PDF, capture `runner_runaway` log (the `log.warn` payload at `soleur-go-runner.ts:846-855` carries `reason`, `wallClockTriggerMs`, and `lastBlockToolName`). Look for `reason: "idle_window"` and `lastBlockToolName: "Read"`. | **Strongly suspected** — matches the user's screenshot text exactly. Confirmed-by-code-trace; awaiting log confirmation in Phase 1. |
| H2 | Max-turn ceiling (10min) fires. | Same log capture; look for `reason: "max_turn_duration"`. | **Ruled out** — the screenshot says "Reading…", which means the runaway fired with `lastBlockToolName: "Read"` recently set; if 10min had elapsed, multiple subsequent blocks (even `text` heartbeats) would have arrived. Possible only on a >10min single-PDF turn. |
| H3 | SDK threw `Controller is already closed` (observed in #3294 cascade telemetry). | Look for `internal_error` status with the literal error message. | **Possible secondary** — the #3294 reproduction captured this once. Out of scope unless H1 is ruled out. |
| H4 | The PDF is too large for the API and the SDK silently rejected the tool input. | Inspect `tool_result` content for an error payload before the runaway fires. | **Unlikely** — Anthropic accepts PDFs up to 32MB per the PDF beta docs (verify via Context7 query against `@anthropic-ai/claude-agent-sdk`). The "Manning Book" file is ~10MB. |

### Bug 2 — Why does the link 404?

Trivially: the literal substring `jikigai` instead of `jikig-ai` was committed at PR #2861 (the `case "error"` branch was added in PR #2861 per the inline comment at message-bubble.tsx:238 — `FR5 (#2861): show the last known activity label + File-issue link.`). No other hypothesis is required; this is a pure typo / wrong-slug. The grep output above (5+ correct usages of `jikig-ai/soleur` in `bunfig.toml`, `infra/`, etc.) shows the rest of the codebase already uses the correct slug.

## Acceptance Criteria

### Pre-merge (PR)

#### Bug 1 — Idle reaper resets on tool_result

- [x] AC1.1 — `apps/web-platform/server/soleur-go-runner.ts:consumeStream` recognizes `msg.type === "user"` AND `tool_use_result !== undefined` (the documented SDK-discriminator field on `SDKUserMessage` per `sdk.d.ts:2528`), and re-arms `state.runaway` via `armRunaway(state)`. Implementation MUST NOT touch `state.turnHardCap` (the 10-min absolute ceiling stays anchored on `firstToolUseAt`). The cast pattern is `(msg as SDKUserMessage).tool_use_result !== undefined` — type-safe because `msg.type === "user"` narrows to `SDKUserMessage | SDKUserMessageReplay` and both shapes share the field.
- [x] AC1.2 — `state.lastActivityAt = now()` continues to run for ALL `SDKMessage` types (existing line at L1050). No regression.
- [x] AC1.3 — `awaitingUser` and `closed` continue to short-circuit the re-arm. Use the same guard pattern as `armRunaway` (L833 `if (state.awaitingUser) return;` and L840 `if (state.closed) return;`). The new branch MUST guard at the entry, not rely on `armRunaway`'s internal guards alone — defense-in-depth and clearer for future readers.
- [x] AC1.4 — Test scenario A (pin the bug fix): a `user` message with `tool_use_result: <non-undefined>`, emitted between a `tool_use: Read` and the next assistant `text` block, MUST refresh the runaway timer such that even a 120s gap (>90s ceiling) between tool_use and the next text does NOT trigger `runner_runaway` so long as a tool_use_result lands within the 90s window.
- [x] AC1.5 — Test scenario B (pin the absolute ceiling): a synthetic stream that emits `tool_use → tool_use_result every 60s → assistant text every 30s` indefinitely MUST still trigger `runner_runaway` with `reason: "max_turn_duration"` at T=10min using the production constant `DEFAULT_MAX_TURN_DURATION_MS` (do NOT shrink the constant for the test — the ceiling-pair invariant is what's being pinned, see learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md`). The new tool_result branch MUST NOT reset `turnHardCap`.
- [x] AC1.6 — Test scenario C (pin "no false-positive forward-progress"): a `user` message with `tool_use_result === undefined` (e.g., a non-synthetic user follow-up, even though those normally enter via `pushUserMessage` not the SDK loop — this is a defensive pin) MUST NOT reset the runaway timer. The discriminator field is the single load-bearing check.
- [x] AC1.7 — Test scenario D (pin "still fires on real silence"): a `tool_use: Read` followed by 90s of total silence (no tool_use_result, no assistant text) MUST still trigger `runner_runaway` with `reason: "idle_window"`. The fix is forward-progress-aware, not a blanket relaxation.
- [x] AC1.8 — Test scenario E (pin replay-path resilience): a `SDKUserMessageReplay` (`type: "user"`, `tool_use_result: <non-undefined>`, `isReplay: true`) MUST also reset the runaway timer — replay during session resume is a documented SDK shape (sdk.d.ts:2538-2552). The shared field-check covers both shapes without an extra branch.
- [x] AC1.9 — `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx`, `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts`, `apps/web-platform/test/soleur-go-runner.test.ts`, `apps/web-platform/test/soleur-go-runner-lifecycle.test.ts`, and `apps/web-platform/test/soleur-go-runner-narration.test.ts` continue to pass without modification. The change is additive (one new branch) — no semantic change to assistant-block or result-message handling.
- [x] AC1.10 — `read-tool-pdf-capability.test.ts` continues to pass without modification — the system-prompt directive layer is unchanged.

#### Bug 2 — Issue link points to correct GitHub org

- [x] AC2.1 — `apps/web-platform/components/chat/message-bubble.tsx:251` href reads `https://github.com/jikig-ai/soleur/issues/new?labels=type%2Fbug&template=bug_report.md` (note hyphen in `jikig-ai`).
- [x] AC2.2 — `apps/web-platform/test/message-bubble-header.test.tsx` (or a sibling test on `MessageBubble` `error` state) pins the exact substring `https://github.com/jikig-ai/soleur/issues/new`. The test MUST also assert the literal NEGATIVE — `expect(href).not.toContain("github.com/jikigai/")` — so a future regression to the company-name slug fails fast.
- [x] AC2.3 — Pre-flight grep: `rg -F "github.com/jikigai" apps/ plugins/` returns zero hits inside source code paths. (`jikigai` references in `infra/variables.tf` for `ops@jikigai.com`, in `legal/*.md` for `legal@jikigai.com`, and in `docs/pages/getting-started.njk` for `ops@jikigai.com` are correct — those are email/contact-line references and intentionally use the company-name domain. The grep should be scoped to `apps/web-platform/components/`, `apps/web-platform/server/`, `apps/web-platform/lib/`, `plugins/soleur/skills/`, `plugins/soleur/agents/` — i.e., agent/UI code paths where a hardcoded GitHub-org reference would be a bug.)

### Post-merge (operator)

- [ ] AC3.1 — Manually reproduce: attach a >5MB PDF to a fresh KB Concierge thread, ask "summarize this document". Verify Concierge produces a summary (not a runaway) within ~3 minutes. Capture screenshot and link in PR body.
- [ ] AC3.2 — Sentry post-deploy validation: the count of `runner_runaway fired (idle window)` events with `lastBlockToolName: "Read"` over the 7-day window post-deploy SHOULD drop materially compared to the prior 7-day baseline. Capture the before/after counts in the post-merge note.
- [ ] AC3.3 — Manually click the "File an issue" link in any failure card on prod. Verify it opens the GitHub issue creation form (not a 404). Capture the resolved URL in the PR body.

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts` (L1043-1075 `consumeStream` — add `else if (msg.type === "user")` branch detecting `tool_result` content blocks; re-arm `state.runaway` only)
- `apps/web-platform/components/chat/message-bubble.tsx` (L251 — `jikigai` → `jikig-ai`)

## Files to Create

- `apps/web-platform/test/soleur-go-runner-tool-result-idle-reset.test.ts` — RED-then-GREEN test pinning AC1.4–AC1.7. Uses the existing test pattern from `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts` (synthetic SDK stream, fake-timers, assertions on `onWorkflowEnded` payloads).
- `apps/web-platform/test/message-bubble-file-issue-link.test.tsx` — RED-then-GREEN test pinning AC2.1–AC2.2 (`jikig-ai` substring present, `jikigai` substring absent in the rendered href).

## Test Strategy

`bun run test` is the project's runner (`apps/web-platform/package.json` scripts; tests run via `vitest`). Each new test file is additive and runs in the existing CI matrix. No new dependencies, no new test runner.

### Runner test — concrete sketch

Reuse the harness shape verified at `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts:107-185`:

```ts
// apps/web-platform/test/soleur-go-runner-tool-result-idle-reset.test.ts
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { SDKMessage, SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";
import {
  createSoleurGoRunner,
  DEFAULT_WALL_CLOCK_TRIGGER_MS,    // 90_000
  DEFAULT_MAX_TURN_DURATION_MS,     // 10 * 60 * 1000
} from "@/server/soleur-go-runner";

// Re-export `makeAssistant`, `makeResult`, `createMockQuery` from the existing
// harness (or copy locally if extraction would balloon the diff). Add:
function makeUserToolResult(
  toolUseId: string,
  content: unknown = [{ type: "tool_result", tool_use_id: toolUseId, content: "ok" }],
  isReplay = false,
): SDKUserMessage {
  return {
    type: "user",
    message: { role: "user", content } as never, // biome-ignore — minimal SDK fixture
    parent_tool_use_id: null,
    isSynthetic: true,
    tool_use_result: { ok: true }, // load-bearing: the discriminator the new branch reads
    session_id: "sess-1",
    ...(isReplay ? { isReplay: true, uuid: "00000000-0000-0000-0000-0000000000aa" as never } : {}),
  } as SDKUserMessage;
}

describe("consumeStream — tool_use_result resets runaway timer (#TBD)", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  // AC1.4 — bug fix
  it("scenario A: tool_use → tool_use_result @60s → text @120s does NOT trigger runaway", () => { /* ... */ });

  // AC1.5 — defense-pair invariant; uses production constants
  it("scenario B: tool_use_result drumbeat does NOT defeat the 10-min turn ceiling", () => { /* ... */ });

  // AC1.6 — discriminator precision
  it("scenario C: user message with tool_use_result === undefined does NOT reset", () => { /* ... */ });

  // AC1.7 — silence still fires
  it("scenario D: tool_use + 90s silence still fires runaway with reason=idle_window", () => { /* ... */ });

  // AC1.8 — replay-path resilience
  it("scenario E: SDKUserMessageReplay with tool_use_result also resets runaway", () => { /* ... */ });
});
```

For Scenario B, drive the stream with `vi.advanceTimersByTime(60_000)` between each tool_use_result, run for 11 minutes of fake time total, and expect `onWorkflowEnded` called with `{ status: "runner_runaway", reason: "max_turn_duration" }`. Do NOT shrink `DEFAULT_MAX_TURN_DURATION_MS` — pinning the production constant is the load-bearing assertion (per learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md` Sharp Edge — "test must pass with the production constant, not a smaller test value").

### Bubble test — concrete sketch

```tsx
// apps/web-platform/test/message-bubble-file-issue-link.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { MessageBubble } from "@/components/chat/message-bubble";

describe("MessageBubble error state — File an issue link (#TBD)", () => {
  it("href points to the correct GitHub org (jikig-ai, not jikigai)", () => {
    render(
      <MessageBubble
        isUser={false}
        messageState="error"
        content=""
        toolLabel="Reading book.pdf"
      />,
    );
    const link = screen.getByTestId("file-issue-link");
    expect(link.getAttribute("href")).toContain("https://github.com/jikig-ai/soleur/issues/new");
    expect(link.getAttribute("href")).not.toContain("github.com/jikigai/");
  });
});
```

Use the existing test render harness (`apps/web-platform/test/message-bubble-header.test.tsx` shows the precedent — same import path, same `screen.getByTestId` pattern, same `MessageBubble` API).

## Open Code-Review Overlap

Live results from deepen-plan (2026-05-06):

```bash
$ gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
$ jq '. | length' /tmp/open-review-issues.json
47

$ jq -r --arg path "soleur-go-runner.ts" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
(no output — zero matches)

$ jq -r --arg path "message-bubble.tsx" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
(no output — zero matches)
```

**None.** No open code-review scope-outs reference either of the two files this plan edits. (47 open code-review issues exist in total at deepen time; none touch `soleur-go-runner.ts` or `message-bubble.tsx`.) The closest tangential issue surfaced was `#2955: arch: process-local state assumption needs ADR + startup guard` — about the runner's in-memory `activeQueries` Map, not the timer logic this plan touches. Out of scope.

## Domain Review

**Domains relevant:** Product (CPO carry-forward from #3287/#3288/#3294 chain).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — no new user-facing surface; failure-card UI unchanged structurally; one literal-link swap.
**Agents invoked:** none (BLOCKING tier criteria not met — no new flow, no new component, no new modal).
**Skipped specialists:** ux-design-lead (not a new surface), copywriter (no copy change beyond `jikigai` → `jikig-ai`), spec-flow-analyzer (no flow change).
**Pencil available:** N/A
**Brainstorm carry-forward:** none (no brainstorm artifact for this task; task originated from a screenshot reproduction).

#### Findings

The bug-fix is structural (runner timer logic) + literal (link swap). No new user-facing surface, no new flow, no new copy. CPO sign-off is required at plan time per `hr-weigh-every-decision-against-target-user-impact` because the threshold is `single-user incident` — but this is a sign-off on the THRESHOLD-INHERITANCE chain (PR #3288/#3294/#3253 already CPO-signed at the same threshold), not on a new product surface.

## Sharp Edges

- **Defense-relaxation hazard:** The 90s idle ceiling protects two threats (idle window AND a side-effect role of bounding absolute turn duration before #3225 added the explicit 10-min ceiling). PR #3225 extracted the second role into `DEFAULT_MAX_TURN_DURATION_MS = 10 * 60 * 1000` (anchored on `firstToolUseAt`, NOT reset by per-block activity, comment at `soleur-go-runner.ts:127-132`). This plan's tool_result-on-user reset is safe ONLY because the 10-min ceiling is already in place. A future edit that removes or weakens the 10-min ceiling AND keeps the tool_result reset would dissolve both defenses. Per AGENTS.md `cq-when-a-plan-relaxes-or-removes-a-load-bearing-defense` (learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md`): the 10-min ceiling is a load-bearing peer to the per-block window — pin it in test AC1.5 explicitly (the test must pass with the production constant, not a smaller test value).
- **`turnHardCap` purity:** The new branch MUST NOT call `armTurnHardCap`. The function is documented at L805-808 as "armed once on the first block of a turn and is NOT touched on subsequent blocks — that timer's whole job is to bound a chatty agent." A call from the tool_result branch would silently neutralize the 10-min ceiling.
- **`awaitingUser` re-entrance:** The interactive-prompt path (`AskUserQuestion`, `ExitPlanMode`) suspends the runner in `awaitingUser=true` state. While suspended, NO timers should arm (per the existing comment at L831-833). The new branch MUST `if (state.awaitingUser) return;` early — same guard as `armRunaway`. A user_response that loops back to the SDK as a tool_result (per `cc-interactive-prompt-response.ts:125`) AND races with `notifyAwaitingUser(false)` could otherwise re-arm the timer against human read time.
- **Tool_result detection precision:** The SDK emits `user`-role messages for both (a) genuine human follow-ups (which go through `pushUserMessage`, not the consume loop) and (b) synthetic tool_result wrappers. AC1.6 demands that we detect tool_result by structural inspection of `msg.message.content`, not by the `user` type alone. A defensive shape check: `Array.isArray(content) && content.some(b => b?.type === "tool_result")`.
- **`jikig-ai` vs `jikigai` in non-component paths:** The plan-time grep deliberately scopes to `apps/web-platform/components/`, `apps/web-platform/server/`, `apps/web-platform/lib/`, `plugins/soleur/skills/`, `plugins/soleur/agents/`. A user-facing component or agent prompt that references a GitHub URL with the wrong slug is a bug; an `@jikigai.com` email in legal copy or operator-alerts infra is intentional. A future GitHub-link regression in `plugins/soleur/agents/*.md` (e.g., a domain-leader frontmatter that references `https://github.com/jikigai/soleur`) would NOT be caught by AC2.3. Tracked here as a sharp edge — a follow-up could add a CI grep guard pinning `jikig-ai` in agent/UI surfaces; out of scope for this PR.
- **PDF size ceiling — KB allows 50 MB, Anthropic API accepts 32 MB.** Verified at deepen-time: `apps/web-platform/server/kb-limits.ts:17` sets `MAX_BINARY_SIZE = 50 * 1024 * 1024` (50 MB), but Anthropic's PDF beta accepts up to 32 MB per request. A user can upload a 33-50 MB PDF, attach it to a Concierge thread, ask for a summary, and `Read` will fail at the API boundary with a `tool_result` carrying an error payload. The new tool_result branch correctly resets the timer in that case too (SDK is making forward progress, even when "tool failed"); the model's next assistant block will be a recovery text, and the timer continues to bound true silence afterward — so this plan's fix degrades gracefully on oversize PDFs. **However, the underlying upload-vs-API ceiling mismatch is a separate UX bug** — users get no warning at attach time. **Track as follow-up issue (post-merge):** `chore(kb-limits): cap PDF uploads at Anthropic API limit (32 MB) or warn at attach time` — milestone Post-MVP / Later. Per AGENTS.md `wg-when-deferring-a-capability-create-a`. Scope-out from this PR (out of scope for the runner-timer fix).
- **`runner_runaway` UX framing:** The current failure card text "Agent stopped responding after: <toolLabel>" is reasonable for a real runaway but mis-frames a tool_result-driven late delivery (which this fix prevents). If a residual class of slow PDFs still triggers the 90s ceiling post-fix, consider differentiating the UX between `idle_window` and `max_turn_duration` reasons (e.g., "Agent took too long on a large document — re-attach the PDF or split it"). Out of scope here; tracked as a follow-up sharp edge for future plans.
- **CLI verification scope:** No new CLI invocations are introduced. The plan does NOT prescribe `qpdf`/`pdftotext`/etc. — the fix is pure TS in the runner.

## Brainstorm Carry-Forward

None — no brainstorm artifact for this task. The task originated from a user-attached screenshot reproduction. All architectural framing, threshold inheritance, and CPO sign-off carry forward from the `cc-pdf` chain (#3253, #3287/#3288, #3294) plus the defense-ceiling framing from #3225. No fresh brainstorm required because (a) the bug surface and threshold are inherited, (b) the fix is structural (single function branch + 1-char swap), (c) the architectural design space is bounded (the `forward-progress on tool_result` reset is the only correct fix; raising 90s further would relapse to the pre-#3225 design).

## Resume Prompt

```
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-06-fix-cc-pdf-idle-reaper-and-issue-link-org-plan.md. Branch: feat-one-shot-concierge-pdf-and-issue-link-fix. Worktree: .worktrees/feat-one-shot-concierge-pdf-and-issue-link-fix/. Issue: TBD. Plan reviewed, implementation next.
```
