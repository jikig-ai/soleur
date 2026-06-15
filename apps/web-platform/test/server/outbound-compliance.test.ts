import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import {
  OutboundComplianceError,
  resolveJurisdiction,
  validateComplianceConditions,
  validateEmailHeaders,
  assertRecipientAllowed,
  normalizeEmail,
  recipientHash,
  type OutboundComplianceRequest,
} from "@/server/email-triage/outbound-compliance";

// A fully-compliant EU/UK request fixture — every C1–C4 field + all 6 Art. 14
// elements present. Individual tests delete fields to drive each refuse path.
function euCompliantRequest(): OutboundComplianceRequest {
  return {
    to: "journalist@example.com",
    from: "Founder <hello@mail.soleur.ai>",
    subject: "Your piece on solo-founder tooling",
    bodyText: "Hi — I read your listicle and built something relevant.",
    jurisdiction: "eu_uk",
    postalAddress: "Jikigai, 1 Rue de Test, 75001 Paris, France", // C1
    optOut: "Reply STOP to never hear from me again.", // C2
    art14: {
      identity: "Jikigai (jikigai.com), data controller",
      purpose: "One-time outreach about a relevant tool",
      legalBasis: "Legitimate interest (Art. 6(1)(f))",
      dataSource: "Your publicly published article byline",
      retention: "Deleted within 30 days unless you reply",
      rights: "Access, erasure, objection — email privacy@jikigai.com",
    },
    ftcDisclosure: "I'm the founder; free access offered — material connection.", // C4
  };
}

function usCompliantRequest(): OutboundComplianceRequest {
  return {
    to: "editor@example.com",
    from: "Founder <hello@mail.soleur.ai>",
    subject: "Quick idea for your roundup",
    bodyText: "Hi — built a tool your readers may like.",
    jurisdiction: "us",
    postalAddress: "Jikigai, 1 Test St, Wilmington DE 19801, USA",
    optOut: "Reply STOP to opt out.",
    ftcDisclosure: "Founder offering free access — material connection.",
  };
}

describe("resolveJurisdiction — default-to-strict", () => {
  it("returns eu_uk for unknown / low-confidence input (never lenient US fallthrough)", () => {
    expect(resolveJurisdiction(undefined)).toBe("eu_uk");
    expect(resolveJurisdiction("unknown")).toBe("eu_uk");
    expect(resolveJurisdiction("")).toBe("eu_uk");
    expect(resolveJurisdiction("xx")).toBe("eu_uk");
  });

  it("returns us only for an explicit US signal", () => {
    expect(resolveJurisdiction("us")).toBe("us");
    expect(resolveJurisdiction("US")).toBe("us");
  });

  it("returns eu_uk for explicit EU/UK signals", () => {
    expect(resolveJurisdiction("eu")).toBe("eu_uk");
    expect(resolveJurisdiction("uk")).toBe("eu_uk");
    expect(resolveJurisdiction("eu_uk")).toBe("eu_uk");
  });
});

describe("validateComplianceConditions — C1/C2/C4 (all jurisdictions)", () => {
  it("passes a fully-compliant EU/UK request", () => {
    expect(() => validateComplianceConditions(euCompliantRequest())).not.toThrow();
  });

  it("passes a fully-compliant US request", () => {
    expect(() => validateComplianceConditions(usCompliantRequest())).not.toThrow();
  });

  it("C1: throws when postal-address footer is absent", () => {
    const r = euCompliantRequest();
    delete (r as Partial<OutboundComplianceRequest>).postalAddress;
    expect(() => validateComplianceConditions(r)).toThrow(OutboundComplianceError);
    try {
      validateComplianceConditions(r);
    } catch (e) {
      expect((e as OutboundComplianceError).code).toBe("c1_postal_address_missing");
    }
  });

  it("C1: throws when postal address is blank/whitespace", () => {
    const r = euCompliantRequest();
    r.postalAddress = "   ";
    expect(() => validateComplianceConditions(r)).toThrow(/c1/i);
  });

  it("C2: throws when opt-out line is absent", () => {
    const r = euCompliantRequest();
    delete (r as Partial<OutboundComplianceRequest>).optOut;
    try {
      validateComplianceConditions(r);
      throw new Error("should have thrown");
    } catch (e) {
      expect((e as OutboundComplianceError).code).toBe("c2_opt_out_missing");
    }
  });

  it("C4: throws when FTC material-connection disclosure is absent", () => {
    const r = euCompliantRequest();
    delete (r as Partial<OutboundComplianceRequest>).ftcDisclosure;
    try {
      validateComplianceConditions(r);
      throw new Error("should have thrown");
    } catch (e) {
      expect((e as OutboundComplianceError).code).toBe("c4_ftc_disclosure_missing");
    }
  });
});

