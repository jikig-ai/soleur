---
module: cc-soleur-go (Concierge router)
date: 2026-05-06
problem_type: integration_issue
component: server-prompt-builder + sdk-toolset-config
symptoms:
  - "Concierge replies 'environment is missing poppler-utils' on KB PDF chat"
  - "Approve/Deny modal pops with `find . -name \"*.pdf\"` for end users"
  - "Five prior prompt-only fixes (#3253, #3263, #3278, #3287/#3288, #3294) reduced but never eliminated the cascade"
root_cause: prompt_only_mitigation_plateau + sdk_semantics_misread
severity: critical
tags: [pdf, sdk-tooling, prompt-engineering, agent-native, prompt-injection]
related_prs: [3253, 3263, 3278, 3287, 3288, 3294, 3326, 3338]
related_issues: [3346, 3342, 3343, 3344, 3345, 3332, 3243]
---

# Learning: cc-concierge PDF summary cascade — durable structural fix

## Problem

Soleur Concierge (web-platform Knowledge Base view) couldn't reliably summarize PDFs that were already in the user's knowledge-base. Five prior prompt-only fixes layered increasingly assertive directives (a positive baseline directive, an artifact-frame positional pin, a named-binary exclusion list) yet a ~30% reproduction rate persisted in Sentry: the model would emit `apt-get install poppler-utils`, `find . -name "*.pdf"`, or `pip3 install pdfplumber` against its training prior, and the cc-soleur-go path would surface those Bash calls as `review_gate` modals with raw shell strings to non-technical end users.

The user's stated bug-report framing nailed the core breakages:

1. *"It can't find the PDF albeit it's in the knowledge-base."*
2. *"Asking for irrelevant low level technical approval that the user has no clue about."*

## Solution

Two structural changes that, together, close the surface (commit `db8dccda` + review fix-inline `8ced14c9` + P2 follow-up `7019487e`):

### 1. Server-side PDF text extraction at cold-Query construction

`apps/web-platform/server/pdf-text-extract.ts` (new):
- Lazy import `pdfjs-dist@5.4.296/legacy/build/pdf.mjs` (shared cache with `kb-preview-metadata.ts`).
- `isEvalSupported: false`; no `onPassword` callback (encrypted PDFs reject cleanly with `PasswordException`).
- 15 MB input cap (`INPUT_BUFFER_CAP_BYTES`) before parser invocation — refuses oversized buffers without paying the 200-300 MB RSS spike pdfjs-dist exhibits on full-buffer parse.
- **Independent `MAX_PAGES = 500` cap on the page-iteration loop.** Critical: `capChars` halt alone is insufficient because attacker-crafted PDFs can declare 1M empty pages (zero text per page → break never fires). The loop has its own bound.
- `doc.destroy()` in `finally`; `page.cleanup()` in per-iteration finally.
- Returns `null` on any parse failure (caller mirrors to Sentry).

`apps/web-platform/server/kb-document-resolver.ts` PDF branch:
- Reads file as Buffer (NOT utf-8), passes to `extractPdfText`.
- On success, returns `{ artifactPath, documentKind: "pdf", documentContent: text }` so the agent NEVER calls Read.
- On null, falls through to existing Read directive + `reportSilentFallback` mirror with `op: "extractPdfText"`.
- Adds `Sentry.addBreadcrumb({ category: "cc-pdf-extractor", data: { ok, pageCount, truncated, textBytes, pathBasename } })` for observability.

`apps/web-platform/server/soleur-go-runner.ts` `buildSoleurGoSystemPrompt` PDF branch:
- When `documentContent` is non-empty AND ≤50 KB: inline body via the same `<document>...</document>` wrapper the text branch uses — same sanitizer (`/[\x00-\x1f\x7f  ]/g`), same `</document>` escape, same 50 KB cap.
- Append `PDF_INLINE_EXCLUSION_CLAUSE` (named-binary list) as belt-and-suspenders even when body is inlined — last brake if the model gets confused by garbled extraction.
- When body is empty/oversized: fall through to existing `buildPdfGatedDirective` Read path.

### 2. SDK-level Bash hard-block via `disallowedTools`

`apps/web-platform/server/agent-runner-query-options.ts` adds `extraDisallowedTools?: readonly string[]` arg, merged with canonical `[WebSearch, WebFetch]`.

`apps/web-platform/server/cc-dispatcher.ts realSdkQueryFactory` passes:
- `allowedTools: [Read, Glob, Grep, LS, NotebookRead, TodoWrite, ExitPlanMode]` — auto-approve safe tools (avoids canUseTool round-trip).
- `extraDisallowedTools: [Bash, Edit, Write]` — HARD-BLOCK at SDK level. The model can't see these tools at all.

The first iteration of this fix only narrowed `allowedTools`, which the multi-agent review (security/architecture/agent-native) flagged as non-load-bearing — see Key Insight #2.

## Key Insight

### Insight 1 — Prompt iteration plateaus; structural fixes close training-prior cascades

Five PRs of increasingly assertive directives (positive lead, anti-priming guard, exclusion list, positional pin) reduced the failure rate but couldn't eliminate it. The structural alternative — server-side text extraction + SDK toolset hard-block — closes the surface deterministically: the model never has to "find the PDF" because the body is already in the prompt, and even if its training prior wins, Bash isn't in its tool surface to emit.

**Generalization:** When a behavioral fix has plateaued at a non-zero reproduction rate after 3+ iterations, look for the structural reframing — what infrastructure layer can make the wrong path *unreachable* instead of *unattractive*?

### Insight 2 — SDK `allowedTools` is auto-approve, NOT restriction

