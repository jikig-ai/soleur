# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-fix-2326-kb-share-dangling-rows/knowledge-base/project/plans/2026-04-17-fix-kb-share-dangling-rows-plan.md
- Status: complete

### Errors

None

### Decisions

- **Option A (content_sha256 binding)** chosen over inode+mtime or cron-cleanup — closes delete→re-upload, rename→recreate, and overwrite resurrection completely; SHA-256 of 50 MB is ~25-35 ms on native OpenSSL so view-time cost is negligible.
- **Hash raw file bytes, not post-parse content.** `readContent` strips frontmatter before returning `content` — hashing that would silently pass frontmatter-only edits. Added `readContentRaw` helper and a dedicated test scenario.
- **Stream-hash on creation, buffer-hash on view.** Creation uses `hashStream(handle.createReadStream())` so we don't hold two 50 MB buffers; view uses `hashBytes` over the buffer `readBinaryFile` already produces — no double-read.
- **Revoke-and-reissue on content drift at creation time.** If a user re-shares a modified file, the stale row is revoked and a fresh token issued — keeps endpoint idempotent and user-friendly.
- **New UI error variant (`content-changed`).** Discriminated via response body `code`, not status code, so the existing 410→revoked mapping stays intact. Tier re-assessed NONE→ADVISORY during deepen.
- **Pre-apply migration audit fork.** Row-count probe with three branches (0, 1-10, >10) so the defensive `update ... set revoked = true` doesn't surprise operators at scale.

### Components Invoked

- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Bash, Read, Grep, Edit, Write, Glob
- gh CLI (issue #2326, #2316, #2309 metadata)
- markdownlint-cli2 (plan + tasks lint pass, 0 errors)
