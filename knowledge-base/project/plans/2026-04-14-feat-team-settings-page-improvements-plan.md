---
title: "feat: Team Settings Page improvements"
type: feat
date: 2026-04-14
semver: patch
---

# feat: Team Settings Page improvements

## Overview

Reorganize the Settings page layout by removing redundant sections from the General page and creating a dedicated Billing page. The Connected Services section already has its own "Integrations" tab in the sidebar and should not also appear on the General page. The Billing section is substantial enough to warrant its own dedicated page accessible from the Settings sidebar.

## Problem Statement

The General settings page (`/dashboard/settings`) currently contains five sections: Account, Project, API Key, Connected Services, and Billing. Two of these are redundant or misplaced:

1. **Connected Services** is duplicated -- it appears both as a link card on the General page AND as the "Integrations" sidebar tab (`/dashboard/settings/services`). The General page version is just a link to the Integrations page.
2. **Billing** is a complex, self-contained section with subscription management, cancellation flows, and invoice history. It deserves its own dedicated page accessible from the sidebar rather than being buried at the bottom of the General page.

## Proposed Solution

### 1. Remove Connected Services from General Page

Remove the "Connected Services" `<section>` from `settings-content.tsx` (lines 90-108). This is a simple deletion -- the section just contains a description and a "Manage Services" link that points to `/dashboard/settings/services`, which is already the "Integrations" sidebar tab.

**Files to modify:**

- `apps/web-platform/components/settings/settings-content.tsx` -- remove the Connected Services section JSX and its data dependencies
- `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` -- remove the `serviceTokenCount` query since it was only used by the Billing section on this page (Billing will move to its own page)

### 2. Remove Billing from General Page

Remove the `<BillingSection>` component and its `<CancelRetentionModal>` from `settings-content.tsx` (lines 110-118). Remove the associated imports and props (`subscriptionStatus`, `currentPeriodEnd`, `cancelAtPeriodEnd`, `conversationCount`, `serviceTokenCount`, `createdAt`).

**Files to modify:**

- `apps/web-platform/components/settings/settings-content.tsx` -- remove BillingSection import, remove billing-related props from interface and component, remove the JSX
- `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` -- remove billing-related queries (`userData` subscription fields, `conversationCount`, `serviceTokenCount`) and props from the `<SettingsContent>` component

### 3. Create Dedicated Billing Page

Create a new route at `/dashboard/settings/billing` that hosts the existing `BillingSection` component. This page will fetch the required billing data server-side and pass it as props, following the same pattern as the existing settings page.

**Files to create:**

- `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx` -- new server component that fetches billing data and renders `BillingSection` wrapped in `SettingsShell`

### 4. Add Billing to Settings Sidebar

Add a "Billing" tab to the `SETTINGS_TABS` array in `settings-shell.tsx`.

**Files to modify:**

- `apps/web-platform/components/settings/settings-shell.tsx` -- add `{ href: "/dashboard/settings/billing", label: "Billing" }` to `SETTINGS_TABS`

### Summary of Final Sidebar Tabs

| Tab | Route | Status |
|-----|-------|--------|
| General | `/dashboard/settings` | Existing (slimmed down) |
| Team | `/dashboard/settings/team` | Existing (unchanged) |
| Integrations | `/dashboard/settings/services` | Existing (unchanged) |
| Billing | `/dashboard/settings/billing` | New |

### Summary of Files Changed

| File | Action | Description |
|------|--------|-------------|
| `apps/web-platform/components/settings/settings-content.tsx` | Modify | Remove Connected Services section, BillingSection, and related props/imports |
| `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` | Modify | Remove billing/service queries and props no longer needed |
| `apps/web-platform/components/settings/settings-shell.tsx` | Modify | Add Billing tab to sidebar |
| `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx` | Create | New billing page with server-side data fetching |

## Acceptance Criteria

- [ ] Connected Services section no longer appears on the General settings page
- [ ] Billing section no longer appears on the General settings page
- [ ] New Billing page exists at `/dashboard/settings/billing`
- [ ] Billing page shows all existing billing functionality (subscription status, manage/cancel buttons, invoice list)
- [ ] "Billing" tab appears in the Settings sidebar navigation (both desktop sidebar and mobile tab bar)
- [ ] All existing billing API routes (`/api/billing/portal`, `/api/billing/invoices`, `/api/checkout`) continue to work
- [ ] The `CancelRetentionModal` continues to function on the new Billing page
- [ ] General settings page still shows Account, Project, API Key, and Danger Zone sections
- [ ] No regressions in Team or Integrations pages

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

This is a straightforward UI reorganization that moves existing components to better navigation locations. The billing component is reused as-is with no modifications to its interface or behavior.

## Test Scenarios

- Given a user on the General settings page, when the page loads, then they should NOT see a "Connected Services" section
- Given a user on the General settings page, when the page loads, then they should NOT see a "Billing" section
- Given a user on the General settings page, when the page loads, then they should see Account, Project, API Key, and Danger Zone sections
- Given a user navigating the Settings sidebar, when they view the sidebar tabs, then they should see General, Team, Integrations, and Billing tabs
- Given a user clicking the Billing sidebar tab, when the page loads, then they should see subscription status, management buttons, and invoice history
- Given a user on the Billing page with an active subscription, when they click "Cancel Subscription", then the retention modal should appear and function correctly
- Given a user on the Billing page, when they click "Manage Subscription", then they should be redirected to the Stripe billing portal
- Given a user on mobile, when they view the bottom tab bar, then they should see all four settings tabs including Billing

## Non-Goals

- Redesigning the Billing UI itself -- the existing `BillingSection` component is reused as-is
- Changing the Integrations/Connected Services page behavior
- Adding new billing features
- Modifying billing API routes

## Context

- Issue: #2155
- Milestone: Phase 3 (Make it Sticky)
- The `BillingSection` component (`billing-section.tsx`) is a self-contained client component that fetches invoices client-side and handles all billing interactions
- The `CancelRetentionModal` (`cancel-retention-modal.tsx`) is tightly coupled with `BillingSection` and moves with it
- The `SettingsShell` component (`settings-shell.tsx`) provides both the desktop sidebar and mobile bottom tab bar navigation

## References

- `apps/web-platform/components/settings/settings-content.tsx` -- current General page content
- `apps/web-platform/components/settings/settings-shell.tsx` -- settings sidebar/tab navigation
- `apps/web-platform/components/settings/billing-section.tsx` -- billing component to move
- `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` -- current General page data fetching
- `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` -- pattern reference for new billing page
- Learning: `knowledge-base/project/learnings/2026-04-13-billing-review-findings-batch-fix.md` -- recent billing area fixes
