# Session State

## Plan Phase

- Plan file: knowledge-base/project/specs/feat-fix-kb-pdf-upload-formdata/tasks.md
- Status: complete

### Errors

None

### Decisions

- Root cause: Next.js default body size limit (1 MB) rejects PDF uploads >1 MB via server actions
- Fix: Add `experimental.middlewareClientMaxBodySize: 25 * 1024 * 1024` to next.config.ts
- 25 MB limit with 5 MB headroom for multipart overhead
- Single config change, no API route refactoring needed
- Pre-existing `serverActions` config location warning is a separate concern

### Components Invoked

- soleur:plan
- soleur:deepen-plan
