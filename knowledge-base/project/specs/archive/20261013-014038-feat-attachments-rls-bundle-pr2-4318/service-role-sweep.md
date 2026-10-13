---
date: 2026-05-25
feature: attachments-rls-bundle-pr2-4318
plan: knowledge-base/project/plans/2026-05-25-feat-attachments-workspace-shared-pr2-plan.md
phase: 3.5
ac: AC13
---

# Service-role surface sweep — chat-attachments bucket

`rg -n "storage\.from\(['\"]chat-attachments['\"]\)" apps/web-platform/` run 2026-05-25 on `feat-attachments-rls-bundle-pr2-4318`.

| # | File:Line | Caller context | Op | Service-role? | Assertion shape |
|---|---|---|---|---|---|
| 1 | `apps/web-platform/server/account-delete.ts:188` | full account-delete cascade | `.remove(allPaths)` | yes | Phase 5 widens enumeration via `message_attachments` ⨝ `conversations.user_id = departing_user`; Art. 17 carve-out retains co-uploaded objects in shared convs. |
| 2 | `apps/web-platform/server/attachment-pipeline.ts:149` | message-author persist+download (legacy + cc-soleur-go) | `.download(att.storagePath)` | no — docstring (`PersistAttachmentsArgs.supabase`) mandates tenant-scoped client; RLS via mig 068 SELECT policy is load-bearing | Path-prefix guard at `:91-96` enforces `${userId}/${conversationId}/`. Author's own upload (via presign) lands there; co-member uploads happen on the co-member's OWN persist call (segment-1 = their userId). Defense-in-depth note added inline. |
| 3 | `apps/web-platform/server/dsar-export.ts:1198` | DSAR export bucket-enumeration | `.list(...)` (metadata) + `.download(...)` (bytes) | yes | Phase 5 widens enumeration to workspace-scope; pre-download seam (architecture P1-5) re-asserts `(foldername)[2]` resolves to a conv the DSAR requester participated in. |
| 4 | `apps/web-platform/app/api/attachments/url/route.ts:71` | tenant-initiated signed-URL mint | `.createSignedUrl(...)` | yes (service mints URL; tenant identity is upstream) | **Phase 3 widening** (this PR): inline conv lookup + `is_workspace_member` precedes the createSignedUrl call. `reportSilentFallback` on cutover-deny. |
| 5 | `apps/web-platform/app/api/attachments/presign/route.ts:115` | tenant-initiated upload-URL mint | `.createSignedUploadUrl(...)` | yes (service mints URL; tenant identity is upstream) | **Phase 3 widening** (this PR): inline conv lookup + `is_workspace_member` precedes the createSignedUploadUrl. Storage policy (mig 068 INSERT) narrows the actual upload to own-folder regardless. |

## Byte-fetch site that is NOT yet a fetch — documentation deferred to future PR

`apps/web-platform/server/agent-runner.ts:569` selects `message_attachments(filename, content_type, size_bytes)` joined to `messages` via a tenant-scoped client. Metadata-only today; if/when transitioned to a byte-fetch path, an explicit `assertReaderMayAccessAttachment(...)` call (or equivalent inline conv-membership check) MUST be inserted before the fetch — same shape as the url/route.ts Phase 3 widening. Inline comment added.

## Closeout

All service-role byte-read callsites either (a) widen enumeration in Phase 5 (sites 1, 3) or (b) carry inline conv-membership widening in Phase 3 (sites 4, 5). Site 2 (tenant-scoped, path-prefix-guarded) is load-bearing on RLS — mig 068's SELECT policy widening covers the co-member case at the storage layer.

Negative-space gate (AC13): `rg "storage\.from\(['\"]chat-attachments['\"]\).*\.\(download\|createSignedUrl\)" apps/web-platform/server/` returns matches only at sites 1, 3, and each is preceded (within 30 lines) by the explicit reader-may-access check documented above.
