export const PENDING_ENTRY_DELAY_MS = 150;
export const NAV_MIN_VISIBLE_MS = 400;
// ~8s "Still working…" escalation delay (feat-ui-action-feedback brief §5/§7)
// — one constant, consumed by every escalation site (billing-section,
// sign-out-confirm-modal); per-episode timer reset lives at the call site.
export const PENDING_ESCALATION_MS = 8_000;
// The 30s termination horizon. Two semantically distinct clocks share the
// value: PENDING_WATCHDOG_MS releases a hung action-pending episode
// (usePendingAction) and NAV_STALL_MS force-stops a hung nav-pending episode.
// Both live here so retuning the horizon can't drift them apart silently;
// the names stay distinct because the failure classes differ.
export const PENDING_WATCHDOG_MS = 30_000;
export const NAV_STALL_MS = PENDING_WATCHDOG_MS;
