// PR-F (#3244, #3940) Phase 5 — RV13 (Kieran P2.3).
//
// Single source of truth for runtime-cost legal disclosures rendered on
// the dashboard Today section. Imported (not duplicated) by every render
// site so a legal-copy edit lands at one location.
//
// The substring "disclaims warranty for runtime cost" is load-bearing —
// gated by the today-banner test and by the BSL 1.1 LICENSE language
// covering Anthropic API costs incurred by autonomous-draft turns. Edit
// the substring only with CLO sign-off.

export const RUNTIME_COST_DISCLOSURE =
  "Soleur disclaims warranty for runtime cost. Autonomous drafts call the " +
  "Anthropic API against your own key; per-tenant hourly cost caps apply " +
  "and trips pause the runtime. Drafts shown here have NOT been sent — " +
  "you decide whether to send, edit, or discard each one.";
