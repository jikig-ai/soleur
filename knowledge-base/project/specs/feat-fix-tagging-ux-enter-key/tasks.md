# Tasks: fix: Enter key selects autocomplete item instead of sending message

## Phase 1: Setup

- [x] 1.1 Research root cause of Enter key conflict between ChatInput and AtMentionDropdown
- [x] 1.2 Identify event propagation order (textarea onKeyDown fires before document listener)
- [x] 1.3 Determine fix approach (atMentionVisible prop)

## Phase 2: Core Implementation

- [x] 2.1 Add `atMentionVisible?: boolean` prop to `ChatInputProps` interface in `apps/web-platform/components/chat/chat-input.tsx`
- [x] 2.2 Modify `handleKeyDown` in ChatInput to early-return when `atMentionVisible` is true and Enter is pressed
- [x] 2.3 Add `atMentionVisible` to `handleKeyDown` dependency array
- [x] 2.4 Pass `atMentionVisible={atVisible}` from chat page to ChatInput in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`

## Phase 3: Testing

- [x] 3.1 Add test in `apps/web-platform/test/chat-input.test.tsx`: "does not send on Enter when atMentionVisible is true"
- [x] 3.2 Add test in `apps/web-platform/test/chat-input.test.tsx`: "sends on Enter when atMentionVisible is false (default behavior)"
- [x] 3.3 Verify existing AtMentionDropdown tests still pass
- [x] 3.4 Verify existing ChatInput tests still pass
- [x] 3.5 Run full test suite for web-platform
