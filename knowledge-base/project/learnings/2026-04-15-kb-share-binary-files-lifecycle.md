---
name: KB share button missing on non-markdown files (PDF, image, CSV)
description: The share affordance was only wired into the markdown branch of the KB viewer and the server rejected non-.md paths; extending to binaries required a full-stack fix with shared hardening helper.
date: 2026-04-15
category: ui-bugs
module: kb-sharing
issue: 2232
pr: 2282
tags: [kb, share, pdf, binary, csp, security, refactor, helper-extraction]
---

# Learning: KB Share Button on Binary Files

## Problem

`vision.md` showed a Share button; uploaded PDFs/images did not. Two bugs stacked:

1. **UI asymmetry** — `SharePopover` was rendered only in the markdown branch of `app/(dashboard)/dashboard/kb/[...path]/page.tsx`. The non-markdown branch (returned early on non-`.md`) had no share control.
2. **Server `.md`-only gate** — `/api/kb/share` rejected anything not ending in `.md` with 400, so wiring the UI alone would 400 on click. The public viewer `/api/shared/[token]` + `/shared/[token]` page only knew how to serve/render markdown.

## Solution

Three-layer fix in one PR:

1. **UI wiring** — render `<SharePopover documentPath={joinedPath} />` in the non-markdown branch header, symmetric with markdown.
2. **Shared helper `server/kb-binary-response.ts`** — extracted the hardened binary-serving logic previously inlined in `/api/kb/content/[...path]/route.ts`. Provides `readBinaryFile(kbRoot, relativePath)` returning a tagged-union result, and `buildBinaryResponse({ buffer, contentType, disposition, rawName })` emitting CSP, X-Content-Type-Options, RFC 6266 Content-Disposition, size and cache headers. Both `/api/kb/content` and `/api/shared/[token]` call the same helper so a fix in one propagates to both.
3. **Owner + public APIs fork on extension** — `.md` or extensionless → `readContent` → JSON; else → `readBinaryFile` → binary response. Owner API also validates file existence + regular-file + size-limit at share creation so dead links are rejected up front rather than materializing as 413s later.
4. **Viewer page branches on Content-Type** — `application/json` → `<MarkdownRenderer>`; `application/pdf` → existing `<PdfPreview>` (reused from authenticated viewer); `image/*` → `<img>`; else → download link. Middleware CSP (`worker-src 'self' blob:`, `img-src 'self' blob: data:`) was already configured for pdfjs; no middleware changes needed.

## Key Insight

**When the same hardening pattern appears in two routes, extract it BEFORE duplicating it.** The `/api/kb/content` binary path had evolved six hardening PRs (CSP headers, size guard, symlink rejection, async I/O, Content-Disposition sanitization). Copy-pasting that into `/api/shared/[token]` would have guaranteed future drift — the next hardening PR would touch one and forget the other. Extracting `readBinaryFile` + `buildBinaryResponse` encoded the invariant "both routes return byte-identical responses with identical security headers" as a shared dependency. Review agents immediately proposed a contract test for byte-level parity (issue #2303) to keep that invariant enforced over time.

Secondary: **point-of-use re-validation still applies even when the path came from the DB, not the request.** The public `/api/shared/[token]` reads `document_path` from `kb_share_links` (owner-supplied at share creation, not raw request input). Per the `2026-04-11-service-role-idor` learning, service-role operations must re-validate at point of use regardless of upstream validation. `readBinaryFile` does `isPathInWorkspace` + symlink + size checks on every call — skipping them because "the owner set it at creation time" defeats the defense.

## Security Hardening Applied Post-Review

- **Null-byte guard** (`readBinaryFile` + `POST /api/kb/share`) — a `\0` in `document_path` previously crashed `path.join` with `ERR_INVALID_ARG_VALUE` returning a generic 500. Now rejected as 403/400 explicitly.
- **RFC 6266 Content-Disposition** — emits both ASCII fallback `filename="..."` and UTF-8 `filename*=UTF-8''...`. Previous sanitization only replaced control characters and produced mangled downloads for non-ASCII names.
- **O_NOFOLLOW + fd-based read** — closes the lstat→readFile TOCTOU. Opening with `O_NOFOLLOW` rejects symlinks at the syscall layer; subsequent `fstat` and `readFile` operate on the held fd so swap-between-syscalls attacks can't redirect the read.

## Session Errors

1. **Write tool silently partial-applied after a security hook warning fired** — First Write of `app/shared/[token]/page.tsx` triggered `security_reminder_hook.py` (regex on child-process call patterns, irrelevant to the file content). The hook returned error output but only a prefix of the file content landed. Detected three tool calls later when the old-code-path error surfaced in tests. **Recovery:** switched to sequential `Edit` calls. **Prevention:** after any `Write` whose hook output mentions a rule/security warning, immediately `Read` the file to verify the full content landed. A skill-instruction edit in `work/SKILL.md` Phase 2 would help: "After every `Write` that produces non-empty hook output, verify the file size/line count matches expectations before proceeding."
2. **Chased a mock bug instead of a stale-file bug** — `TypeError: res.json is not a function` in `shared-page-ui.test.tsx`. First hypothesis: `new Headers({...})` was behaving oddly in happy-dom; switched to a plain-object mock. Didn't fix it. Root cause was error #1 (file not fully written). **Prevention:** when a test fails with behavior that contradicts a recent edit, first `Read` the file under test before modifying the test itself.
3. **6 of 9 review agents rate-limited simultaneously** — `security-sentinel`, `performance-oracle`, `pattern-recognition-specialist`, `test-design-reviewer`, `agent-native-reviewer`, `data-integrity-guardian` returned "You've hit your limit · resets 2pm". Only `architecture-strategist`, `code-quality-analyst`, `git-history-analyzer` produced findings. **Recovery:** proceeded with 3 successful + inline security/bug review focused on concrete fixes (null-byte, RFC 6266, TOCTOU, missing 413 test). **Prevention:** the review skill's Rate Limit Fallback gate only triggers when ALL agents fail; it should also detect "majority rate-limited" (≥50%) and either offer to resume later or automatically run the inline fallback for the missing coverage areas.

## Prevention / Follow-ups

- **Contract test** (issue #2303) — assert `/api/kb/content/<path>` (authenticated) and `/api/shared/<token>` (public, binary branch) return byte-identical response bodies and identical headers for the same underlying file.
- **Unified file-kind classifier** (issues #2297, #2317) — `isMarkdownExt`, `CONTENT_TYPE_MAP`, and the client-side viewer dispatch should share one source of truth.
- **Server-declared kind** (issue #2304) — instead of sniffing `Content-Type` client-side, the public API could return a discriminated payload tag, closing the silent-downgrade path where an unexpected content-type falls through to a download link.

## Related

- `knowledge-base/project/learnings/security-issues/2026-04-12-binary-content-serving-security-headers.md` — origin of the CSP, nosniff, filename-sanitization, async-I/O pattern applied here.
- `knowledge-base/project/learnings/security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments.md` — service-role IDOR: re-validate at point of use.
- `knowledge-base/project/learnings/2026-04-07-symlink-escape-recursive-directory-traversal.md` — symlink rejection at every read site.
- `knowledge-base/project/learnings/ui-bugs/2026-04-10-kb-nav-tree-disappears-on-file-select.md` — same UI-branch-asymmetry class of bug.
- `knowledge-base/project/plans/2026-04-10-feat-kb-document-sharing-plan.md` — original sharing design; notes `.md`-only was MVP scope.
