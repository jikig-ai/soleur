---
type: bug-fix
issue: 3346
branch: feat-one-shot-concierge-pdf-summary-fix
prior_issues: [3253, 3263, 3278, 3287, 3288, 3294, 3326]
related_open_issues: [3332, 3243]
follow_through_issues: [3344, 3345]
review_scope_outs: [3342, 3343]
requires_cpo_signoff: true
---

# fix(cc-concierge): durable PDF summary path + suppress raw Bash approval prompts in end-user chat

## Enhancement Summary

**Drafted on:** 2026-05-06 (initial plan).
**Deepened on:** 2026-05-06 (same session, post initial draft).
**Sections enhanced:** 5 (`pdfjs-dist` API verification, SDK tool-name surface verification, lock-step parity edge cases, password/encrypted PDF handling, Bash modal repro path).
**Research sources used:** SDK type defs at `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk@0.2.85/sdk-tools.d.ts` (canonical tool names: `BashInput`, `FileReadInput`, `GlobInput`, `GrepInput` — and `sdk.d.ts:allowedTools` example `['Read', 'Grep', 'Glob', 'Bash']`); `pdfjs-dist@5.4.296/types/src/display/api.d.ts` (`getTextContent` signature, `onPassword` callback contract); existing call site `apps/web-platform/server/kb-preview-metadata.ts:83-103` (lazy-import + `isEvalSupported: false` + `doc.destroy()` pattern); prior plan `2026-05-05-fix-cc-pdf-poppler-cascade-phase2-positional-and-exclusion-list-plan.md` (parity grep `supports PDF files`); Mozilla pdf.js password-handling docs.

### Key Improvements Discovered During Deepen-Pass

1. **SDK canonical tool names verified at v0.2.85.** `sdk-tools.d.ts` exports `BashInput`, `FileReadInput`, `GlobInput`, `GrepInput` (note: `FileRead`, not `Read`, in the type-name surface — but `sdk.d.ts:1230` shows the runtime tool-name is `'Read'` per the `tools: ['Read', 'Grep', 'Glob', 'Bash']` allowedTools example). Canonical SDK tool-name list at v0.2.85 (for `allowedTools` filtering): `Read`, `Edit`, `Write`, `Glob`, `Grep`, `Bash`, `WebSearch`, `WebFetch`, `TodoWrite`, `ExitPlanMode`, `LS`, `NotebookRead`, `NotebookEdit` (PreToolUse hook matcher at `agent-runner-query-options.ts:134` enumerates `Read|Write|Edit|Glob|Grep|LS|NotebookRead|NotebookEdit|Bash`, and `permission-callback.ts:435-445` adds `ExitPlanMode` + `SOLEUR_GO_SAFE_UX_TOOLS` for `TodoWrite`). The `CC_PATH_ALLOWED_TOOLS` constant proposed in §Files to Edit must match the `'Read'` runtime name, not `'FileRead'`.

2. **`pdfjs-dist@5.4.296` `onPassword` callback contract.** `api.d.ts:onPassword: Function` — when the loaded document is password-protected and `onPassword` is NOT set, `getDocument().promise` rejects with a `PasswordException`. Our `extractPdfText` deliberately does NOT set `onPassword`, so encrypted PDFs reject cleanly and `null` is returned — exactly the fall-through-to-Read-directive behavior we want. Sentry mirror at `op: "extractPdfText"` will record one event per encrypted PDF. The Read-directive fallback is also unable to read encrypted PDFs (the SDK Read tool 32 MB API path also fails on encrypted PDFs), so the user gets a content-grounded error message in either path — no degradation introduced.

3. **`getTextContent()` returns `TextContent.items: Array<TextItem | TextMarkedContent>`.** `TextItem.str` is the per-item string. Joining with `\n` between items loses inline reading order; joining within-item with empty string and between-items with `\n` is the codebase convention. For single-column books like the user's `Manning Book - Effective Platform Engineering.pdf`, `item.str + " "` joined with `\n` between items yields readable continuous text. Multi-column or table-heavy PDFs may be garbled — accepted tradeoff for ≤50 KB inline; over the cap routes to Read which sees the original document.

4. **Bash review-gate hides under `safe-bash` near-miss telemetry.** `permission-callback.ts:526-548` emits `feature: "cc-permissions", op: "safe-bash-near-miss"` when a leading token starts with a safe-bash verb but extends past it (e.g., `lsof` near `ls`). When `find` or `apt-get` reach the gate today, they do NOT match the near-miss prefix regex (because `find`/`apt-get` are not derived from any safe-bash verb). Acceptance criterion T7 should NOT rely on near-miss events — instead assert directly that the cc-path SDK Query receives `allowedTools` excluding `Bash`, AND assert in the e2e Playwright test that zero `review_gate` WS frames are observed.

