---
name: Image placeholder leak + cc-soleur-go attachment drop
description: Two coupled bugs surfaced together — claude-agent-sdk text-editor placeholders leaked into chat output, and the cc-soleur-go path silently dropped msg.attachments
date: 2026-05-05
category: integration-issues
module: apps/web-platform
tags: [command-center, websockets, attachments, claude-agent-sdk, prompt-injection]
related_pr: 3254
related_issues: [3258, 3259, 3260]
---

# Learning: `[Image #N]` placeholder leak + cc-soleur-go attachment drop

## Problem

Production output (Command Center / KB chat) showed literal `[Image #1] [Image #2]` strings in chat history. Two distinct root causes were entangled:

1. **Text-paste leak.** When users paste an image, browsers populate `clipboardData.files` AND `clipboardData.getData("text/plain")`. The `chat-input` paste handler intercepted only `.files`. Inside the agent, the `claude-agent-sdk` text-editor renders pasted-image placeholders as the literal token `[Image #N]`. That token was making it back through the WS into the `messages.content` column verbatim.
2. **cc-soleur-go attachment drop.** The legacy single-leader path (`agent-runner.sendUserMessage`) processed `msg.attachments` (validate path-prefix, INSERT `message_attachments`, download to workspace, append `attachmentContext` to the prompt). The newer `cc-soleur-go` path (`dispatchSoleurGo`) accepted attachments at the WS boundary and then never used them — silently dropped on the floor before reaching the LLM.

The two bugs masked each other: when the SDK saw no attached image (because cc dropped it) it fell back to the placeholder token, which then leaked.

## Solution

Multi-layer fix in PR #3254:

- **`apps/web-platform/lib/image-placeholder-detect.ts` (new)** — single-source-of-truth detector. Uses `.replace(re, () => count++)` to sidestep the `lastIndex` reset trap from learning `2026-04-17-pii-regex-scrubber-three-invariants.md`.
- **`apps/web-platform/server/image-paste-strip.ts` (new)** — server-side strip + `image_paste_lost` WS error. Mirrors to Sentry via `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`.
- **`apps/web-platform/server/attachment-pipeline.ts` (new)** — extracted `agent-runner.ts:1342-1421` verbatim. Now used by BOTH legacy and cc paths. Eliminates drift — the cc path will never silently lag again.
- **`cc-dispatcher.ts`** — combined ownership-check with `last_active` bump (single UPDATE/RETURNING round-trip), then INSERT `messages` row, then call shared pipeline. The cc path didn't persist `messages` at all before — surfaced during deepen-plan as a Phase 3 architectural correction.
- **`chat-input.tsx`** — paste guard checks `text/plain` clipboard data for the pattern; rejects with user-facing toast.
- **Hardened filename sanitizer** — `[/\\\x00-\x1f\x7f  ]` (review finding). U+2028/U+2029 line separators would otherwise let a crafted filename forge a second `- file.png ...` line in the LLM-facing `attachmentContext` block (prompt injection).

## Key Insight

**When two paths claim "the same feature," lift the work into a shared module the moment the second path appears.** The legacy path had already evolved a 79-line attachment ritual; the cc path was written as if attachments were optional. Verbatim extraction into `attachment-pipeline.ts` is the only durable fix — anything else lets one path drift while tests on the other path stay green.

A second insight: **placeholder tokens emitted by upstream tools (claude-agent-sdk, OpenAI tool-call IDs, etc.) are surface-area for prompt injection if they reach user-visible storage.** Strip at the WS boundary, not at the LLM boundary, so they never enter the database.

## Session Errors

- **Literal U+2028/U+2029 chars in TS source** — embedded directly in `attachment-pipeline.ts` regex literal AND comments (copied from a reference). TS parser failed with `TS1161 Unterminated regular expression literal`. Recovery: replaced with `  ` escape sequences. **Prevention:** never embed raw bidi/line-separator codepoints in source — always use `\uXXXX` escapes in regex literals AND in comments. (Discoverability: TS error is loud; learning-file entry is sufficient — no AGENTS.md rule needed.)
- **`cc-dispatcher.test.ts` broke after adding `messages.insert` to `dispatchSoleurGo`** — the new `supabase().from("messages").insert(...)` triggered `Missing SUPABASE_URL` because the existing test mock only stubbed `from("conversations")`. Recovery: extended the `vi.mock("@/lib/supabase/service")` from-table switch. **Prevention:** when adding a new DB table to a function under test, audit the test file's mock surface BEFORE the implementation push. (Discoverability: vitest fails loudly; learning-file entry is sufficient.)
- **`code-simplicity-reviewer` DISSENT on `pre-existing-unrelated` filings** — the cc-dispatcher.ts diff added new INSERT/persistence sites that *exacerbated* the patterns I claimed were pre-existing. Recovery: re-filed Filing #2 as `architectural-pivot`; fixed Filing #3 inline (combined ownership UPDATE + last_active bump). **Prevention:** when claiming `pre-existing-unrelated`, run the exacerbation grep (`git diff origin/main...HEAD -- <file> | grep '^+' | grep <pattern>`) — non-zero hits invalidate the criterion. **Already covered** by AGENTS.md `rf-review-finding-default-fix-inline` and `knowledge-base/project/learnings/2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md` — no new rule needed.
- **EADDRINUSE on QA dev-server start (port 3000)** — port held by another process; standard QA flow. Recovery: skipped browser scenarios (covered by 54 unit/component tests). **Prevention:** QA skill already documents `PORT=3099 doppler run ... npm run dev` workaround — no new rule needed.

## Cross-References

- Fix: PR #3254
- Filed scope-outs: #3258 (cc workspace download flake), #3259 (architectural-pivot — cc messages-insert location), #3260 (cleanup)
- Related learnings:
  - `2026-04-17-pii-regex-scrubber-three-invariants.md` — `lastIndex` reset trap (avoided here via callback form)
  - `2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md` — exacerbation grep for scope-out criteria
  - `cq-silent-fallback-must-mirror-to-sentry` (AGENTS.md) — `reportSilentFallback` pattern used in `image-paste-strip.ts`