describe("validateComplianceConditions — C3 EU/UK Art. 14 (6 discrete predicates)", () => {
  const elements: Array<keyof NonNullable<OutboundComplianceRequest["art14"]>> = [
    "identity",
    "purpose",
    "legalBasis",
    "dataSource",
    "retention",
    "rights",
  ];

  for (const el of elements) {
    it(`C3: throws when Art. 14 element "${el}" is missing (EU/UK)`, () => {
      const r = euCompliantRequest();
      delete r.art14![el];
      try {
        validateComplianceConditions(r);
        throw new Error("should have thrown");
      } catch (e) {
        expect(e).toBeInstanceOf(OutboundComplianceError);
        expect((e as OutboundComplianceError).code).toBe(`c3_art14_${el.toLowerCase()}_missing`);
      }
    });
  }

  it("C3: throws when art14 block is entirely absent (EU/UK)", () => {
    const r = euCompliantRequest();
    delete (r as Partial<OutboundComplianceRequest>).art14;
    expect(() => validateComplianceConditions(r)).toThrow(/c3/i);
  });

  it("C3: US jurisdiction does NOT require Art. 14 elements", () => {
    const r = usCompliantRequest();
    expect(r.art14).toBeUndefined();
    expect(() => validateComplianceConditions(r)).not.toThrow();
  });

  it("C3: unknown jurisdiction is treated as EU/UK-strict (Art. 14 required)", () => {
    const r = usCompliantRequest();
    r.jurisdiction = "unknown" as OutboundComplianceRequest["jurisdiction"];
    // no art14 → must throw under strict default
    expect(() => validateComplianceConditions(r)).toThrow(/c3/i);
  });
});

describe("validateEmailHeaders — RFC-5322 + injection guard", () => {
  it("passes clean headers", () => {
    expect(() =>
      validateEmailHeaders({
        to: "journalist@example.com",
        from: "Founder <hello@mail.soleur.ai>",
        subject: "A normal subject line",
        replyTo: "hello@mail.soleur.ai",
      }),
    ).not.toThrow();
  });

  it.each([
    ["CR in to", { to: "a@b.com\rcc: evil@x.com" }],
    ["LF in to", { to: "a@b.com\ncc: evil@x.com" }],
    ["CRLF in subject", { subject: "Hi\r\nBcc: evil@x.com" }],
    ["NUL in to", { to: "a@b.com\x00" }],
    ["control char in subject", { subject: "Hi\x01there" }],
    ["U+2028 in subject", { subject: "Line sep" }],
    ["U+2029 in to", { to: "a@b.com " }],
    ["DEL in reply-to", { replyTo: "a@b.com\x7f" }],
  ])("throws on %s", (_label, override) => {
    const base = {
      to: "journalist@example.com",
      from: "Founder <hello@mail.soleur.ai>",
      subject: "A normal subject line",
      replyTo: "hello@mail.soleur.ai",
    };
    expect(() => validateEmailHeaders({ ...base, ...override })).toThrow(
      OutboundComplianceError,
    );
  });

  it("throws on a malformed (non-RFC-5322) recipient address", () => {
    expect(() =>
      validateEmailHeaders({
        to: "not-an-email",
        from: "Founder <hello@mail.soleur.ai>",
        subject: "Hi",
      }),
    ).toThrow(/rfc.?5322|invalid|address/i);
  });

  it("caps recipient count (cold 1:1 — single recipient only)", () => {
    expect(() =>
      validateEmailHeaders({
        to: "a@example.com, b@example.com",
        from: "Founder <hello@mail.soleur.ai>",
        subject: "Hi",
      }),
    ).toThrow(/recipient|count|single/i);
  });
});

describe("assertRecipientAllowed — exfiltration / own-domain / role guard", () => {
  it("allows a normal external recipient", () => {
    expect(() => assertRecipientAllowed("journalist@example.com")).not.toThrow();
  });

  it.each([
    "ops@jikigai.com",
    "founder@jikigai.com",
    "anyone@soleur.ai",
    "notifications@soleur.ai",
  ])("rejects internal/own-domain recipient %s", (addr) => {
    expect(() => assertRecipientAllowed(addr)).toThrow(OutboundComplianceError);
  });

  it.each(["postmaster@example.com", "abuse@example.com", "noreply@example.com", "no-reply@example.com"])(
    "rejects role/bare address %s",
    (addr) => {
      expect(() => assertRecipientAllowed(addr)).toThrow(/role|bare|disallow/i);
    },
  );
});

describe("normalizeEmail", () => {
  it("lowercases and trims", () => {
    expect(normalizeEmail("  Foo.Bar@Example.COM ")).toBe("foo.bar@example.com");
  });
});

describe("recipientHash — deterministic keyed HMAC (cross-campaign stability)", () => {
  const PEPPER = "test-pepper-deterministic-0123456789";

  beforeEach(() => {
    vi.stubEnv("EMAIL_HASH_PEPPER", PEPPER);
  });
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("is stable across calls for the same address (no per-row salt)", () => {
    const a = recipientHash("journalist@example.com");
    const b = recipientHash("journalist@example.com");
    expect(a).toBe(b);
  });

  it("is stable across case/whitespace variants (normalizes first)", () => {
    expect(recipientHash("  Journalist@Example.com ")).toBe(
      recipientHash("journalist@example.com"),
    );
  });

  it("canonicalizes display-name form to the same hash as the bare address (suppression-bypass guard)", () => {
    // Suppressing `a@b.com` MUST match a send addressed `Name <a@b.com>` — else
    // an opted-out contact is silently re-mailed (security review #5325).
    expect(recipientHash("Friendly Name <journalist@example.com>")).toBe(
      recipientHash("journalist@example.com"),
    );
  });

  it("differs for different addresses", () => {
    expect(recipientHash("a@example.com")).not.toBe(recipientHash("b@example.com"));
  });

  it("produces a 64-char hex SHA-256 digest", () => {
    expect(recipientHash("journalist@example.com")).toMatch(/^[0-9a-f]{64}$/);
  });

  it("throws (fails loud) when EMAIL_HASH_PEPPER is unset — never a silent unsalted hash", () => {
    vi.stubEnv("EMAIL_HASH_PEPPER", "");
    expect(() => recipientHash("journalist@example.com")).toThrow(/EMAIL_HASH_PEPPER/);
  });
});
