import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  redactRow,
  MESSAGE_REDACT_FIELDS,
  MESSAGE_NON_REDACT_ALLOWLIST,
} from "@/server/dsar-export";

// feat-reasoning-chat-boxes (#5370) — DSAR coverage for the turn_summary row.
// (a) A turn_summary the SUBJECT authored (user_id = subject) exports with
//     UN-redacted `content` — the Art. 15(4) author-redaction predicate keys on
//     user_id, NOT role, so the user's own summary stays in their export.
// (b) message_kind is a structural discriminator → classified non-redact.
// (c) conversation-delete cascades the row away (distinct from account-delete):
//     turn_summary sets conversation_id, so the mig-001 FK cascade erases it.

const FOUNDER = "52af49c2-d68e-477b-ba76-129e41807c7c";

function turnSummaryRow(userId: string | null): Record<string, unknown> {
  return {
    id: "row-1",
    conversation_id: "conv-1",
    user_id: userId,
    role: "assistant",
    content: "Fixed the side panel so it stays open on mobile.",
    message_kind: "turn_summary",
  };
}

describe("DSAR — turn_summary exports with un-redacted content (Art. 15(4))", () => {
  it("does NOT redact a turn_summary the subject authored", () => {
    const row = turnSummaryRow(FOUNDER);
    // Subject-authored → shouldRedact = false (== !isSubjectAuthored).
    const applied = redactRow(row, /*shouldRedact*/ false, MESSAGE_REDACT_FIELDS);
    expect(applied).toBe(false);
    expect(row.content).toBe("Fixed the side panel so it stays open on mobile.");
    expect(row.message_kind).toBe("turn_summary");
  });

  it("redacts content for a turn_summary authored by ANOTHER user, but KEEPS message_kind", () => {
    const row = turnSummaryRow("some-other-user");
    const applied = redactRow(
      row,
      /*shouldRedact*/ true,
      MESSAGE_REDACT_FIELDS,
      "user_id",
      "member_deadbeef",
    );
    expect(applied).toBe(true);
    expect(row.content).toBeNull(); // content ∈ MESSAGE_REDACT_FIELDS
    expect(row.user_id).toBe("member_deadbeef"); // pseudonymised
    expect(row.message_kind).toBe("turn_summary"); // structural — never nulled
  });

  it("classifies message_kind as non-redact (structural discriminator)", () => {
    expect(MESSAGE_NON_REDACT_ALLOWLIST).toContain("message_kind");
    expect(MESSAGE_REDACT_FIELDS).not.toContain("message_kind");
  });
});

describe("DSAR — conversation-delete cascade (distinct from account-delete)", () => {
  it("messages.conversation_id FK is ON DELETE CASCADE (mig 001) — turn_summary inherits it", () => {
    const sql = readFileSync(
      join(__dirname, "..", "supabase", "migrations", "001_initial_schema.sql"),
      "utf8",
    );
    // turn_summary rows set conversation_id (NOT NULL), so deleting the parent
    // conversation cascades the summary row away with no special handling.
    expect(sql).toMatch(
      /conversation_id\s+uuid\s+not null\s+references\s+public\.conversations\(id\)\s+on delete cascade/i,
    );
  });
});
