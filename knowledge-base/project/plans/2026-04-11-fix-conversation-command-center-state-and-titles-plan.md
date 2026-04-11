---
title: "fix: conversation command center state and titles"
type: fix
date: 2026-04-11
issue: "#1962"
deepened: 2026-04-11
---

# Fix Conversation Command Center State and Titles

## Enhancement Summary

**Deepened on:** 2026-04-11
**Sections enhanced:** 5
**Research sources:** Context7 Supabase docs, project learnings, codebase pattern analysis

### Key Improvements

1. Title derivation now has a cascading fallback chain (user message -> raw message -> assistant message -> leader label -> "Untitled")
2. Status update uses optimistic UI with Supabase `{ error }` destructuring (per learning: silent error return values)
3. Action menu follows existing popover pattern from `share-popover.tsx` with outside-click dismissal
4. Realtime deduplication handled -- optimistic update + Realtime subscription coexist without flicker

### Institutional Learnings Applied

- **Supabase silent error return values:** Always destructure `{ error }` from every Supabase call (learning: 2026-03-20)
- **Vitest module-level Supabase mock timing:** Mock tracked functions in the `vi.mock()` factory, not inside test bodies (learning: 2026-04-06)
- **Supabase ReturnType resolves to never:** Use explicit `SupabaseClient` type import when typing lazy getters (learning: 2026-04-05)

---

Two bugs in the Command Center make conversations hard to manage:

1. Some conversations display as "Untitled conversation" when the first user message is missing or empty
2. Users cannot change conversation status -- "Needs attention" (failed) stays stuck forever because there is no UI to transition state

## Root Cause Analysis

### Untitled Conversations

`deriveTitle()` in `hooks/use-conversations.ts:26-32` returns "Untitled conversation" when:

- No user-role message exists for the conversation (e.g., the message insert failed after conversation creation)
- The first user message is only `@leader` mentions with no remaining content after stripping

The `domain_leader === "system"` case is already handled (hardcoded to "Project Analysis"), but general conversations without user messages fall through.

### Stuck Status

The `ConversationRow` component in `components/inbox/conversation-row.tsx` is purely navigational -- clicking always goes to `/dashboard/chat/[id]`. There is no mechanism for the user to mark a "failed" conversation as "completed" (dismissing the error) or to archive/complete conversations they no longer need.

The RLS policy (`"Users can manage own conversations" for all using (auth.uid() = user_id)`) already permits client-side updates, so no migration is needed.

### Research Insights

**Why conversations end up untitled:**

1. **Race condition on creation:** `createConversation()` in `ws-handler.ts:136` inserts the conversation row before the first user message is saved (`saveMessage()` in `agent-runner.ts:232`). If the WebSocket disconnects between these two operations, the conversation exists without any messages.
2. **System conversations:** Conversations created by the `/api/repo/status` route with `domain_leader: "system"` use an internal system message format that `deriveTitle()` does not recognize as user content.
3. **@-mention-only messages:** A user typing only `@cto` and sending triggers conversation creation, but after stripping the mention pattern `/@\w+\s*/g`, nothing remains.

**Why the "Needs attention" state persists:**

The `failed` status is set in `agent-runner.ts:1100-1108` when the agent session throws an error (e.g., API timeout, model error). The only path back to `active` is sending a new message (which creates a new session), but the conversation row in the Command Center navigates to the chat page rather than providing in-place state management. The user must navigate to the conversation, send a message to "restart" it, or live with the stuck badge.

## Acceptance Criteria

- [ ] Conversations with no user messages display a meaningful fallback title (e.g., first assistant message content, or leader-specific label like "CTO conversation")
- [ ] Conversations where the first user message is only @-mentions after stripping display the raw message instead of empty string
- [ ] Each conversation row has a status-change action (click/menu) that allows the user to transition status
- [ ] Valid transitions: any status -> "completed" (dismiss/archive), "failed" -> "active" (retry), "waiting_for_user" -> "completed" (dismiss)
- [ ] Status change persists to Supabase and updates UI immediately (optimistic update)
- [ ] Realtime subscription already in `use-conversations.ts` picks up the persisted change
- [ ] Existing tests in `test/command-center.test.tsx` and `test/components/conversation-row.test.tsx` continue passing
- [ ] New tests cover: title fallback scenarios, status change UI interaction, optimistic update behavior

