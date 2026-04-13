# Tasks: Dashboard Agent Identity Badges and Team Icon Customization

**Branch:** `feat-dashboard-agent-identity`
**Plan:** [2026-04-13-feat-dashboard-agent-identity-badges-plan.md](../../plans/2026-04-13-feat-dashboard-agent-identity-badges-plan.md)
**Issue:** #2129
**PR:** #2130

## Phase 1: PR 1 — Data Model + Default Badges

### 1.1 Extend domain leader type definitions

- [x] Add `defaultIcon` field (lucide-react icon name) to `DOMAIN_LEADERS` in `apps/web-platform/server/domain-leaders.ts`
- [x] Add `color` field (Tailwind color token) to `DOMAIN_LEADERS`
- [x] Map all 8 leaders + system: CMO/Megaphone/pink-500, CTO/Cog/blue-500, CFO/TrendingUp/emerald-500, CPO/Boxes/violet-500, CRO/Target/orange-500, COO/Wrench/amber-500, CLO/Scale/slate-400, CCO/Headphones/cyan-500, system/logo/neutral-600
- [x] Update `leader-colors.ts` to reconcile with new color values (green→emerald, purple→violet, red→slate, teal→cyan, yellow→amber)

### 1.2 Create shared LeaderAvatar component

- [x] Create `apps/web-platform/components/leader-avatar.tsx`
- [x] Accept props: `leaderId`, `size` (sm/md/lg), optional `className`
- [x] Resolve icon: default lucide-react icon → Soleur logo (system/null)
- [x] Render circular badge with leader's background color and white icon
- [x] Include `aria-label="{leader name} avatar"`
- [x] Memoize icon resolution

### 1.3 Replace duplicated badge rendering

- [x] `apps/web-platform/components/inbox/conversation-row.tsx` — replace `LeaderBadge` (lines 101-116) with `LeaderAvatar`
- [x] `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — replace inline avatar in `MessageBubble` (lines 437-449) with `LeaderAvatar`
- [x] `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — replace inline badges in foundation cards, LeaderStrip, and suggested prompts

### 1.4 Restrict Soleur badge + remove dead profile icon

- [x] `LeaderAvatar` renders Soleur logo only when `leaderId` is `"system"` or null/undefined
- [x] Delete `UserIcon` circle at `dashboard/page.tsx` lines 423-426
- [x] Delete `UserIcon` SVG component at `dashboard/page.tsx` lines 660-665

### 1.5 Verify and test PR 1

- [ ] Run dev server, verify all 8 leaders show distinct icons in conversation list
- [ ] Verify message bubbles show per-leader icons
- [ ] Verify system messages show Soleur logo
- [ ] Verify profile icon is removed
- [ ] Verify no visual regression on status badges, layout, chat

## Phase 2: PR 2 — Custom Icon Upload

### 2.1 Supabase migration

- [x] Create migration adding nullable `custom_icon_path` text column to `team_names` table
- [x] Column stores relative KB path (e.g., `settings/team-icons/cto.png`)
- [x] Existing RLS policy covers new column — no GRANT changes needed

### 2.2 Extend API and hook

- [x] Extend `/api/team-names` route to GET/PUT `custom_icon_path`
- [x] Extend `use-team-names.tsx` hook with `getIconPath(leaderId)` and `updateIcon(leaderId, path)`

### 2.3 Add upload to team settings

- [x] Make leader avatar clickable in `team-settings.tsx` (click-to-upload)
- [x] Open native file picker on click, constrained to PNG/SVG/WebP
- [x] Client-side validation: max 256x256px, max 100KB
- [x] Upload via existing KB upload API to `knowledge-base/settings/team-icons/{leader_id}.{ext}`
- [x] Show upload progress on avatar
- [x] Show toast error with retry on failure
- [x] Add "Reset" button when custom icon is set

### 2.4 Extend LeaderAvatar for custom icons

- [x] Add custom icon resolution step: check `custom_icon_path` → render `<img>` via `/api/kb/content/{path}`
- [x] Handle 404 (deleted file) gracefully — fall back to default icon
- [x] Add `alt="{leader name} custom icon"` on custom images

### 2.5 Git storage setup

- [x] Add `.gitignore` negation rules for `knowledge-base/settings/team-icons/` (*.png,*.svg, *.webp)
- [x] Verify KB upload API commits to correct path

### 2.6 Verify and test PR 2

- [ ] Upload a custom icon, verify it appears across all surfaces
- [ ] Reset to default, verify lucide icon restores
- [ ] Upload oversized file, verify client-side rejection
- [ ] Verify custom icon persists across page refresh
- [ ] Verify 404 fallback (manually delete file, check avatar renders default)
