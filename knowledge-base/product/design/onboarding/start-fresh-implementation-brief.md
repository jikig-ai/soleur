# Start Fresh Onboarding -- Implementation Brief

Target file: `apps/web-platform/app/(dashboard)/dashboard/page.tsx`

## Architecture Overview

The dashboard page renders one of three mutually exclusive states based on
knowledge-base file existence. Detection happens via a new API endpoint or
hook that checks four KB paths. The states are evaluated as early returns
in render order:

1. **First-Run State** -- `overview/vision.md` does NOT exist
2. **Foundations State** -- `overview/vision.md` exists, but fewer than 4 foundation files exist
3. **Command Center** -- all 4 foundation files exist (current page, unchanged)

### Foundation Files

| Card Label | KB Path | Check |
|---|---|---|
| Vision | `overview/vision.md` | Exists = done |
| Brand Identity | `marketing/brand-guide.md` | Exists = done |
| Business Validation | `product/business-validation.md` | Exists = done |
| Legal Foundations | `legal/privacy-policy.md` | Exists = done |

---

## Data Layer

### New Hook: `useFoundationStatus`

Location: `apps/web-platform/hooks/use-foundation-status.ts`

```
Returns: {
  loading: boolean;
  error: string | null;
  foundations: {
    vision: boolean;
    brand: boolean;
    validation: boolean;
    legal: boolean;
  };
  completedCount: number;  // 0-4
  allComplete: boolean;    // completedCount === 4
  hasVision: boolean;      // shortcut for foundations.vision
}
```

Implementation: call `GET /api/kb/content/overview/vision.md` (and the
other three paths) in parallel on mount. A 404 means the file does not
exist (done = false). A 200 means it exists (done = true). A 503
(workspace not ready) should surface as a loading state.

Alternatively, a single new API route `GET /api/kb/foundations` could
return all four statuses in one round-trip to avoid 4 parallel fetches.
The hook should re-fetch when the page regains focus
(`document.addEventListener("visibilitychange")`) to pick up files
created in a chat session that the user navigated back from.

### Cache Invalidation

After a chat conversation creates a foundation file, the user navigates
back to `/dashboard`. The `visibilitychange` listener triggers a re-fetch
so the UI transitions to the correct state without a full page reload.

---

## State 1: First-Run State

**Condition:** `!hasVision && !loading`

### Layout

- Full-viewport centered layout (matches existing Command Center empty state pattern)
- Container: `mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10`
- Vertically centered content stack with generous whitespace

### Content Hierarchy (top to bottom)

1. **Soleur mark**
   - The amber "S" badge from `WelcomeCard`: `h-12 w-12 rounded-lg bg-amber-600 text-lg font-bold text-white`, centered, displaying "S"
   - `mb-6`

2. **Section label**
   - `text-xs font-medium tracking-widest text-amber-500 uppercase`
   - Text: `WELCOME TO SOLEUR`
   - `mb-3`

3. **Headline**
   - `text-3xl font-semibold text-white text-center md:text-4xl`
   - Placeholder text (copywriter finalizes): "Describe your startup idea."
   - `mb-3`

4. **Subheadline**
   - `text-sm text-neutral-400 text-center max-w-md`
   - Placeholder text: "Tell your AI team what you're building. They'll start with your vision and grow from there."
   - `mb-10`

5. **Chat input (focused)**
   - Reuse the `ChatInput` component from `components/chat/chat-input.tsx`
   - `w-full max-w-xl`
   - `placeholder`: "I'm building a platform that..." (copywriter finalizes)
   - On submit: navigate to `/dashboard/chat/new?msg={encodeURIComponent(message)}`
   - The chat session will create `overview/vision.md` automatically via the agent runner
   - No `@mention` support needed here -- pass no-op handlers for `onAtTrigger`/`onAtDismiss`
   - No leader strip. No suggested prompts. The single input is the only interactive element.

6. **Trust line**
   - `text-xs text-neutral-500 text-center mt-4`
   - Placeholder: "Your AI team starts building your company knowledge from this first conversation."

### What is NOT present

