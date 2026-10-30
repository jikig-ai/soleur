// #9545 PR2 — the id shared by the egress audit page heading (the view renders it) and the refresh
// button (it moves focus there once a refresh settles). Kept in its own module so the view and the
// button never import each other.
export const EGRESS_AUDIT_HEADING_ID = "egress-audit-heading";