## Implementation

### 1. Fix Title Derivation (`hooks/use-conversations.ts`)

**File:** `apps/web-platform/hooks/use-conversations.ts`

Update `deriveTitle()` to handle edge cases with a cascading fallback chain:

```typescript
function deriveTitle(messages: Message[], conversationId: string): string {
  const firstUserMsg = messages.find(
    (m) => m.conversation_id === conversationId && m.role === "user",
  );
  if (firstUserMsg) {
    const content = firstUserMsg.content.replace(/@\w+\s*/g, "").trim();
    if (content.length > 0) {
      return content.length > 60 ? `${content.slice(0, 57)}...` : content;
    }
    // User message was only @-mentions -- use the raw message
    const raw = firstUserMsg.content.trim();
    if (raw.length > 0) {
      return raw.length > 60 ? `${raw.slice(0, 57)}...` : raw;
    }
  }

  // Fallback: use first assistant message content
  const firstAssistantMsg = messages.find(
    (m) => m.conversation_id === conversationId && m.role === "assistant",
  );
  if (firstAssistantMsg) {
    const stripped = firstAssistantMsg.content.replace(/[#*`_~\[\]()]/g, "").trim();
    if (stripped.length > 0) {
      return stripped.length > 60 ? `${stripped.slice(0, 57)}...` : stripped;
    }
  }

  return "Untitled conversation";
}
```

Update the enrichment logic to use `domain_leader` as a final fallback before "Untitled":

```typescript
const enriched: ConversationWithPreview[] = convData.map((conv: Conversation) => {
  const { text, leader } = derivePreview(messages, conv.id);
  let title: string;
  if (conv.domain_leader === "system") {
    title = "Project Analysis";
  } else {
    const derived = deriveTitle(messages, conv.id);
    title = derived === "Untitled conversation" && conv.domain_leader
      ? `${conv.domain_leader.toUpperCase()} conversation`
      : derived;
  }
  return { ...conv, title, preview: text, lastMessageLeader: leader };
});
```

#### Research Insights

**Best Practices:**

- Call `deriveTitle()` only once per conversation (the current plan calls it twice in the ternary -- refactored above to store in a variable)
- Keep the regex strip pattern `/@\w+\s*/g` consistent with the chat input's mention detection pattern
- Truncation at 57 chars + "..." = 60 chars total -- consistent with email subject line best practice for scannability

**Edge Cases:**

- Messages with only whitespace after stripping: guard with `.trim()` before length check
- Messages containing only emoji (e.g., a user sends just a thumbs-up): these pass through correctly since they are not stripped by the `@` pattern
- Very long first messages (500+ chars): truncation at 60 is correct, prevents layout overflow in the row component

### 2. Add Status Change to ConversationRow (`components/inbox/conversation-row.tsx`)

**File:** `apps/web-platform/components/inbox/conversation-row.tsx`

Add an action menu following the existing popover pattern from `components/kb/share-popover.tsx`:

- A "..." (ellipsis/more) button positioned at the right edge of each row
- On click, opens a small dropdown with status transition options
- Uses `useRef` + outside-click listener for dismissal (same pattern as `SharePopover`)
- Calls `e.stopPropagation()` on the menu button to prevent row navigation

**Allowed transitions per current status:**

| Current Status | Available Actions |
|---|---|
| `waiting_for_user` | Mark as completed |
| `active` | Mark as completed |
| `completed` | (no actions -- already terminal) |
| `failed` | Mark as completed, Retry (mark as active) |

```typescript
interface ConversationRowProps {
  conversation: ConversationWithPreview;
  onStatusChange?: (id: string, newStatus: ConversationStatus) => void;
}

