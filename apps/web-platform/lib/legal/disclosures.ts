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

// PR-B (#4379) — autonomous AI runtime disclosure for PA-22.
//
// Rendered alongside RUNTIME_COST_DISCLOSURE above the Today section.
// Tells the operator that Spawn-clicked agents call Anthropic autonomously
// under their BYOK key AND that Anthropic's default retention applies
// until the Zero-Retention amendment is signed. The Zero-Retention amendment
// status lives in PA-22 (f) of knowledge-base/legal/article-30-register.md
// and is checked by scripts/check-pa-22.sh.
//
// The substring "Anthropic retains API request bodies" is load-bearing —
// gated by PA-22 (f). Edit only with CLO sign-off and only after updating
// the register's Zero-Retention amendment status.
export const RUNTIME_AI_DISCLOSURE =
  "Spawn agents call Anthropic autonomously under your BYOK key. Anthropic " +
  "retains API request bodies for up to 30 days for safety review unless " +
  "you sign the Zero-Retention amendment on the Anthropic Console.";
