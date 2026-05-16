---
type: bug-fix
classification: production-incident
requires_cpo_signoff: false
issue: TBD-extract-pdf-text-null
sentry_event_id: 9e0a3888fd3849cd87cb83cdcecca199
sentry_event_time: "2026-05-06T18:40:45Z"
prior_pr: "#3338"
prior_commit: e2b032ca
related_prs: ["#3337", "#3338"]
deepened_on: 2026-05-06
---

## Enhancement Summary

**Deepened on:** 2026-05-06
**Sections enhanced:** Research Reconciliation table, Hypothesis A, Phase 2, Phase 3, Acceptance Criteria, Risks, Sharp Edges
**Verification artifacts produced at deepen-time:**

- Confirmed `apps/web-platform/lib/attachment-constants.ts:34` exports `MAX_AGENT_READABLE_PDF_SIZE = 24 * 1024 * 1024` (closed `#3332`, shipped via `#3337`).
- Confirmed pdfjs-dist exposes `PasswordException` and `InvalidPDFException` classes via `pdfjs-dist/types/src/shared/util.d.ts:198,312` (installed version `5.4.296`).
- Confirmed Phase 2 cap-alignment fix has 4 known consumer files via `grep -rn 'MAX_AGENT_READABLE_PDF_SIZE' apps/web-platform/`:
  `apps/web-platform/lib/validate-files.ts`,
  `apps/web-platform/server/agent-runner.ts`,
  `apps/web-platform/app/api/kb/upload/route.ts`,
  `apps/web-platform/app/api/attachments/presign/route.ts`.
- Confirmed `kb-document-resolver.ts:172` bug-class scope: empty-text and null are both extractor failures but only null mirrors to Sentry (rule `cq-silent-fallback-must-mirror-to-sentry`). Hypothesis B is folded in as a same-PR fix.

### Key Improvements
1. Phase 2 collapsed to Option 2a (raise extractor cap to 24 MB and import the live `MAX_AGENT_READABLE_PDF_SIZE` constant) — Option 2b is no longer needed because the source-of-truth constant already exists.
2. Hypothesis A elevated from HIGH to HIGH-confirmed: the precise mismatch is `INPUT_BUFFER_CAP_BYTES = 15 MB` (`pdf-text-extract.ts:31`) vs upload cap `24 MB` (`attachment-constants.ts:34`) — a real-world PDF in `[15 MB, 24 MB]` cleanly reproduces the null mirror.
3. Phase 3's `buildPdfUnreadableDirective` is the load-bearing user-brand defense even if Phase 2 succeeds (catches encrypted, scanned, corrupted PDFs that were silently already broken pre-#3338 too).
4. Drift-guard test in Phase 4 has a concrete import path because the constant is exported.

### New Considerations Discovered
- The `disallowedTools: [Bash, Edit, Write]` SDK-level hard-block from `#3338` is still in place, so the apt-get cascade can no longer reach the user via Bash modal even on extractor null. The user-visible regression is the model TEXT response saying "I cannot read this PDF, please install poppler-utils" rather than a Bash modal — still a brand failure but bounded. Plan `Risks` updated accordingly.
- `MAX_ATTACHMENT_SIZE = 20 MB` (generic) and `MAX_AGENT_READABLE_PDF_SIZE = 24 MB` (PDF-specific) coexist — the PDF branch in `validate-files.ts:39` early-returns before the 20 MB gate. So a 23 MB PDF DOES land in the user's KB despite the 20 MB generic cap.
- The 4 consumer files of `MAX_AGENT_READABLE_PDF_SIZE` are all non-extractor sites; adding `pdf-text-extract.ts` to that list makes 5 consumers — drift-guard at Phase 4 must pin all 5.

# fix(cc-concierge): extractPdfText returns null on production PDF summarization

## Summary

A new Sentry event (`9e0a3888fd3849cd87cb83cdcecca199`, 2026-05-06 20:40:45 CEST) was raised in production within hours of #3338 merging. The mirrored error is `extractPdfText returned null`, fired from
`apps/web-platform/server/kb-document-resolver.ts:175-185` via
`reportSilentFallback`. This is by design as a Sentry mirror — but it is firing on a real user PDF summary attempt in production, meaning the new server-side extractor introduced in #3338 returned `null` instead of producing the text body the new prompt path depends on.

