# Tasks: feat: custom leader names as @mention handles

## Phase 1: Setup

- [x] 1.1 Research current onSelect handler, parseAtMentions, validation, and getDisplayName
- [x] 1.2 Confirm server already resolves custom names via reverse-lookup (no changes needed)

## Phase 2: Core Implementation

- [ ] 2.1 Update `VALID_PATTERN` in `apps/web-platform/server/team-names-validation.ts` to disallow spaces
- [ ] 2.2 Update error message for space validation
- [ ] 2.3 Change `onSelect` in chat page to insert `getDisplayName(id)` instead of leader ID

## Phase 3: Testing

- [ ] 3.1 Update validation tests in `apps/web-platform/test/team-names.test.ts` for single-word enforcement
- [ ] 3.2 Verify existing AtMentionDropdown tests still pass
- [ ] 3.3 Verify domain-router tests still pass (custom name resolution)
- [ ] 3.4 Run full test suite for web-platform
