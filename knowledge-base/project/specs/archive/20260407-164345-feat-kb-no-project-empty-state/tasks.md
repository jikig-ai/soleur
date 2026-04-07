# Tasks: KB No-Project Empty State

## Phase 1: Implementation

### 1.1 Add no-project empty state to KB page

- [ ] 1.1.1 Read `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx`
- [ ] 1.1.2 Add `if (error === "not-found")` branch before the generic `if (error)` block
- [ ] 1.1.3 Render centered empty state with folder icon, heading, description, and CTA link
- [ ] 1.1.4 CTA links to `/connect-repo?return_to=/dashboard/kb` using the existing `Link` import

## Phase 2: Testing

### 2.1 Verify error state handling

- [ ] 2.1.1 Verify `"not-found"` error renders the new no-project empty state
- [ ] 2.1.2 Verify `"unknown"` error still renders the generic error message
- [ ] 2.1.3 Verify `"workspace-not-ready"` still renders the workspace setup state
- [ ] 2.1.4 Verify CTA link points to `/connect-repo?return_to=/dashboard/kb`

### 2.2 Run existing tests

- [ ] 2.2.1 Run `npx vitest run` for the web-platform test suite
- [ ] 2.2.2 Run TypeScript type check (`npx tsc --noEmit`)

## Phase 3: Lint and commit

### 3.1 Pre-commit checks

- [ ] 3.1.1 Run `npx markdownlint-cli2 --fix` on changed `.md` files
- [ ] 3.1.2 Run compound before committing
