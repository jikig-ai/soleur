# Tasks — fix(server): bound three CodeQL http↔file flows (alerts #215, #230, #280)

Plan: `knowledge-base/project/plans/2026-11-03-fix-codeql-http-file-access-batch-plan.md`

## Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

- [ ] 1.1 `apps/web-platform/test/server/inngest/cron-safe-commit.test.ts`: `config.prBody` > `MAX_PR_BODY_CHARS` → POST body ≤ cap, ends with the `⚠️ … truncated` marker, and `reportSilentFallback` sees `safe-commit-pr-body-truncated`.
- [ ] 1.2 `apps/web-platform/test/c4-stage-sources.test.ts`: mismatched `known`/cache buffer (right key, wrong bytes / wrong size) → `blob integrity mismatch` `io_error` refusal, no file written; happy-path stage still passes (Guard 1 rows 1–6).
- [ ] 1.3 `apps/web-platform/test/server/inngest/cron-compound-promote-draft-edit.test.ts`: assembled text over the derived cap → `fail("too-large")` before any scratch write.
- [ ] 1.4 Confirm all three new tests FAIL against the unmodified source (red).

## Phase 2 — Fixes

- [ ] 2.1 `_cron-safe-commit.ts`: add `MAX_PR_BODY_CHARS = 60_000`; cap the assembled `prBody` (after `prBodyExtras` join) with the loud-truncation marker + `reportSilentFallback` op `safe-commit-pr-body-truncated`. (alert #215)
- [ ] 2.2 `c4-stage-sources.ts`: immediately before `writeFile(target, buf, …)`, assert `buf.length === s.size && gitBlobSha(buf) === s.sha` → `StageAbort` `io_error` `blob integrity mismatch`. Covers fetch + `cacheGet` + `known` provenance uniformly. (alert #230)
- [ ] 2.3 `cron-compound-promote.ts` `deriveDiff`: compute assembled size (`base.length` + `Σ newLines.length` + 1) and `return fail("too-large")` before the scratch `writeFile` loop when > `EDIT_TARGET_MAX_BYTES + EDIT_NEW_LINES_MAX * SKILL_EDIT_LINE_MAX_CHARS`. (alert #280)

## Phase 3 — Verification

- [ ] 3.1 All new tests green; run the three touched test files.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (the repo-prescribed typecheck form — never `npm run -w typecheck`).
- [ ] 3.3 Affected-suite run per work Phase gates; record which commit the full run covered.

## Phase 4 — Disposition bookkeeping

- [ ] 4.1 PR body: per-alert table (alert / rule / sink / fix applied / residual disposition) + `Reviewed-Coverage: sequential-fallback` + `Closes` line NOT used (no tracker issues — cite alert numbers only, medium severity).
- [ ] 4.2 If any alert remains open post-merge, the PR body notes it as mitigated-not-dismissed (operator sign-off required to dismiss).
- [ ] 4.3 Commit author: Jean Deruelle <jean.deruelle@jikigai.com> — never `devin-ai-integration[bot]`.
