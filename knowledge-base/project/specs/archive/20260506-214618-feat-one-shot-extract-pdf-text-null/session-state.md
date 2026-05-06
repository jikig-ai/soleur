# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-extract-pdf-text-null/knowledge-base/project/plans/2026-05-06-fix-extract-pdf-text-null-in-production-plan.md
- Status: complete

### Errors
None

### Decisions
- Root-cause hypothesis (HIGH confidence): cap mismatch between #3337 (24 MB upload cap) and #3338 (15 MB extractor cap). PDFs in [15 MB, 24 MB] band trip `INPUT_BUFFER_CAP_BYTES = 15 MB` at `apps/web-platform/server/pdf-text-extract.ts:31` and return null.
- Phase 2 collapsed to one option: align extractor cap to `MAX_AGENT_READABLE_PDF_SIZE = 24 MB` from `apps/web-platform/lib/attachment-constants.ts:34` (4 live consumers; no new constants file — YAGNI).
- Phase 1 ships unconditionally: discriminated-union return type with failure-class telemetry (`oversized_buffer | lazy_import_failed | encrypted | corrupted | parse_error | empty_text`).
- Phase 3 adds `buildPdfUnreadableDirective` to replace gated directive whenever extractor errors — load-bearing user-brand defense per single-user-incident threshold.
- Hypothesis B (empty-text from scanned PDFs) folded in as same-PR fix — `kb-document-resolver.ts:172` only mirrors null to Sentry, not empty text (`cq-silent-fallback-must-mirror-to-sentry` gap).
- Phase 0 (Sentry event lookup) is gated load-bearing — operator must fetch the actual event payload before code edits begin to confirm or refute Hypothesis A.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Bash, Read, Edit, Write
- Direct codebase verification of pdf-text-extract.ts, kb-document-resolver.ts, soleur-go-runner.ts, kb-preview-metadata.ts, attachment-constants.ts, Dockerfile, package.json
- gh pr view #3338, gh issue view #3346, git show f275007d (#3337)
