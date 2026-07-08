// PII-column-drift guard (plan AC6 / arch P2-4). The stage-enum drift-guard in
// crm-tools.test.ts asserts the stage CHECK set but does NOT cover the PII
// column lists — a silent drift (adding a new PII column to the SELECT, or the
// read layer diverging from the agent path) would ship unnoticed. This test
// pins the EXACT canonical column sets that both the agent path (crm-tools.ts)
// and the read routes/RPC share via server/crm/crm-reads.ts.
//
// If a beta_contacts / interview_notes / beta_contact_stage_transitions column
// is added or removed, this test fails on purpose — forcing a conscious review
// of whether the new column is safe to egress to the browser (AC5 leak class).

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
