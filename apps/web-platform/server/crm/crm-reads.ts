// Shared beta-CRM read-column constants — the SINGLE source of truth for which
// columns the owner-scoped read surfaces select (feat-beta-crm-ui #6172,
// ADR-102 UI phase). Two consumers:
//   1. The agent path (crm-tools.ts) — its owner-scoped reads.
//   2. The read routes / detail RPC (app/api/crm/*, migration 127) — the
//      browser-facing GET surfaces.
//
// Co-locating the column lists here prevents PII-column drift: a new
// beta_contacts column that becomes egressable to the browser MUST be a
// conscious edit here, guarded by crm-reads.test.ts (arch P2-4 — the stage-enum
// drift-guard in crm-tools.test.ts does NOT cover these columns). The read
// routes never forward raw Postgres error text (AC5); the query builders are
// inlined in their single consuming route (simplicity review) — this module
// exports ONLY the column-list constants, no query wrappers.
//
// These strings are the exact sets migration 126 created; keep them
// byte-identical to the beta_contacts / interview_notes /
// beta_contact_stage_transitions definitions.

/** beta_contacts head columns, in table-definition order. */
export const CONTACT_COLUMNS =
  "id, user_id, name, company, role, source, stage, next_action, " +
  "next_action_date, last_contact, amount, currency, amount_basis, " +
  "expected_close_date, created_at, updated_at";

/** interview_notes columns (append-only dual-lens conversation notes). */
export const NOTE_COLUMNS =
  "id, contact_id, user_id, body, lens, occurred_at, created_at";

/** beta_contact_stage_transitions columns (append-only velocity source). */
export const TRANSITION_COLUMNS =
  "id, contact_id, user_id, from_stage, to_stage, entered_at";
