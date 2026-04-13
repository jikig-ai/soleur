# Tasks: Dashboard Agent Identity Badges and Team Icon Customization

**Branch:** `feat-dashboard-agent-identity`
**Plan:** [2026-04-13-feat-dashboard-agent-identity-badges-plan.md](../../plans/2026-04-13-feat-dashboard-agent-identity-badges-plan.md)
**Issue:** #2129
**PR:** #2130

## Phase 1: PR 1 — Data Model + Default Badges

### 1.1 Extend domain leader type definitions

- [ ] Add `defaultIcon` field (lucide-react icon name) to `DOMAIN_LEADERS` in `apps/web-platform/server/domain-leaders.ts`
- [ ] Add `color` field (Tailwind color token) to `DOMAIN_LEADERS`
- [ ] Map all 8 leaders + system: CMO/Megaphone/pink-500, CTO/Cog/blue-500, CFO/TrendingUp/emerald-500, CPO/Boxes/violet-500, CRO/Target/orange-500, COO/Wrench/amber-500, CLO/Scale/slate-400, CCO/Headphones/cyan-500, system/logo/neutral-600
- [ ] Update `leader-colors.ts` to reconcile with new color values (green→emerald, purple→violet, red→slate, teal→cyan, yellow→amber)

### 1.2 Create shared LeaderAvatar component

- [ ] Create `apps/web-platform/components/leader-avatar.tsx`
- [ ] Accept props: `leaderId`, `size` (sm/md/lg), optional `className`
- [ ] Resolve icon: default lucide-react icon → Soleur logo (system/null)
- [ ] Render circular badge with leader's background color and white icon
- [ ] Include `aria-label="{leader name} avatar"`
- [ ] Memoize icon resolution

### 1.3 Replace duplicated badge rendering

- [ ] `apps/web-platform/components/inbox/conversation-row.tsx` — replace `LeaderBadge` (lines 101-116) with `LeaderAvatar`
- [ ] `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — replace inline avatar in `MessageBubble` (lines 437-449) with `LeaderAvatar`
- [ ] `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — replace inline badges in foundation cards, LeaderStrip, and suggested prompts

### 1.4 Restrict Soleur badge + remove dead profile icon

- [ ] `LeaderAvatar` renders Soleur logo only when `leaderId` is `"system"` or null/undefined
- [ ] Delete `UserIcon` circle at `dashboard/page.tsx` lines 423-426
- [ ] Delete `UserIcon` SVG component at `dashboard/page.tsx` lines 660-665

### 1.5 Verify and test PR 1

- [ ] Run dev server, verify all 8 leaders show distinct icons in conversation list
- [ ] Verify message bubbles show per-leader icons
- [ ] Verify system messages show Soleur logo
- [ ] Verify profile icon is removed
- [ ] Verify no visual regression on status badges, layout, chat

## Phase 2: PR 2 — Custom Icon Upload

### 2.1 Supabase migration

- [ ] Create migration adding nullable `custom_icon_path` text column to `team_names` table
- [ ] Column stores relative KB path (e.g., `settings/team-icons/cto.png`)
- [ ] Existing RLS policy covers new column — no GRANT changes needed

### 2.2 Extend API and hook

- [ ] Extend `/api/team-names` route to GET/PUT `custom_icon_path`
- [ ] Extend `use-team-names.tsx` hook with `getIconPath(leaderId)` and `updateIcon(leaderId, path)`

### 2.3 Add upload to team settings

- [ ] Make leader avatar clickable in `team-settings.tsx` (click-to-upload)
- [ ] Open native file picker on click, constrained to PNG/SVG/WebP
- [ ] Client-side validation: max 256x256px, max 100KB
- [ ] Upload via existing KB upload API to `knowledge-base/settings/team-icons/{leader_id}.{ext}`
- [ ] Show upload progress on avatar
- [ ] Show toast error with retry on failure
- [ ] Add "Reset" button when custom icon is set

### 2.4 Extend LeaderAvatar for custom icons

- [ ] Add custom icon resolution step: check `custom_icon_path` → render `<img>` via `/api/kb/content/{path}`
- [ ] Handle 404 (deleted file) gracefully — fall back to default icon
- [ ] Add `alt="{leader name} custom icon"` on custom images

### 2.5 Git storage setup

- [ ] Add `.gitignore` negation rules for `knowledge-base/settings/team-icons/` (*.png,*.svg, *.webp)
- [ ] Verify KB upload API commits to correct path

### 2.6 Verify and test PR 2

- [ ] Upload a custom icon, verify it appears across all surfaces
- [ ] Reset to default, verify lucide icon restores
- [ ] Upload oversized file, verify client-side rejection
- [ ] Verify custom icon persists across page refresh
- [ ] Verify 404 fallback (manually delete file, check avatar renders default)
