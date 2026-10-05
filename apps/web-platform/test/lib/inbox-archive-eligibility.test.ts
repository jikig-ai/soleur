import { describe, it, expect } from "vitest";
import {
  archiveEligibility,
  emailRowEligibility,
  inboxRowEligibility,
  keyOf,
  REASON_COPY,
  type ArchiveEligibilityReason,
} from "@/lib/inbox-archive-eligibility";
import type { MergedInboxItem } from "@/lib/inbox-severity";
import type { EmailTriageItem } from "@/components/inbox/email-triage-row";

const email = (
  status: string,
  statutory_class: string | null,
): EmailTriageItem => ({
  id: "e1",
  message_id: null,
  sender: "ops@example.test",
  subject: "s",
  summary: null,
  mail_class: null,
  statutory_class,
  rule_id: null,
  status,
  status_changed_at: null,
  acknowledged_at: status === "acknowledged" ? "2026-09-30T00:00:00Z" : null,
  received_at: "2026-09-30T00:00:00Z",
  created_at: "2026-09-30T00:00:00Z",
});

const mergedEmail = (
  status: string,
  statutory_class: string | null,
): MergedInboxItem => ({
  kind: "email",
  id: "e1",
  severity: statutory_class ? "action_required" : "info",
  pinned: statutory_class !== null && status !== "archived",
  outstanding: statutory_class !== null && status !== "archived",
  email: email(status, statutory_class),
});

const mergedInbox = (
  severity: "action_required" | "attention" | "info",
  acted_at: string | null,
  status: "unread" | "read" | "archived" = "read",
): MergedInboxItem => ({
  kind: "inbox",
  id: "i1",
  severity,
  pinned: false,
  outstanding: severity === "action_required" && acted_at === null,
  inbox: {
    id: "i1",
    severity,
    source: "task_completed",
    title: "t",
    source_ref: null,
    status,
    created_at: "2026-09-30T00:00:00Z",
    read_at: null,
    acted_at,
    archived_at: status === "archived" ? "2026-09-30T00:00:00Z" : null,
  },
});

describe("emailRowEligibility — enum-exhaustive over status × statutory", () => {
  it.each([
    ["new", null, "ok"],
    ["new", "dsar", "statutory"],
    ["acknowledged", null, "already_acknowledged"],
    ["acknowledged", "dsar", "statutory"],
    ["archived", null, "already_archived"],
    ["archived", "dsar", "already_archived"],
  ] as const)("status=%s statutory=%s → %s", (status, stat, want) => {
    expect(emailRowEligibility({ status, statutory_class: stat })).toBe(want);
  });
});

describe("inboxRowEligibility — enum-exhaustive over severity × acted_at", () => {
  it.each([
    ["action_required", null, "needs_action"],
    ["action_required", "2026-09-30T00:00:00Z", "ok"],
    ["attention", null, "ok"],
    ["info", null, "ok"],
  ] as const)("severity=%s acted_at=%s → %s", (sev, acted, want) => {
    expect(
      inboxRowEligibility({
        severity: sev,
        acted_at: acted,
        status: "read",
      }),
    ).toBe(want);
  });

  it("archived inbox row → already_archived", () => {
    expect(
      inboxRowEligibility({
        severity: "info",
        acted_at: null,
        status: "archived",
      }),
    ).toBe("already_archived");
  });
});

describe("archiveEligibility (MergedInboxItem adapter)", () => {
  it.each([
    [mergedEmail("new", null), "ok"],
    [mergedEmail("new", "breach"), "statutory"],
    [mergedEmail("acknowledged", null), "already_acknowledged"],
    [mergedEmail("archived", null), "already_archived"],
    [mergedInbox("action_required", null), "needs_action"],
    [mergedInbox("action_required", "2026-09-30T00:00:00Z"), "ok"],
    [mergedInbox("info", null), "ok"],
  ] as const)("merged row → %s", (item, want) => {
    expect(archiveEligibility(item)).toBe(want);
  });
});

describe("keyOf", () => {
  it("produces the kind:id contract shared with the bulk-archive body", () => {
    expect(keyOf({ kind: "email", id: "abc" })).toBe("email:abc");
    expect(keyOf({ kind: "inbox", id: "abc" })).toBe("inbox:abc");
  });
});

describe("REASON_COPY", () => {
  it("covers every non-ok reason", () => {
    const reasons: Exclude<ArchiveEligibilityReason, "ok">[] = [
      "statutory",
      "needs_action",
      "already_acknowledged",
      "already_archived",
    ];
    for (const r of reasons) {
      expect(REASON_COPY[r]).toBeTruthy();
    }
    // No copy for the archivable case — it has no disabled state.
    expect("ok" in REASON_COPY).toBe(false);
  });
});