- No leader strip (the founder hasn't established context yet -- showing 8 specialists is premature)
- No suggested prompt cards (the first message must be open-ended to capture the founder's vision)
- No "New conversation" button (the inline input IS the action)
- No filter bar, no conversation list

### Responsive Behavior

| Breakpoint | Change |
|---|---|
| 375px (mobile) | Headline `text-3xl`, input full-width with `px-4` page padding |
| 768px (tablet) | Headline `text-4xl`, input `max-w-xl` centered |
| 1024px (desktop) | Same as tablet, layout naturally centered by `max-w-3xl` container |

### Skeleton / Loading State

While `useFoundationStatus` is loading, render:

- The same centered layout
- A pulsing amber "S" badge (add `animate-pulse`)
- Two skeleton text bars (`h-4 w-48 rounded bg-neutral-800 animate-pulse` and `h-3 w-64`)
- A skeleton input bar (`h-[44px] w-full max-w-xl rounded-xl bg-neutral-800/50 animate-pulse`)

### Transition to State 2

When the founder submits a message, they navigate to `/dashboard/chat/new?msg=...`.
The agent creates `overview/vision.md` during the conversation. When the founder
navigates back to `/dashboard`, `useFoundationStatus` re-fetches and finds
`vision.md` exists. The hook now returns `hasVision: true` with
`completedCount: 1`, which renders State 2.

---

## State 2: Foundations State

**Condition:** `hasVision && !allComplete && !loading`

### Layout

- Same full-viewport centered layout as existing empty state
- Container: `mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10`

### Content Hierarchy (top to bottom)

1. **Section label**
   - `text-xs font-medium tracking-widest text-amber-500 uppercase`
   - Text: `YOUR FOUNDATIONS`
   - `mb-3`

2. **Headline**
   - `text-3xl font-semibold text-white text-center md:text-4xl`
   - Placeholder text: "Let's build your company's foundation."
   - `mb-3`

3. **Subheadline**
   - `text-sm text-neutral-400 text-center max-w-md`
   - Placeholder text: "Complete these to give your AI team the context they need to work effectively."
   - `mb-2`

4. **Progress indicator**
   - `text-xs text-neutral-500 text-center`
   - Text: `{completedCount} of 4 complete`
   - `mb-8`

5. **Foundation cards grid**
   - Uses the existing 2-col/4-col grid pattern from the dashboard: `grid w-full grid-cols-2 gap-3 md:grid-cols-4`
   - Four cards, one per foundation (see Card Specification below)
   - `mb-10`

6. **Chat input + leader strip**
   - The `ChatInput` component, full `@mention` support enabled
   - Below: the leader strip (identical to existing empty state pattern)
   - The founder can use the cards OR type a freeform message

### Foundation Card Specification

Each card uses the existing card styling pattern from the dashboard prompt cards.

**Not-Done Card (clickable prompt):**

```
Container: button element
Classes: flex flex-col gap-2 rounded-xl border border-neutral-800 bg-neutral-900/50 p-4 text-left transition-colors hover:border-neutral-600
```

Structure:

- **Icon row**: A category-appropriate icon, `text-lg`
  - Vision: eye or lightbulb icon
  - Brand Identity: paintbrush or palette icon
  - Business Validation: chart-bar or trending-up icon
  - Legal Foundations: shield or scale icon
- **Title**: `text-sm font-medium text-white` -- the card label (e.g., "Brand Identity")
- **Description**: `text-xs text-neutral-500` -- one-line hint (e.g., "Define your brand voice and visual identity")

On click: navigate to `/dashboard/chat/new?msg={encodeURIComponent(promptText)}`

The `promptText` values (placeholder -- copywriter finalizes):

- Brand Identity: "Help me define our brand identity"
- Business Validation: "Help me validate our business model"
- Legal Foundations: "Help me set up our legal foundations"

**Done Card (completed, non-interactive link):**

```
Container: anchor element linking to /dashboard/kb/{path}
Classes: flex flex-col gap-2 rounded-xl border border-neutral-800/50 bg-neutral-900/30 p-4 text-left transition-colors hover:border-neutral-700
```

Structure:

- **Icon row**: A green checkmark circle icon, `text-lg text-green-500`
  - SVG: circle with checkmark, or use `text-green-500` on a check character
- **Title**: `text-sm font-medium text-neutral-400` -- the card label with muted text (visually subordinate to incomplete cards)
- **Link hint**: `text-xs text-neutral-600` -- "View in Knowledge Base"

The done state is visually distinct: muted colors (neutral-400 title instead of white, neutral-800/50 border, bg-neutral-900/30) signal completion without drawing attention away from remaining tasks.

**Vision Card (always done in State 2):**

The Vision card always shows as done since `hasVision: true` is the entry condition for State 2. It uses the Done Card treatment above.

### Card Order

Fixed order regardless of completion status: Vision, Brand Identity, Business Validation, Legal Foundations. This keeps the layout stable -- cards do not re-sort as they complete.

### Responsive Behavior

| Breakpoint | Change |
|---|---|
| 375px (mobile) | Grid: `grid-cols-2`, cards stack in 2x2. Chat input full-width. Leader strip wraps. |
| 768px (tablet) | Grid: `grid-cols-4`, all cards in one row. Chat input centered. |
| 1024px (desktop) | Same as tablet. `max-w-3xl` container keeps everything readable. |

### Skeleton / Loading State

While `useFoundationStatus` is loading:

- Same centered layout
- Section label skeleton: `h-3 w-32 rounded bg-neutral-800 animate-pulse`
- Headline skeleton: `h-6 w-64 rounded bg-neutral-800 animate-pulse`
- Four card skeletons in the grid: each `rounded-xl border border-neutral-800 bg-neutral-900/50 p-4 animate-pulse` containing two shimmer bars (`h-4 w-20 rounded bg-neutral-800` and `h-3 w-28 rounded bg-neutral-800`)
- Chat input skeleton: `h-[44px] w-full rounded-xl bg-neutral-800/50 animate-pulse`

### Transition to State 3

As the founder completes foundation conversations, each creates the corresponding
KB file. On each return to `/dashboard`, the hook re-fetches. When
`completedCount === 4`, the hook returns `allComplete: true` and the page
falls through to the existing Command Center (State 3).

No explicit "finish onboarding" button. The transition is automatic and driven
entirely by KB file existence.

---

## State 3: Command Center (Existing)

**Condition:** `allComplete || loading error fallback`

No changes. The current `DashboardPage` component renders as-is. This includes:

- Empty state with suggested prompts + leader strip (when 0 conversations)
- Filter bar + conversation list (when conversations exist)

### Error / Fallback Behavior

If `useFoundationStatus` errors (API unreachable, workspace not ready), fall
through to State 3 (Command Center). The onboarding states are progressive
enhancement -- they should never block a user from accessing the conversation
inbox. The Command Center works fine without foundation files.

---

## Integration Pattern

The dashboard page's render logic becomes:

```
function DashboardPage() {
  const { loading, error, hasVision, allComplete } = useFoundationStatus();
  const router = useRouter();
  // ...existing state...

  // Early return: First-Run State
  if (!loading && !error && !hasVision) {
    return <FirstRunState />;
  }

  // Early return: Foundations State
  if (!loading && !error && hasVision && !allComplete) {
    return <FoundationsState foundations={...} />;
  }

  // Default: Command Center (existing code, unchanged)
  // ...existing return...
}
```

The `FirstRunState` and `FoundationsState` can be extracted into
separate components in `components/onboarding/` to keep the dashboard
page file manageable:

- `components/onboarding/first-run-state.tsx`
- `components/onboarding/foundations-state.tsx`
- `components/onboarding/foundation-card.tsx`

---

## Design Tokens Reference

All values from `brand-guide.md` Visual Direction and existing dashboard code:

| Token | Value | Usage |
|---|---|---|
| Page background | `bg-neutral-950` | Main content area (from layout.tsx) |
| Card background | `bg-neutral-900/50` | Card surfaces |
| Card border | `border-neutral-800` | Card and divider borders |
| Gold accent text | `text-amber-500` | Section labels |
| Gold gradient CTA | `from-[#D4B36A] to-[#B8923E]` | Primary buttons |
| Amber send button | `bg-amber-600` | Chat input send button |
| Primary text | `text-white` | Headlines |
| Secondary text | `text-neutral-400` | Subheadlines, descriptions |
| Tertiary text | `text-neutral-500` | Captions, hints |
| Muted text | `text-neutral-600` | Done-state metadata |
| Completed accent | `text-green-500` | Checkmark on done cards |
| Input border | `border-neutral-700` | Chat input, select inputs |
| Input background | `bg-neutral-900` | Chat input textarea |
| Sharp corners | `rounded-xl` | Cards (existing pattern -- note: brand guide says 0px, but dashboard consistently uses rounded-xl; follow the existing code) |

---

## Accessibility Notes

- Foundation cards use `button` elements (not-done) and `a` elements (done) for correct semantics
- All interactive elements have minimum 44px touch targets (consistent with existing patterns -- see `min-h-[44px]` in layout nav items)
- The chat input's `textarea` receives autofocus in State 1 to guide the founder directly to typing
- Done cards link to `/dashboard/kb/{path}` for keyboard-navigable access to completed files
- Progress text ("2 of 4 complete") provides screen reader context for the visual card states
- Color is not the sole differentiator between done/not-done cards -- text content ("View in Knowledge Base" vs. prompt text) and icon change both reinforce state
