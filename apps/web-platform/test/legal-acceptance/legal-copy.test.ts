/**
 * #12011 PR-C task B1/B2 (AC12): the legal-acceptance copy deck.
 *   - no string reachable from the module says "verified", "reviewed", "legally binding", "audit-ready" or "compliant";
 *   - the two notices are carried word for word from the counsel note (sections (c) and (c-2));
 *   - the deck is PROVISIONAL under the CLO sign-off gate, exactly like approval-copy.ts.
 */
import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import * as copy from "@/lib/legal-acceptance-copy";

const NOTE = join(__dirname, "..", "..", "..", "..", "knowledge-base", "legal", "audits", "2026-11-founder-legal-acceptance-dsar-and-notice-note.md");
const FORBIDDEN = /verified|reviewed|legally binding|audit-ready|compliant/i;

/** Every string reachable from an export, calling function-valued entries with representative arguments. */
function collect(v: unknown, out: string[] = []): string[] {
  if (typeof v === "string") out.push(v);
  else if (typeof v === "function") {
    const probes: unknown[][] = [
      ["customer-terms", "3"],
      ["Customer terms", "3", "4"],
      ["2026-11-04T10:42:00Z"],
      ["2026-11-14"],
      [12],
      [1000, 1000],
      [],
    ];
    for (const args of probes) {
      try {
        const r = (v as (...a: unknown[]) => unknown)(...args);
        collect(r, out);
      } catch {
        /* wrong arity for this probe */
      }
    }
  } else if (v && typeof v === "object") Object.values(v).forEach((x) => collect(x, out));
  return out;
}

/** The text of the blockquote that follows a heading starting with `heading`, without the surrounding bold markers. */
function noticeFromNote(heading: string): string {
  const lines = readFileSync(NOTE, "utf8").split("\n");
  const at = lines.findIndex((l) => l.startsWith(heading));
  expect(at, `heading ${heading} not found in the note`).toBeGreaterThan(-1);
  const quote = lines.slice(at + 1).find((l) => l.startsWith("> "));
  expect(quote, `no blockquote after ${heading}`).toBeDefined();
  const m = /^> \*\*(.+)\*\*$/.exec(quote as string);
  expect(m, "the notice is one bold blockquote line").not.toBeNull();
  return (m as RegExpExecArray)[1];
}

const all = collect(copy);

describe("legal-acceptance copy (AC12)", () => {
  it("walks a non-trivial set of strings (the check is not vacuous)", () => {
    expect(all.length).toBeGreaterThan(50);
  });

  it("never says verified, reviewed, legally binding, audit-ready or compliant", () => {
    for (const s of all) expect(s, s).not.toMatch(FORBIDDEN);
  });

  it("has no em dash anywhere", () => {
    for (const s of all) expect(s, s).not.toContain("—");
  });

  it("the forbidden-word check bites (a planted string is caught)", () => {
    expect(FORBIDDEN.test("This was Verified")).toBe(true);
    expect(FORBIDDEN.test("Legally binding")).toBe(true);
    expect(FORBIDDEN.test("Confirmed with an email code")).toBe(false);
  });
});

describe("the notices are word for word from the counsel note", () => {
  it("(c) the Request changes notice matches byte for byte", () => {
    expect(copy.LEGAL_COPY.requestChangesNotice).toBe(noticeFromNote("## (c) Notice"));
  });

  it("(c-2) the card-level notice matches byte for byte and keeps the retention placeholder", () => {
    expect(copy.LEGAL_COPY.cardNotice).toBe(noticeFromNote("## (c-2) Card-level notice"));
    expect(copy.LEGAL_COPY.cardNotice).toContain("[period to be confirmed by counsel]");
  });
});

describe("the deck is PROVISIONAL (CLO sign-off pending)", () => {
  it("is flagged provisional with empty sign-off fields", () => {
    expect(copy.LEGAL_COPY.PROVISIONAL).toBe(true);
    expect(copy.LEGAL_COPY.signOff).toEqual({ cpo: null, clo: null });
  });
});

describe("wording that must not claim more than happened", () => {
  it("the accepted line says how the answer was given, with the UTC time", () => {
    expect(copy.confirmedWithCodeLine("2026-11-04T10:42:00Z")).toBe("Confirmed with an email code, Wed 4 Nov 2026, 10:42 UTC");
    expect(copy.LEGAL_COPY.signedInLine).toBe("Signed in with your account.");
  });

  it("an answer is final and the way to change it is a new version (task 6.10): declined and changes requested say so, no undo", () => {
    for (const t of [copy.LEGAL_COPY.declined.body, copy.LEGAL_COPY.changesRequested.body, copy.LEGAL_COPY.finalNote]) {
      expect(t, t).toMatch(/new version/i);
    }
    expect(copy.LEGAL_COPY.finalNote).toMatch(/final/i);
    expect(all.join("\n")).not.toMatch(/\bundo\b(?! it)/i);
  });

  it("never promises a delivery of the note or a reply that nothing in the product performs yet", () => {
    const joined = all.join("\n");
    expect(joined).not.toMatch(/goes to your team|will come back to you|back to you for a fresh answer|your note to your team/i);
    expect(copy.LEGAL_COPY.changesRow.body).toMatch(/saved with your decision/i);
    expect(copy.LEGAL_COPY.changesRequested.body).not.toMatch(/will come back|new version will/i);
    // the ban bites
    expect(/goes to your team|will come back to you/i.test("Your note goes to your team.")).toBe(true);
  });

  it("the locked wording is neutral: it does not say a new code helps right away (the per-user ceiling also answers locked)", () => {
    const t = copy.LEGAL_COPY.dialog.verifyError.locked;
    expect(t).toMatch(/15 minutes/);
    expect(t).not.toMatch(/send a new code/i);
  });

  it("has copy for a code that no longer counts and for the resend wait", () => {
    expect(copy.LEGAL_COPY.dialog.reverify).toMatch(/new code/i);
    expect(copy.LEGAL_COPY.dialog.reverify).toMatch(/nothing was recorded/i);
    expect(copy.LEGAL_COPY.dialog.resendWait).toBeTruthy();
  });

  it("format helpers", () => {
    expect(copy.legalTextLabel("customer-terms")).toBe("Customer terms");
    expect(copy.formatLegalUtc("not a date")).toBe("");
  });
});
