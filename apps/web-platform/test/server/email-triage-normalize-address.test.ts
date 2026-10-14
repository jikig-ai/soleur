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

  const addr = (i: number) =>
    `r${String(i).padStart(3, "0")}@inbound.soleur.ai`;

  it("pins the cap at 20 valid addresses", () => {
    expect(MAX_INBOUND_RECIPIENTS).toBe(20);
  });

  it("keeps at most 20 VALID addresses, first-N in source order, sorted", () => {
    // Descending input: the kept set is the FIRST 20 (r099..r080), and the
    // early-return path must still be sorted.
    const many = Array.from({ length: 45 }, (_, i) => addr(99 - i));
    const out = buildRecipients(many);
    expect(out).toHaveLength(20);
    expect(out).toEqual(Array.from({ length: 20 }, (_, i) => addr(80 + i)));
  });

  it("the cap counts VALID addresses: invalid entries do not use it up", () => {
    const mixed = [
      ...Array.from({ length: 10 }, () => "not-an-address"),
      ...Array.from({ length: 25 }, (_, i) => addr(i)),
    ];
    expect(buildRecipients(mixed)).toHaveLength(20);
  });

  it("the cap is global across sources and the FIRST source wins", () => {
    const envelope = ["envelope@inbound.soleur.ai"];
    const header = Array.from({ length: 40 }, (_, i) => addr(i));
    const out = buildRecipients(envelope, header);
    expect(out).toHaveLength(20);
    expect(out).toContain("envelope@inbound.soleur.ai");
  });

  it("a hostile all-invalid list is bounded by the raw-entry cap", () => {
    const junk = Array.from({ length: 10_000 }, () => "x");
    const real = [addr(1)];
    // The valid address sits past 4x the cap, so it is never examined.
    expect(buildRecipients(junk, real)).toEqual([]);
  });
});
