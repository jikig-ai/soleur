// Single switch for the per-issue Concierge conversation backend. False in v1
// (offline — opening soon). Lifted out of issue-concierge-panel.tsx so the panel
// AND the New Issue dialog's disabled "Create with Concierge" field share ONE
// literal (no divergent second copy). Going live later is a one-flag flip + the
// composer/dialog wiring (tracked follow-up).
export const CONCIERGE_ONLINE = false;
