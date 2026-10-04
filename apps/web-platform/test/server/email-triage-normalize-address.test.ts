import { describe, expect, it } from "vitest";

import {
  buildRecipients,
  normalizeInboundAddress,
  MAX_INBOUND_RECIPIENTS,
} from "@/server/email-triage/events";

// Pure helpers behind the inbound routing key (ADR-269). The webhook route
// normalizes recipients BEFORE the Inngest event is sent, so the event store
// only ever holds normalized addresses (no display names, no mixed case).

describe("normalizeInboundAddress", () => {
  it("lowercases and trims a bare address", () => {
    expect(normalizeInboundAddress("  Triage@Inbound.Soleur.AI ")).toBe(
      "triage@inbound.soleur.ai",
    );
  });

  it("extracts the address from a `Name <addr>` form", () => {
    expect(
      normalizeInboundAddress('"Ops Team" <Triage@inbound.soleur.ai>'),
    ).toBe("triage@inbound.soleur.ai");
  });

  it("rejects non-string input", () => {
    for (const bad of [null, undefined, 42, {}, [], true]) {
      expect(normalizeInboundAddress(bad)).toBeNull();
    }
  });

  it("rejects malformed addresses", () => {
    for (const bad of [
      "",
      "   ",
      "no-at-sign",
      "@no-local.example",
      "local@",
      "two@@ats.example",
      "a@b",
      "a b@c.example",
      "<>",
    ]) {
      expect(normalizeInboundAddress(bad)).toBeNull();
    }
  });

  it("rejects an address longer than 320 characters", () => {
    const long = `${"a".repeat(310)}@inbound.soleur.ai`;
    expect(long.length).toBeGreaterThan(320);
    expect(normalizeInboundAddress(long)).toBeNull();
  });
});

describe("buildRecipients", () => {
  it("normalizes, dedupes and sorts across every source field", () => {
    const out = buildRecipients(
      ["Zed@Inbound.soleur.ai", "triage@inbound.soleur.ai"],
      ["TRIAGE@inbound.soleur.ai"],
    );
    expect(out).toEqual(["triage@inbound.soleur.ai", "zed@inbound.soleur.ai"]);
  });

  it("drops non-string entries and non-array sources", () => {
    expect(
      buildRecipients(
        [42, null, "triage@inbound.soleur.ai", {}],
        "not-an-array",
        undefined,
      ),
    ).toEqual(["triage@inbound.soleur.ai"]);
  });

  it("returns [] when no source yields a valid address", () => {
    expect(buildRecipients(undefined, null, ["nope"])).toEqual([]);
  });

  it("caps the number of raw entries it examines", () => {
    const many = Array.from(
      { length: MAX_INBOUND_RECIPIENTS + 25 },
      (_, i) => `r${String(i).padStart(3, "0")}@inbound.soleur.ai`,
    );
    const out = buildRecipients(many);
    expect(out).toHaveLength(MAX_INBOUND_RECIPIENTS);
    // First-N of the raw list, never the last-N.
    expect(out).toContain("r000@inbound.soleur.ai");
    expect(out).not.toContain(
      `r${String(MAX_INBOUND_RECIPIENTS + 24).padStart(3, "0")}@inbound.soleur.ai`,
    );
  });
});
