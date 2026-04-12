# Spec: KB File Upload

**Issue:** [#1974](https://github.com/jikig-ai/soleur/issues/1974)
**Phase:** 3 (Make it Sticky)
**Priority:** P3-low
**Brainstorm:** [2026-04-12-kb-file-upload-brainstorm.md](../../brainstorms/2026-04-12-kb-file-upload-brainstorm.md)

## Problem Statement

Users cannot upload files (images, PDFs, documents) to their knowledge base through the web platform. The KB viewer is read-only — it displays git-backed markdown files but provides no way to add non-markdown content. Founders who want to store reference materials (brand assets, financial PDFs, data CSVs) must commit them via git CLI, which breaks the "no-code" promise of the platform.

## Goals

1. Users can upload files to any KB directory via the web UI
2. Uploaded files are committed to the git repo (full data portability)
3. Agents can discover and reference uploaded files natively
4. KB viewer displays all file types (not just .md)

## Non-Goals

- Git LFS support (per-user repos are small enough without it)
- Bulk upload / zip extraction
- File editing in the browser (view-only for non-.md files)
- Drag-and-drop onto FileTree (deferred — per-directory button is V1)
- Version history UI for uploaded files (git history exists but no UI)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Per-directory upload button appears on hover in the FileTree sidebar |
| FR2 | Clicking the button opens a native file picker filtered to allowed types |
| FR3 | Allowed types: PNG, JPEG, GIF, WebP, PDF, CSV, TXT, DOCX |
| FR4 | Maximum file size: 20MB per file |
| FR5 | Upload commits the file to the user's git repo via GitHub Contents API through the server-side proxy |
| FR6 | After upload, the FileTree refreshes to show the new file |
| FR7 | Non-markdown files are visible in the FileTree (images, PDFs, etc.) |
| FR8 | Clicking a non-markdown file shows a preview (images), embedded viewer (PDFs), or download link (other types) |
| FR9 | Upload shows a loading/progress indicator during commit |
| FR10 | Duplicate filename prompts user to overwrite or cancel |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Upload API route: `POST /api/kb/upload` — accepts file + target directory path, commits via GitHub Contents API using GitHub App installation token |
| TR2 | File content sent as base64 to GitHub Contents API (their required format) |
| TR3 | `kb-reader.ts` expanded: `buildTree` includes all file types (not just .md), `readContent` serves binary files |
| TR4 | New route: `GET /api/kb/file/[...path]` — serves binary KB files with correct Content-Type headers |
| TR5 | File type validation on both client and server (allowlist, not blocklist) |
| TR6 | Path traversal protection on upload target directory (reuse `isPathInWorkspace` from kb-reader.ts) |
| TR7 | Server-side file size validation (reject > 20MB before GitHub API call) |

## Test Scenarios

| # | Scenario | Expected |
|---|----------|----------|
| T1 | Upload a PNG image to a KB directory | File appears in FileTree, clicking shows image preview |
| T2 | Upload a PDF to a KB directory | File appears in FileTree, clicking shows embedded PDF viewer or download |
| T3 | Upload a file > 20MB | Rejected with clear error message |
| T4 | Upload an unsupported file type (.exe) | Rejected with clear error message |
| T5 | Upload a file with the same name as existing file | User prompted to overwrite or cancel |
| T6 | Upload to a deeply nested directory | File committed to correct path in git |
| ~~T7~~ | ~~After upload, agent can reference the file in conversation~~ | ~~Agent sees file in KB tree and can discuss it~~ — **Descoped from V1.** Agents see file names in tree but reading binary content requires separate server-side access path. Tracked in follow-up issue. |
| T8 | Path traversal attempt (../../etc/passwd) | Rejected by server validation |
