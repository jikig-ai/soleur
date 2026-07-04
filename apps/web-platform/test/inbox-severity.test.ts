import { describe, it, expect } from "vitest";
import type { EmailTriageItem } from "@/components/inbox/email-triage-row";
import {
  mergeAndRank,
  partitionForDisplay,
  deriveEmailSeverity,
  buildInboxDeepLink,
  countOutstandingActionRequired,
  NEEDS_YOU_CAP,
  type InboxItemRowData,
  type InboxItemSeverity,
} from "@/lib/inbox-severity";

function email(overrides: Partial<EmailTriageItem>): EmailTriageItem {
  return {
    id: overrides.id ?? "e-" + Math.random().toString(36).slice(2, 8),
    message_id: null,
    sender: "sender@example.com",
    subject: "subject",
    summary: null,
    mail_class: null,
    statutory_class: null,
    rule_id: null,
    status: "new",
    status_changed_at: null,
    acknowledged_at: null,
    received_at: "2026-07-01T00:00:00.000Z",
    created_at: "2026-07-01T00:00:00.000Z",
    ...overrides,
  };
}

function inbox(overrides: Partial<InboxItemRowData>): InboxItemRowData {
  return {
    id: overrides.id ?? "i-" + Math.random().toString(36).slice(2, 8),
    severity: "info",
    source: "task_completed",
    title: "Chief Legal Officer finished",
    source_ref: null,
    status: "unread",
    created_at: "2026-07-01T00:00:00.000Z",
    read_at: null,
    acted_at: null,
    archived_at: null,
    ...overrides,
  };
}

describe("deriveEmailSeverity — statutory is action_required, clock/status-independent", () => {
  it("every non-archived statutory row is action_required regardless of status", () => {
    for (const status of ["new", "acknowledged"] as const) {
      expect(
        deriveEmailSeverity(email({ statutory_class: "breach", status })),
      ).toBe<InboxItemSeverity>("action_required");
    }
  });

  it("far-from-deadline statutory is STILL action_required (chip color ≠ severity)", () => {
    // received_at years ago vs. today — severity never derives from the clock,
    // so both a near and a far statutory item resolve identically.
    const nearNow = email({
      statutory_class: "dsar",
      received_at: "2026-07-04T00:00:00.000Z",
    });
    const longAgo = email({
      statutory_class: "dsar",
      received_at: "2000-01-01T00:00:00.000Z",
    });
    expect(deriveEmailSeverity(nearNow)).toBe("action_required");
    expect(deriveEmailSeverity(longAgo)).toBe("action_required");
  });

  it("non-statutory email is info", () => {
    expect(deriveEmailSeverity(email({ mail_class: "vendor" }))).toBe("info");
  });
});

describe("mergeAndRank — pin-first, then severity, then recency", () => {
  it("non-archived statutory pins first (uncapped), above native action_required", () => {
    const statutory = email({
      id: "stat",
      statutory_class: "breach",
      status: "acknowledged", // acknowledged still pins
      received_at: "2026-06-01T00:00:00.000Z", // older than everything else
    });
    const nativeAction = inbox({
      id: "native",
      severity: "action_required",
      created_at: "2026-07-04T00:00:00.000Z", // newest
    });
    const info = inbox({ id: "info", severity: "info" });

    const merged = mergeAndRank([nativeAction, info], [statutory]);
    // Statutory pinned first even though it is the OLDEST item.
    expect(merged[0].id).toBe("stat");
    expect(merged[0].pinned).toBe(true);
    // Then the native action_required (not pinned), then info.
    expect(merged[1].id).toBe("native");
    expect(merged[2].id).toBe("info");
  });

  it("orders by recency DESC within the same severity", () => {
    const older = inbox({ id: "old", severity: "info", created_at: "2026-07-01T00:00:00.000Z" });
    const newer = inbox({ id: "new", severity: "info", created_at: "2026-07-04T00:00:00.000Z" });
    const merged = mergeAndRank([older, newer], []);
    expect(merged.map((m) => m.id)).toEqual(["new", "old"]);
  });
});

describe("outstanding count (nav badge)", () => {
  it("counts action_required that is not resolved (statutory always, native until acted)", () => {
    const items = mergeAndRank(
      [
        inbox({ severity: "action_required", acted_at: null }), // outstanding
        inbox({ severity: "action_required", acted_at: "2026-07-02T00:00:00.000Z" }), // acted → not
        inbox({ severity: "info" }),
      ],
      [email({ statutory_class: "regulator", status: "new" })], // outstanding
    );
    expect(countOutstandingActionRequired(items)).toBe(2);
  });
});

describe("partitionForDisplay — NEEDS YOU cap, statutory exempt", () => {
  it("pins are ALWAYS visible; only non-pinned action_required overflow", () => {
    const pinned = Array.from({ length: 3 }, (_, i) =>
      email({ id: `s${i}`, statutory_class: "breach", status: "new" }),
    );
    const nonPinned = Array.from({ length: NEEDS_YOU_CAP + 5 }, (_, i) =>
      inbox({ id: `a${i}`, severity: "action_required" }),
    );
    const merged = mergeAndRank(nonPinned, pinned);
    const { needsYouVisible, needsYouOverflow, goodToKnow } =
      partitionForDisplay(merged);

    // Every pinned statutory item is visible (never capped).
    for (const p of pinned) {
      expect(needsYouVisible.some((m) => m.id === p.id)).toBe(true);
    }
    // Total visible NEEDS YOU is capped; room for unpinned = CAP - pinnedCount.
    const unpinnedVisible = needsYouVisible.filter((m) => !m.pinned).length;
    expect(unpinnedVisible).toBe(NEEDS_YOU_CAP - pinned.length);
    expect(needsYouOverflow).toBe(nonPinned.length - unpinnedVisible);
    expect(goodToKnow).toHaveLength(0);
  });
});

describe("buildInboxDeepLink — from source_ref ids, null when target absent", () => {
  it("task_completed links to the conversation", () => {
    expect(buildInboxDeepLink("task_completed", { conversationId: "c1" })).toBe(
      "/dashboard/chat/c1",
    );
  });
  it("task_completed with no ref is non-navigating (null)", () => {
    expect(buildInboxDeepLink("task_completed", null)).toBeNull();
  });
  it("system uses an explicit same-origin path or defaults to /dashboard", () => {
    expect(buildInboxDeepLink("system", { path: "/dashboard/billing" })).toBe(
      "/dashboard/billing",
    );
    expect(buildInboxDeepLink("system", null)).toBe("/dashboard");
    // Never trust an off-origin / non-relative path.
    expect(buildInboxDeepLink("system", { path: "https://evil.example" })).toBe(
      "/dashboard",
    );
  });
  it("not-yet-shipped sources (approval_required/autopilot_run) are non-navigating", () => {
    expect(buildInboxDeepLink("approval_required", { any: "x" })).toBeNull();
    expect(buildInboxDeepLink("autopilot_run", { any: "x" })).toBeNull();
  });
});
