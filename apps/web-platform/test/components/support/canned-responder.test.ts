import { describe, it, expect } from "vitest";
import { getSupportReply } from "@/components/support/canned-responder";
import {
  SUPPORT_KB_HREF,
  SUPPORT_STARTER_CHIPS,
} from "@/components/support/support-persona";

describe("getSupportReply", () => {
  it("returns a distinct keyed reply for each starter chip", () => {
    const replies = SUPPORT_STARTER_CHIPS.map((c) =>
      getSupportReply(c.label, c.key),
    );
    // Each chip gets its own answer (not one fixed string).
    expect(new Set(replies).size).toBe(SUPPORT_STARTER_CHIPS.length);
  });

  it("falls back to a generic reply for free-text input", () => {
    const reply = getSupportReply("something totally unrelated");
    expect(reply.length).toBeGreaterThan(0);
    // Generic reply differs from every keyed reply.
    for (const c of SUPPORT_STARTER_CHIPS) {
      expect(reply).not.toBe(getSupportReply(c.label, c.key));
    }
  });

  it("every reply restates coming-soon and includes the KB escape hatch", () => {
    const all = [
      getSupportReply("free text"),
      ...SUPPORT_STARTER_CHIPS.map((c) => getSupportReply(c.label, c.key)),
    ];
    for (const reply of all) {
      expect(reply.toLowerCase()).toContain("coming soon");
      expect(reply).toContain(SUPPORT_KB_HREF);
    }
  });
});