`@anthropic-ai/claude-agent-sdk@0.2.85 sdk.d.ts:858-862`:
> List of tool names that are auto-allowed without prompting for permission. ... **To restrict which tools are available, use the `tools` option instead.**

`sdk.d.ts:877-882` (`disallowedTools`):
> These tools will be removed from the model's context and cannot be used, even if they would otherwise be allowed.

The plan's deepen-pass cited `sdk.d.ts:1230` for the load-bearing claim "model literally cannot emit Bash" — but that line is in the unrelated `settings/settingSources` section. **Multi-agent review caught the misread before merge.**

**Generalization:** When a plan claims load-bearing SDK semantics, copy the docstring verbatim into the plan. Cite line numbers from the actual relevant section. Multi-agent review reliably catches docstring-paraphrase drift; single-author review does not.

### Insight 3 — Independent cap dimensions for parser DoS

The PDF extractor has TWO independent input dimensions: byte size and page count. A `capChars` halt on extracted text length is necessary but insufficient — a 1 MB PDF declaring 1M empty pages produces 0 chars per page and the cap never fires, but the loop pins the event loop. Multi-agent review (security P1-B) caught this before merge; the fix is `MAX_PAGES = 500` enforced independently, surfaced as `truncated: true` in the breadcrumb.

**Generalization:** When wrapping a parser library, enumerate ALL adversarial input dimensions (size, count, depth, recursion, compression ratio) and cap each independently. A single cap on one dimension leaves the others as DoS vectors.

### Insight 4 — Lock-step parity factories beat substring grep tests

The cc + leader prompt builders MUST stay byte-identical for shared directives. PR #3294 introduced `buildPdfGatedDirective(path, NO_ASK)` as the single source of truth, and `agent-runner-system-prompt.test.ts` asserts `prompt.toContain(factoryOutput)` for byte equality. This invariant survived the new inline-PDF branch addition because both builders import the same factory.

**Generalization:** When two code paths must produce byte-identical output for the same args, extract a shared factory and assert `toContain(factoryOutput)` — not just substring matches. The substring approach drifts silently when wording changes; the factory approach forces both builders to update together.

## Session Errors

1. **pdfjs-dist@5.4.296 explicitly rejects Node Buffer.** First test runs returned null; debug showed `"Please provide binary data as Uint8Array, rather than Buffer."` from `api_utils.js:60`. The pre-existing `kb-preview-metadata.ts:88-90` comment claims "pdfjs accepts Buffer directly" — stale. Recovery: wrap to plain `Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength)` no-copy view. **Prevention:** when adding a second caller of a parser library, verify the type contract via SDK type defs before relying on the first caller's comment. Filed scope-out #3342 to fix `kb-preview-metadata.ts` itself.

2. **SDK `allowedTools` non-load-bearing claim shipped to first commit.** Plan deepen-pass cited the wrong sdk.d.ts line; the implementation passed `allowedTools` thinking it would restrict the model's tool surface. Multi-agent review (3 of 8 agents independently) caught the misread. Recovery: switched to `extraDisallowedTools: [Bash, Edit, Write]` + updated T6b test to assert against `disallowedTools`. **Prevention:** plan/deepen-plan skills should add a "copy docstring verbatim" verification for any SDK semantics claim. Multi-agent review at PR time is the durable safety net — single-author review would have shipped the broken fix.

3. **Edit tool silently rewrote `  ` regex escape sequence to actual U+2028/U+2029 bytes** in soleur-go-runner.ts line 553, causing esbuild to emit "Unterminated regular expression" because U+2028 is a JS line terminator that ends a regex literal. Rule `cq-regex-unicode-separators-escape-only` already documents this. Recovery: byte-replaced via Python to restore the escape notation. **Prevention:** the rule already exists; consider a PreToolUse hook that scans Edit/Write `new_string` for literal U+2028/U+2029 inside `/.../` regex character classes and rejects.

4. **Resolver `_workspacePathCache` leaked across tests** using same userId "u1" — pre-existing tests passed for the wrong reason because each `beforeEach` created a new tmpRoot but the cache returned the OLD tmpRoot. New PDF tests (which actually depend on the read succeeding) exposed this. Recovery: added `_resetWorkspacePathCacheForTests()` to `beforeEach`. **Prevention:** when extending a test file that exercises a module with module-level caches, scan for cache-reset helpers and call them in `beforeEach`. The test-design reviewer flagged this as a latent test-isolation bug fixed as a side effect.

5. **Synthesized PDF "password-protected" fixture infeasible.** Tried to test the `PasswordException` path but synthesizing valid encrypted PDFs requires implementing RC4/AES-128 + key derivation — disproportionate scope. Recovery: collapsed to a "mid-stream-truncated body" test (same code path: any pdfjs reject → caught → null) with explicit comment about scope; renamed test to match actual behavior. **Prevention:** when a test name overstates coverage, rename to actual behavior with a comment about what's NOT covered. Aspirational naming is a worse anti-pattern than collapsed scope.

6. **Initial "control-char strip" assertion false-fired** because the regex `/[\x00-\x1f\x7f]/` includes `\n` (0x0a) and the wrapper template has legitimate newlines. Recovery: scoped the regex to `/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/`. **Prevention:** when asserting "control chars stripped" on a string built from a template, exclude template-introduced legit chars (\n\r\t).

7. **`gh pr view` returned HTTP 504** during review setup. Recovery: fell through to git metadata. **Prevention:** add retry-with-backoff to gh API calls or rely on git for branch metadata when possible.

## Tags
category: integration_issue
module: cc-soleur-go
