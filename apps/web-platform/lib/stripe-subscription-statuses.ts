// DB statuses that represent a billable / live subscription — eligible to be
// cancelled by customer.subscription.deleted. Excludes "none" (never
// subscribed) and "cancelled" (terminal — see SUBSCRIPTION_UPDATABLE_STATUSES).
export const SUBSCRIPTION_LIVE_STATUSES = ["active", "past_due", "unpaid"] as const;

// DB statuses on which customer.subscription.updated and
// checkout.session.completed may overwrite the row. Includes "none" so a
// first-time subscription activation (none → active) succeeds. Excludes
// "cancelled" — cancelled is terminal; no .updated event should ever move a
// row off it (a stale .updated arriving after .deleted must be a no-op
// regardless of newStatus). NOTE: This guards status-resurrection only.
// Payload columns (current_period_end, cancel_at_period_end) are protected
// by the processed_stripe_events dedup table (migration 030, #2772).
export const SUBSCRIPTION_UPDATABLE_STATUSES = [
  "none",
  ...SUBSCRIPTION_LIVE_STATUSES,
] as const;
