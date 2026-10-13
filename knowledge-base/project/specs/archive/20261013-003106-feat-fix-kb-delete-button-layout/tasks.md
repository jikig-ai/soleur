# Tasks: Fix KB Delete Button Layout

## Phase 1: Implementation

### 1.1 Fix file node time span visibility on hover

- [x] In `apps/web-platform/components/kb/file-tree.tsx`, update the file node time span (around line 320) to conditionally add `group-hover:opacity-0 transition-opacity` only for attachment files (`isAttachment`)
- [x] Ensure `.md` file rows do not hide the time label on hover

### 1.2 Fix directory node time span visibility on hover

- [x] In `apps/web-platform/components/kb/file-tree.tsx`, update the directory node time span (around line 227) to add `group-hover:opacity-0 transition-opacity`

## Phase 2: Testing

### 2.1 Update existing tests

- [x] Verify existing tests in `apps/web-platform/test/file-tree-delete.test.tsx` still pass
- [x] Add test: attachment file time span has `group-hover:opacity-0` class
- [x] Add test: `.md` file time span does NOT have `group-hover:opacity-0` class

### 2.2 Visual verification

- [ ] QA: hover attachment file row -- time label fades out, delete button fades in
- [ ] QA: hover `.md` file row -- time label stays visible
- [ ] QA: hover directory row -- time label fades out, upload button fades in
- [ ] QA: no layout shift during hover transitions
