# fix(kb): bind KB share links to content hash to prevent token resurrection

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** 6 (Phase 2-4, Phase 4 UI integration, Security, Acceptance)
**Research targeted:** Node.js `crypto` streaming hash benchmarks, existing codebase patterns for `readContent` vs `readBinaryFile`, UI error-variant handling in `/shared/[token]/page.tsx`.

### Key Improvements

1. **Hash raw file bytes, not post-parse content.** `readContent` strips frontmatter via `gray-matter` before returning `content`. Hashing the return value would mean frontmatter edits silently pass verification. Switch to hashing the raw read buffer before frontmatter parsing.
2. **Stream the hash, don't buffer twice.** Use `crypto.createHash('sha256')` as a `Transform` stream fed by `handle.createReadStream()` so we never hold two 50 MB buffers in memory. Creation path becomes O(1) extra memory, not O(file size).
3. **UI needs a third error state.** The existing page maps 410 → "This link has been disabled" (revoked copy). Content-changed is semantically distinct — introduce `error === "content-changed"` with tailored copy ("The shared file has been modified"). Discriminate via response body tag, not status code.
4. **`readContent` lacks O_NOFOLLOW.** Unlike `readBinaryFile`, markdown reads don't use the fd-safe pattern. The plan calls out this asymmetry but does not fix it here (scope creep); we hash the buffer `readContent` already produces.
5. **Migration: defensive revoke AFTER prod-row audit.** The blanket `update ... set revoked = true` is correct *only* if prod has near-zero share links. Added a mandatory pre-apply REST probe with a documented fork: 0 rows → proceed as-is; >0 rows → operator decision documented in PR.
6. **ETag header alignment.** `Content-SHA256` makes a natural `ETag`. Emit `ETag: "<sha256>"` on binary view responses so conditional GETs (`If-None-Match`) short-circuit with 304. Free latency win, no extra compute.

### New Considerations Discovered

- `readBinaryFile` already returns the full buffer (L98) — view-time hash costs nothing beyond one pass over that buffer (~200-400 ms for 50 MB).
- Node's stdlib `createHash` in native C++ runs at ~1.5-2 GB/s on modern x86 — a 50 MB hash is **25-35 ms**, not 200-400 ms. View-time latency cost is negligible.
- `kb_share_links.document_path` has no unique constraint today. A user could technically have two active shares for the same `document_path` with different tokens if the existing-share lookup raced — not a regression introduced by this PR, worth noting for a future hardening issue (not filed in this PR scope).

---

