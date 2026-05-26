# Tasks: fix(cc-concierge): extractPdfText returned null in production

Plan: `knowledge-base/project/plans/2026-05-06-fix-extract-pdf-text-null-in-production-plan.md`
Branch: `feat-one-shot-extract-pdf-text-null`
Sentry event: `9e0a3888fd3849cd87cb83cdcecca199` (2026-05-06 18:40:45 UTC)

## Phase 0 — Diagnosis

- [x] 0.1 Fetch Sentry event `9e0a3888fd3849cd87cb83cdcecca199` via Sentry MCP (or Playwright MCP against the dashboard if MCP unavailable).
- [x] 0.2 Document the event's `extra.pathBasename`, breadcrumb data (`ok`, `pageCount`, `textBytes`), and any file-size tag in the PR description / plan addendum.
- [x] 0.3 Confirm or refute Hypothesis A (file size > 15 MB and ≤ 24 MB).

## Phase 1 — Failure-class telemetry (always ships)

- [x] 1.1 Define `PdfExtractErrorClass` discriminated-union return type in `apps/web-platform/server/pdf-text-extract.ts`.
- [x] 1.2 Update each `return null` site to return `{ error: <class> }` with the correct class.
- [x] 1.3 Branch in outer catch: `pdfjs.PasswordException` → `encrypted`, `InvalidPDFException` → `corrupted`, else → `parse_error`.
- [x] 1.4 Detect zero-text post-loop → `empty_text` (Hypothesis B fold-in).
- [x] 1.5 Update `apps/web-platform/server/kb-document-resolver.ts` to handle the new shape and pass `errorClass` into `reportSilentFallback.extra` and the Sentry breadcrumb.
- [x] 1.6 Mirror `empty_text` to Sentry distinctly via `op: "extractPdfText.empty_text"`.
- [x] 1.7 Update `apps/web-platform/test/pdf-text-extract.test.ts` to assert new shape on each path; add encrypted-PDF mock test.
- [x] 1.8 Update `apps/web-platform/test/cc-dispatcher-concierge-context.test.ts` to assert `extra.errorClass` and add the new `empty_text` scenario.

## Phase 2 — Cap alignment (Hypothesis A fix)

- [x] 2.1 Locate `#3337`'s upload-cap source-of-truth file (likely `apps/web-platform/server/kb-upload-validator.ts` or similar). Verify exact path during work.
- [x] 2.2 Decide between Option 2a (raise extractor to 24 MB) vs Option 2b (introduce shared `kb-limits.ts` constant and add too-large directive).
- [x] 2.3 Read `apps/web-platform/infra/main.tf` to verify runner instance memory headroom for 400 MB peak RSS at 24 MB input.
- [x] 2.4 Implement chosen option.
- [x] 2.5 Add regression test: synthesized 20 MB PDF extracts successfully (or hits the typed too-large directive on Option 2b).

## Phase 3 — Replace apt-get-cascade fallback

- [x] 3.1 Add `documentExtractError?: PdfExtractErrorClass` to `DispatchArgs` in `apps/web-platform/server/cc-dispatcher.ts`.
- [x] 3.2 Thread `documentExtractError` from `kb-document-resolver.ts` return → `cc-dispatcher.ts` → `realSdkQueryFactory` → `buildSoleurGoSystemPrompt`.
- [x] 3.3 Add `buildPdfUnreadableDirective(path, NO_ASK, errorClass)` helper in `apps/web-platform/server/soleur-go-runner.ts`.
- [x] 3.4 Add new branch in `buildSoleurGoSystemPrompt` that selects `buildPdfUnreadableDirective` over `buildPdfGatedDirective` when `documentExtractError` is set.
- [x] 3.5 Add prompt-builder tests for `oversized_buffer`, `encrypted`, `empty_text`, `corrupted`, `parse_error` — assert directive shape, assert NO `pdftotext` / `apt-get` / `find` / `pdftoppm` substrings.

## Phase 4 — Drift guard and observability

- [x] 4.1 Add `apps/web-platform/test/kb-pdf-cap-alignment.test.ts` — imports both caps, asserts upload ≤ extractor.
- [x] 4.2 Document the `errorClass` breadcrumb shape in `knowledge-base/project/learnings/bug-fixes/<topic>.md` (date picked at write-time per `cq-no-prescribed-dates` sharp-edge equivalent).
- [x] 4.3 (Optional) Configure Sentry alert rule for `kb-concierge-context / extractPdfText*` with 1+/hour threshold for 48h post-merge.

## Phase 5 — Verification

- [x] 5.1 `bun run typecheck` clean.
- [x] 5.2 `bun test` — all PDF and concierge-context tests pass.
- [x] 5.3 Manual QA via Playwright MCP: open the same PDF the user used, attempt summarization, confirm no `apt-get` / `find` modal AND either successful summary OR graceful "I can't read this PDF" reply.
- [x] 5.4 PR body includes `Closes #<TBD>` once issue is filed; threshold is `single-user incident` so apply requires_cpo_signoff.
