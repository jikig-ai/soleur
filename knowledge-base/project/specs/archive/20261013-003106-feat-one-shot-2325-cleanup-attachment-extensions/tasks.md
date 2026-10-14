# Tasks — feat-one-shot-2325-cleanup-attachment-extensions

Derived from `knowledge-base/project/plans/2026-04-18-chore-cleanup-attachment-extensions-and-max-binary-size-plan.md`.

Issue: #2325

## 1. Core Implementation

### 1.1. Inline `ATTACHMENT_EXTENSIONS`

- [x] 1.1.1. Open `apps/web-platform/server/kb-binary-response.ts`.
- [x] 1.1.2. Delete line 36: `export const ATTACHMENT_EXTENSIONS = new Set([".docx"]);`.
- [x] 1.1.3. Replace line 143 expression `ATTACHMENT_EXTENSIONS.has(ext)` with `ext === ".docx"`.
- [x] 1.1.4. Confirm no other consumers: `rg "ATTACHMENT_EXTENSIONS" apps/ plugins/ --type ts --type tsx` returns zero matches.

### 1.2. Import `MAX_BINARY_SIZE` in tests

- [x] 1.2.1. Open `apps/web-platform/test/kb-share-allowed-paths.test.ts`.
- [x] 1.2.2. Add import near the `@/app/api/kb/share/route` import: `import { MAX_BINARY_SIZE } from "@/server/kb-binary-response";`.
- [x] 1.2.3. Replace line 144 `Buffer.alloc(50 * 1024 * 1024 + 1)` with `Buffer.alloc(MAX_BINARY_SIZE + 1)`.
- [x] 1.2.4. Confirm no stray `50 * 1024 * 1024` literal remains in the test file.

## 2. Verification

- [x] 2.1. Run affected test file:

  ```bash
  cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-share-allowed-paths.test.ts
  ```

- [x] 2.2. Run binary-response test suite:

  ```bash
  cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-binary-response*.test.ts
  ```

- [x] 2.3. Type-check:

  ```bash
  cd apps/web-platform && ./node_modules/.bin/tsc --noEmit
  ```

## 3. Ship

- [x] 3.1. Commit: `refactor(kb): inline ATTACHMENT_EXTENSIONS + import MAX_BINARY_SIZE in tests`.
- [x] 3.2. Open PR with body: `Closes #2325` and `Ref #2300`.
- [x] 3.3. Confirm acceptance criteria in the plan are all checked before merge.
