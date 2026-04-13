# Spec: Invoice History + Failed Payment Recovery

**Issue:** #1079
**Phase:** 3 (Make it Sticky)
**Priority:** P2
**Branch:** feat-invoice-recovery

## Problem Statement

The billing system has a pricing page (#656) and subscription management (#1078), but no way for founders to view their invoice history, no notification when payments fail, and no mechanism to recover from failed payments or enforce access restrictions on unpaid accounts.

## Goals

1. Founders can view their invoice history with PDF download links
2. Failed payments are surfaced via in-app banner with a path to resolution
3. Unpaid subscriptions result in read-only access (not full lockout)
4. Webhook handlers correctly track subscription status transitions

## Non-Goals

- Custom card-update form (using Stripe Customer Portal instead)
- Custom retry logic (using Stripe Smart Retries)
- Custom failed payment emails (using Stripe built-in emails)
- Local invoice storage (fetching from Stripe API on demand)
- 3-month auto-deletion for unpaid accounts (separate issue)
- Recurring email reminders during grace period (separate issue)

## Functional Requirements

| ID | Requirement |
|----|------------|
| FR1 | Invoice list page displays all invoices for the current user's Stripe customer, fetched server-side via `stripe.invoices.list()` |
| FR2 | Each invoice row shows date, amount, status, and a download link to the Stripe-hosted PDF |
| FR3 | In-app banner appears when `subscription_status` is `past_due` or `unpaid`, with a link to Stripe Customer Portal |
| FR4 | Banner is persistent (not dismissible) for `unpaid` status, dismissible for `past_due` |
| FR5 | When `subscription_status` is `unpaid`, the app enters read-only mode: KB viewable, conversations viewable, but no new conversations or agent execution |
| FR6 | Webhook handler processes `invoice.payment_failed` and sets `subscription_status = 'past_due'` |
| FR7 | Webhook handler processes `customer.subscription.updated` and sets status to `unpaid` when Stripe marks subscription as unpaid |
| FR8 | Webhook handler processes `invoice.paid` and restores `subscription_status = 'active'` |
| FR9 | All webhook events are deduplicated by Stripe `event.id` for idempotency |
| FR10 | Stripe Customer Portal sessions are created dynamically via `stripe.billingPortal.sessions.create()` (replace hardcoded test URL) |

## Technical Requirements

| ID | Requirement |
|----|------------|
| TR1 | Database migration adds `suspended_at timestamptz` to users table |
| TR2 | Webhook signature verification uses existing `stripe.webhooks.constructEvent()` pattern |
| TR3 | Webhook route remains in `EXEMPT_ROUTES` for CSRF (no Origin header from Stripe) |
| TR4 | Middleware checks `subscription_status` following the existing T&C check pattern |
| TR5 | Middleware billing check fails open (if query errors, allow access) |
| TR6 | All Supabase queries destructure `{ data, error }` and check error (per learnings) |
| TR7 | Stripe secrets stored in Doppler (`dev` and `prd` configs) |
| TR8 | Migration verified applied to production post-merge (per AGENTS.md) |

## Test Scenarios

| ID | Scenario | Expected Result |
|----|----------|----------------|
| TS1 | `invoice.payment_failed` webhook fires | `subscription_status` updated to `past_due` |
| TS2 | Duplicate `invoice.payment_failed` event | Second event is no-op (idempotent) |
| TS3 | `customer.subscription.updated` with `status: unpaid` | `subscription_status` updated to `unpaid`, `suspended_at` set |
| TS4 | `invoice.paid` after failed payment | `subscription_status` restored to `active`, `suspended_at` cleared |
| TS5 | User with `past_due` status visits dashboard | Banner shown, full access retained |
| TS6 | User with `unpaid` status tries to start conversation | Blocked, shown read-only message |
| TS7 | User with `unpaid` status views KB | Access allowed (read-only) |
| TS8 | Invoice list page loads for user with Stripe customer | Invoices displayed with PDF links |
| TS9 | Invoice list page loads for user without Stripe customer | Empty state shown |
| TS10 | Billing page Portal link | Creates dynamic portal session (not hardcoded test URL) |
