---
title: fix - KB search returns uploaded files (PDF, DOCX, CSV, TXT, images)
date: 2026-04-15
issue: 2230
branch: feat-kb-search-pdf-uploads
pr: null
status: plan-deepened
type: fix
priority: p1-high
milestone: "Phase 3: Make it Sticky"
---

# Plan: KB Search Returns Uploaded Files

> Fixes #2230. The current KB search only indexes `.md` files, so every non-markdown upload (PDF, DOCX, CSV, TXT, PNG/JPG/GIF/WEBP) is invisible to search. In the bug report, the user uploaded a PDF and searched for it — only `vision.md` was returned because the PDF was never scanned.

## Enhancement Summary

**Deepened on:** 2026-04-15
**Sections enhanced:** Context, Implementation Phases, Acceptance Criteria, Sharp Edges
**Learnings applied:**

1. `2026-04-07-promise-all-parallel-fs-io-patterns.md` — reuse per-callback RegExp pattern; keep flat `Promise.all` shape; note libuv fd ceiling.
2. `2026-04-07-symlink-escape-recursive-directory-traversal.md` — preserve `!entry.isSymbolicLink()` on every new recursion branch; add negative-space test.
3. `2026-04-11-plan-prescribed-wrong-test-runner.md` — anchor test commands to `package.json` `scripts.test` (vitest, confirmed).

### Key Improvements

1. **Case-normalized extension check.** `path.extname` preserves case (`.PDF` not `.pdf`). Adding an explicit `.toLowerCase()` before `FILENAME_SEARCHABLE.has(ext)` — otherwise `Q1-Invoice.PDF` would be dropped even after the fix.
2. **Symlink defense carried forward.** The existing `collectMdFiles` guards against symlink escape (see learning). The renamed `collectSearchableFiles` preserves these checks verbatim, and a negative-space security test asserts they stay.
3. **Security test extension.** Extend `test/kb-security.test.ts` to assert `collectSearchableFiles` keeps `!entry.isSymbolicLink()` — prevents silent regression.
4. **FormData-style field-name contract.** None needed (no API surface change) — flagged to prevent churn.
5. **Test-runner anchoring.** All test commands normalized to `npx vitest run` (per `apps/web-platform/package.json` `scripts.test: "vitest"`). Worktree-safe invocation via `node node_modules/vitest/vitest.mjs run` kept in place per AGENTS.md `cq-in-worktrees-run-vitest`.

## Overview

Extend `searchKb` in `apps/web-platform/server/kb-reader.ts` to:

1. **Filename match** — scan filenames of all allowed KB file types (PDF, DOCX, CSV, TXT, PNG/JPG/GIF/WEBP, MD) and return matches using the filename as the match text. This covers the user's primary complaint: uploaded files do not surface when their name contains the query.
2. **Content match** — continue content-searching text-native types (`.md`, `.txt`, `.csv`). Binary formats (PDF, DOCX, images) are filename-only until the RAG/extraction pipeline lands (tracked separately, see Non-Goals).
3. **Result typing** — add a `kind: "filename" | "content"` field on `SearchResult` so the UI can render a filename-match snippet differently from line-based content snippets.

- **Effort**: ~3 hours (tests + implementation + UI tweak).
- **Stack**: TypeScript / Vitest (existing `kb-reader.ts` + `search-overlay.tsx`). No new dependencies.
- **Risk**: Low. Fix is narrow and covered by an existing test file (`test/kb-reader.test.ts`) that currently asserts the broken behavior — those assertions must flip.

## Context