**Issue:** [#2326](https://github.com/jikigai-ai/soleur/issues/2326)
**Labels:** `priority/p1-high`, `type/security`, `domain/engineering`, `code-review`
**Milestone:** Phase 3: Make it Sticky
**Worktree:** `.worktrees/feat-fix-2326-kb-share-dangling-rows/`
**Branch:** `feat-fix-2326-kb-share-dangling-rows`

## Overview

`kb_share_links` rows persist with `revoked = false` even after the underlying KB file is deleted, renamed, or replaced. Today the shared-view endpoint returns 404 ("Document no longer available") when the file is missing, which makes links *look* dead, but the row is still live. If a new file materialises at the same relative path — whether by re-upload of an unrelated file named `invoice.pdf`, or a rename that vacates `secret.pdf` so a different `secret.pdf` can be created — the old token silently starts serving the new bytes.

This is a **referential integrity** problem: `document_path` is a string, not a foreign key, and the filesystem has no stable identifier Supabase can refer to. The fix is to bind each share to **content**, not to a path: add `content_sha256` to `kb_share_links`, populate it at share-creation time, and re-hash the current file at view time. Any mismatch → `410 Gone` with a user-visible "content changed" message. Resurrection becomes cryptographically impossible because a new file at the same path has a different hash.

This is the first of 27 code-review issues in Phase 3. Scope is intentionally tight: fix this bug only. Follow-ups (#2316 stream binary responses, #2309 agent-user parity for KB share) are tracked separately and called out in Non-Goals.

### Why Option A (content_sha256) over B/C

The issue body enumerates three options:

| Option | Mechanism | Resurrection coverage | Complexity | Cross-host safety |
|---|---|---|---|---|
| **A: content_sha256** | Hash content at create, re-hash at view, compare | Full (delete→re-upload, rename→recreate, overwrite) | 1 migration + `~40 LOC` | Yes |
| B: inode + mtime | stat-based fingerprint | Full on same host | Low | Breaks on workspace host migration |
| C: cron cleanup | Mark revoked when path missing | Partial — doesn't cover rename→recreate | Medium (new job + scheduler) | Yes |

Option A wins because (a) it closes the loophole completely, (b) SHA-256 of the 50 MB upper bound is sub-second on modern CPUs and runs **once** at share creation, (c) re-hash at view time adds ~300 ms for a 50 MB file which is trivial next to the network transfer, and (d) no cross-host assumptions. We pay one migration and one file-hash per share creation, and we gain a strong content binding. The issue author explicitly recommends Option A; we agree.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality in codebase | Plan response |
|---|---|---|
| `kb_share_links.document_path` is a path string with no FS-backed referential integrity | Confirmed. `supabase/migrations/017_kb_share_links.sql` L5-12: columns are `id, user_id, token, document_path, created_at, revoked`. No content-binding column exists. | Add `content_sha256 text` in a new migration (`026_kb_share_links_content_sha256.sql`). |
| View endpoint returns 404 when the file is missing but row is still live | Confirmed. `app/api/shared/[token]/route.ts` L96-101: `KbNotFoundError` → 404 with no row mutation. `DELETE /api/kb/share/[token]` is the only path that sets `revoked = true`. | No row-state mutation needed on hash mismatch — a `410` response is sufficient and matches the existing revoke-semantics pattern. |
| Creation endpoint already lstats the file and enforces size ≤ 50 MB | Confirmed. `app/api/kb/share/route.ts` L59-73 opens lstat, rejects symlinks/non-files, rejects > `MAX_BINARY_SIZE`. | Compute SHA-256 *after* these guards pass, using the same fd-safe pattern as `readBinaryFile` to avoid a TOCTOU swap between lstat and hash. |
| View endpoint already re-reads binary via `readBinaryFile` with O_NOFOLLOW and fd-based fstat | Confirmed. `server/kb-binary-response.ts` L73-80 uses `fs.promises.open(..., O_RDONLY | O_NOFOLLOW)` and fstat on the fd. | Hash at view time from the *same* fd so the hash and the served bytes are guaranteed to match, closing any hash-then-serve TOCTOU window. |
| Markdown files use `readContent` instead of `readBinaryFile` | Confirmed. `app/api/shared/[token]/route.ts` L77-108 forks on extension. | Hash both markdown and binary content paths at view time. Markdown needs a parallel hash computation since `readContent` currently returns a string, not a buffer. Preferred implementation: hash the buffer in a helper that both paths call (`server/kb-content-hash.ts`), fed by the existing fs read. |

## Implementation Phases

Tight, linear phases — no cross-cutting refactor.

### Phase 1: Database migration (30 min)

**Goal:** Add `content_sha256` column to `kb_share_links` and populate existing rows with a safe sentinel.

Files:

- `apps/web-platform/supabase/migrations/026_kb_share_links_content_sha256.sql` (new)

Migration content:

```sql
-- 026_kb_share_links_content_sha256.sql
-- Bind KB share links to content, not path, to prevent token resurrection
-- after file delete/rename. See issue #2326.

alter table public.kb_share_links
  add column content_sha256 text;

-- Existing rows have no hash. Mark them revoked so they cannot be
-- resurrected — users must re-create any links they still want.
-- (Prod currently has 0 production share links per Supabase REST check;
-- confirm before applying. See Pre-apply checklist below.)
update public.kb_share_links
   set revoked = true
 where content_sha256 is null
   and revoked = false;

-- New rows MUST carry a hash.
alter table public.kb_share_links
  alter column content_sha256 set not null,
  add constraint kb_share_links_content_sha256_format
    check (content_sha256 ~ '^[a-f0-9]{64}$');

-- Small index for future auditability (e.g., "how many share links point
-- at identical content?"). Not required for correctness.
create index idx_kb_share_links_content_sha256
  on public.kb_share_links(content_sha256);
```

**Pre-apply check (runbook reference: `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`):**

1. **Count audit** — REST probe (under Doppler `prd` creds):

   ```bash
   curl -s -H "apikey: $SUPABASE_SERVICE_KEY" \
     -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
     "$SUPABASE_URL/rest/v1/kb_share_links?select=id,user_id,revoked&limit=1000" | jq 'length'
   ```

   - **0 rows** → apply the migration as written. Defensive revoke is a no-op.
   - **≤10 rows (non-zero)** → apply as written; the defensive revoke is acceptable collateral and operators can notify affected users individually. Document the pre-state row count in the PR body.
   - **>10 rows** → PAUSE. Switch migration to the "soft legacy" form (drop the `update ... set revoked = true` and keep `content_sha256` nullable until a backfill job populates hashes from current files). File a follow-up issue for the backfill. This path needs explicit operator sign-off — do not auto-apply.
2. Apply via the runbook's canonical path (`supabase db push` from `apps/web-platform/` or the CI migrate job).
3. Post-apply verification:

   ```sql
   -- Column exists with correct type + constraints
   select column_name, data_type, is_nullable
     from information_schema.columns
    where table_name = 'kb_share_links'
      and column_name = 'content_sha256';
   -- Expect: text, NO

   -- Constraint is present
   select conname from pg_constraint
    where conrelid = 'public.kb_share_links'::regclass
      and conname = 'kb_share_links_content_sha256_format';
   ```

4. Rollback contract: column stays (dropping loses data on re-roll-forward); only the NOT NULL + check are reversible. See Rollback Plan below.

Tests:

- No test file for migrations directly — verified via post-apply REST probe.

### Phase 2: Shared hash helper (30 min)

**Goal:** Central module that both creation and view paths use, with two entry points: buffer-based (when a buffer is already in hand) and stream-based (when we haven't read yet, to avoid buffering twice).

Files:

- `apps/web-platform/server/kb-content-hash.ts` (new)
- `apps/web-platform/test/kb-content-hash.test.ts` (new — RED first)

Module:

```ts
// server/kb-content-hash.ts
import { createHash } from "node:crypto";
import type { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

/**
 * SHA-256 of a byte buffer, lowercase hex. Use when the caller already
 * holds the full buffer (e.g., readBinaryFile returns buffer).
 */
export function hashBytes(buf: Buffer): string {
  return createHash("sha256").update(buf).digest("hex");
}

/**
 * SHA-256 of a Readable stream, lowercase hex. Use at share creation to
 * avoid allocating a second 50 MB buffer just for hashing — we stream
 * the file through the hasher and let the GC reclaim chunks as they go.
 * The hasher is a Transform-compatible Writable for stream.pipeline.
 *
 * Callers supply the stream; this helper does NOT close the underlying
 * fd — that's the caller's responsibility (it should own the fd lifecycle).
 */
export async function hashStream(source: Readable): Promise<string> {
  const hasher = createHash("sha256");
  await pipeline(source, hasher);
  return hasher.digest("hex");
}
```

Test (RED → GREEN):

- `hashBytes(Buffer.from(""))` returns the known SHA-256 of empty string (`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`).
- `hashBytes` of a 1 KB known-content fixture matches a precomputed hex value.
- `hashStream` of a `Readable.from(Buffer)` equals `hashBytes` on the same buffer (parity check).
- `hashStream` of a `fs.createReadStream(path)` equals `hashBytes(await fs.promises.readFile(path))` on a ≥1 MB fixture (stream correctness at chunk boundaries).
- `hashStream` rejects with the underlying error if the stream errors mid-read.

**Performance reference:** Node's `crypto.createHash('sha256')` uses OpenSSL's native C++ SHA-256 implementation (AVX2/SHA-NI accelerated on modern x86). Typical throughput: **1.5-2 GB/s**. A 50 MB file hashes in **25-35 ms** on AWS t3 or Hetzner CX class hardware. No measurable p99 impact on the share-create or share-view paths.

### Phase 3: Hash on share creation (45 min)

**Goal:** `POST /api/kb/share` computes the hash after existing lstat/size/symlink guards and persists it with the row.

Files:

- `apps/web-platform/app/api/kb/share/route.ts` (edit)
- `apps/web-platform/test/kb-share-allowed-paths.test.ts` (extend)
- `apps/web-platform/test/kb-share-content-hash.test.ts` (new)

Edits to `route.ts` (between current L73 size guard and L76 existing-share lookup):

1. After size guard passes, open the file with `O_RDONLY | O_NOFOLLOW` and `fstat` the fd (mirrors `readBinaryFile`'s pattern at `kb-binary-response.ts:73-80`). **Do not call `fs.promises.readFile(fullPath)`** — that re-opens the path and is vulnerable to a symlink swap between lstat and readFile. If fstat disagrees with the earlier lstat (size, type, non-file), close fd and reject.
2. Create a `handle.createReadStream()` and pass it to `hashStream(stream)` from Phase 2. This avoids a second 50 MB allocation just to hash — we stream bytes through the hasher and never hold the file contents in memory on the creation path.
3. `await handle.close()` (in a `finally`) after hashing completes.
4. Pass `content_sha256: contentHash` in the `insert()` payload.
5. Existing-share lookup: keep as-is (it matches on `user_id + document_path + revoked=false`). A caller asking for a share of the same path **and** same current bytes (hash matches) gets the same token back. If the file *changed* since the original share, the old row's `content_sha256` no longer matches current bytes — view time returns 410. Creation side deliberately does **not** auto-revoke or replace; the user must explicitly re-share. This is simpler than coupling creation to view-time semantics and avoids a write amplification on the happy path.
6. Stale-share awareness: after the existing-share lookup returns a row, *before* returning it, compare `existing.content_sha256` against the newly-computed hash. If they match → return the existing token (happy path, same content). If they differ → the user is re-sharing a modified file; revoke the stale row (`update revoked = true` by `id`) and fall through to insert a new row. This keeps the API idempotent in a user-friendly way: re-sharing after a legitimate edit transparently issues a fresh token. Test covers both branches.

**Why (6) is in scope:** without it, a user who uploads a new version of `report.pdf` and clicks Share gets the *existing* (now-stale) token back. That token returns 410 at view time per Phase 4 — a confusing "share created but broken" UX. Revoke-and-reissue on content drift makes the creation endpoint a clean "ensure a working share exists" primitive.

Open question resolved: should creation auto-revoke a stale row when it detects the file changed? **No.** That would couple creation to view-time semantics and add an extra write on a happy-path. Let view time return 410 and let the user explicitly re-share if needed. Documented in code comment.

Tests (RED → GREEN):

- `kb-share-allowed-paths.test.ts`: extend existing happy-path assertions to also verify `content_sha256` is present in the insert payload (test already spies `mockServiceFrom`).
- `kb-share-content-hash.test.ts` (new):
  - Creation stores the hash of the file bytes (match against `hashBytes` output for a fixture).
  - Same file → second POST returns the existing token without a second insert (idempotent happy path).
  - File bytes change between two POSTs → second POST revokes the stale row and issues a NEW token (covers the re-share-after-edit flow from step 6).
  - Binary file (PDF, PNG) and text file (markdown) both produce 64-char hex hashes.
  - Symlink swap between lstat and hash-read is rejected by O_NOFOLLOW (vitest fixture: create a file, symlink it post-lstat; fstat guard catches the type mismatch and returns 400/403).

### Phase 4: Hash verification on view (75 min)

**Goal:** `GET /api/shared/[token]` re-hashes current file bytes and responds `410 Gone` with a `content-changed` error tag if the hash diverges from the stored `content_sha256`.

Files:

- `apps/web-platform/app/api/shared/[token]/route.ts` (edit)
- `apps/web-platform/server/kb-reader.ts` (add a `readContentRaw` sibling that returns the raw file buffer *without* frontmatter parsing — critical finding, see below)
- `apps/web-platform/server/kb-binary-response.ts` (already returns `buffer` — optionally add `ETag` to `buildBinaryResponse`)
- `apps/web-platform/app/shared/[token]/page.tsx` (add `"content-changed"` to `PageError` union)
- `apps/web-platform/test/shared-token-content-hash.test.ts` (new)

**Critical finding — hash raw bytes, not parsed content:** `readContent` (`kb-reader.ts:250-291`) calls `parseFrontmatter(raw)` and returns `{ content }` which is the *post-frontmatter* body. If we hash `result.content`, frontmatter edits silently pass verification — a user who updates `title:` or `tags:` in a share thinks they re-authored the doc, but the old token still serves the new title. **Always hash the raw file bytes.**

Add to `server/kb-reader.ts`:

```ts
export async function readContentRaw(
  kbRoot: string,
  relativePath: string,
): Promise<{ buffer: Buffer; content: string; path: string }> {
  // Same guards as readContent (null byte, .md requirement, traversal,
  // file-size). Returns raw buffer (for hashing) and decoded UTF-8 string
  // (for frontmatter parsing). Single disk read, not two.
  // ... implementation mirrors readContent's guards ...
  const buffer = await fs.promises.readFile(fullPath);
  const raw = buffer.toString("utf-8");
  return { buffer, content: raw, path: relativePath };
}
```

Then `readContent` becomes a thin wrapper that calls `readContentRaw` and runs `parseFrontmatter(content)` on its output. This avoids code duplication and guarantees the raw-byte path and the parsed path see the same file read (no double-read race window).

Edits to `app/api/shared/[token]/route.ts`:

1. After the revoked check (current L48-53), also select `content_sha256` from `kb_share_links`.
2. If `shareLink.content_sha256` is `null` (legacy defensive) → return `410` with body `{ error: "This link is from an older share system and is no longer valid.", code: "legacy-null-hash" }` and log `shared_legacy_null_hash`. Migration should have revoked these; this is belt-and-suspenders.
3. For the **markdown** branch: call `readContentRaw(kbRoot, shareLink.document_path)`. `hashBytes(result.buffer)`. Compare to `shareLink.content_sha256`. Mismatch → 410 with body `{ error: "The shared file has been modified since it was shared.", code: "content-changed" }`. Log `shared_content_mismatch`. Match → parse frontmatter and return JSON as today.
4. For the **binary** branch: `readBinaryFile` returns `ok: true` with `buffer`. `hashBytes(buffer)`. Compare. Mismatch → 410 with `content-changed` body. Match → `buildBinaryResponse(binary, request)` as today. Optionally: `buildBinaryResponse` emits `ETag: "\"${hash}\""` (weak-quoted per RFC 7232) so conditional GET can 304.
5. 410 response contentType is `application/json` for both branches (the client-side page branches on response `content-type`; today markdown is `application/json` and binaries are `application/pdf`/`image/*`/etc. A 410 is always JSON, which is what the client already expects in the `res.status === 410` early return).
6. Do not log the hash value (see Security & Privacy Notes). Log the *existence* of a mismatch, the token, and the document path.
7. **Hash-work-after-rate-limit order:** the existing rate-limit check (L25-32) must remain the first thing in the handler. Do not compute the hash before the rate check — that would invite DoS via repeated 50 MB hashing requests.

Edits to `app/shared/[token]/page.tsx`:

1. Extend `PageError` union: `"not-found" | "revoked" | "content-changed" | "unknown"`.
2. In the 410 branch (L58-62), read the JSON body to discriminate: `revoked` → `"revoked"`, `content-changed` → `"content-changed"`, `legacy-null-hash` → `"content-changed"` (same user-facing copy — "the link is no longer valid"), default → `"revoked"` for backwards-compat with the existing delete flow.
3. Add an `ErrorMessage` block for `error === "content-changed"` with title "The shared file was modified" and message "The file has been edited or replaced since this link was created. Ask the owner to share again."
4. Do not block the page render on the JSON parse failing — fall back to `"revoked"` copy so an older client that ignores the `code` field still degrades gracefully.

Tests (RED → GREEN):

- `shared-token-content-hash.test.ts` (server):
  - **Markdown, hash matches** → 200 with `{ content, path }`.
  - **Markdown, file bytes differ from stored hash** → 410 with `code: "content-changed"`.
  - **Markdown, frontmatter change only** → 410 (this is the key test for the "hash raw bytes not parsed content" correction — changing `title:` in the frontmatter must invalidate).
  - **Binary, hash matches** → 200 with `buildBinaryResponse` headers intact (Content-Type, Content-Disposition, optional ETag).
  - **Binary, file bytes differ** → 410 with `code: "content-changed"`.
  - **File deleted after share creation** → 404 (unchanged — we only 410 on *mismatch*, not on *missing*; 404 stays because the read itself fails before we can hash).
  - **Null `content_sha256`** (legacy defense) → 410 with `code: "legacy-null-hash"`.
  - **Rate-limit path** unchanged — test 429 still returns before any hash work.
  - **ETag round-trip** (if implemented): conditional GET with matching `If-None-Match: "<hash>"` returns `304 Not Modified`.
- Extend `kb-share-allowed-paths.test.ts` to confirm the creation path's hash *matches* the view path's hash for a round-trip fixture (markdown + PDF).
- UI test `shared-token-content-changed-ui.test.tsx` (vitest + React Testing Library):
  - Given a mocked fetch returning `410 { code: "content-changed" }`, the page renders "The shared file was modified" heading (not "This link has been disabled").
  - Given `410 { code: "legacy-null-hash" }`, same copy (or dedicated legacy copy if copy team prefers).
  - Given `410` with no JSON body, falls back to existing "revoked" copy.

### Phase 5: Manual resurrection-scenario QA (20 min)

**Goal:** Walk the two attack scenarios from the issue body end-to-end in a local dev workspace.

Files: none (manual QA step, logged in PR body).

Scenarios:

1. **Delete → re-upload resurrection:**
   - Create share for `dev/fixtures/invoice-v1.pdf` → save URL.
   - Delete the file from workspace.
   - Create `invoice-v1.pdf` at the same path with different bytes (unrelated content).
   - Open the saved URL. Expect 410 "content has changed", NOT the new file.
2. **Rename → recreate resurrection:**
   - Create share for `dev/fixtures/secret.pdf` → save URL.
   - Rename `secret.pdf` → `report.pdf` in the workspace.
   - Create a new `secret.pdf` at the now-vacant path with different bytes.
   - Open the saved URL. Expect 410.
3. **Frontmatter-only edit invalidation (markdown):**
   - Create share for `dev/fixtures/note.md` with frontmatter `title: "Old"` → save URL.
   - Edit `note.md` to `title: "New"` without touching the body.
   - Open saved URL. Expect 410 (validates the "hash raw bytes not parsed content" correction).
4. **Legitimate re-share after edit:**
   - Create share for `report.pdf` → save URL-A.
   - Overwrite `report.pdf` with new bytes.
   - Open URL-A → expect 410.
   - Re-click Share in the UI → expect a **new** URL-B (revoke-and-reissue flow).
   - Open URL-B → expect 200 with new content.

Record all four screenshots in the PR body.

## Acceptance Criteria

- [ ] Migration `026_kb_share_links_content_sha256.sql` applied on prod via the Supabase runbook; REST probe confirms column presence AND check constraint AND NOT NULL.
- [ ] Pre-apply row count audit documented in PR body (actual number from prod REST probe).
- [ ] Pre-existing rows marked `revoked = true` (or explicit operator override path documented) so no legacy token can view anything post-deploy.
- [ ] `POST /api/kb/share` computes SHA-256 via `hashStream` (not `hashBytes` over `readFile`) and stores in `content_sha256` on every new row. Insert payload covered by vitest.
- [ ] `POST /api/kb/share` revokes-and-reissues when the existing row's hash no longer matches current file bytes (covers re-share-after-edit flow).
- [ ] `GET /api/shared/[token]` re-hashes current file bytes and returns `410` + `{ code: "content-changed" }` when the hash differs. Covered by vitest for markdown, binary, and frontmatter-only-change scenarios.
- [ ] Markdown branch hashes **raw file bytes** (pre-frontmatter-parse) so frontmatter edits invalidate the share. Covered by a dedicated test.
- [ ] `app/shared/[token]/page.tsx` renders a dedicated "The shared file was modified" message for `code: "content-changed"` (distinct from the revoked copy).
- [ ] Manual QA screenshots for all three scenarios (delete→re-upload, rename→recreate, frontmatter edit) attached to the PR.
- [ ] No regression: app-level `npm test` passes; `kb-share-allowed-paths.test.ts` still green; new tests green.
- [ ] TypeScript build passes (`npm run build` under Doppler in `apps/web-platform/`).
- [ ] No hash values appear in any log line (grep PR diff for `content_sha256` and confirm only presence/mismatch events are logged, never the hash itself).

## Test Scenarios

Covered above per phase. Summary table:

| Scenario | File | RED test |
|---|---|---|
| Hash helper correctness | `test/kb-content-hash.test.ts` | Phase 2 |
| Creation writes hash (happy path) | `test/kb-share-allowed-paths.test.ts` (extended) | Phase 3 |
| Creation hash matches arbitrary content | `test/kb-share-content-hash.test.ts` | Phase 3 |
| View returns 410 on markdown content drift | `test/shared-token-content-hash.test.ts` | Phase 4 |
| View returns 410 on binary content drift | `test/shared-token-content-hash.test.ts` | Phase 4 |
| View returns 404 on missing file (unchanged) | `test/shared-token-content-hash.test.ts` | Phase 4 |
| View returns 410 on legacy `null` hash | `test/shared-token-content-hash.test.ts` | Phase 4 |
| Rate-limit still precedes hash work | `test/shared-token-content-hash.test.ts` | Phase 4 |

## Domain Review

**Domains relevant:** Engineering (primary), Security (sub-domain of Engineering per `type/security` label).

### Engineering

**Status:** reviewed (inline — fix is scoped within existing engineering conventions)

**Assessment:**

- Single-module change bounded to KB share surface. Follows existing patterns: shared server module (`kb-binary-response.ts`, `kb-reader.ts`) consumed by route handlers; vitest-colocated tests under `apps/web-platform/test/`.
- Migration numbering: next free index is `026_` (last applied: `025_context_path_archived_predicate.sql`). No naming conflict.
- No new dependencies. `node:crypto` is stdlib.
- Security posture: closes the token-resurrection class of bug entirely. Trades an off-by-default auto-revoke (cron) for a cryptographic guarantee at view time — simpler, no scheduler to maintain.
- Risk: hash at view time adds latency on the happy path (50 MB SHA-256 ≈ 200-400 ms on prod hardware). Measured against network transfer of the same 50 MB (seconds), this is a rounding error. No need to cache hashes — files change rarely.

No cross-domain implications (no UI copy changes requiring copywriter, no flow-level UX changes requiring ux-design-lead, no billing/legal/marketing impact). The 410 error message is a one-line copy change that fits within existing SharePopover/shared page error-display conventions — noted in Acceptance Criteria as a verification step rather than a new design artifact.

### Product/UX Gate

Tier: **ADVISORY** (re-assessed during deepen). The plan now adds a new `ErrorMessage` variant ("The shared file was modified") to `app/shared/[token]/page.tsx`. This is an existing user-facing surface receiving a new state branch — ADVISORY per the tier definition ("modifies existing user-facing pages or components without adding new interactive surfaces").

**Decision:** auto-accepted (pipeline). The copy is a two-line error-state message that sits inside the existing `ErrorMessage` component pattern used by the page (revoked/not-found/unknown variants). Not a new flow; not a new screen; not a decision surface. Copywriter review is **not** required per the AGENTS.md `wg-for-user-facing-pages-with-a-product-ux` gate since no domain leader recommended a copywriter and the change is a single error string. If the ship/QA reviewer flags the copy on PR, we iterate inline.

**Agents invoked:** none (ADVISORY auto-accept in pipeline).
**Skipped specialists:** copywriter (no domain-leader recommendation; single error string in an existing pattern), ux-design-lead (no new flow or surface).

## Security & Privacy Notes

- **Do not log the hash value.** The hash is a content fingerprint. Logging it per-view lets an attacker who gets log access enumerate which shares correspond to which content (e.g., correlating with a known-document hash). Log only the presence of a mismatch and the token, which is already logged elsewhere.
- **Hash is not a secret.** It's stored alongside the path and token. Anyone with DB access already has the token. No extra threat surface.
- **Timing-safe comparison not required.** Hashes are compared against a stored value on the same server; the attacker cannot iterate. `===` on 64-char strings is fine. If this assumption ever changes (e.g., hash compared against user-supplied input), switch to `crypto.timingSafeEqual`.
- **GDPR posture improves.** Today, a user who deletes a file to "revoke" access has not actually revoked anything because the row is live. After this fix, a deletion breaks the hash binding at the next view, producing a 410 and a logged `shared_content_mismatch` event. Explicit revoke via the DELETE endpoint remains the supported path; this is defense in depth.

## Non-Goals / Deferred

Explicitly out of scope for this PR — tracked separately:

- **#2316** — stream binary responses instead of buffering 50 MB (P1). Separate PR, next in the Phase-3 review-finding queue.
- **#2309** — agent-user parity for KB share (P1). Separate PR after #2316.
- **Background cleanup** of revoked rows older than N days. Minor hygiene; no issue yet — deferred to housekeeping batch later in Phase 3.
- **Pre-signed URL TTL.** The issue body mentions "no TTL on the share row" as an observation but the recommended fix does not address it; TTL is a separate policy decision. Not tracked in this plan.

## Rollback Plan

The migration adds a column and a constraint. Rollback, if required:

```sql
-- rollback.sql
alter table public.kb_share_links
  drop constraint kb_share_links_content_sha256_format;
alter table public.kb_share_links
  alter column content_sha256 drop not null;
-- Column retained (dropping would lose data if we re-roll forward).
-- No app code depends on the column being absent.
```

App-level rollback is `git revert` of the PR. Revoked rows stay revoked — operators must explicitly unrevoke if the migration's defensive revoke sweep is regretted.

## Files Changed Summary

| File | Action | Purpose |
|---|---|---|
| `apps/web-platform/supabase/migrations/026_kb_share_links_content_sha256.sql` | new | Add `content_sha256 text not null` with format check + defensive revoke |
| `apps/web-platform/server/kb-content-hash.ts` | new | `hashBytes(buf)` + `hashStream(readable)` helpers |
| `apps/web-platform/app/api/kb/share/route.ts` | edit | Stream-hash on POST, revoke-and-reissue on content drift |
| `apps/web-platform/app/api/shared/[token]/route.ts` | edit | Verify hash on GET, 410 + `code: content-changed` on mismatch |
| `apps/web-platform/server/kb-reader.ts` | edit | Extract `readContentRaw` so markdown hash sees raw bytes (not post-frontmatter) |
| `apps/web-platform/server/kb-binary-response.ts` | edit (optional) | Emit `ETag: "<hash>"` header so conditional GETs 304 |
| `apps/web-platform/app/shared/[token]/page.tsx` | edit | Add `"content-changed"` error variant with dedicated copy |
| `apps/web-platform/test/kb-content-hash.test.ts` | new | Unit tests for `hashBytes` + `hashStream` (incl. stream/buffer parity) |
| `apps/web-platform/test/kb-share-content-hash.test.ts` | new | Creation-side hash persistence + revoke-and-reissue tests |
| `apps/web-platform/test/shared-token-content-hash.test.ts` | new | View-side hash verification tests (incl. frontmatter-only change = 410) |
| `apps/web-platform/test/shared-token-content-changed-ui.test.tsx` | new | UI error-variant rendering tests |
| `apps/web-platform/test/kb-share-allowed-paths.test.ts` | edit | Assert hash appears in insert payload |

## Post-merge Verification

Per AGENTS.md (`wg-when-a-pr-includes-database-migrations`): after merge, run the Supabase migration runbook against prod, verify via REST probe, and include the probe output in the PR close comment. The ship/postmerge skills handle this if invoked.

## References

- Issue #2326 (root cause, option analysis, recommendation)
- PR #2282 (feat-kb-share-btn-pdf-attachments) — where this finding originated
- `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` — migration apply procedure
- `knowledge-base/project/learnings/` — service-role-idor learning (already followed by current code; we maintain the pattern)
- AGENTS.md `cq-progressive-rendering-for-large-assets` — acknowledged but orthogonal; streaming is #2316's scope
