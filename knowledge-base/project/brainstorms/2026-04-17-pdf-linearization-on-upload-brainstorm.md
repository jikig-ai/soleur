---
title: PDF Linearization on Upload
date: 2026-04-17
topic: pdf-linearization-on-upload
issue: 2456
branch: pdf-linearization
status: captured
---

# Brainstorm: Server-Side PDF Linearization on Upload

## What We're Building

Add `qpdf --linearize` to the KB upload route (`apps/web-platform/app/api/kb/upload/route.ts`). Before committing a `.pdf` file to the user's connected GitHub repo, run qpdf to produce a linearized version and commit that instead of the original. If qpdf fails (encrypted, malformed, subprocess error), commit the user's original file unchanged and log a warning.

This makes newly-uploaded PDFs render page 1 within ~1-2s regardless of total page count, by leveraging the HTTP Range + PDF.js range-transport path already shipped in #2451, #2452, #2455.

## Why This Approach

Issue #2456 originally proposed on-demand linearization in the **read path**, backed by a ~250MB in-memory LRU cache. Research and the CTO assessment surfaced three problems with that tier:

1. **Wrong cache tier.** KB PDFs are immutable once committed. Caching a deterministic transform of immutable input in volatile RAM means paying the qpdf cost again on every deploy, every OOM, every replica scale-out.
2. **Stampede risk.** Concurrent first-reads of a large PDF (e.g., from a dashboard grid or search result set) all trigger qpdf simultaneously. A correct LRU would need a per-key mutex, adding complexity over just persisting the bytes once.
3. **Multi-replica cost.** At 3 replicas that's 750MB RAM for one corpus. Cold-start penalty hits the first user after every deploy.

The CTO's preferred alternative — "linearize-on-read, persist to R2" — does not map to this codebase. KB content lives in the **user's git repo** (committed via the GitHub Contents API from `apps/web-platform/app/api/kb/upload/route.ts`). There is no R2 bucket for KB content. The only persistence surfaces are (a) the user's git repo or (b) per-replica disk, neither of which a read-path cache uses well.

Linearize-on-upload is the cleanest seam: one-time cost, zero RAM, persistent in git, no cache invalidation, scales free across replicas. The upload path already holds the full buffer in memory and already has a commit step; qpdf slots in between them.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| When to linearize | On upload, before commit to git | One-time cost, persistent, zero RAM, survives deploys and replica scaling |
| What to commit | Linearized version replaces original | User's git repo stays single-file per PDF; qpdf `--linearize` is semantically lossless (same document, same pages, reorganized byte layout) |
| Legacy PDFs | Only new uploads benefit | Simplest scope. No backfill script. Users who want the fix on an existing PDF re-upload it. Documented as a known limitation. |
| qpdf failure handling | Commit original, log warning | Linearization is a perf optimization, not a correctness gate. Encrypted/malformed PDFs still reach the user's repo. Telemetry tracks failure rate. |
| qpdf install location | Runner stage of `apps/web-platform/Dockerfile` via `apt-get install -y qpdf` | Existing base is `node:22-slim` (debian); qpdf installs cleanly alongside git, bubblewrap, socat. ~15MB image bloat. |
| qpdf invocation | `child_process.spawn("qpdf", ["--linearize", "-", "-"])` with stdin/stdout | Avoids temp-file disk I/O. Enforced subprocess timeout (default 10s). |
| Upload latency impact | Accepted (+500ms–1s for a 20MB PDF) | 20MB is the current upload cap. qpdf runtime is linear in file size. Acceptable trade for permanent fix. |

## Non-Goals

- **Backfill of existing non-linearized PDFs.** The 60-page "Au Chat Pôtan" PDF that originally reproduced the bug stays slow until it is re-uploaded. If this becomes a broader pain point, file a follow-up issue for an admin-triggered batch job that walks connected repos and re-commits linearized versions.
- **In-memory or disk caching.** Explicitly rejected during brainstorm — git-backed persistence is strictly superior.
- **Encrypted PDF handling.** `qpdf --linearize` refuses password-protected PDFs. These files commit as-is and continue to require near-full download before page 1 renders.
- **Async / queued linearization.** Upload blocks on qpdf. Async would require a job queue and a multi-state upload UX, not worth it at current scale.
- **Changes to the read path.** `apps/web-platform/server/kb-binary-response.ts` is untouched. HTTP Range + `disableAutoFetch` stay as shipped.

## Open Questions

1. **`qpdf` in `node:22-slim` apt sources?** Need to verify during implementation (`docker run node:22-slim apt-cache search qpdf`). If missing, the fallback is qpdf's official `.deb` or a multi-stage build that copies the qpdf binary + its libs from a builder layer.
2. **Upload route timeout ceiling.** Next.js API routes default to 10s. qpdf on a 20MB linearly-structured PDF is ~500ms–1s; pathological inputs could exceed. Confirm `maxDuration` export on the route handler and either align with the subprocess timeout or bump it.
3. **Warning telemetry path.** The upload route already has an error path; need to confirm whether qpdf warnings should route to Sentry, Better Stack, or plain `console.warn`. Likely inherit the route's existing observability wiring.

## Domain Assessments

**Spawned:** Engineering (CTO). **Inferred from user answers:** Product.

### Engineering

**Summary:** CTO challenged the in-memory LRU proposal as architecturally wrong for immutable content, flagging stampede risk, multi-replica RAM cost (~750MB at 3 replicas), cold-start penalty after every deploy, and encrypted-PDF fallback gaps. Recommended measure-first, then linearize-on-upload. Problem was confirmed real post-#2455, so we proceed directly to upload-path implementation.

### Product

**Summary:** The decision to commit the original on qpdf failure (rather than reject the upload) confirms linearization is a perf optimization, not a product gate. No UX messaging change is needed. Users see faster page-1 rendering on new uploads; legacy PDFs keep working as-is with the same pre-#2456 behavior.