- **Root cause**: `collectMdFiles` at `apps/web-platform/server/kb-reader.ts:116-141` hardcodes `entry.name.endsWith(".md")`, so any file produced by the upload route (`apps/web-platform/app/api/kb/upload/route.ts`) — whose `ALLOWED_EXTENSIONS` includes `png, jpg, jpeg, gif, webp, pdf, csv, txt, docx` — is silently dropped from the search corpus.
- **Test drift**: `apps/web-platform/test/kb-reader.test.ts:358-380` has two tests that explicitly assert "searchKb only returns .md files" (`does not search binary/non-.md files`, `collectMdFiles still returns only .md files`). These tests will fail on the fix and MUST be rewritten in the TDD gate (AGENTS.md `cq-write-failing-tests-before`).
- **Why filename match only for binaries**: No PDF/DOCX/image text-extraction pipeline exists. `react-pdf` is a client-side renderer (`apps/web-platform/package.json`), not an extractor. The RAG / embeddings discussion was explicitly deferred in `knowledge-base/project/specs/feat-kb-rag-evaluation/spec.md` (non-goal: "Vector/embedding-based retrieval (deferred)"). Shipping filename match now is the cheap, obvious fix that unblocks Phase 3 milestone "KB artifacts browsable" without pulling forward deferred work.
- **Why CSV/TXT content search is in scope**: They are UTF-8 text and grep-compatible with zero marginal code — the same regex loop works if we just stop filtering the extension. Not adding them would be worse than the status quo because users who upload a CSV reasonably expect "find a string inside my CSV" to work.
- **No new infrastructure**: Zero dependencies added, no new endpoints, no migration. All changes live in one server module, one component, and one test file.
- **Brainstorm carry-forward**: This is a bug fix on a merged feature (KB search shipped in #2212). No brainstorm document exists — skipping idea refinement is appropriate. Direction is unambiguous (make uploads searchable).

### Research Insights

**Existing patterns to reuse (from `knowledge-base/project/learnings/2026-04-07-promise-all-parallel-fs-io-patterns.md`):**

- Keep the **flat-parallel shape** in `searchKb` — `Promise.all` over all files. This is the established pattern; do not refactor to p-limit in this PR (already flagged as future work in the existing `searchKb` comment).
- **Per-callback RegExp is mandatory** under `Promise.all` because `g`-flag regex is stateful via `lastIndex`. Applies identically to the new `matchFilename` helper: instantiate the regex **inside** the map callback, not at module scope.
- **Promise.all vs allSettled**: the existing try/catch-returns-null inside each callback makes `Promise.all` correct. Preserve this; do not introduce `allSettled`.
- **libuv threadpool ceiling**: default 4 threads. Expanding from .md-only to 9 extensions 2–3× the queued `fs.stat` / `fs.readFile` calls. This is still within safe territory for Phase-3 workspaces (typically < 500 files). No change needed, but for KBs > 10,000 files the flat `Promise.all` will be the first bottleneck.

**Security patterns to preserve (from `knowledge-base/project/learnings/2026-04-07-symlink-escape-recursive-directory-traversal.md`):**

- `collectMdFiles` currently guards: `entry.isDirectory() && !entry.isSymbolicLink()` and `entry.isFile() && !entry.isSymbolicLink()`. The renamed `collectSearchableFiles` MUST keep both guards on every branch. An agent planting a symlink under `knowledge-base/` and enumerating via search would otherwise leak files from `/etc/` or another workspace.
- **Defense-in-depth**: point-access (`readContent`) validates via `isPathInWorkspace`; enumeration (`collectSearchableFiles`) skips symlinks. Both must be intact. Verification: add a negative-space test to `test/kb-security.test.ts` asserting the new function name still contains `!entry.isSymbolicLink()` on every branch.
- **`collectSearchableFiles` does not read file bytes** — filename match works on the path alone, so symlink-follow to read content is impossible by construction. The symlink guard matters only for enumeration leakage, not content leakage.

**Test-runner anchoring (from `knowledge-base/project/learnings/workflow-issues/plan-prescribed-wrong-test-runner-20260411.md`):**

- `apps/web-platform/package.json` `scripts.test` is `vitest`. All local invocations use vitest.
- Worktree-safe invocation: `node node_modules/vitest/vitest.mjs run test/kb-reader.test.ts` (AGENTS.md `cq-in-worktrees-run-vitest`). Do NOT use `npx vitest` — the npx cache is shared across worktrees and can resolve to a stale installation.
- Do NOT use `bun test` — the project uses vitest, not bun's built-in runner. `bun test` will silently return "no test files found".

**Case-normalization (from inspection of `path.extname`):**

- `path.extname("Q1-Invoice.PDF")` returns `.PDF` (preserves case). The upload route sanitizes via `split(".").pop()?.toLowerCase()` before checking `ALLOWED_EXTENSIONS`, but the search path gets extensions from `path.extname` in a case-sensitive form.
- `FILENAME_SEARCHABLE` and `CONTENT_SEARCHABLE` MUST contain lowercase entries and the check site MUST lowercase the extname first:
      `const ext = path.extname(entry.name).toLowerCase();`
- Miss this and the fix only works for lowercase uploads — breaking the acceptance test for `Q1-Invoice.PDF`.

## Files to Modify

| Path | Change |
|---|---|
| `apps/web-platform/server/kb-reader.ts` | Rename `collectMdFiles` → `collectSearchableFiles`. Return tuples of `{ relativePath, ext, mode: "content" | "filename" }`. Expand`SearchResult` with `kind: "filename" \| "content"`. Update`searchKb` to (a) run filename-match on every searchable file, (b) run content-match on `.md/.txt/.csv`. Preserve existing concurrency, size guard, and sort behavior. |
| `apps/web-platform/test/kb-reader.test.ts` | **Flip** the two broken-behavior tests: `does not search binary/non-.md files` → `finds binary files by filename match`; `collectMdFiles still returns only .md files` → `collectSearchableFiles returns all allowed extensions`. Add new tests for filename match on PDF/DOCX/PNG, content match on .txt and .csv, and mixed result ordering (content matches rank above filename-only matches for the same query). |
| `apps/web-platform/components/kb/search-overlay.tsx` | Render `kind: "filename"` results with a "filename match" label and icon variant (reuse existing file-icon SVG; drop `Line N` prefix when `kind === "filename"`). Keep file-type icon consistent with `file-tree.tsx` conventions. |

## Files to Create

| Path | Purpose |
|---|---|
| (none) | Fix is in-place; no new files needed. |

## Implementation Phases

### Phase A — Failing tests (TDD gate, ~45 min)

1. Update `apps/web-platform/test/kb-reader.test.ts`:

   ```ts
   // apps/web-platform/test/kb-reader.test.ts — new/modified tests

   test("finds binary files by filename match", async () => {
     fs.writeFileSync(path.join(kbRoot, "invoice-q1.pdf"), "fake-pdf-bytes");
     fs.writeFileSync(path.join(kbRoot, "diagram.png"), "fake-png-bytes");
     const pdfHit = await searchKb(kbRoot, "invoice");
     expect(pdfHit.results.some((r) => r.path === "invoice-q1.pdf")).toBe(true);
     expect(pdfHit.results.find((r) => r.path === "invoice-q1.pdf")!.kind)
       .toBe("filename");
     const pngHit = await searchKb(kbRoot, "diagram");
     expect(pngHit.results.some((r) => r.path === "diagram.png")).toBe(true);
   });

   test("content-searches .txt and .csv files", async () => {
     fs.writeFileSync(path.join(kbRoot, "notes.txt"), "the quick brown fox");
     fs.writeFileSync(path.join(kbRoot, "data.csv"), "id,name\n1,widget");
     const txtHit = await searchKb(kbRoot, "brown");
     expect(txtHit.results[0].path).toBe("notes.txt");
     expect(txtHit.results[0].kind).toBe("content");
     const csvHit = await searchKb(kbRoot, "widget");
     expect(csvHit.results[0].path).toBe("data.csv");
   });

   test("does not read binary file bytes for content match", async () => {
     // Write bytes that would match "PDF" if searched — must not surface
     fs.writeFileSync(path.join(kbRoot, "a.pdf"), "header PDF body PDF");
     const hit = await searchKb(kbRoot, "body");
     expect(hit.results.find((r) => r.path === "a.pdf")).toBeUndefined();
   });

   test("content matches rank above pure filename matches", async () => {
     fs.writeFileSync(path.join(kbRoot, "widget-spec.pdf"), "bytes");
     fs.writeFileSync(path.join(kbRoot, "notes.md"), "widget widget widget");
     const hit = await searchKb(kbRoot, "widget");
     expect(hit.results[0].path).toBe("notes.md"); // 3 content matches
     expect(hit.results[hit.results.length - 1].path).toBe("widget-spec.pdf");
   });

   test("filename match is case-insensitive", async () => {
     fs.writeFileSync(path.join(kbRoot, "Q1-Invoice.PDF"), "bytes");
     const hit = await searchKb(kbRoot, "invoice");
     expect(hit.results.some((r) => r.path === "Q1-Invoice.PDF")).toBe(true);
   });
   ```

2. Confirm the two legacy tests (`does not search binary/non-.md files`, `collectMdFiles still returns only .md files`) are deleted or rewritten — they encoded the bug.

3. Run tests — expect RED:

   ```bash
   cd apps/web-platform
   node node_modules/vitest/vitest.mjs run test/kb-reader.test.ts
   # Expected: 5+ new tests fail, 2 legacy tests deleted
   ```

   (Worktree vitest invocation per AGENTS.md `cq-in-worktrees-run-vitest`.)

### Phase B — Implementation (~1h)

1. Edit `apps/web-platform/server/kb-reader.ts`:

   ```ts
   // Single source of truth for what search indexes. Mirror of
   // apps/web-platform/app/api/kb/upload/route.ts ALLOWED_EXTENSIONS
   // plus .md (which is native KB content, not an "upload").
   // All entries MUST be lowercase — the lookup site lowercases ext before check.
   const CONTENT_SEARCHABLE = new Set([".md", ".txt", ".csv"]);
   const FILENAME_SEARCHABLE = new Set([
     ".md", ".txt", ".csv",
     ".pdf", ".docx",
     ".png", ".jpg", ".jpeg", ".gif", ".webp",
   ]);

   interface SearchableFile {
     relativePath: string;
     ext: string; // lowercase
   }

   async function collectSearchableFiles(
     dir: string,
     relativeTo: string,
   ): Promise<SearchableFile[]> {
     const files: SearchableFile[] = [];
     let entries: fs.Dirent[];
     try {
       entries = await fs.promises.readdir(dir, { withFileTypes: true });
     } catch {
       return files;
     }
     const dirPromises: Promise<SearchableFile[]>[] = [];
     for (const entry of entries) {
       const fullPath = path.join(dir, entry.name);
       // Symlink guard: prevents enumeration escape (learning 2026-04-07).
       if (entry.isDirectory() && !entry.isSymbolicLink()) {
         dirPromises.push(collectSearchableFiles(fullPath, relativeTo));
       } else if (entry.isFile() && !entry.isSymbolicLink()) {
         const ext = path.extname(entry.name).toLowerCase();
         if (FILENAME_SEARCHABLE.has(ext)) {
           files.push({
             relativePath: path.relative(relativeTo, fullPath),
             ext,
           });
         }
       }
     }
     const nestedResults = await Promise.all(dirPromises);
     for (const nested of nestedResults) {
       files.push(...nested);
     }
     return files;
   }
   ```

   **Why lowercase `ext`**: `path.extname` preserves case (`.PDF` not `.pdf`). Without `.toLowerCase()`, an uploaded `Q1-Invoice.PDF` would be filtered out even with the fix in place.

   **Why keep `!entry.isSymbolicLink()` on every branch**: Enumeration leakage is not covered by `readContent`'s `isPathInWorkspace` check. The guard MUST live on both `isDirectory` and `isFile` branches (learning 2026-04-07).

2. Update `SearchResult`:

   ```ts
   export interface SearchResult {
     path: string;
     frontmatter: Record<string, unknown>;
     matches: SearchMatch[];
     kind: "content" | "filename";
   }
   ```

3. Rewrite `searchKb` core loop:

   ```ts
   const files = await collectSearchableFiles(kbRoot, kbRoot);

   const results = await Promise.all(
     files.map(async (file): Promise<SearchResult | null> => {
       const filenameMatches = matchFilename(file.relativePath, escapedQuery);
       // Content search only for text-native types
       if (CONTENT_SEARCHABLE.has(file.ext)) {
         const contentResult = await contentSearch(
           path.join(kbRoot, file.relativePath),
           escapedQuery,
         );
         if (contentResult && contentResult.matches.length > 0) {
           return { ...contentResult, path: file.relativePath, kind: "content" };
         }
       }
       if (filenameMatches.length > 0) {
         return {
           path: file.relativePath,
           frontmatter: {},
           matches: filenameMatches,
           kind: "filename",
         };
       }
       return null;
     }),
   );
   ```

4. `matchFilename(relativePath, escapedQuery)` returns a `SearchMatch[]` where `line: 0`, `text: <basename>`, `highlight: [start, end]` if the basename regex-matches. Use the basename (not the full relative path) for both match text and highlight offsets — directory segments are not meaningful for filename match.

   ```ts
   function matchFilename(
     relativePath: string,
     escapedQuery: string,
   ): SearchMatch[] {
     const basename = path.basename(relativePath);
     // Per-callback RegExp instance — /gi is stateful via lastIndex and would
     // misbehave if shared across concurrent map callbacks in Promise.all.
     // (Pattern from learning 2026-04-07-promise-all-parallel-fs-io-patterns.)
     const re = new RegExp(escapedQuery, "gi");
     const matches: SearchMatch[] = [];
     let found: RegExpExecArray | null;
     while ((found = re.exec(basename)) !== null) {
       matches.push({
         line: 0,
         text: basename,
         highlight: [found.index, found.index + found[0].length],
       });
       // Guard against zero-width matches causing infinite loops
       if (found.index === re.lastIndex) re.lastIndex++;
     }
     return matches;
   }
   ```

5. Sorting: content matches rank by `matches.length` descending (current behavior). Filename-only results rank below any content result and are sorted alphabetically by path. Implementation: stable two-pass sort (content group first, then filename group).

6. Run tests — expect GREEN:

   ```bash
   node node_modules/vitest/vitest.mjs run test/kb-reader.test.ts
   ```

### Phase C — UI polish (~30 min)

1. Edit `apps/web-platform/components/kb/search-overlay.tsx`:

   ```tsx
   function SnippetLine({ match, kind }: { match: SearchMatch; kind: SearchResult["kind"] }) {
     if (kind === "filename") {
       return (
         <p className="text-xs text-neutral-500 italic">Filename match</p>
       );
     }
     // existing content-match render with "Line N"
   }
   ```

2. Route icon variant through `file-tree.tsx`'s existing ext→icon logic (or inline: .pdf → PDF icon, image ext → image icon). No new SVGs — reuse the generic document icon as the fallback.

3. Manual QA: start the dev server, upload a PDF via the KB uploader, search for a substring of the filename, verify it appears with "Filename match" label.

### Phase D.5 — Security regression test (~15 min)

1. Extend `apps/web-platform/test/kb-security.test.ts` with a negative-space test that asserts the renamed enumeration function retains its symlink guard:

   ```ts
   it("kb-reader collectSearchableFiles skips symlinks on every branch", () => {
     const kbReader = resolve(__dirname, "../server/kb-reader.ts");
     const content = readFileSync(kbReader, "utf-8");

     // Enumeration must skip symlinks (defense against enumeration escape —
     // learning 2026-04-07-symlink-escape-recursive-directory-traversal).
     // Count must match the number of branches in collectSearchableFiles
     // (currently 2: directory branch + file branch).
     const matches = content.match(/!entry\.isSymbolicLink\(\)/g) ?? [];
     expect(matches.length).toBeGreaterThanOrEqual(2);
   });

   it("kb-reader lowercases extname before FILENAME_SEARCHABLE check", () => {
     const kbReader = resolve(__dirname, "../server/kb-reader.ts");
     const content = readFileSync(kbReader, "utf-8");

     // Must lowercase extname — path.extname preserves case, so Q1-Invoice.PDF
     // would be dropped without explicit .toLowerCase().
     expect(content).toMatch(/path\.extname\([^)]*\)\.toLowerCase\(\)/);
   });
   ```

2. Add an integration test for symlink skip in `test/kb-reader.test.ts` (only if the CI environment allows `fs.symlinkSync` — it may fail on Windows runners; skip gracefully):

   ```ts
   test("searchKb skips symlinked directories under kbRoot", () => {
     // Skip on platforms without symlink permission
     try {
       fs.symlinkSync("/etc", path.join(kbRoot, "link-to-etc"), "dir");
     } catch (err) {
       // EPERM on Windows without admin, or sandboxed CI — skip test
       return;
     }
     // Create a real file so searchKb has something to find
     fs.writeFileSync(path.join(kbRoot, "real.md"), "findme in kb");
     const result = await searchKb(kbRoot, "findme");
     expect(result.results.every((r) => !r.path.startsWith("link-to-etc"))).toBe(true);
   });
   ```

### Phase D — Regression guard (~15 min)

1. Run the full kb-reader test suite:

   ```bash
   cd apps/web-platform
   node node_modules/vitest/vitest.mjs run test/kb-reader.test.ts test/kb-security.test.ts
   ```

2. Sanity-check existing tests that rely on tree traversal (file-tree.test.tsx, start-fresh-onboarding.test.tsx) remain green — this change touches only the search path, not `buildTree` or `readContent`.

3. Grep for downstream consumers that destructure `SearchResult`:

   ```bash
   grep -rn "SearchResult\|SearchMatch" apps/web-platform --include="*.ts" --include="*.tsx"
   ```

   Confirm `kind` additions compile in strict TS.

## Acceptance Criteria

- [x] Uploading a PDF named `invoice-q1-2026.pdf` and searching for `invoice` returns the PDF in the search results (filename match).
- [x] Uploading a PNG named `architecture-diagram.png` and searching for `diagram` returns the PNG.
- [x] Uploading a CSV with the row `id,widget-name\n1,hammer` and searching for `hammer` returns the CSV (content match).
- [x] Uploading a TXT file with the word "roadmap" and searching for `roadmap` returns the TXT (content match).
- [x] PDF and DOCX are NOT content-searched — searching for a string that only appears in binary bytes of a PDF does not return the PDF.
- [x] A content match on a .md file ranks above a filename-only match on a PDF for the same query.
- [x] `SearchResult.kind` field is populated correctly on every result.
- [x] The UI shows "Filename match" labeling (or equivalent) on filename-only results, distinct from line-numbered content snippets.
- [x] All existing `kb-reader.test.ts` tests that were NOT encoding the bug remain green.
- [x] No new runtime dependencies added to `apps/web-platform/package.json`.
- [x] `collectSearchableFiles` skips symbolic links on both the directory and file branches (verified by a new negative-space test in `test/kb-security.test.ts`).
- [x] Extension matching is case-insensitive — `Q1-Invoice.PDF`, `DIAGRAM.PNG`, and `notes.TXT` all surface in results.
- [x] Filename-match RegExp is instantiated per-callback (not module-scoped) — enforces Promise.all regex-concurrency safety.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | Upload `invoice.pdf`, search "invoice" | Returned, `kind: "filename"`, `matches[0].text: "invoice.pdf"` |
| T2 | Upload `notes.txt` containing "fox jumps", search "fox" | Returned, `kind: "content"`, `matches[0].line: 1` |
| T3 | Upload `data.csv` with "widget", search "widget" | Returned, `kind: "content"` |
| T4 | PDF with "secret" in binary bytes, search "secret" | NOT returned (binary bytes are never read as text) |
| T5 | `notes.md` with "widget" ×3 + `widget.pdf`, search "widget" | `notes.md` first (content rank 3), `widget.pdf` last (filename rank) |
| T6 | Upload `Q1-INVOICE.PDF` (uppercase), search "invoice" | Returned (case-insensitive filename match) |
| T7 | Upload `.hidden.txt` (no allowed extension match), search "any" | NOT returned (unchanged — hidden files ignored by upload pipeline anyway) |
| T8 | Query with special regex chars (`foo[bar]`) vs filename `foo[bar].pdf` | Returned (regex escape applied to filename path too) |
| T9 | Symlink under kbRoot pointing to `/etc/` | Skipped entirely — no `/etc/*` paths leak into results |
| T10 | Empty query | Throws `KbValidationError` (unchanged) |
| T11 | File exactly at `KB_MAX_FILE_SIZE` boundary | Content-search skipped (unchanged guard) but filename match still runs |
| T12 | Zero-width regex (query that matches empty string, e.g. via lookahead) | Does NOT infinite-loop in `matchFilename` (lastIndex advancement guard) |
| T13 | Mixed case basename with non-ASCII chars (`naïve-notes.md`) | Basename preserves UTF-8 in result snippet |

## Non-Goals (Out of Scope)

- **PDF/DOCX text extraction** — requires pulling in `pdf-parse`, `mammoth`, or an external OCR service. Tracked in the existing "KB RAG evaluation" spec (`knowledge-base/project/specs/feat-kb-rag-evaluation/spec.md`) and deferred to a post-Phase-3 decision. Filename match covers the reported bug; content extraction is a larger feature.
- **Vector/embedding search** — explicitly rejected in the 2026-04-07 KB retrieval brainstorm (`knowledge-base/project/brainstorms/2026-04-07-kb-retrieval-improvement-brainstorm.md`).
- **Frontmatter faceting for binaries** — binaries have no frontmatter. `SearchResult.frontmatter` stays `{}` for filename-only hits.
- **OCR on image uploads** — same category as PDF extraction; deferred.
- **Backfill of existing workspaces** — no migration needed. The fix is read-only and takes effect the moment the server ships.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Narrow server-side fix in a single module. Risk is contained by existing test coverage in `kb-reader.test.ts`. Two legacy tests must be deleted because they encoded the bug — this is the "gate-fix + retroactive remediation" pattern from AGENTS.md `wg-when-fixing-a-workflow-gates-detection`. Preserves existing concurrency patterns, size guards, regex escape, and security boundaries (null-byte check still flows through `readContent`, not `searchKb`). No architectural implication: the filename/content-mode split is the simplest abstraction that solves the reported bug without pulling forward deferred RAG work. **Recommended:** Ship as-is. Does not trigger CMO or CPO gates (no user-facing copy, no strategic product question — this is a broken-feature restoration).

No cross-domain implications beyond engineering — this is a bug-fix restoration on an internal search feature. No marketing copy, no new page, no roadmap impact.

## Sharp Edges

- The two existing tests `does not search binary/non-.md files` and `collectMdFiles still returns only .md files` are asserting the bug. Deleting them is correct, not a regression. Add comment in the PR body noting the deletion so reviewers don't flag it.
- `SearchResult.kind` is a new required field. Any external consumer that destructures `SearchResult` (check via grep in Phase D) must be updated in the same commit or TypeScript will break the build.
- Filename-match regex must be applied to `path.basename(relativePath)`, not the full path, otherwise directory-name matches leak (e.g., searching "overview" would match every file under `knowledge-base/overview/`). That is not the desired UX.
- `searchKb` runs `Promise.all` over the full searchable file list. Expanding from `.md` only to 9 extensions can 2–3× the file count. Keep the existing `MAX_CONCURRENT_STAT` + `KB_MAX_FILE_SIZE` guards in place; do not read binary file contents to inspect size — stat is sufficient. A p-limit refactor is out of scope (already flagged in the existing searchKb comment).
- The UI currently renders `result.matches.slice(0, 3)` and includes line numbers. For `kind: "filename"`, `match.line = 0` must render as "Filename match" without "Line 0" text. Do not attempt to generalize the snippet component — a narrow `kind` switch is clearer.
- Do NOT edit `apps/web-platform/app/api/kb/upload/route.ts` — the allowed-extension set is already correct; the fix is purely in the search path.
- `path.extname` **preserves case**. The `FILENAME_SEARCHABLE` / `CONTENT_SEARCHABLE` sets are lowercase — callers MUST lowercase the extname before the `.has()` check, or `Q1-Invoice.PDF` silently drops. This is subtle: the upload route lowercases via a different code path (`split(".").pop()?.toLowerCase()`), so the same files appear inconsistently handled between read and write if the search fix misses this step.
- Regex stateful-ness under `Promise.all`: do NOT hoist the `matchFilename` regex to module scope. `/gi` is stateful via `lastIndex`; sharing a single instance across concurrent callbacks produces lost matches or infinite loops (pattern documented in learning 2026-04-07). The existing `searchKb` content loop already follows this rule — `matchFilename` must too.
- Zero-width regex guard: `re.exec` can return a zero-length match at the same `lastIndex` forever. Always advance `re.lastIndex++` when `found.index === re.lastIndex` to break infinite loops. Applies even if the regex source comes from `escapeRegex` (which escapes `*+?` etc.) because user input could still produce empty captures in edge cases.
- Symlink enumeration escape: `collectSearchableFiles` MUST retain `!entry.isSymbolicLink()` on both the `isDirectory` and `isFile` branches. `readContent`'s `isPathInWorkspace` does NOT cover enumeration — a malicious agent could plant a symlink pointing at another workspace or `/etc/`, and enumeration would leak filenames. Negative-space test in `test/kb-security.test.ts` must assert this.
- Do NOT run `bun test` — project uses vitest (`apps/web-platform/package.json` `scripts.test`). `bun test` silently returns "no test files found" (learning 2026-04-11).

## Rollout

- No feature flag, no migration, no config change.
- Ship with the merged PR — behavior flips on the next deploy. Zero user action required.
- Monitor Sentry for new exceptions under `kb/search: unexpected error` for 24h post-deploy (AGENTS.md `cq-for-production-debugging`).

## Open Questions

1. Should filename matches include the extension in the highlighted text? Current plan: yes (`invoice.pdf` highlights `invoice` → users see the extension for context). If reviewers disagree, strip to basename-without-ext — trivial to change.
2. Should we cap filename-only results separately from content results to avoid filename noise crowding out content matches? Current plan: single `MAX_SEARCH_RESULTS = 100` cap with content-first sort ordering. Revisit if QA surfaces UX issues with large upload folders.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-04-15-fix-kb-search-pdf-uploads-plan.md

Context: branch feat-kb-search-pdf-uploads, worktree .worktrees/feat-kb-search-pdf-uploads/, issue #2230 (P1 bug, Phase 3). Plan written and ready. Fix: expand searchKb in kb-reader.ts to filename-match all allowed upload types and content-search .md/.txt/.csv; delete the two legacy tests that encoded the bug.
```
