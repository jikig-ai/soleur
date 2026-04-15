---
title: Tasks — KB Search Returns Uploaded Files
issue: 2230
branch: feat-kb-search-pdf-uploads
plan: knowledge-base/project/plans/2026-04-15-fix-kb-search-pdf-uploads-plan.md
status: pending
---

# Tasks: KB Search Returns Uploaded Files

Tracks implementation of the fix for #2230 — uploaded PDFs (and other non-.md files) are invisible to KB search because `collectMdFiles` filters on `.md` only.

## 1. Setup

- [ ] 1.1 Confirm worktree is `feat-kb-search-pdf-uploads` and current with `main`.
- [ ] 1.2 Review plan: `knowledge-base/project/plans/2026-04-15-fix-kb-search-pdf-uploads-plan.md`.
- [ ] 1.3 Verify no new deps are needed (`grep pdf-parse apps/web-platform/package.json` — expect empty).

## 2. Failing Tests (TDD Gate — AGENTS.md cq-write-failing-tests-before)

- [ ] 2.1 Open `apps/web-platform/test/kb-reader.test.ts`.
- [ ] 2.2 Delete tests `does not search binary/non-.md files` (line ~358) and `collectMdFiles still returns only .md files` (line ~368) — these encoded the bug.
- [ ] 2.3 Add test `finds binary files by filename match` covering `invoice.pdf` and `diagram.png` with `kind: "filename"` assertion.
- [ ] 2.4 Add test `content-searches .txt and .csv files` asserting `kind: "content"` on matches.
- [ ] 2.5 Add test `does not read binary file bytes for content match` (write bytes containing the query, assert PDF not returned).
- [ ] 2.6 Add test `content matches rank above pure filename matches`.
- [ ] 2.7 Add test `filename match is case-insensitive` (`Q1-Invoice.PDF` matches `invoice`).
- [ ] 2.8 Run `cd apps/web-platform && node node_modules/vitest/vitest.mjs run test/kb-reader.test.ts` — confirm RED on all 5 new tests.

## 3. Core Implementation

- [ ] 3.1 In `apps/web-platform/server/kb-reader.ts`, define module-scoped constants `CONTENT_SEARCHABLE` (`.md/.txt/.csv`) and `FILENAME_SEARCHABLE` (full upload set + `.md`).
- [ ] 3.2 Rename `collectMdFiles` → `collectSearchableFiles`. Return `{ relativePath, ext }[]`. Gate on `FILENAME_SEARCHABLE`.
- [ ] 3.3 Extend `SearchResult` interface with `kind: "content" | "filename"`.
- [ ] 3.4 Add `matchFilename(basename, escapedQuery)` helper returning `SearchMatch[]` using `path.basename(relativePath)` as text; `line: 0`.
- [ ] 3.5 Rewrite `searchKb` loop: run content-search only when `CONTENT_SEARCHABLE.has(ext)`, fall back to filename-match for other types or when content returned zero matches.
- [ ] 3.6 Implement two-pass sort: content results first (by `matches.length` desc), then filename-only results (alphabetical by path).
- [ ] 3.7 Keep `KB_MAX_FILE_SIZE` stat guard and `MAX_SEARCH_RESULTS = 100` cap unchanged.
- [ ] 3.8 Preserve existing regex escape (`escapeRegex`) and per-callback RegExp instantiation (stateful `/g`).
- [ ] 3.9 Run vitest — confirm GREEN on all new tests and all unchanged legacy tests.

## 4. UI Polish

- [ ] 4.1 Edit `apps/web-platform/components/kb/search-overlay.tsx` `SnippetLine` to branch on `kind`. Render "Filename match" label when `kind === "filename"`.
- [ ] 4.2 Pass `kind` into `SnippetLine` from `SearchResultCard`.
- [ ] 4.3 Optional (skip if time-boxed): add file-type icon variant for PDF/image — reuse inline SVG patterns from `file-tree.tsx`. Fallback to existing document icon.

## 5. Regression Guard

- [ ] 5.1 Run full test suite for affected modules:
      `cd apps/web-platform && node node_modules/vitest/vitest.mjs run test/kb-reader.test.ts test/kb-security.test.ts`.
- [ ] 5.2 Grep for `SearchResult` / `SearchMatch` consumers:
      `grep -rn "SearchResult\|SearchMatch" apps/web-platform --include="*.ts" --include="*.tsx"`.
      Confirm TS compiles against the new `kind` field.
- [ ] 5.3 Run `npx tsc --noEmit` in `apps/web-platform` (or the configured lint/typecheck script).

## 6. Manual QA

- [ ] 6.1 Start dev server. Upload `invoice-test.pdf` (or any PDF) via the KB uploader.
- [ ] 6.2 Open KB search, type `invoice-test`. Confirm PDF appears with "Filename match" labeling.
- [ ] 6.3 Upload `data.csv` with a known row. Search a value from the row — confirm CSV returns with line-number snippet.
- [ ] 6.4 Upload a PNG; confirm filename match works and file-icon renders.
- [ ] 6.5 Capture screenshot for the PR body (per AGENTS.md `rf-before-shipping-verify`).

## 7. Ship

- [ ] 7.1 Run `npx markdownlint-cli2 --fix` on any modified `.md` files.
- [ ] 7.2 Run `skill: soleur:compound` (AGENTS.md `wg-before-every-commit-run-compound-skill`).
- [ ] 7.3 `skill: soleur:ship` to enforce full PR workflow, semver label (patch — bug fix), and review gates.
- [ ] 7.4 PR body must include `Closes #2230` (AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] 7.5 Note in PR body: two legacy tests deleted because they encoded the bug.
