# KB File Upload Brainstorm

**Date:** 2026-04-12
**Issue:** [#1974](https://github.com/jikig-ai/soleur/issues/1974)
**Branch:** feat-kb-file-upload
**Participants:** Founder, CPO, CMO, CTO

## What We're Building

Independent file upload in the KB viewer — users upload files (images, PDFs, CSVs, text files, .docx) directly to a KB directory. Files are committed to the git repo via the GitHub Contents API through the server-side proxy, giving agents native discoverability and full data portability.

## Why This Approach

**Data portability wins.** The founder's entire knowledge base, including uploads, lives in their git repo. They `git clone` and walk away with everything. No vendor lock-in on file storage.

**Agent discoverability.** Because files are committed to git, agents see them the same way they see any KB file — no retrieval layer needed. This directly supports the compounding moat (Theme T3: Make the Moat Visible).

**Infrastructure reuse.** Chat attachments (#1961, shipped) proved Supabase Storage + presigned URLs. However, for KB we chose git-committed over Supabase Storage because portability and agent access outweigh the simplicity of blob storage.

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Storage target | Git repo (committed via GitHub Contents API) | Data portability — user clones repo and has everything. Agents see files natively. |
| 2 | Upload path | Server-side proxy (GitHub App installation token) | Consistent with CI/CD proxy architecture (3.10). No GitHub credentials needed in browser. |
| 3 | File types | Expanded: images (PNG, JPEG, GIF, WebP), PDFs, CSV, plain text (.txt), .docx | Broader than chat attachments. Text-based formats are natively useful to agents. |
| 4 | Max file size | 20MB per file | Matches chat attachment limit. Keeps git manageable for per-user repos. |
| 5 | UI placement | Per-directory upload button in FileTree sidebar | Intuitive — "upload to this folder." Button appears on hover for each directory. |
| 6 | Rollout strategy | Full upload flow in single PR | Complete feature: upload button, API route, kb-reader expansion, binary file serving. |
| 7 | Architectural principle | Data portability as standing requirement | All user data must be exportable via git clone. Added to constitution and AGENTS.md. |

## Open Questions

1. **GDPR deletion scope** — #1976 tracks Supabase Storage blob purge for chat attachments. KB uploads in git need a different deletion path (git history rewriting or accept that deleted files persist in history). Likely accept git history persistence with a "delete file" action that removes from HEAD.
2. **Upload progress UX** — Reuse the XHR progress indicator from chat attachments? GitHub Contents API is synchronous (base64 in request body), so progress is less meaningful than streaming to Storage.
3. **Conflict handling** — What if a file with the same name already exists? Options: overwrite (new commit), rename with suffix, or reject with error.
4. **kb-reader.ts expansion** — Currently hardcoded to `.md`. Need to show all file types in the tree and serve binary files via a new route. How to render non-markdown files in the content area (image preview, PDF viewer, or download link)?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Feature is correctly deferred (P3-low). Infrastructure is proven via chat attachments. Core UX question resolved: git-committed for data portability. Not in roadmap feature table — needs to be added when promoted. Should not compete with P1 items in current sprint.

### Marketing (CMO)

**Summary:** Reinforces compounding moat messaging — "your KB gets richer with every upload." Table-stakes for knowledge management competitors. Needs clear file type list and storage limit communication for pricing page. Recommends conversion-optimizer for upload flow layout review.

### Engineering (CTO)

**Summary:** Chat attachment infrastructure (presign, upload UX) partially reusable for validation patterns, but KB upload uses GitHub Contents API instead of Supabase Storage. Core risk is kb-reader.ts expansion — currently filesystem/.md only, needs to serve all file types. Medium-high complexity (3-5 days) for git-committed approach. Recommends architecture decision record for storage strategy.