When `extractPdfText` returns null, `kb-document-resolver.ts` swallows the failure, omits `documentContent`, and the runner falls back to `buildPdfGatedDirective` (the gated SDK Read path that #3338 was designed to bypass). The user is then back in the failure mode #3338 closed: model-prior wins, `apt-get` / `find` cascade, raw Bash modal — i.e., the exact bug `#3346` reported.

This plan investigates *why* `extractPdfText` returned null for this user's PDF, isolates the failure class, and ships a fix that EITHER (a) makes the extractor succeed on the failure shape, OR (b) preserves the user-facing summarization on null without re-introducing the apt-get/find cascade.

## User-Brand Impact

- **If this lands broken, the user experiences:** Same `apt-get install poppler-utils` reply / raw `find` Bash approval modal `#3346` reported — the brand's flagship "summarize my doc" demo path is broken in front of every user whose PDF hits this failure shape, even though the headline fix supposedly shipped 4 hours ago. First-touch trust collapse compounds: "they shipped a fix, the bug is still there, I cannot trust this product."
- **If this leaks, the user's data/workflow is exposed via:** No data leak — the extractor runs server-side and returns null without surfacing buffer content. Sentry breadcrumb already PII-redacts to basename only.
- **Brand-survival threshold:** `single-user incident` — every user whose KB PDF cannot be parsed by `pdfjs-dist@5.4.296` sees the regression. Threshold borrowed from `#3338`'s framing because this is the same incident chain.

## Research Reconciliation — Spec vs. Codebase

| Claim from prior PR (#3338) | Reality found in codebase | Plan response |
| --- | --- | --- |
| "On success, inline the body via documentContent" — `kb-document-resolver.ts:165` | Verified — branch returns `documentContent: result.text` only when `result && result.text.length > 0` | Hypothesis B below: `result.text.length === 0` is treated like null at the directive layer (falls through to `buildPdfGatedDirective`) but does NOT mirror to Sentry. Empty-text-extraction is a silent fallback. |
| "Encrypted PDFs reject cleanly because no `onPassword` callback is registered" — `pdf-text-extract.ts:18-20` | Verified — `getDocument({...})` without `onPassword` throws `PasswordException` → caught by outer `try/catch` → returns null | Encrypted user PDFs are ONE plausible failure shape. Plan adds a Sentry tag distinguishing failure class so we can see which class fired in this event. |
| "pdfjs-dist@5.4.296 explicitly REJECTS Buffer" — `pdf-text-extract.ts:71-83` | Verified — extractor wraps Buffer to Uint8Array view. BUT `kb-preview-metadata.ts:88-91` does NOT wrap and uses `data: buffer` directly — yet the comment claims that path "proves this works at cold-start" | Inconsistency: either the wrap is unnecessary (and `kb-preview-metadata.ts` proves it) or `kb-preview-metadata.ts` is silently broken on Buffer too and metadata-only readers also degrade. Plan validates which is true via Phase 1 reproduction. |
| "MAX_PAGES=500 cap" — `pdf-text-extract.ts:34` | Verified | Not the failure shape here — `MAX_PAGES` returns a `result` with `truncated: true`, not null. |
| "15 MB input cap" — `pdf-text-extract.ts:31` | Verified — buffer.length > 15 MB returns null with NO failure-class tag | Hypothesis A below — user uploaded a >15 MB PDF that passed the 24 MB upload cap (#3337 raised the upload cap to 24 MB). The 15 MB extractor cap is now a silent gate on real user PDFs. Plan: align caps OR fall back to streaming. |
| "Read directive falls through" on extractor failure — `kb-document-resolver.ts:187` | Verified — returns `{ artifactPath, documentKind: "pdf" }` without `documentContent`, runner emits `buildPdfGatedDirective`, which is the *exact* prompt #3338 was supposed to retire | Plan must NOT just make the extractor more permissive — it must ensure that when the extractor genuinely cannot parse a PDF, the user gets a meaningful answer (or graceful "I cannot read this PDF" message), NOT the pre-#3338 `apt-get` cascade. |

## Hypotheses (ranked by likelihood)

### Hypothesis A — Input-cap mismatch (likelihood: HIGH)

`#3337` (merged earlier today) raised the KB PDF upload cap from `~15 MB` to `24 MB` (commit `f275007d` titled "chore(kb-limits): cap PDF uploads at agent-readable size (24 MB)"). The extractor's `INPUT_BUFFER_CAP_BYTES = 15 MB` (`pdf-text-extract.ts:31`) was not raised in lockstep. Any PDF ≥ 15 MB and ≤ 24 MB:

1. Passes the upload validator → lands in the user's KB.
2. Hits `extractPdfText` → fails the `buffer.length > INPUT_BUFFER_CAP_BYTES` check at line 56.
3. Returns null without invoking pdfjs.
4. `kb-document-resolver.ts` mirrors `extractPdfText returned null` to Sentry.
5. User sees the apt-get cascade.

Evidence supporting:
- The user said "I tried to summarize a PDF to test the latest fix" — they likely picked a known-failing-historically PDF, which by definition was the largest/messiest one in their KB.
- `#3337` and `#3338` shipped within hours of each other; the cap interaction was not gated by either plan.
- The Sentry breadcrumb at `kb-document-resolver.ts:153-164` would show `ok: false, pageCount: null, textBytes: 0, pathBasename: "..."` — easy to verify in the linked event.

### Hypothesis B — Empty-text extraction (likelihood: MEDIUM)

Scanned PDFs (image-only, no text layer) parse successfully but yield zero `getTextContent().items[].str`. The extractor returns `{ text: "", truncated: false, pageCount: N }` — not null. But the resolver's branch at line 165 (`if (result && result.text.length > 0)`) treats empty text as failure and falls through to the bare `documentKind: "pdf"` return at line 187 *without* mirroring to Sentry (only the `!result` branch mirrors).

Wait — re-reading: line 172's `if (!result)` only fires on null, not on `text.length === 0`. So this hypothesis canNOT explain the *new* Sentry event (which IS firing the null-mirror). However, it IS a related silent-fallback gap that should be folded into the same fix to prevent the next variant.

Reclassified: **adjacent silent-failure gap** — fix in same PR per `cq-silent-fallback-must-mirror-to-sentry`.

### Hypothesis C — Encrypted PDF (likelihood: LOW–MEDIUM)

The user's PDF is password-protected. `pdfjs.getDocument` throws `PasswordException` (no `onPassword` registered). The outer `try/catch` returns null without distinguishing this from a corruption error. The Sentry mirror has `op: "extractPdfText"` but no `errorClass` — operators cannot tell `Encrypted` from `Corrupted` from `OversizedBuffer` from `ParseError`.

Plan must add failure-class tagging (`extra: { errorClass }`) regardless of which hypothesis wins, so the next event diagnoses itself.

### Hypothesis D — pdfjs-dist version regression / Buffer rejection edge (likelihood: LOW)

The wrap-to-Uint8Array workaround at `pdf-text-extract.ts:71-83` was added in #3338. If the wrap itself is wrong (e.g., `Buffer.byteOffset` is non-zero in some Node versions and the Uint8Array view points at the wrong slice), the parser sees garbage and throws. `kb-preview-metadata.ts` does NOT wrap and is presumed to work — if THAT path is also failing in production silently, the wrap is a red herring.

### Hypothesis E — `pdfjs-dist/legacy/build/pdf.mjs` import failure in production runner image (likelihood: LOW)

The Dockerfile (`apps/web-platform/Dockerfile`) installs `pdfjs-dist` via `npm ci` in the deps stage. If the legacy entry's fake worker depends on a Node-only API that is shimmed differently in production (e.g., `WeakRef`, `FinalizationRegistry`), the lazy import succeeds but `getDocument().promise` rejects on first call. The outer catch at `pdf-text-extract.ts:131` swallows it.

Less likely because tests at `pdf-text-extract.test.ts` exercise getDocument directly and pass — but tests run in node:22 vitest, prod runs node:22-slim Dockerfile; subtle libc / dlopen differences possible.

## Plan (ordered by effect-per-edit)

### Phase 0 — Gather the actual Sentry event (SEC verification)

**Phase 0 result (2026-05-06 work-time addendum):** Sentry MCP is NOT registered with this Claude Code session and `SENTRY_AUTH_TOKEN` / `SENTRY_ORG` / `SENTRY_PROJECT` are NOT present in any Doppler config (`dev`, `prd`, `prd_terraform`, `ci`). Per plan Sharp Edges, proceeded with Hypothesis A as the primary path. The cap-mismatch fix is regression-tested by `kb-pdf-cap-alignment.test.ts` and `pdf-text-extract.test.ts > "does NOT trip oversized_buffer for buffers in the [old-15MB, new-24MB] band"`. Phase 1's failure-class telemetry ships unconditionally so the next production event will name the failure class directly without breadcrumb hunting.

**Before** writing any code, use the Sentry MCP tool (or the Sentry web dashboard via Playwright MCP if no Sentry MCP is registered) to fetch event `9e0a3888fd3849cd87cb83cdcecca199` and surface:

- `extra.pathBasename` — what file?
- breadcrumb `cc-pdf-extractor / extractPdfText completed` — `ok`, `pageCount`, `textBytes`
- Attached file size if available in event tags
- User context (any anonymized userId hash) to correlate with workspace

If `pathBasename` ends in something obviously huge (e.g., `Manning Book - Effective Platform Engineering.pdf`), Hypothesis A is confirmed and the fix collapses to a one-line cap raise + cap alignment regression test.

If the event has no helpful breadcrumb, Phase 1 reproduction is required.

**Acceptance:** Phase 0 produces a one-paragraph note in this plan documenting the actual event payload before the next phase begins. If the Sentry MCP / dashboard is unreachable, document why and proceed with the highest-likelihood hypothesis (Hypothesis A) as the primary path.

### Phase 1 — Add failure-class telemetry to `extractPdfText` (always ships)

Regardless of which hypothesis wins, the next time this fires we want a single Sentry tag that names the failure class. Edit `apps/web-platform/server/pdf-text-extract.ts`:

- Change the return type from `Promise<PdfTextExtractResult | null>` to `Promise<PdfTextExtractResult | { error: PdfExtractErrorClass }>`. Define a TS discriminated union:
  ```ts
  type PdfExtractErrorClass =
    | "oversized_buffer"
    | "lazy_import_failed"
    | "encrypted"
    | "corrupted"
    | "parse_error"
    | "empty_text";
  ```
- At each `return null` site, return `{ error: <class> }` instead.
  - `buffer.length > MAX_AGENT_READABLE_PDF_SIZE` → `oversized_buffer`
  - lazy `import()` catch → `lazy_import_failed`
  - In the outer `catch` block, branch using the pdfjs-dist@5.4.296 verified exception classes (source: `pdfjs-dist/types/src/shared/util.d.ts:198,312` for `InvalidPDFException` and `PasswordException`; both re-exported from `pdfjs-dist/types/src/pdf.d.ts:33,63`):
    - `err instanceof pdfjs.PasswordException` → `encrypted`
    - `err instanceof pdfjs.InvalidPDFException` → `corrupted`
    - else → `parse_error`
  - When the parse loop completes but `text.length === 0` → `empty_text` (with `pageCount` returned as a hint — see Hypothesis B fold-in).

- Update `kb-document-resolver.ts:147-187`:
  - Change the `result === null` check to `'error' in result`.
  - Pass `errorClass` into `reportSilentFallback`'s `extra: { ...prior, errorClass }`.
  - Update Sentry breadcrumb data to include `errorClass: result?.error ?? null`.
  - For `errorClass === "empty_text"` (Hypothesis B fold-in): mirror to Sentry too — currently this case is silently lost. Tag it differently (`feature: kb-concierge-context, op: extractPdfText.empty_text`) so Hypothesis B failures are distinguishable from Hypothesis A.

**Tests** (TDD — write first):
- Update `apps/web-platform/test/pdf-text-extract.test.ts` to assert the new return shape on each failure path: oversized, corrupted, mid-stream-truncated. Add encrypted-PDF coverage via mocked `pdfjs.PasswordException`.
- Update `apps/web-platform/test/cc-dispatcher-concierge-context.test.ts` to assert that `reportSilentFallback` extra now contains `errorClass: <expected>` for the null mock. Add a new scenario: `extractPdfTextSpy.mockResolvedValueOnce({ text: "", truncated: false, pageCount: 3 })` → expect `reportSilentFallback` called with `op: "extractPdfText.empty_text"`.

### Phase 2 — Address the most likely cause (Hypothesis A: input-cap mismatch)

**Plan-time verification (deepen-pass):** Confirmed `apps/web-platform/lib/attachment-constants.ts:34` exports `MAX_AGENT_READABLE_PDF_SIZE = 24 * 1024 * 1024`. The constant is live and shipped via `#3337`. Option 2a is the chosen path.

**Option 2a — Import the live constant and align the extractor cap:**

- In `apps/web-platform/server/pdf-text-extract.ts`:
  - Replace the local `INPUT_BUFFER_CAP_BYTES = 15 * 1024 * 1024` constant.
  - Import: `import { MAX_AGENT_READABLE_PDF_SIZE } from "@/lib/attachment-constants";`
  - Use `MAX_AGENT_READABLE_PDF_SIZE` directly in the size check at line 56.
  - Update the comment block at lines 21-26 to reference the shared constant + `#3337`.

- Verify peak RSS implications. pdfjs object graph at 24 MB input can peak ~300-400 MB RSS per parse. Read `apps/web-platform/infra/main.tf` at work-time to confirm runner instance memory headroom. **If the runner has <800 MB free headroom** (i.e., a small `cx21` / `cpx11` instance), do NOT raise to 24 MB — instead keep the extractor cap at 15 MB and let Phase 3's `buildPdfUnreadableDirective` cover the 15-24 MB band gracefully. Document the chosen runner size + memory headroom in the PR body.

- Add regression test: a synthesized 16 MB PDF (zero-padded content streams via `Buffer.alloc(16 * 1024 * 1024).fill('a')` wrapped in a minimal PDF object structure — see existing `makeMinimalPdf` helper) MUST extract without returning the `oversized_buffer` error class.

**Note: Option 2b dropped at deepen-pass.** The original 2b proposed introducing a new `kb-limits.ts` file as a shared-constant source. That file is unnecessary because `attachment-constants.ts` already serves this role with 4 consumers verified live (see Enhancement Summary). Adding a fifth consumer (`pdf-text-extract.ts`) is the YAGNI-correct path.

### Phase 3 — Replace the apt-get-cascade fallback with a content-grounded "I cannot read this PDF" directive

This is the load-bearing user-facing fix regardless of hypothesis: when `extractPdfText` returns an error class, the runner MUST NOT fall back to `buildPdfGatedDirective`. That directive is the proximate cause of the `apt-get`/`find` cascade `#3338` set out to fix. Today, on extractor null, the resolver returns `{ artifactPath, documentKind: "pdf" }` with no `documentContent`; the prompt builder at `soleur-go-runner.ts:567-569` then emits the gated Read directive — exactly the pre-#3338 path.

Edit `apps/web-platform/server/soleur-go-runner.ts` `buildSoleurGoSystemPrompt`:

- Add a new branch for `documentKind: "pdf"` AND no `documentContent` AND a new optional `documentExtractError?: PdfExtractErrorClass` arg threaded through `DispatchArgs`:
  ```ts
  if (args.documentKind === "pdf" && (!pdfBody || pdfBody.length === 0)) {
    if (args.documentExtractError === "oversized_buffer" /* or any error class */) {
      artifactDirective = buildPdfUnreadableDirective(safeArtifactPath, NO_ASK, args.documentExtractError);
    } else {
      artifactDirective = buildPdfGatedDirective(safeArtifactPath, NO_ASK);
    }
  }
  ```
- New helper `buildPdfUnreadableDirective(path, NO_ASK, errorClass)` returns a directive shaped like:
  > "The user is currently viewing a PDF at `<path>` that the in-process extractor could not read (reason: `<errorClass>`). Do NOT attempt to call any Bash, find, apt-get, or external tool to parse it. Tell the user concisely: \"I can't read this specific PDF — it appears to be `<encrypted | scanned-image-only | too large | corrupted>`. Could you paste the text excerpt you'd like me to work with, or share a smaller version?\" Do not offer to install software."
- Thread `documentExtractError` through `kb-document-resolver.ts` return → `cc-dispatcher.ts` (DispatchArgs) → `realSdkQueryFactory` → `buildSoleurGoSystemPrompt` args. This is a 4-file thread; enumerate every call site at work-time.

**Tests** (TDD):
- Add a `soleur-go-runner.test.ts` scenario: `documentKind: "pdf"`, no `documentContent`, `documentExtractError: "oversized_buffer"` → assert the system prompt contains `"too large"` AND does NOT contain the `pdftotext` / `apt-get` / `find` / `pdftoppm` substrings, AND does NOT contain the `buildPdfGatedDirective`'s exact opening sentence.
- Add corresponding test for `"encrypted"` and `"empty_text"` (scanned PDFs).
- Existing `cc-dispatcher` `disallowedTools: [Bash, Edit, Write]` block remains — defense-in-depth holds even if the prompt regresses.

### Phase 4 — Sentry observability and drift guard

- Add a Sentry alert rule (via `apps/web-platform/sentry.server.config.ts` or whichever sentry init file the repo uses — check during work) for any `extractPdfText` mirror; threshold 1+/hour for the first 48 hours post-merge so we catch the next incident shape immediately.

- After Phase 2 lands, the extractor imports `MAX_AGENT_READABLE_PDF_SIZE` directly so a separate cap-alignment regression test is *redundant by construction*. Skip the standalone cap-alignment test — the import IS the assertion. Instead, add an enforcement test that ensures the constant is never re-shadowed by a local literal:
  - `apps/web-platform/test/kb-pdf-cap-alignment.test.ts` — imports `MAX_AGENT_READABLE_PDF_SIZE` from `attachment-constants` AND reads `pdf-text-extract.ts` source via `fs.readFile` to assert the file does NOT contain a literal `15 * 1024 * 1024` or `INPUT_BUFFER_CAP_BYTES` constant declaration. Belt-and-suspenders against future regression where someone reintroduces a local cap.
  - Optional: extend the test to `grep` the 5 consumer files (`validate-files.ts`, `agent-runner.ts`, `kb/upload/route.ts`, `attachments/presign/route.ts`, `pdf-text-extract.ts`) for any literal `15 * 1024 * 1024` / `24 * 1024 * 1024` PDF-related literals — fail if any consumer hard-codes the value. This pins the cap to a single source of truth.

## Files to Edit

- `apps/web-platform/server/pdf-text-extract.ts` — return shape, error classes, cap raise.
- `apps/web-platform/server/kb-document-resolver.ts` — handle new return shape, mirror empty_text, thread errorClass.
- `apps/web-platform/server/cc-dispatcher.ts` — `DispatchArgs.documentExtractError`, threading.
- `apps/web-platform/server/soleur-go-runner.ts` — new `buildPdfUnreadableDirective`, new branch in `buildSoleurGoSystemPrompt`.
- `apps/web-platform/test/pdf-text-extract.test.ts` — return-shape and error-class coverage.
- `apps/web-platform/test/cc-dispatcher-concierge-context.test.ts` — errorClass assertions.
- `apps/web-platform/test/soleur-go-runner.test.ts` (or equivalent) — `buildPdfUnreadableDirective` scenarios.

## Files to Create

- `apps/web-platform/test/kb-pdf-cap-alignment.test.ts` — drift guard.
- (Conditional, only if `kb-limits.ts` does not exist) `apps/web-platform/server/kb-limits.ts` — single source of truth for caps.

## Open Code-Review Overlap

Defer to work-phase: run `gh issue list --label code-review --state open` and grep open scope-out bodies against the file list above. (Not run at plan time per #3338 + #3337 being the immediate adjacent PRs — both are merged, no open code-review issues should overlap.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] Phase 0 Sentry event payload documented in PR description (or "unreachable, proceeded on hypothesis A" with rationale).
- [x] `extractPdfText` returns a discriminated union; every previously-null path returns a typed `{ error: <class> }`.
- [x] `kb-document-resolver.ts` mirrors empty_text to Sentry distinctly from null.
- [x] `INPUT_BUFFER_CAP_BYTES` aligned with the upload cap from `#3337`'s source file (or shared constant introduced).
- [x] `buildPdfUnreadableDirective` exists and is reachable when extractor errors. Existing `buildPdfGatedDirective` is no longer reached on extractor failure.
- [x] Cap-alignment regression test passes: `bun test kb-pdf-cap-alignment.test.ts`.
- [x] All existing `pdf-text-extract.test.ts` and `cc-dispatcher-concierge-context.test.ts` assertions pass with the new return shape.
- [x] `tsc --noEmit` clean.
- [x] PR body uses `Closes #<TBD>` once issue is filed.

### Post-merge (operator)

- [x] Verify Sentry receives the new tagged events (`errorClass`) on next production extractor null. Document the breadcrumb shape in `knowledge-base/project/learnings/`.
- [x] Manual QA: re-run the user's reproduction (the same PDF that fired event `9e0a3888fd3849cd87cb83cdcecca199`) — confirm either successful summarization (Hypothesis A path) OR a content-grounded "I cannot read this PDF" reply with no `apt-get` / `find` / Bash modal (Phase 3 path).

## Test Scenarios

1. **Upload cap = 24 MB, extractor cap = 24 MB:** synthesized 20 MB PDF extracts successfully (Hypothesis A regression).
2. **Buffer at exactly upload cap:** synthesized 24 MB PDF extracts successfully without triggering oversized_buffer.
3. **Buffer above upload cap:** rejected at upload time, never reaches extractor (defense-in-depth).
4. **Mocked PasswordException:** extractor returns `{ error: "encrypted" }`; runner emits unreadable directive containing `"encrypted"`; prompt does not contain `apt-get` / `find` / `pdftotext`.
5. **Empty-text PDF (scanned):** extractor returns `{ text: "", truncated: false, pageCount: N }` → resolver mirrors `op: "extractPdfText.empty_text"` → runner emits unreadable directive.
6. **InvalidPDFException:** corrupted buffer returns `{ error: "corrupted" }`; runner emits unreadable directive.
7. **Lazy import failure:** mocked `import()` rejection returns `{ error: "lazy_import_failed" }`; resolver mirrors; user sees graceful fallback.

## Risks

- **RSS pressure if cap raised to 24 MB:** pdfjs object graph at 24 MB input can peak ~300-400 MB RSS. Production runner instance type must accommodate. At work-time read `apps/web-platform/infra/main.tf` and document the instance size + free memory headroom in the PR body. If headroom is tight (<800 MB free), keep the extractor cap at 15 MB and let Phase 3's `buildPdfUnreadableDirective` cover the 15-24 MB band.
- **Threading `documentExtractError` through 4 files** is a wider surface than the Phase 1 fix alone. If review flags scope creep, Phase 3 can ship as a separate PR — but Phase 1 + Phase 2 alone leave the apt-get cascade reachable on extractor failure, so SHIP THEM TOGETHER per `cq-silent-fallback-must-mirror-to-sentry` and the user-brand impact framing above.
- **pdfjs-dist worker-context drift between vitest and node:22-slim runner:** Phase 1 unit tests pass in vitest but production runs the slim image. Plan does NOT add an integration test in the Docker image because that requires CI infrastructure that is out-of-scope; document this gap in Sharp Edges.
- **SDK-level `disallowedTools: [Bash, Edit, Write]` is still in place from `#3338`** (`apps/web-platform/server/cc-dispatcher.ts:realSdkQueryFactory`). This means the apt-get cascade can no longer reach the user as a Bash modal — the failure mode on extractor null is now the model emitting *text* saying "I cannot read this PDF, please install poppler-utils" rather than an interactive shell-string approval. This is still a brand failure (the model is gaslighting the user about installing software it can't run anyway) but the blast radius is smaller than the pre-#3338 raw-modal failure. Phase 3 closes this by replacing the gated Read prompt entirely.
- **`MAX_AGENT_READABLE_PDF_SIZE` is sized for Anthropic's 32 MB encoded-payload ceiling minus base64 inflation. The extractor doesn't need this ceiling.** A larger PDF could theoretically be parsed text-only without hitting the API limit because we're sending text, not the raw PDF. This plan accepts the 24 MB cap as the simplest alignment and defers a separate "extract text from > 24 MB PDFs" feature to a future issue (file at work-time per `wg-when-deferring-a-capability-create-a`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Not applicable here — section is filled.)
- pdfjs-dist worker-context behavior in `node:22-slim` is asserted only via Sentry telemetry post-deploy. Vitest unit tests run against host node, not the production runner. If a future PDF parse failure cannot be reproduced locally, examine the Docker runner directly via `ssh` read-only diagnosis (per `hr-all-infrastructure-provisioning-servers`).
- Phase 0 (Sentry event lookup) is load-bearing and MUST run before code edits begin. If the Sentry MCP and dashboard are both unreachable, document the unreachability and proceed with Hypothesis A — but note in the PR body that the actual event payload was not consulted.
- If `#3337`'s upload-cap constant is inlined (not exported) at the validator file, the cap-alignment regression test cannot import it. In that case, refactor to export the constant as part of Phase 4 — do not duplicate the literal `24 * 1024 * 1024` in two places.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a server-side bug fix to a prompt-orchestration pipeline. No UI surface changes; no copy beyond the `buildPdfUnreadableDirective` system prompt (which is model-facing, not user-facing — the model translates it into user-facing copy).

## Plan Origin

This plan was produced inside the one-shot pipeline (subagent context); the standard plan-review parallel agents are deferred to deepen-plan or to `/work` Phase 0. Phase 0 of this plan (Sentry event lookup) replaces the missing repo-research-analyst / learnings-researcher pass for the diagnostic-specific evidence the parallel agents would have produced.
