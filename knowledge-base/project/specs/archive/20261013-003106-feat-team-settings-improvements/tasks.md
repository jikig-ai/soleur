# Tasks: Team Settings Page Improvements

Issue: #2155

## Phase 1: Remove Redundant Sections from General Page

### 1.1 Remove Connected Services section from settings-content.tsx

- [x] Remove the Connected Services `<section>` JSX (lines 90-108)
- [x] Remove the `serviceTokenCount` prop from the interface and component parameters
- [x] Verify no other code in this file references `serviceTokenCount` after billing removal

### 1.2 Remove Billing section from settings-content.tsx

- [x] Remove `BillingSection` import
- [x] Remove billing-related props from `SettingsContentProps` interface: `subscriptionStatus`, `currentPeriodEnd`, `cancelAtPeriodEnd`, `conversationCount`, `serviceTokenCount`, `createdAt`
- [x] Remove the `<BillingSection>` JSX and its props
- [x] Verify the component still compiles with remaining sections (Account, Project, API Key, Danger Zone)

### 1.3 Clean up General page data fetching

- [x] In `app/(dashboard)/dashboard/settings/page.tsx`, remove queries no longer needed: `conversationCount`, `serviceTokenCount`, and subscription fields from `userData` select
- [x] Remove corresponding props from `<SettingsContent>` component invocation
- [x] Verify the page still renders correctly with reduced data fetching

## Phase 2: Create Billing Page

### 2.1 Create billing page route

- [x] Create `app/(dashboard)/dashboard/settings/billing/page.tsx`
- [x] Implement as a server component following the pattern from the General settings page
- [x] Fetch billing-required data: `subscription_status`, `current_period_end`, `cancel_at_period_end`, `created_at` from users table
- [x] Fetch `conversationCount` and `serviceTokenCount` for the retention modal
- [x] Render `<SettingsShell>` wrapping `<BillingSection>` with all required props
- [x] Include auth check with redirect to `/login` if unauthenticated

### 2.2 Add Billing tab to settings sidebar

- [x] In `settings-shell.tsx`, add `{ href: "/dashboard/settings/billing", label: "Billing" }` to `SETTINGS_TABS` array
- [x] Verify the tab appears in both desktop sidebar and mobile bottom tab bar
- [x] Verify active state highlighting works correctly for the billing route

## Phase 3: Verification

### 3.1 Visual verification

- [x] General page shows only Account, Project, API Key, and Danger Zone sections
- [x] Billing page loads at `/dashboard/settings/billing` with full billing UI
- [x] Settings sidebar shows 4 tabs: General, Team, Integrations, Billing
- [x] Mobile bottom tab bar shows all 4 tabs
- [x] Active tab highlighting works on all 4 routes

### 3.2 Functional verification

- [x] Billing page subscription management buttons work (portal redirect)
- [x] Cancel subscription flow with retention modal works on billing page
- [x] Invoice list loads on billing page
- [x] No console errors on any settings page
