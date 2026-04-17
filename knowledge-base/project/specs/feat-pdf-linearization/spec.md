---
title: Server-Side PDF Linearization on Upload
status: specified
issue: 2456
brainstorm: knowledge-base/project/brainstorms/2026-04-17-pdf-linearization-on-upload-brainstorm.md
branch: pdf-linearization
date: 2026-04-17
---

# Spec: Server-Side PDF Linearization on Upload

## Problem Statement

Non-linearized PDFs in the KB viewer cannot render progressively, even after the HTTP Range (#2451) and PDF.js `disableAutoFetch` (#2455) fixes landed. Page 1 does not appear until ~100% of the file is downloaded, because PDF.js must locate scattered cross-reference tables throughout the document body before it can decode any page. Confirmed post-#2455 on a 60-page "Au Chat Pôtan" PDF.

## Goals

- **G1.** Newly-uploaded PDFs render page 1 within ~2s in the KB viewer regardless of total file size (up to the 20MB upload cap).
- **G2.** Preserve existing HTTP Range + PDF.js range-transport code paths unchanged (`apps/web-platform/server/kb-binary-response.ts` untouched).
- **G3.** Keep the KB upload route's contract (`POST /api/kb/upload` FormData with `file`, `targetDir`, `sha`; existing response shape) unchanged.
- **G4.** Graceful fallback when qpdf cannot process a file — upload always succeeds with either linearized or original bytes.

## Non-Goals

- **NG1.** Backfill of PDFs already committed before this change ships.
- **NG2.** In-memory or disk-based linearization caches (explicitly rejected in brainstorm).
- **NG3.** Async / queued linearization with a multi-state upload UX.
- **NG4.** Linearization of password-protected PDFs (commit original, skip qpdf).
- **NG5.** Any modification to the PDF viewer client code or PDF.js configuration.

## Functional Requirements

- **FR1.** When a file with extension `.pdf` is uploaded via `POST /api/kb/upload`, the handler MUST attempt `qpdf --linearize` on the upload buffer before committing to GitHub.
- **FR2.** On qpdf success (exit 0), the linearized bytes MUST replace the original in the commit payload sent to the GitHub Contents API.
- **FR3.** On qpdf failure (non-zero exit, spawn error, timeout, encrypted input), the original bytes MUST be committed unchanged and a structured warning MUST be logged with filename, size, and failure reason.
- **FR4.** Non-PDF uploads MUST bypass the qpdf step entirely with no subprocess invocation and no measurable latency regression.
- **FR5.** The upload response payload returned to the client MUST remain unchanged in shape and fields.

## Technical Requirements

- **TR1.** Add `qpdf` to the runner stage of `apps/web-platform/Dockerfile` via `apt-get install -y --no-install-recommends qpdf`, adjacent to the existing runtime dep install for git/bubblewrap/socat. Verify `qpdf --version` succeeds in the built image.
- **TR2.** Introduce a helper at `apps/web-platform/server/pdf-linearize.ts` (or equivalent sibling of `kb-binary-response.ts`) that:
  - Accepts a `Buffer` input.
  - Spawns `qpdf --linearize - -` via `child_process.spawn`, pipes input via stdin, collects stdout.
  - Enforces a configurable subprocess timeout (default 10s).
  - Returns `{ ok: true, buffer }` on success or `{ ok: false, reason }` on any failure.
  - Never throws — all errors are caught and returned as structured results.
- **TR3.** The upload route (`apps/web-platform/app/api/kb/upload/route.ts`) MUST call the helper for `.pdf` uploads, log a warning on failure, and use the original buffer when the helper returns `ok: false`.
- **TR4.** No new npm dependencies. qpdf is invoked via Node's built-in `child_process`, not a wrapper library.
- **TR5.** No changes to `apps/web-platform/server/kb-binary-response.ts` or any PDF viewer client code.
- **TR6.** Upload route `maxDuration` export (if present) MUST accommodate the subprocess timeout plus GitHub commit latency. Align to a single value (suggested 30s) and document.

## Acceptance Criteria

- **AC1.** `docker build` succeeds and the resulting runner image answers `qpdf --version` with a non-zero exit-0 response.
- **AC2.** Uploading a known non-linearized PDF via the KB upload route results in a GitHub commit whose content returns `Linearization: yes` when run through `qpdf --check`.
- **AC3.** Uploading a password-protected PDF results in the original being committed, a warning being logged with reason containing "encrypted" or equivalent, and the upload response reporting success.
- **AC4.** Uploading a 20MB non-linearized PDF completes end-to-end within 5 seconds (upload + qpdf + GitHub commit).
- **AC5.** Opening an uploaded-and-linearized PDF in the KB viewer renders page 1 within 2 seconds on a cold page load on a typical broadband connection.
- **AC6.** Uploading a non-PDF file (`.md`, `.png`, `.csv`) produces no qpdf subprocess invocation and no latency regression versus `main`.
- **AC7.** The upload response payload for any input (PDF or non-PDF, success or fallback) matches the response shape currently produced on `main`.

## Risks

- **R1.** **Upload latency regression.** qpdf on a pathologically-scattered 20MB PDF could exceed the 10s subprocess timeout. Mitigation: timeout triggers FR3 fallback; user still gets their file committed.
- **R2.** **Docker image size growth.** +~15MB for qpdf + transitive libs. Acceptable; documented.
- **R3.** **Semantic-but-not-byte equivalence.** qpdf `--linearize` is documented lossless at the document level, but produces byte-different output. Users viewing the file outside the KB (git log diff, direct GitHub download) see the linearized bytes, not their exact original bytes. Documented in NG4 and brainstorm.
- **R4.** **qpdf in node:22-slim apt sources unverified.** Mitigated by a 30-second pre-implementation check; if absent, use a multi-stage build copying the qpdf binary from a debian base.

## Implementation Outline (for planning)

- Entry point: `apps/web-platform/app/api/kb/upload/route.ts` (existing PDF code path)
- New helper: `apps/web-platform/server/pdf-linearize.ts`
- Dockerfile: `apps/web-platform/Dockerfile` runner stage
- Tests: unit tests for the helper (success, timeout, spawn failure, encrypted-PDF fallback); integration test for the upload route covering PDF success path and fallback path
