// PII-column-drift guard (plan AC6 / arch P2-4). The stage-enum drift-guard in
// crm-tools.test.ts asserts the stage CHECK set but does NOT cover the PII
// column lists — a silent drift (adding a new PII column to the SELECT, or the
// read layer diverging from the agent path) would ship unnoticed. This test
// pins the EXACT canonical column sets that both the agent path (crm-tools.ts)
// and the read routes/RPC share via server/crm/crm-reads.ts.
//
// This is a change-DETECTOR, not a schema-enforcer: it pins the constants to
// hand-copied literals, so its value is diff-visibility (a column add/remove
// shows up as a failing assertion a reviewer must consciously update), NOT
// live DB-schema verification. If a column is added to both the constant and
// this literal in one edit, it passes — the guard is the review friction, not
// a DB round-trip. (Behavioral DB-shape proofs live in the gated integration
// tests.)

import { describe, expect, it } from "vitest";
import {
  CONTACT_COLUMNS,
  NOTE_COLUMNS,
  TRANSITION_COLUMNS,
} from "@/server/crm/crm-reads";

describe("crm-reads column-list constants (PII-column-drift guard)", () => {
  it("CONTACT_COLUMNS is the exact beta_contacts head column set", () => {
    expect(CONTACT_COLUMNS).toBe(
      "id, user_id, name, company, role, source, stage, next_action, " +
        "next_action_date, last_contact, amount, currency, amount_basis, " +
        "expected_close_date, created_at, updated_at",
    );
  });

  it("NOTE_COLUMNS is the exact interview_notes column set", () => {
    expect(NOTE_COLUMNS).toBe(
      "id, contact_id, user_id, body, lens, occurred_at, created_at",
    );
  });

  it("TRANSITION_COLUMNS is the exact beta_contact_stage_transitions column set", () => {
    expect(TRANSITION_COLUMNS).toBe(
      "id, contact_id, user_id, from_stage, to_stage, entered_at",
    );
  });

  it("column constants contain no duplicate or empty column names", () => {
    for (const cols of [CONTACT_COLUMNS, NOTE_COLUMNS, TRANSITION_COLUMNS]) {
      const names = cols.split(",").map((c) => c.trim());
      expect(names.every((n) => n.length > 0)).toBe(true);
      expect(new Set(names).size).toBe(names.length);
    }
  });
});
