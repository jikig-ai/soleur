export const PENDING_ENTRY_DELAY_MS = 150;
export const NAV_MIN_VISIBLE_MS = 400;
// ~8s "Still working…" escalation delay (feat-ui-action-feedback brief §5/§7)
// — one constant, consumed by every escalation site (billing-section,
// sign-out-confirm-modal); per-episode timer reset lives at the call site.
export const PENDING_ESCALATION_MS = 8_000;