5. **Lock-step parity edge: `agent-runner.ts` artifact-injection block at L580-632 handles a 3-state branch.** The leader-side artifact injection has THREE states today: (a) text file ≤50 KB inline body, (b) text file >50 KB Read directive, (c) PDF Read directive. State (c) does NOT currently inline content — it always emits the Read directive plus the gated exclusion list. Adding the new "PDF with extracted body" branch requires landing it in BOTH builders simultaneously OR introducing an explicit divergence with a documented rationale. Choice: land in BOTH (lock-step parity is load-bearing per #3294 §Lock-step parity test). The leader path benefits from the inline-body branch when a domain leader is invoked while a KB PDF is in scope (already supported via `context.path` threading).

### New Considerations Discovered

- **Test PDFs must be synthesized inline, not committed as binaries.** Per `cq-test-fixtures-synthesized-only`, the `pdf-text-extract.test.ts` fixtures must be byte-arrays constructed in test code. Two options: (a) inline a short hand-crafted minimal-PDF byte sequence (PDF version `%PDF-1.4` + minimal trailer + one text block — ~500 bytes), (b) generate via `pdfjs-dist` if a writer is exposed, OR via `pdf-lib` (need to verify it's NOT a forbidden cascade dep — it isn't; the cascade list is `pdftotext` / `pdfplumber` / `pdf-parse` / `PyPDF2` / `PyMuPDF` / `fitz`). Decision: inline a minimal PDF byte sequence in the test file. No new runtime dependency. **Why:** adding `pdf-lib` as a devDependency for one test file is overkill, and a hand-crafted minimal PDF is well-documented (Adobe ISO 32000-1).

- **`extractPdfText` UTF-8 boundary.** PDFs returning Unicode text via `getTextContent()` already hand back JS strings (UTF-16 internally). When we `.slice(0, capChars)` we cut on JS-string code-unit boundaries — surrogate pairs split across `\uD800–\uDFFF` boundaries are the only risk. Safer: cap by ACCUMULATED character count, not by post-concatenation slice; halt page-iteration when total exceeds cap, then truncate the last page's text at the next code-point boundary. Implementation: track running length, accumulate page-by-page, halt the for-loop on `runningLength + page.length > capChars`, then on the partial page text take `pageText.slice(0, capChars - runningLength)` (still has surrogate-pair risk but is the standard JS approach). Acceptable.

- **Streaming text content is available** (`page.streamTextContent()`) but not needed at our scale (50 KB inline). Synchronous `getTextContent()` is simpler and matches `kb-preview-metadata.ts` style.

- **`isEvalSupported: false` MUST be passed to `getDocument()`** to avoid `Function()` usage in the worker — defense-in-depth in a server context that may have CSP. Mirrors `kb-preview-metadata.ts:91`.

- **Audit `find` / `apt-get` reachability before merging.** Add a smoke test (or local Playwright reproduction) that confirms with `Bash` removed from `allowedTools`, the SDK rejects the tool-call BEFORE `canUseTool` is invoked. Test seam: instrument `permission-callback.ts createCanUseTool` with a counter; on the cc-path with the new `allowedTools`, the counter for `Bash` calls should be exactly zero across all reproductions.

- **The plan-time grep verification for `supports PDF files`** (the lock-step parity invariant) lands the new inline-body branch in `agent-runner.ts` AND `soleur-go-runner.ts`; running `git grep "supports PDF files"` post-edit must show ≥4 matches: 2 in source (the two builders' Read-directive branches) and ≥2 in tests (parity assertion). Verify before marking the implementation phase complete.

Closes the user-reported regression on Concierge KB chat where opening a KB PDF and asking "summarize this PDF" still returns a poppler-utils install cascade and pops a `find . -name "*.pdf"` Bash approval modal at the end user. Multiple prior prompt-only fixes (#3263, #3278, #3287/#3288, #3294) reduced the failure rate but did not eliminate it — the durable fix combines a server-side PDF text extraction path (so the agent never has to "find" or "decode" the PDF) with toolset hardening (so a regression cannot put a raw Bash modal in front of an end user).

This plan also files two follow-through issues for adjacent work the user explicitly called out: widening the safe-bash allowlist so the web-platform Concierge can do the same in-conversation exploration that the Claude Code plugin does, and a UX track for hiding the raw approval modal entirely behind a friendlier surface.

## Overview

**Root cause (problem 1 — PDF summary fails):** The cc-soleur-go path delegates PDF reading to the Anthropic SDK's `Read` tool, which natively supports PDFs up to 32 MB by base64-uploading the bytes to the Anthropic Files API. Three failure modes have been observed in production:

1. **Model overrides the prompt and shells out.** Despite `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` (#3253) + the gated named-binary exclusion list (#3294), the model's training prior on `pdftotext` / `pdfplumber` / `pdf-parse` / `PyPDF2` / `apt-get install poppler-utils` still occasionally wins. The Sentry breadcrumb data captured in PR #3288 confirmed the directive WAS reaching the model on every cold-Query construction; the model just overrode it. Prompt-only mitigations have plateaued.
2. **Even when Read is called, large PDFs hit timer/budget walls.** PR #3326 fixed the 90s idle-window runaway by resetting on SDK `tool_use_result`; the absolute 10-min ceiling remains. Open issue #3332 documents the 32 MB Anthropic API ceiling that mismatches the 50 MB KB upload cap.
3. **The agent doesn't always know which PDF the user means.** When the user phrases the question as "summarize this PDF" without the artifact frame already injected (warm Query, Concierge router scope, model self-reset), the agent falls back to `find . -name "*.pdf"` to discover the file, which pops a Bash approval modal.

**Root cause (problem 2 — raw Bash modal in end-user chat):** The cc-soleur-go path inherits the legacy domain-leader threat model where `Bash` is in scope (`apps/web-platform/server/permission-callback.ts:447-680`) with a `safe-bash` allowlist for read-only verbs (`pwd`, `ls`, `cat`, `head`, `git status`, etc.). `find` and `apt-get` are intentionally NOT in the safe-bash allowlist, so they fall through to a `review_gate` WS event that the chat surface renders as an Approve/Reject modal. End users are not equipped to evaluate `find` vs `apt-get install -y poppler-utils 2>&1` — both are technical Bash strings.

**Durable fix (this plan):**

1. **Server-side PDF text extraction at cold-Query construction (load-bearing).** When the Concierge resolver detects `documentKind === "pdf"`, extract the PDF's text via `pdfjs-dist/legacy/build/pdf.mjs` (already installed at `apps/web-platform/node_modules/pdfjs-dist@5.4.296`, already used server-side at `apps/web-platform/server/kb-preview-metadata.ts:83`), cap at the existing 50 KB inline budget, and inline the text into the system prompt the same way `documentKind === "text"` already does. The agent never has to call Read — and "summarize this PDF" becomes a pure text task. PDFs over the inline cap fall through to the existing Read-directive branch (which still works for 32 MB-ceiling PDFs the agent can read natively, with a friendlier preflight error for the rest).
2. **Bash sandboxing for the cc-soleur-go path.** Move the cc-path to an explicit `allowedTools` whitelist that excludes `Bash` for the Concierge router (`CC_ROUTER_LEADER_ID`), forcing the model to use `Read`/`Glob`/`Grep` instead of shelling out. This change is scoped to the cc-soleur-go path only — the legacy domain-leader path keeps its current Bash gate. A small audit confirms the model has full access to the same KB-exploration capabilities through the SDK's native Read/Glob/Grep tools.
3. **Filed scope-outs for the user-asked-for adjacent work.** Two follow-through issues (see §Follow-Through Issues): widen safe-bash to support Claude-Code-plugin-like flows post-cleanup; hide the raw approval modal behind a domain-appropriate surface (e.g., "The agent wants to inspect a file — allow?") so even when a Bash gate fires it does not show shell strings to non-technical users.

The acceptance criterion is the user's stated criterion: opening a KB PDF and asking "summarize this PDF" returns a content-grounded summary without `apt-get` or `find` approval prompts.

## User-Brand Impact

- **If this lands broken, the user experiences:** First-touch trust collapse on the brand's flagship demo path. A user opens their first private knowledge-base PDF, asks Concierge to summarize it, and watches the agent (a) ask for `sudo apt-get install poppler-utils`, then (b) pop a `find . -name "*.pdf"` Bash approval modal, then (c) "summarize" the book from training-data prior. They do not re-attach a private document to a system that confidently lied about its own capabilities. This is the single most-reproduced first-touch failure on the platform — five prior PRs in the chain have not closed it.
- **If this leaks, the user's data/workflow is exposed via:** No data leak (the agent never reads the file). Trust leak: the user sees a raw Bash approval modal containing `find . -name "*.pdf"` or `apt-get install -y poppler-utils 2>&1` and concludes Concierge is trying to mutate their workspace to compensate for missing capabilities. Reverse-confidence signal that bleeds into every subsequent KB interaction. Inherits the framing from the entire #3253 → #3294 chain.
- **Brand-survival threshold:** `single-user incident` — same threshold as the entire cc-pdf cascade chain (PRs #3253, #3263, #3278, #3287/#3288, #3294, #3326 all gated at this level). A single reproduction on a deployed `web-v0.64.x` against the user's primary KB document already happened (the screenshots in this issue body, post-#3294, post-#3326). CPO sign-off is required at plan time per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`; `user-impact-reviewer` runs at review-time.

`requires_cpo_signoff: true` per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`. Carry-forward sign-off from the cascade chain — threshold and artifact framing are unchanged. CPO must explicitly re-sign because this plan introduces a structural change (toolset narrowing) the prior plans did not.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body / user description) | Codebase reality | Plan response |
| --- | --- | --- |
| "Agent doesn't know how to read PDFs that ARE present in the KB" | `apps/web-platform/server/kb-document-resolver.ts:107-109` returns `{ artifactPath, documentKind: "pdf" }` for PDFs WITHOUT inlining text. The system prompt then carries an assertive Read directive but no body. | The "doesn't know" framing is not exact — the resolver DOES surface the path to the system prompt. The failure mode is downstream: the model either ignores the directive (Hypothesis B/C from PR #3294) or the Read tool fails on >32 MB or hits the timer wall. Plan response: extract text server-side (no Read call) for ≤50 KB inline, fall through to Read for the rest. |
| "It should locate them via the workspace/KB index, not by shelling out to find" | The Concierge already has the `artifactPath` from the start_session frame (`context.path` → `resolveConciergeDocumentContext`). When the model emits `find`, it is overriding the system prompt — not because the path was missing. Verified at `ws-handler.ts:825-832` (resolver call) + `cc-dispatcher.ts:548-555` (system-prompt threading). | Plan response: keep the resolver path-injection, AND remove `Bash` from the cc-path toolset so the model cannot fall back to `find` even if it tries. |
| "It should extract text via an in-process/library path, not demand apt-get install poppler-utils" | `pdfjs-dist@5.4.296` is already installed (`apps/web-platform/package-lock.json:10294`). The legacy entry (`pdfjs-dist/legacy/build/pdf.mjs`) is server-side usable and already used at `apps/web-platform/server/kb-preview-metadata.ts:83-92`. `getDocument().promise → page.getTextContent()` returns text items without needing `poppler-utils` / `pdftotext` / `canvas` / `node-canvas`. | Plan response: add `extractPdfText(buffer, capBytes)` to a new `apps/web-platform/server/pdf-text-extract.ts` (new file, single responsibility), call from `resolveConciergeDocumentContext` for `documentKind: "pdf"`. Cap input size at the existing `PREVIEW_MAX_BYTES = 15 MB` to avoid the 200-300 MB RSS spike documented at `kb-preview-metadata.ts:18-24`. |
| "Concierge surface must not surface raw shell tool approvals" | `permission-callback.ts:577-588` emits `review_gate` WS events with the raw command string in the `question` field. `chat-surface.tsx` renders these as Approve/Reject modals. The cc-path uses the same gate (`cc-dispatcher.ts:460-471 → registerCcBashGate`). | Plan response: scope the cc-path to a tighter `allowedTools` set that EXCLUDES `Bash` (the cc-path is router-only — it never needs to shell out). The legacy domain-leader path keeps Bash + the gate. The user's adjacent ask (widen safe-bash for in-conversation exploration) is filed as a follow-through issue, not folded in. |
| "Multiple prior attempts have not fixed this" | Verified via `git log`: PRs #3263 (2026-05-05), #3278, #3288 (Phase 1 instrumentation), #3294 (Phase 2 positional + exclusion list), #3326 (timer fix). Each addressed a real but different failure mode. | Plan response: this is a structural fix that closes the remaining surface, not another prompt iteration. The `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` and the gated exclusion list stay (they harden the >50 KB fall-through path) — the new server-side extraction path makes them mostly unreachable on first-turn summarization. |
| "Choose `pdfjs-dist` or `pdf-parse`" | `pdfjs-dist` is already installed and used server-side. `pdf-parse` is unmaintained (last release 2018, Node 12 era — flagged as a hallucinated tool the MODEL emits in the cascade — see `read-tool-pdf-capability.test.ts:133` exclusion list). Adding `pdf-parse` would land us in the exact training-prior trap the gated directive warns the model AGAINST. | Plan response: use `pdfjs-dist/legacy/build/pdf.mjs` exclusively. Do NOT add `pdf-parse`. |
| "Anthropic SDK's Read natively supports PDFs" — claim from #3253 plan | Verified at `@anthropic-ai/claude-agent-sdk@0.2.85`. SDK Read base64-uploads the bytes to the Anthropic Files API; ceiling is 32 MB per request. | Plan response: the SDK Read path stays as the >50 KB fallback. `kb-limits.ts MAX_BINARY_SIZE = 50 MB` triggers issue #3332 (separate scope-out). This plan does NOT change the upload cap. |

## Hypotheses

This plan is reactive (failure mode confirmed by user screenshots), not investigative — but documenting the disambiguation against past plans:

| Hypothesis | Detection | Conclusion |
| --- | --- | --- |
| **A — Resolver doesn't reach `documentKind: "pdf"` branch** | `ws-handler.ts:825-832` always calls `resolveConciergeDocumentContext` when `context.path && !warmCcQuery`. Verified path: `start_session → liveSession.contextPath → handleUserMessage → resolveConciergeDocumentContext → dispatchSoleurGo`. | Ruled out — confirmed by PR #3288 breadcrumb data (`hasContextPath: true`, `documentKindResolved: "pdf"` on every cold-Query). |
| **B — Prompt directive is below override threshold** | PR #3294 acknowledged this and added named-tool exclusion list. User reports failure persists. | Confirmed (additive to A). The model's tool-class prior occasionally still wins. Prompt iteration cannot close it deterministically. |
| **C — Model takes the long path: Read → 32 MB API → timer wall → fallback** | PR #3326 fixed the 90s timer reset on `tool_use_result`. User screenshot post-#3326 shows the cascade still emerging on multi-MB books. | Confirmed (additive to B). Even with the timer fix, the model emits `find` / `apt-get` BEFORE invoking Read on first turn ~30% of the time per Sentry. |
| **D — Bash is reachable from the cc-path at all** | `cc-dispatcher.ts:545-585` does NOT pass `allowedTools` → `agent-runner-query-options.ts:166` only sets it `if (args.allowedTools !== undefined)` → SDK default = all built-in tools allowed → `Bash` is callable. | Confirmed. This is the toolset-shape gap the plan closes. |

The structural fix (extract text server-side + remove Bash from cc-path) is the union of "make the desired path easier than the cascade" and "remove the cascade entirely from the agent's toolset". Either alone is insufficient (prompt-only has now plateaued; toolset narrowing alone leaves the >50 KB Read path on the timer wall). Together they close the surface.

## Open Code-Review Overlap

Two open scope-outs touch files this plan will modify. Per the plan-skill overlap gate:

- **#3332** (`chore(kb-limits): cap PDF uploads at 32 MB or warn at attach time`) — touches `apps/web-platform/server/kb-limits.ts`. **Disposition: acknowledge.** This plan does NOT touch the upload cap. The 50 MB → 32 MB UX-warning fix is its own concern (upload-time UX vs in-conversation read-time fallback). When this plan's >50 KB Read fallback fires on a 32–50 MB PDF, the agent will receive the Anthropic API failure as a tool_result and degrade gracefully (per PR #3326's `handleUserMessage` branch). #3332 stays open and gets a comment linking back to this PR.
- **#3243** (`arch: decompose cc-dispatcher.ts into focused modules`) — touches `apps/web-platform/server/cc-dispatcher.ts`. **Disposition: acknowledge.** This plan adds a small amount of code to `realSdkQueryFactory` (the new `allowedTools` arg threading). #3243 is a larger refactor that deserves its own cycle. The new code is shape-compatible with the proposed decomposition. #3243 stays open.

#3331 (`extract shared SDK fixture harness from 5 runner test files`) and #3242 (`tool_use WS event lacks raw name field for agent consumers`) and #2955 (`process-local state assumption needs ADR + startup guard`) are tangential — this plan adds tests but does not touch the shared fixture, does not touch the WS tool_use event shape, and does not introduce new process-local state.

## Files to Edit

1. **`apps/web-platform/server/kb-document-resolver.ts`** — `resolveConciergeDocumentContext` PDF branch (currently L93-109): when `isPdf && !providedContent`, call new `extractPdfText(buffer, CONCIERGE_INLINE_CAP_BYTES)`. On success ≤50 KB → return `{ artifactPath, documentKind: "pdf", documentContent: extractedText }`. On extraction failure or oversize → fall through to existing `{ artifactPath, documentKind: "pdf" }` (Read directive). All errors mirror to Sentry via `reportSilentFallback({ feature: "kb-concierge-context", op: "extractPdfText", extra: { userId, pathBasename } })` per `cq-silent-fallback-must-mirror-to-sentry`.
2. **`apps/web-platform/server/soleur-go-runner.ts`** — `BuildSoleurGoSystemPromptArgs` already accepts `documentKind: "pdf" | "text"` + `documentContent`. Extend the `documentKind === "pdf"` branch (L543-545 today) so when `documentContent` is non-empty, emit a text-style inline directive (mirroring the `documentKind === "text"` body wrapper at L546-572) — same `<document>...</document>` wrapper, same control-char + U+2028/U+2029 sanitization, same `</document>` escape, same 50 KB cap. When `documentContent` is empty, fall through to the existing `buildPdfGatedDirective` Read path. Hold the existing exclusion-list directive — it is now belt-and-suspenders for the >50 KB Read path.
3. **`apps/web-platform/server/cc-dispatcher.ts`** — `realSdkQueryFactory` (L421-612). Pass an explicit `allowedTools` list to `buildAgentQueryOptions` that includes the SDK built-ins the cc-router NEEDS but EXCLUDES `Bash`, `Edit`, `Write`. Canonical list verified against `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk@0.2.85/sdk-tools.d.ts` (runtime tool names: `Read`, `Edit`, `Write`, `Glob`, `Grep`, `Bash`, `WebSearch`, `WebFetch`, `TodoWrite`, `ExitPlanMode`, `LS`, `NotebookRead`, `NotebookEdit`). Proposed `CC_PATH_ALLOWED_TOOLS = ["Read", "Glob", "Grep", "LS", "NotebookRead", "TodoWrite", "ExitPlanMode"]`. `WebSearch`/`WebFetch` are already in `disallowedTools` (`agent-runner-query-options.ts:48 CANONICAL_DISALLOWED_TOOLS`) — `disallowedTools` and `allowedTools` are independent SDK chain steps; both narrow the surface. The legacy domain-leader path (`agent-runner.ts startAgentSession`) is untouched — it has its own `allowedTools` derived from `platformToolNames + pluginMcpServerNames`.
4. **`apps/web-platform/server/agent-runner-query-options.ts`** — no functional change, but the JSDoc for `allowedTools` (currently L78-86) gets a clarifying comment that the cc-path now passes a non-empty list to scope away from Bash. Drift-guard test in `agent-runner-query-options.test.ts` may need an additional assertion if it currently snapshots the cc-path output.
5. **`apps/web-platform/test/read-tool-pdf-capability.test.ts`** — add scenarios:
   - `buildSoleurGoSystemPrompt({ artifactPath: "...pdf", documentKind: "pdf", documentContent: "<extracted text>" })` returns a prompt that contains `<document>` + the extracted text + `</document>`.
   - `documentContent` over 50 KB → falls through to `buildPdfGatedDirective` (the existing test scenarios still pass).
   - The new branch DOES NOT contain the named-binary exclusion list (the model has the body inline; the directive is unnecessary noise on the inline path).
6. **`apps/web-platform/test/cc-dispatcher-concierge-context.test.ts`** — extend with a scenario that exercises `resolveConciergeDocumentContext` for a fixture PDF (use a small synthesized PDF buffer; ≤2 KB) and asserts:
   - Return shape includes `documentContent` with the expected text.
   - On a deliberately corrupted PDF buffer, returns `{ artifactPath, documentKind: "pdf" }` without `documentContent` AND emits a single Sentry mirror with `op: "extractPdfText"`.
   - On an oversized PDF (mock the extractor to return a 60 KB string), falls through to the Read-directive branch.
7. **`apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx`** — add or extend a scenario that asserts the cc-path SDK Query is constructed with `allowedTools` that does not contain `Bash`. Lock the invariant at the test layer (otherwise a future deps-injection edit could silently re-widen the toolset). Use the existing test seam pattern from `agent-runner-query-options.test.ts`.
8. **`apps/web-platform/test/agent-runner-query-options.test.ts`** — drift-guard the cc-path snapshot: confirm `allowedTools` is present and excludes Bash. The legacy snapshot stays exactly as today.

## Files to Create

1. **`apps/web-platform/server/pdf-text-extract.ts`** — single responsibility: `extractPdfText(buffer: Buffer | Uint8Array, capBytes: number): Promise<{ text: string; truncated: boolean; pageCount: number } | null>`. Uses `pdfjs-dist/legacy/build/pdf.mjs` lazy-imported (mirrors `kb-preview-metadata.ts` pattern). Iterates pages 1..N, calls `page.getTextContent()`, joins items with `\n`, halts at `capBytes`, returns `truncated: true` if halted. Errors return `null`; caller mirrors to Sentry. Input cap = 15 MB (mirrors `PREVIEW_MAX_BYTES`) — refuses larger buffers. Always calls `doc.destroy()` in a `finally` block (mirrors `kb-preview-metadata.ts:103`).
2. **`apps/web-platform/test/pdf-text-extract.test.ts`** — unit-tests against synthesized PDFs:
   - Small PDF (e.g., a 2-page "Hello World" buffer) → `text` matches expected, `truncated: false`, `pageCount: 2`.
   - Cap-truncated PDF — text exactly `capBytes` long, `truncated: true`.
   - Corrupted buffer → `null`.
   - Empty PDF (zero pages) → `{ text: "", truncated: false, pageCount: 0 }` (downstream resolver decides whether to inline an empty body or fall through).
   - Buffer over 15 MB input cap → `null`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Opening a KB PDF in the chat UI and asking "summarize this PDF" returns a content-grounded summary in ≤30s on a ≤200-page book (the test fixture pinned in the e2e test). Reproduce on local dev with `bun dev` + Playwright MCP against the seeded fixture.
- [ ] No `apt-get` / `find` / `pdftotext` / `pdfplumber` / `pdf-parse` / `PyPDF2` / `PyMuPDF` / `fitz` / `pip3 install` Bash modal pops in the Concierge surface during the reproduction. Asserted via Playwright MCP `browser_console_messages` capturing zero `review_gate` WS frames in the test session, AND via a regression unit test on `cc-dispatcher` that asserts `allowedTools` excludes `Bash`.
- [ ] `extractPdfText` unit tests pass (8 scenarios above).
- [ ] `read-tool-pdf-capability.test.ts` extended scenarios pass.
- [ ] `cc-dispatcher-concierge-context.test.ts` extended scenarios pass.
- [ ] `tsc --noEmit` clean.
- [ ] Multi-agent review (≥9 agents per `rf-review-finding-default-fix-inline`); 0 P1; all findings either fixed inline or filed as scope-out.
- [ ] PR body uses `Closes #N` for the issue this plan files at issue-creation step (currently `TBD`).
- [ ] PR body uses `Ref #3332` (size-cap UX warning, separate scope) and `Ref #3243` (cc-dispatcher decomposition, separate scope).
- [ ] CPO sign-off captured in the PR body Brand-Survival section (carry-forward from the #3253 → #3294 chain plus explicit re-sign on toolset narrowing).
- [ ] `user-impact-reviewer` review pass at the multi-agent review gate per `requires_cpo_signoff`.

### Post-merge (operator)

- [ ] Manual verification on a fresh prod conversation: attach the user's `Manning Book - Effective Platform Engineering.pdf` (the bug-report fixture) and ask "summarize this PDF". Expect a content-grounded summary referencing chapter titles or specific concepts in the book — NOT a training-prior summary. Verify zero Bash approval modals during the reproduction.
- [ ] Sentry breadcrumb monitoring window: 24h post-deploy, watch for `feature: "kb-concierge-context", op: "extractPdfText"` events. Expect a low background of legitimate failures (corrupted PDFs, password-protected PDFs); investigate any spike.
- [ ] Sentry monitoring: zero `cc-permissions / safe-bash-near-miss` events with `leadingToken: "find"` or `leadingToken: "apt-get"` in the cc-path window. (The legacy domain-leader path may still emit these — that's fine; the cc-path is what users see.)
- [ ] Two follow-through issues filed (see §Follow-Through Issues below) and milestoned.

## Implementation Phases

### Phase 1 — `pdf-text-extract.ts` helper (TDD)

1. Write failing unit tests (`pdf-text-extract.test.ts`) for the 8 scenarios.
2. Implement `extractPdfText` using `pdfjs-dist/legacy/build/pdf.mjs`. Mirror the `kb-preview-metadata.ts` lazy-import + `isEvalSupported: false` + `doc.destroy()`-in-finally pattern. Page-by-page text extraction halts at `capBytes`.
3. Verify `bun test apps/web-platform/test/pdf-text-extract.test.ts` is green.

### Phase 2 — Wire into `kb-document-resolver.ts`

1. Extend `resolveConciergeDocumentContext` PDF branch (L107-109 today) to:
   - Read the file via `readFile(fullPath)` (binary, not utf-8). Reuse the `isPathInWorkspace` guard from L128.
   - Call `extractPdfText(buffer, CONCIERGE_INLINE_CAP_BYTES)`.
   - On `{ text, truncated: false }` and `text.length > 0` → return `{ artifactPath, documentKind: "pdf", documentContent: text }`.
   - On `{ truncated: true }` (≥50 KB extracted, body capped) → return `{ artifactPath, documentKind: "pdf", documentContent: text }` (use the cap'd body — better than no body).
   - On `null` (extraction failed) → return existing `{ artifactPath, documentKind: "pdf" }` (Read directive fallback). Mirror to Sentry with `op: "extractPdfText"`.
2. Update `cc-dispatcher-concierge-context.test.ts` scenarios.
3. Verify the new return shape flows through `buildSoleurGoSystemPrompt` correctly (Phase 3 below).

### Phase 3 — `buildSoleurGoSystemPrompt` PDF-with-content branch

1. Extend the `documentKind === "pdf"` branch in `buildSoleurGoSystemPrompt` (`soleur-go-runner.ts` L543-545):
   - When `args.documentContent` is non-empty AND ≤50 KB, emit the same `<document>...</document>` wrapper used by `documentKind === "text"` (L546-572). Reuse the existing sanitizer (`replace(/[\x00-\x1f\x7f  ]/g, "")` + `</document>` escape).
   - When `args.documentContent` is empty, fall through to existing `buildPdfGatedDirective(safeArtifactPath, NO_ASK)`.
2. Mirror the same change in `agent-runner.ts` artifact-injection block (L580-632) for the legacy domain-leader path. The two builders MUST stay in lock-step — `agent-runner-system-prompt.test.ts` enforces parity at L320+. Add the parity assertion for the new inline-text-from-PDF branch.
3. Update `read-tool-pdf-capability.test.ts` scenarios.

### Phase 4 — `cc-dispatcher.ts` toolset narrowing

1. Add a `CC_PATH_ALLOWED_TOOLS` constant near the top of `cc-dispatcher.ts`: `["Read", "Glob", "Grep", "LS", "TodoWrite", "ExitPlanMode"]` (audit against the SDK's default-allow surface — verify with `Read` of `node_modules/@anthropic-ai/claude-agent-sdk/lib/types.d.ts` or equivalent for the canonical tool name list at v0.2.85).
2. In `realSdkQueryFactory`, pass `allowedTools: CC_PATH_ALLOWED_TOOLS` to `buildAgentQueryOptions`.
3. The cc-path's `permission-callback.ts` Bash branch becomes unreachable — defense-in-depth `canUseTool` keeps it as a deny-by-default path (an SDK widening that re-enables Bash would still hit the gate, not the user). No code removal here.
4. Update the cc-path snapshot test in `agent-runner-query-options.test.ts` and the e2e render test.

### Phase 5 — Telemetry + Reproduction Verification

1. Add a Sentry breadcrumb at `kb-document-resolver.ts` line where `extractPdfText` is invoked, capturing `{ pageCount, truncated, textBytes, pathBasename }` (PII-redacted; basename only). This is observability for the new code path; complements the existing `emitConciergeDocumentResolutionBreadcrumb` at `ws-handler.ts:835-844` which fires earlier.
2. Run the local reproduction:
   - Seed a test workspace with a representative PDF under `knowledge-base/`.
   - `bun dev` + open KB UI on the PDF.
   - Ask "summarize this PDF".
   - Verify response is content-grounded and zero approval modals fire.
3. Capture the Playwright MCP screenshot for the PR body.

### Phase 6 — Follow-Through Issue Filing

1. File issue **TBD-safe-bash-widen** (title: `chore(safe-bash): widen cc-path safe-bash allowlist for KB exploration parity with Claude Code plugin`). Body: capture the user's stated requirement that the web-platform Concierge should support the same in-conversation exploration the Claude Code plugin does. Reference the current `safe-bash` allowlist (`permission-callback.ts:155-188`) and the candidate verbs the plugin supports (`find`, `grep`, `rg`, `bun test`, `npm test`, etc.). Re-evaluation criterion: post this PR's merge, when at least one user reports needing exploratory Bash in the Concierge. Milestone: `Post-MVP / Later`.
2. File issue **TBD-bash-modal-hide** (title: `feat(cc-chat): replace raw Bash approval modal with intent-shaped UX in Concierge surface`). Body: capture the broader UX concern that even when a Bash gate fires (e.g., for a power user who has opted into `safe-bash-widen`), the modal should show "The agent wants to inspect a file at path X" rather than a raw shell command. Reference `chat-surface.tsx` review_gate rendering. Milestone: `Post-MVP / Later`.

## Test Scenarios

| ID | Scenario | Asserted Behavior |
| --- | --- | --- |
| T1 | Small PDF (≤50 KB extracted text) attached, "summarize this" | System prompt contains `<document>` + extracted text; response is content-grounded; zero Bash modals |
| T2 | Large PDF (>50 KB extracted text) attached, "summarize this" | System prompt contains the cap'd body (or falls through to Read directive on `null`); model invokes Read; response is content-grounded |
| T3 | Corrupted PDF attached, "summarize this" | `extractPdfText` returns `null`; resolver returns `{ artifactPath, documentKind: "pdf" }`; system prompt has the Read directive; Sentry mirror at `op: "extractPdfText"` fires once |
| T4 | Password-protected PDF attached | Same as T3 (extraction fails, falls through). `pdfjs-dist` rejects password-protected docs cleanly. |
| T5 | PDF over 15 MB attached | `extractPdfText` returns `null` (input cap); resolver falls through to Read directive. Issue #3332 covers the 32 MB UX warning separately. |
| T6 | Resolution path runs in browser-language test (no actual SDK invocation) | `cc-dispatcher.ts` constructs SDK Query with `allowedTools: CC_PATH_ALLOWED_TOOLS`; `Bash` is NOT in the list |
| T7 | Model attempts to call Bash on cc-path (via simulated SDK behavior) | The SDK rejects per `allowedTools` filtering before reaching `canUseTool`; no `review_gate` WS event fires; the user sees zero approval modal |
| T8 | Snapshot drift guard | `agent-runner-query-options.test.ts` cc-path snapshot pins `allowedTools` shape; legacy path snapshot is unchanged |
| T9 | Reproduction E2E | Playwright MCP: open `Manning Book - Effective Platform Engineering.pdf` (or fixture stand-in), ask "summarize this PDF", assert response references at least 2 specific chapter titles AND zero `review_gate` WS frames in the session |
| T10 | Inline-text branch parity | `agent-runner-system-prompt.test.ts` asserts the leader path's PDF-with-content branch matches the cc-path's branch byte-for-byte (lock-step parity per the existing `supports PDF files` substring grep) |

## Risks

- **R1 — `pdfjs-dist/legacy` lazy import RSS spike on cold workers.** First call to `extractPdfText` per process triggers the lazy import (~5-10 MB resident). Mitigation: the import is already paid in `kb-preview-metadata.ts`'s `readPdfMetadata` path. The cc-path will share the module instance.
- **R2 — Text extraction quality on PDFs with complex layouts (multi-column, embedded images, OCR'd scans).** `getTextContent()` returns text items with positional metadata; joining with `\n` loses layout. For most KB documents (books, articles, reports), the result is readable. Mitigation: scope to ≤50 KB inline budget; over-budget PDFs route to the Read fallback (which sees the original PDF). Scanned-only PDFs return zero or low-quality text — the Read directive is the right fallback.
- **R3 — Toolset narrowing breaks a workflow.** The cc-router was Bash-callable as a side-effect, not by design. The router's job is to dispatch to `/soleur:go` skills, which then have their own toolsets via the soleur plugin. Internal Bash calls within the router itself were never load-bearing. Mitigation: comprehensive review of cc-path Sentry traces for any `tool: "Bash"` events sourced from the cc-router (not from a routed sub-skill). If found, those workflows file separately under `safe-bash-widen`.
- **R4 — Lock-step parity drift between Concierge and leader prompt builders.** The PDF-with-content branch must land in BOTH `soleur-go-runner.ts` and `agent-runner.ts` (#3294 §Lock-step parity). Mitigation: `agent-runner-system-prompt.test.ts` already enforces this at `supports PDF files` substring level. Add the new inline-body assertion to the same test.
- **R5 — Deepen-pass discovers a missed sub-issue.** Per the deepen-plan flow, this plan goes through deepen-plan next. Defer detailed risk enumeration on adjacent surfaces (multipart PDFs, encrypted PDFs, JBIG2 errors, text extraction in non-LTR languages) to deepen-plan Phase 4.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled with concrete artifacts and threshold; deepen-plan should pass it.
- **Do NOT add `pdf-parse` to the dependency tree.** `pdf-parse` is the most-named binary in the model's training-prior cascade (`read-tool-pdf-capability.test.ts:133`). Adding it as a dep would normalize what the gated directive instructs the model to NOT call. `pdfjs-dist` is already installed and used.
- **Do NOT remove the `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` baseline constant or the `buildPdfGatedDirective` factory.** They harden the >50 KB Read fallback path. The new server-side extraction reduces — but does not eliminate — reliance on Read.
- **Do NOT extend the safe-bash allowlist in this PR.** The user explicitly asked for that as adjacent work; folding it in here would (a) widen blast radius beyond the stated bug, (b) miss the dedicated review surface a safe-bash widening deserves. Filed as a follow-through issue.
- **The cc-path `allowedTools` list is a denylist by exclusion; verify it against the SDK's actual default-allow surface at v0.2.85** before merging. The list above is the candidate; deepen-plan should verify `node_modules/@anthropic-ai/claude-agent-sdk` exports a canonical tool-name enum and reconcile.
- **`extractPdfText` halt-at-capBytes must NOT mid-character-truncate UTF-8.** Use a TextDecoder fall-through or pre-cap on character count, not a raw `.slice(0, capBytes)` on a string that might contain multi-byte chars at the boundary. The existing 50 KB cap in `resolveConciergeDocumentContext` for text files (`content.slice(0, CONCIERGE_INLINE_CAP_BYTES)`) has the same theoretical issue but text-file paths typically slice on ASCII boundaries; PDFs may have stronger Unicode density.
- **Per-test fixture: synthesize PDFs in test setup using `pdfjs-dist`'s own writer or a tiny inline buffer.** Do NOT commit a real PDF binary into the repo (`cq-test-fixtures-synthesized-only`). Use a 2-3 page mock-PDF buffer constant in the test file.
- **Audit `find`-style hand-written cascade-detection regexes BEFORE assuming the prompt directive will catch them.** The model has been observed emitting `which pdftotext` (not `pdftotext` directly), `python3 -c "import PyPDF2"` (not `PyPDF2` directly), `pip3 install pdfplumber` (not `pdfplumber` directly). The exclusion list in `buildPdfGatedDirective` does not catch these wrapped forms — but with `Bash` removed from `allowedTools`, the model literally cannot emit them as tool calls.

## Follow-Through Issues

These are NOT in scope for this PR. They are filed in Phase 6 of implementation and tracked separately:

1. **`chore(safe-bash): widen cc-path safe-bash allowlist for KB exploration parity with Claude Code plugin`** (TBD issue #). User explicitly asked: "we should also consider opening an issue to allow for more tools to be allowed in the safe-bash allowlist as we want to be able to do in the web platform the same process that we do in here in the claude code plugin." Re-evaluation: post-merge of this plan, when at least one Concierge user reports needing exploratory Bash. Milestone: `Post-MVP / Later`.
2. **`feat(cc-chat): replace raw Bash approval modal with intent-shaped UX in Concierge surface`** (TBD issue #). Even when a Bash gate fires (e.g., for a power user post-`safe-bash-widen`), the modal should show "The agent wants to inspect a file at path X" rather than a raw shell command. References `chat-surface.tsx review_gate` rendering. Milestone: `Post-MVP / Later`.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO).

### Engineering (CTO)

**Status:** to-be-spawned at deepen-plan Phase 4.

**Assessment (preliminary, this plan):** The structural fix is well-scoped: a new single-responsibility module (`pdf-text-extract.ts`), a small toolset-narrowing change in `cc-dispatcher.ts`, and prompt-builder parity work in `soleur-go-runner.ts` + `agent-runner.ts`. The lazy-import pattern, error-mirror pattern, and lock-step parity guard are all established in the codebase. The principal architectural concern is whether `pdfjs-dist` server-side text extraction has parity with the SDK Read tool's text quality on real-world PDFs — to be validated in Phase 1 unit tests.

### Product/UX Gate

**Tier:** advisory — this plan modifies an existing UI surface (Concierge chat) without adding new pages or components.

**Decision:** auto-accepted (pipeline). The user-visible output (a content-grounded summary instead of an apt-get cascade) is the explicit acceptance criterion; UX framing is straightforward. UX-specific specialists (ux-design-lead, copywriter) are NOT spawned for this plan because the surface change is a deletion of a bad UX (the raw Bash modal during PDF chat) rather than an addition. The follow-through issue **TBD-bash-modal-hide** covers the broader UX track.

**Agents invoked:** auto-accepted (pipeline) — none.
**Skipped specialists:** ux-design-lead (advisory tier; surface is deletion-shaped); copywriter (no new copy authored).
**Pencil available:** N/A.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-06-fix-cc-concierge-pdf-summary-and-bash-modal-plan.md.
Branch: feat-one-shot-concierge-pdf-summary-fix. Worktree: .worktrees/feat-one-shot-concierge-pdf-summary-fix/.
Issue: TBD (filed at plan-creation step). Refs: prior #3253 / #3263 / #3278 / #3287 / #3288 / #3294 / #3326; related-open #3332 / #3243.
Plan reviewed and deepened — implementation next: server-side pdfjs-dist text extraction at cold-Query, cc-path allowedTools narrowing to exclude Bash, lock-step prompt-builder parity with the leader path, two follow-through issues filed for safe-bash widening + intent-shaped Bash modal.
```