function StatusMenu({
  conversation,
  onStatusChange,
}: {
  conversation: ConversationWithPreview;
  onStatusChange: (id: string, newStatus: ConversationStatus) => void;
}) {
  const [open, setOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClickOutside(e: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [open]);

  const actions = getAvailableActions(conversation.status);
  if (actions.length === 0) return null;

  return (
    <div className="relative" ref={menuRef}>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          setOpen(!open);
        }}
        className="flex h-7 w-7 items-center justify-center rounded-md text-neutral-500 transition-colors hover:bg-neutral-700 hover:text-neutral-300"
        aria-label="Conversation actions"
      >
        <EllipsisIcon className="h-4 w-4" />
      </button>
      {open && (
        <div className="absolute right-0 top-full z-50 mt-1 w-44 rounded-lg border border-neutral-700 bg-neutral-900 py-1 shadow-xl">
          {actions.map((action) => (
            <button
              key={action.status}
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                onStatusChange(conversation.id, action.status);
                setOpen(false);
              }}
              className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-neutral-300 transition-colors hover:bg-neutral-800"
            >
              {action.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function getAvailableActions(status: ConversationStatus): { status: ConversationStatus; label: string }[] {
  switch (status) {
    case "waiting_for_user":
      return [{ status: "completed", label: "Mark as completed" }];
    case "active":
      return [{ status: "completed", label: "Mark as completed" }];
    case "failed":
      return [
        { status: "completed", label: "Dismiss" },
        { status: "active", label: "Retry" },
      ];
    case "completed":
      return [];
  }
}
```

#### Research Insights

**Best Practices:**

- Use `e.stopPropagation()` on both the trigger button AND each menu item click to prevent bubbling to the row's `onClick` handler
- Position with `absolute right-0 top-full` to avoid clipping on narrow viewports
- Add `z-50` to ensure the dropdown renders above adjacent rows
- Use `aria-label` on the trigger button for accessibility
- The menu should not render at all for `completed` conversations (no available actions)

**Performance Considerations:**

- The `useEffect` for outside-click should only attach when `open === true` (already in the pattern)
- Do not create a new Supabase client instance per menu interaction -- the hook-level `createClient()` should be reused

**Mobile touch target:**

- The "..." button must be minimum 44x44px touch target (already specified as `h-7 w-7` = 28px, bump to `min-h-[44px] min-w-[44px]` with padding for touch accessibility on mobile)
- On mobile layout, the menu button should appear in the row's bottom-right area (within the vertical stack)

### 3. Add Status Update Function to `use-conversations.ts`

**File:** `apps/web-platform/hooks/use-conversations.ts`

Export an `updateStatus` function from the hook that:

1. Captures current state for rollback
2. Optimistically updates the local state
3. Calls Supabase with proper `{ error }` destructuring (per learning)
4. On error, reverts the optimistic update and surfaces the error

```typescript
const updateStatus = useCallback(async (conversationId: string, newStatus: ConversationStatus) => {
  // Capture previous state for rollback
  const previousConversations = conversations;

  // Optimistic update
  setConversations((prev) =>
    prev.map((c) =>
      c.id === conversationId
        ? { ...c, status: newStatus, last_active: new Date().toISOString() }
        : c,
    ),
  );

  const supabase = createClient();
  const { error } = await supabase
    .from("conversations")
    .update({ status: newStatus, last_active: new Date().toISOString() })
    .eq("id", conversationId);

  if (error) {
    // Revert optimistic update with captured state
    setConversations(previousConversations);
    setError(`Failed to update status: ${error.message}`);
  }
}, [conversations]);
```

#### Research Insights

**Optimistic Update + Realtime Coexistence:**

The Realtime subscription in `use-conversations.ts:158-166` will receive the same UPDATE event from Postgres after the optimistic write completes. This creates a potential double-update:

1. Optimistic: UI updates immediately
2. Realtime: Postgres broadcasts the change ~100-300ms later

The current Realtime handler `setConversations((prev) => prev.map(...))` re-applies the same values, which is idempotent -- React's state reconciliation will not trigger a re-render if the values match. No additional deduplication logic is needed.

**Error Handling (per Supabase learning):**

- The Supabase JS client does NOT throw on failures -- it returns `{ data, error }`
- Always destructure and check `error` explicitly
- The `createClient()` call returns a browser client that uses the user's session cookie for RLS enforcement -- no additional auth needed

**Rollback Strategy:**

- Capture `conversations` (current state) before the optimistic write
- On error, restore the captured state directly (cheaper than re-fetching)
- Only call `fetchConversations()` as a last resort if state is corrupted

**Race Condition: Multiple rapid clicks:**

- If user clicks "Mark as completed" then immediately clicks "Retry" on the same row, the second optimistic update will overwrite the first
- The Supabase writes are independent (last-write-wins on the server)
- This is acceptable behavior -- the UI always shows the most recent intent

### 4. Update Hook Return Type

**File:** `apps/web-platform/hooks/use-conversations.ts`

```typescript
interface UseConversationsResult {
  conversations: ConversationWithPreview[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
  updateStatus: (conversationId: string, newStatus: ConversationStatus) => Promise<void>;
}
```

Return `updateStatus` from `useConversations`:

```typescript
return { conversations, loading, error, refetch: fetchConversations, updateStatus };
```

### 5. Update Dashboard Page

**File:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx`

Destructure `updateStatus` from the hook and pass to each `ConversationRow`:

```typescript
const { conversations, loading, error, refetch, updateStatus } = useConversations({
  statusFilter,
  domainFilter,
});

// In the conversation list rendering:
{conversations.map((conv) => (
  <ConversationRow
    key={conv.id}
    conversation={conv}
    onStatusChange={updateStatus}
  />
))}
```

## Test Scenarios

- Given a conversation with no messages, when the command center renders, then the title shows the domain leader label (e.g., "CTO conversation") instead of "Untitled conversation"
- Given a conversation where the first user message is "@cto ", when the command center renders, then the title shows "@cto" (raw message)
- Given a conversation with only assistant messages, when the command center renders, then the title shows the assistant message content
- Given a conversation row with status "failed", when the user clicks the action menu and selects "Mark as completed", then the status badge changes to "Completed" immediately and the Supabase update is called
- Given a failed Supabase update, when the user tries to change status, then the status reverts and an error message appears
- Given a conversation with status "waiting_for_user", when the user marks it as "completed", then the row updates and the Realtime subscription does not conflict
- Given a conversation with status "completed", when the row renders, then no action menu button appears

### Test Implementation Notes

**Mock pattern for update calls** (per Vitest Supabase mock learning):

The existing `command-center.test.tsx` uses `createQueryBuilder()` with a thenable pattern. Extend it to track `update` calls:

```typescript
// Add to existing createQueryBuilder:
const mockUpdate = vi.fn().mockReturnThis();

function createQueryBuilder(data: unknown[]) {
  const result = { data, error: null };
  const builder = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    in: vi.fn().mockReturnThis(),
    is: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    single: vi.fn().mockReturnThis(),
    update: mockUpdate,
    then: (onfulfilled: (value: unknown) => unknown) =>
      Promise.resolve(result).then(onfulfilled),
  };
  return builder;
}
```

**Critical:** The `mockUpdate` must be defined at module level (before `vi.mock()`) so the factory can reference it. Defining it inside `beforeEach` is too late -- the Supabase mock factory runs at import time (per learning: 2026-04-06).

## Context

- **Brainstorm:** `knowledge-base/project/brainstorms/2026-04-07-conversation-inbox-brainstorm.md`
- **RLS policy:** "Users can manage own conversations" allows UPDATE via browser client
- **Realtime:** Already subscribed to conversation UPDATE events in `use-conversations.ts:144-176`
- **No migration needed:** Schema already supports all four statuses and RLS permits user updates
- **Key pattern:** Optimistic updates match the existing Realtime subscription -- the subscription will receive the change after Postgres processes it, but the UI updates immediately
- **Popover pattern:** `components/kb/share-popover.tsx` provides the reference implementation for outside-click dismissal menus

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- bug fix for existing UI component with no new user flows, no architectural changes, no external service integration.
