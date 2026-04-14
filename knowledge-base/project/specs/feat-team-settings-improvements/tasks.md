# Tasks: Team Settings Page Improvements

Issue: #2155

## Phase 1: Remove Redundant Sections from General Page

### 1.1 Remove Connected Services section from settings-content.tsx

- [ ] Remove the Connected Services `<section>` JSX (lines 90-108)
- [ ] Remove the `serviceTokenCount` prop from the interface and component parameters
- [ ] Verify no other code in this file references `serviceTokenCount` after billing removal

### 1.2 Remove Billing section from settings-content.tsx

- [ ] Remove `BillingSection` import
- [ ] Remove billing-related props from `SettingsContentProps` interface: `subscriptionStatus`, `currentPeriodEnd`, `cancelAtPeriodEnd`, `conversationCount`, `serviceTokenCount`, `createdAt`
- [ ] Remove the `<BillingSection>` JSX and its props
- [ ] Verify the component still compiles with remaining sections (Account, Project, API Key, Danger Zone)

### 1.3 Clean up General page data fetching

- [ ] In `app/(dashboard)/dashboard/settings/page.tsx`, remove queries no longer needed: `conversationCount`, `serviceTokenCount`, and subscription fields from `userData` select
- [ ] Remove corresponding props from `<SettingsContent>` component invocation
- [ ] Verify the page still renders correctly with reduced data fetching

## Phase 2: Create Billing Page

### 2.1 Create billing page route

- [ ] Create `app/(dashboard)/dashboard/settings/billing/page.tsx`
- [ ] Implement as a server component following the pattern from the General settings page
- [ ] Fetch billing-required data: `subscription_status`, `current_period_end`, `cancel_at_period_end`, `created_at` from users table
- [ ] Fetch `conversationCount` and `serviceTokenCount` for the retention modal
- [ ] Render `<SettingsShell>` wrapping `<BillingSection>` with all required props
- [ ] Include auth check with redirect to `/login` if unauthenticated

### 2.2 Add Billing tab to settings sidebar

- [ ] In `settings-shell.tsx`, add `{ href: "/dashboard/settings/billing", label: "Billing" }` to `SETTINGS_TABS` array
- [ ] Verify the tab appears in both desktop sidebar and mobile bottom tab bar
- [ ] Verify active state highlighting works correctly for the billing route

## Phase 3: Verification

### 3.1 Visual verification

- [ ] General page shows only Account, Project, API Key, and Danger Zone sections
- [ ] Billing page loads at `/dashboard/settings/billing` with full billing UI
- [ ] Settings sidebar shows 4 tabs: General, Team, Integrations, Billing
- [ ] Mobile bottom tab bar shows all 4 tabs
- [ ] Active tab highlighting works on all 4 routes

### 3.2 Functional verification

- [ ] Billing page subscription management buttons work (portal redirect)
- [ ] Cancel subscription flow with retention modal works on billing page
- [ ] Invoice list loads on billing page
- [ ] No console errors on any settings page
