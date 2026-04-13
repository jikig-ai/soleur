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
| FR1 | Invoice list page displays all paid invoices for the current user's Stripe customer, fetched server-side via `stripe.invoices.list()` |
| FR2 | Each invoice row shows date, amount, status, and a download link to the Stripe-hosted PDF |
| FR3 | In-app banner appears when `subscription_status` is `past_due` or `unpaid`, with a link to Stripe Customer Portal |
| FR4 | Banner is persistent (not dismissible) for `unpaid` status, dismissible for `past_due` |
| FR5 | When `subscription_status` is `unpaid`, the app enters read-only mode: KB viewable, conversations viewable, but no new conversations or agent execution |
| FR6 | Webhook handler logs `invoice.payment_failed` for observability but does NOT change `subscription_status` (Stripe fires this on every retry; `customer.subscription.updated` is the authoritative source) |
| FR7 | Webhook handler processes `customer.subscription.updated` and maps Stripe status directly: `past_due` to `past_due`, `unpaid` to `unpaid`, `active` to `active` |
| FR8 | Webhook handler processes `invoice.paid` and restores `subscription_status = 'active'` (belt-and-suspenders alongside `customer.subscription.updated`) |
| FR9 | All webhook updates are idempotent by nature (setting same status is a no-op) — no `stripe_events` idempotency table needed |
| FR10 | Stripe Customer Portal sessions are created dynamically via `stripe.billingPortal.sessions.create()` (replace hardcoded test URL) |

## Technical Requirements

| ID | Requirement |
|----|------------|
| TR1 | Database migration expands `subscription_status` CHECK constraint to include `unpaid` (migration 022) |
| TR2 | Webhook signature verification uses existing `stripe.webhooks.constructEvent()` pattern |
| TR3 | Webhook route remains in `PUBLIC_PATHS` for CSRF (no Origin header from Stripe) |
| TR4 | Middleware checks `subscription_status` in the same query as T&C check (combined `.select("tc_accepted_version, subscription_status")`) |
| TR5 | Middleware billing check fails open (if query errors, allow access) |
| TR6 | All Supabase queries destructure `{ data, error }` and check error (per learnings) |
| TR7 | Stripe secrets stored in Doppler (`dev` and `prd` configs) |
| TR8 | Migration verified applied to production post-merge (per AGENTS.md) |

## Test Scenarios

| ID | Scenario | Expected Result |
|----|----------|----------------|
| TS1 | `invoice.payment_failed` webhook fires | Event logged for observability, `subscription_status` NOT changed |
| TS2 | Duplicate webhook event with same status | Second event is no-op (idempotent update) |
| TS3 | `customer.subscription.updated` with `status: unpaid` | `subscription_status` updated to `unpaid` |
| TS4 | `invoice.paid` after failed payment | `subscription_status` restored to `active` |
| TS5 | User with `past_due` status visits dashboard | Banner shown, full access retained |
| TS6 | User with `unpaid` status tries to start conversation | Blocked via WS gate, shown read-only message |
| TS7 | User with `unpaid` status views KB | Access allowed (read-only, GET passes middleware) |
| TS8 | Invoice list page loads for user with Stripe customer | Invoices displayed with PDF links |
| TS9 | Invoice list page loads for user without Stripe customer | Empty state shown |
| TS10 | Billing page Portal link | Creates dynamic portal session (not hardcoded test URL) |
