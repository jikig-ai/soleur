---
title: "feat: Dashboard Agent Identity Badges and Team Icon Customization"
type: feat
date: 2026-04-13
---

# feat: Dashboard Agent Identity Badges and Team Icon Customization

## Overview

Give each domain leader a distinct visual identity across the Command Center dashboard and let users personalize their AI team's icons. Currently every conversation and message shows a generic Soleur logo — this replaces it with domain-specific badges, adds per-message leader attribution, removes a dead profile icon, and adds an icon customization surface on the existing team settings page.

Delivered as two PRs on the `feat-dashboard-agent-identity` branch:

- **PR 1:** Data model + default badges + profile icon removal + Soleur badge restriction
- **PR 2:** Customization UI (click-to-upload on avatar) on existing team settings page

## Problem Statement

1. The Soleur "S" logo renders identically on every conversation item, message bubble, and leader card — there is zero per-leader visual differentiation beyond a thin `border-l-2` color accent.
2. The Soleur badge was designed for system notifications only, but currently appears on all routed leader messages.
3. A non-functional profile icon (`UserIcon` in a rounded circle) sits in the top-right corner of the inbox header, doing nothing.
4. Users can rename leaders (#1871) but cannot customize their icons — limiting the "your team" personalization experience.

## Proposed Solution

### PR 1: Data Model + Default Badges

**Extend leader type definitions** in `apps/web-platform/server/domain-leaders.ts`:

- Add `defaultIcon` field — a string key referencing a lucide-react icon name (e.g., `"megaphone"`, `"cog"`)
- Add `color` field — Tailwind color token (e.g., `"pink-500"`) consolidating what's currently in `leader-colors.ts`

**Create shared `LeaderAvatar` component** at `apps/web-platform/components/leader-avatar.tsx`:

- Accepts `leaderId`, `size` (sm/md/lg), optional `className`
- Resolves icon: default lucide-react icon → Soleur logo (system/null). Custom icon resolution deferred to PR 2.
- Renders circular badge with leader's background color and icon
- Replaces the 3+ duplicated inline `<img src="/icons/soleur-logo-mark.png">` patterns

**Default icon mapping** (lucide-react icons — no binary assets needed):

| Leader | Domain | Icon | Color |
|--------|--------|------|-------|
| CMO | Marketing | `Megaphone` | pink-500 |
| CTO | Engineering | `Cog` | blue-500 |
| CFO | Finance | `TrendingUp` | emerald-500 |
| CPO | Product | `Boxes` | violet-500 |
| CRO | Sales | `Target` | orange-500 |
| COO | Operations | `Wrench` | amber-500 |
| CLO | Legal | `Scale` | slate-400 |
| CCO | Support | `Headphones` | cyan-500 |
| system | Platform | Soleur logo mark | neutral-600 |

**Update rendering in 3 locations:**

1. `apps/web-platform/components/inbox/conversation-row.tsx` — replace `LeaderBadge` (lines 101-116) with `LeaderAvatar`
2. `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — replace inline avatar in `MessageBubble` (lines 437-449) with `LeaderAvatar`
3. `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — replace inline badges in foundation cards (lines 338-345, 465-472), LeaderStrip (lines 639-648), and suggested prompts

**Restrict Soleur badge:** Only render Soleur logo mark when `leaderId` is `"system"` or `null`/`undefined` (unrouted messages during triage).

**Remove dead profile icon:** Delete the `UserIcon` circle at `apps/web-platform/app/(dashboard)/dashboard/page.tsx` lines 423-426 and the `UserIcon` SVG component at lines 660-665.

### PR 2: Customization UI

**Add icon upload to team settings page** (`apps/web-platform/components/settings/team-settings.tsx`):

- Each `LeaderRow` gets a clickable avatar next to the name input (click-to-upload pattern)
- Clicking the avatar opens a file picker dialog
- A "Reset" button appears when a custom icon is set

**Upload flow:**

- Uses existing KB upload API (`/api/kb/upload`) to commit the file to `knowledge-base/settings/team-icons/{leader_id}.{ext}`
- **Constraints:** Max 256x256px, max 100KB, PNG/SVG/WebP only. Enforced client-side before upload.
- No separate `IconPicker` component needed — the upload is a file input on the avatar element

**Extend data model for custom icons:**

- Add nullable `custom_icon_path` text column to `team_names` table (Supabase migration)
- Stores only file paths (e.g., `settings/team-icons/cto.png`) — no dual-format encoding
- Extend `/api/team-names` route to GET/PUT the icon path
- Extend `use-team-names.tsx` hook with `getIconPath(leaderId)` and `updateIcon(leaderId, path)`

**Icon resolution chain in `LeaderAvatar` (PR 2 addition):**

1. Check `custom_icon_path` from team names context → render `<img>` via `/api/kb/content/{path}`. If 404 (file deleted from repo), fall through to step 2.
2. Fall back to default lucide-react icon from `domain-leaders.ts` `defaultIcon`
3. System/unrouted → Soleur logo mark

**Upload behavior:**

- File picker opens on avatar click
- Shows upload progress inline on the avatar (reuses existing KB upload progress pattern per #2117)
- On success, avatar updates immediately (optimistic)
- "Reset to default" button clears Supabase value, does NOT delete the git-committed file (orphaned files are acceptable at 100KB max)

**Upload error handling:**

- Client-side validation rejects oversized/wrong-format files before upload
- Upload failures (network error, GitHub API rate limit, auth expiry) show a toast error with retry option

**Accessibility:**

- `LeaderAvatar` includes `aria-label="{leader name} avatar"` on the container
- Custom uploaded images get `alt="{leader name} custom icon"`
- Upload trigger is keyboard-accessible (Enter/Space on focused avatar)

**Git storage:**

- Custom icons committed to `knowledge-base/settings/team-icons/` via existing KB upload API (GitHub Contents API + workspace sync)
- Add `.gitignore` negation rules: `!knowledge-base/settings/team-icons/*.png`, `!knowledge-base/settings/team-icons/*.svg`, `!knowledge-base/settings/team-icons/*.webp`
- Users get everything with `git clone` — data portability preserved

## Technical Considerations

### Architecture

- **Shared component extraction:** The `LeaderAvatar` component eliminates 3+ duplicated rendering patterns and provides a single point for icon resolution logic.
- **lucide-react for defaults:** Already a project dependency. Renders perfectly at any size, respects dark mode via CSS `currentColor`, no binary assets to manage. Avoids the `.gitignore` blanket `*.png` ignore issue for defaults.
- **Existing upload infrastructure:** The KB upload API (`/api/kb/upload`) already handles FormData, filename sanitization, extension validation, size limits, and GitHub Contents API commits. The icon upload extends this with tighter constraints (256x256, 100KB).

### Performance

- lucide-react icons are tree-shaken — only imported icons are bundled.
- Custom icon images served via `/api/kb/content/` (filesystem read, no external API call).
- `LeaderAvatar` should memoize icon resolution to avoid redundant context lookups in message lists.

### Dark Mode

- lucide-react icons inherit `currentColor` — work on any background.
- Custom uploaded icons: render on the leader's `color` background circle with a slight inner padding. The colored circle provides consistent contrast regardless of icon content.

### Data Model

- `leader_id` already exists on the `Message` type (`lib/types.ts:130-139`) and is carried via WebSocket `stream_start` events. No message model changes needed for PR 1.
- `team_names` table extension (add `custom_icon_path` column) follows the existing pattern — one row per `(user_id, leader_id)` pair.
- The table uses RLS policies (`auth.uid() = user_id`), not column-level GRANTs. The new column is automatically covered by existing RLS — no GRANT changes needed. (Corrected from initial draft which referenced wrong security model.)

### Color Reconciliation

- The plan proposes updated colors (emerald-500, violet-500, slate-400, cyan-500, amber-500) that differ from existing `leader-colors.ts` values (green-500, purple-500, red-500, teal-500, yellow-500). These are intentional improvements per brand-architect review: slate-400 for CLO avoids error/danger semantics of red-500; amber for COO has better contrast than yellow. Update `leader-colors.ts` as part of PR 1.

### CSP

- No new inline scripts. lucide-react icons render as inline SVG elements (allowed by existing CSP). Custom icons loaded via `<img src>` from same-origin API route (allowed by `img-src 'self'`).

## Acceptance Criteria

### PR 1: Default Badges

- [ ] Each domain leader's conversations and messages display a domain-specific lucide-react icon badge instead of the generic Soleur logo
- [ ] Soleur "S" logo appears only on messages where `leader_id` is `"system"` or null
- [ ] The non-functional profile icon (`UserIcon` circle) is removed from the inbox header
- [ ] Leader cards on the dashboard show domain-specific icons
- [ ] `LeaderAvatar` component is used in all 3 rendering locations (conversation list, message bubble, dashboard cards)
- [ ] Colors from `leader-colors.ts` are consolidated into the leader type definition
- [ ] No visual regression on existing features (status badges, conversation layout, chat functionality)

### PR 2: Customization UI

- [ ] Each leader row on team settings shows a clickable avatar (click-to-upload)
- [ ] Clicking the avatar opens a file picker accepting PNG/SVG/WebP up to 256x256px and 100KB
- [ ] Uploaded icons are committed to `knowledge-base/settings/team-icons/` via git
- [ ] Custom icons appear in `LeaderAvatar` across all surfaces (conversations, messages, cards)
- [ ] "Reset" button removes custom icon and reverts to default lucide-react icon
- [ ] Icon customization persists across sessions (stored in Supabase + git)
- [ ] LeaderAvatar handles missing custom icon files gracefully (404 falls back to default)
- [ ] LeaderAvatar has appropriate aria-labels and alt text
- [ ] Upload failures show toast error with retry option

## Domain Review

**Domains relevant:** Product, Marketing

### Marketing (CMO)

**Status:** reviewed
**Assessment:** Domain badges reinforce CaaS value prop in every conversation — "free marketing" through screenshot-ready social proof. Configurable icons trigger endowment effect (psychological ownership). Risk: user-uploaded icons could clash with Solar Forge aesthetic without constraints (mitigated by 256x256/100KB limits). Per-domain colors not in brand guide — brand-architect assessed and determined they should NOT be added to brand-guide.md (internal semantic mapping, not brand identity). Recommended ux-design-lead for layout and conversion-optimizer for engagement surface analysis.

### Marketing — Conversion Optimizer (brainstorm-recommended)

**Status:** reviewed
**Assessment:** Team settings page alone is insufficient for icon picker engagement — settings pages have single-digit visit rates. Recommended: (1) Optional onboarding "Meet your team" step for personalization during setup, (2) show per-leader badges on welcome card immediately, (3) "share your team" screenshot-ready export card. These are enhancements beyond current scope — tracked as future opportunities, not blockers.

### Marketing — Brand Architect (brainstorm-recommended)

**Status:** reviewed
**Assessment:** Per-domain colors do NOT belong in brand-guide.md — they are internal dashboard semantic identifiers, not brand colors. No conflict with existing brand palette. Proposed color mapping is better than current `leader-colors.ts` values (slate-400 for CLO is more appropriate than red-500; amber for COO better than yellow for contrast). Reconcile during PR 1 implementation. No accessibility overlap concerns across 8 colors.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed (partial)
**Agents invoked:** spec-flow-analyzer, cpo, conversion-optimizer, brand-architect, ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes
**Wireframes:** `knowledge-base/product/design/domain-leaders/agent-identity-badges.pen` (7 frames: icon picker library/upload tabs, upload states, badge sizes sm/md/lg, in-context conversation list, message bubbles, dashboard cards). Library tab wireframe preserved for reference but deferred from implementation per plan review.

#### Spec Flow Analysis Findings

Critical gaps identified and resolved in plan:

1. **Library icon persistence** — Eliminated: library tab removed per plan review (YAGNI). `custom_icon_path` is always a file path.
2. **Popover close behavior** — Eliminated: no popover. Click-to-upload on avatar opens native file picker.
3. **Upload error handling** — Resolved: toast error with retry, reuse existing KB upload progress pattern
4. **Icon deletion on reset** — Resolved: clear Supabase path only, accept orphaned git files (100KB max, acceptable)
5. **Accessibility** — Resolved: aria-labels, alt text, keyboard-accessible upload trigger
6. **Multi-tab sync** — Accepted limitation: icon changes require page refresh in other tabs (same as team name behavior)
7. **Discoverability** — Conversion optimizer recommends onboarding nudge; deferred to future enhancement
8. **Missing 404 fallback** — Added: LeaderAvatar falls back to default icon when custom file returns 404

#### CPO Assessment

- PR 1: No blocking concerns. Proceed.
- PR 2: Requires UX artifact for icon picker (pending ux-design-lead). Sync mechanism resolved (KB API at runtime, not build-time).
- Per-message `leader_id` is correct data model — prerequisite for tag-and-route multi-leader threads.
- **Action required:** Add #2129 to roadmap Phase 3 table before merging.
- Roadmap Current State section is stale (pre-existing issue, #1878).

## Test Scenarios

### PR 1

- Given a conversation routed to the CMO, when viewing the conversation list, then the conversation row displays a Megaphone icon in a pink-500 circle (not the Soleur logo)
- Given a message sent by the CTO leader, when viewing the chat, then the message bubble shows a Cog icon in a blue-500 circle with `border-l-blue-500` accent
- Given a system notification message (leader_id = "system"), when viewing the chat, then the message shows the Soleur "S" logo mark
- Given an unrouted message (leader_id = null), when viewing the chat, then the message shows the Soleur "S" logo mark
- Given the inbox header, when the dashboard loads, then no profile icon (UserIcon circle) appears in the top-right
- Given the dashboard with foundation cards, when viewing a card with a leader, then the card shows the leader's domain icon instead of the generic Soleur logo

### PR 2

- Given the team settings page, when clicking a leader's avatar, then a file picker opens accepting PNG/SVG/WebP
- Given a valid 200x200 PNG selected, when the upload completes, then the file is committed to `knowledge-base/settings/team-icons/` and the leader displays the custom icon across all surfaces
- Given a 1024x1024 PNG selected (oversized), when validation runs, then the upload is rejected with an error message before submission
- Given a leader with a custom icon, when clicking "Reset", then the custom icon path is cleared and the default lucide-react icon is restored
- Given a leader with a custom icon, when viewing on a different device/session, then the custom icon loads from the KB API

### PR 2 — Error & Edge Cases

- Given a valid file selected, when upload fails due to network error, then a toast error appears with a retry option
- Given a leader with `custom_icon_path` pointing to a deleted file, when loading `LeaderAvatar`, then the component falls back to the default lucide icon (no broken image)
- Given the upload in progress, when viewing the avatar in settings, then a progress indicator shows on the avatar

### Browser Verification

- **Badge rendering:** Navigate to `/dashboard`, verify each leader card shows distinct domain icons. Open a conversation, verify message bubbles show per-leader icons.
- **Settings flow:** Navigate to `/dashboard/settings/team`, click a leader's avatar, upload a custom image, verify it appears across dashboard. Click "Reset", verify default icon restores.
- **System messages:** Trigger a system notification, verify it shows the Soleur "S" logo, not a leader icon.

## Success Metrics

- Zero instances of the generic Soleur logo on routed leader messages/conversations after PR 1
- All 8 leaders visually distinguishable at a glance in conversation list and chat
- Custom icon upload-to-display flow completes in under 3 seconds

## Dependencies & Risks

| Dependency/Risk | Mitigation |
|-----------------|------------|
| lucide-react already in project deps | Verify with `package.json` — if missing, install at app level |
| `.gitignore` blanket `*.png` rule | Add negation for `knowledge-base/settings/team-icons/` directory |
| `team_names` table uses RLS | New column covered by existing RLS policy — no migration GRANT changes needed |
| KB upload API commits via GitHub Contents API (requires `GITHUB_TOKEN`) | Already works for other KB uploads — no new auth needed |
| Large icon files bloating git repo | Enforce 100KB max + 256x256 dimensions client-side |

## Open Questions Resolved

| # | Question | Resolution |
|---|----------|------------|
| 1 | Icon sizing and format constraints | 256x256 max, 100KB max, PNG/SVG/WebP |
| 2 | Dark mode rendering | lucide-react icons use `currentColor`. Custom icons render on colored circle background — consistent contrast. |
| 3 | Curated library contents | Deferred (YAGNI). 1 default lucide-react icon per leader. Custom upload for personalization. Library picker can be added later if users request it. |
| 4 | Storage path | `knowledge-base/settings/team-icons/` |
| 5 | Supabase names + git icons sync | Icon path stored in `team_names.custom_icon_path` (Supabase). Actual file in git via KB upload API. Web platform reads via `/api/kb/content/` at runtime. |

## References & Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-13-dashboard-agent-identity-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-dashboard-agent-identity/spec.md`
- Leader type definitions: `apps/web-platform/server/domain-leaders.ts:1-92`
- Team settings page: `apps/web-platform/components/settings/team-settings.tsx:1-114`
- Leader colors: `apps/web-platform/components/chat/leader-colors.ts:1-27`
- Conversation row + LeaderBadge: `apps/web-platform/components/inbox/conversation-row.tsx:101-116`
- MessageBubble avatar: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:437-449`
- Dashboard leader cards: `apps/web-platform/app/(dashboard)/dashboard/page.tsx:301-360`
- Profile icon to remove: `apps/web-platform/app/(dashboard)/dashboard/page.tsx:423-426,660-665`
- KB upload API: `apps/web-platform/app/api/kb/upload/route.ts`
- Team names API: `apps/web-platform/app/api/team-names/route.ts`
- Team names hook: `apps/web-platform/hooks/use-team-names.tsx:1-149`

### Institutional Learnings Applied

- `.gitignore` blanket PNG rule requires negation (`2026-03-10-gitignore-blanket-rules-with-negation.md`)
- PostgREST bytea returns hex — use `text` for icon paths, not `bytea` (`2026-03-17-postgrest-bytea-base64-mismatch.md`)
- Supabase column GRANT override — explicitly add new columns (`2026-03-20-supabase-column-level-grant-override.md`)
- Domain leader extension simplification — generic instructions, not N variants (`2026-02-22-domain-leader-extension-simplification-pattern.md`)
- CSP nonce middleware — no new inline scripts needed (`2026-03-20-nonce-based-csp-nextjs-middleware.md`)
- UX review gap — need IA review beyond code review (`2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md`)

### Related Issues

- #1871 — Named domain leaders (naming implemented, avatar deferred — this PR delivers the avatar)
- #1879 — Personality customization (Post-MVP, out of scope)
- #2129 — This issue
- #2130 — This PR
