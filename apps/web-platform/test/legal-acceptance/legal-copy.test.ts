/**
 * #12011 PR-C task B1/B2 (AC12): the legal-acceptance copy deck.
 *   - no string reachable from the module says "verified", "reviewed", "legally binding", "audit-ready" or "compliant";
 *   - the two notices are carried word for word from the counsel note (sections (c) and (c-2));
 *   - the deck is PROVISIONAL (CLO-agent v1 sign-off of 2026-11-07 only; no human lawyer, the CPO has not signed off), exactly like approval-copy.ts;
 *   - the deck has two deck-owned wordings, terms and acknowledgement, picked by the kind declared for a text key (#12344).
 *     The acknowledgement wording and the shared deck never say "terms", "accept..." or "updated"; no allowlist, no negation stripping.
 */
import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import * as copy from "@/lib/legal-acceptance-copy";
import { getLegalText } from "@/server/legal-acceptance/canonical";
import { FORBIDDEN_CLAIMS } from "./forbidden-claims";
import { TERMS_PRESUMING } from "./terms-presuming";

const NOTE = join(__dirname, "..", "..", "..", "..", "knowledge-base", "legal", "audits", "2026-11-founder-legal-acceptance-dsar-and-notice-note.md");
const FORBIDDEN = FORBIDDEN_CLAIMS; // one list for the deck and the committed texts (forbidden-claims.ts)

/** Probes that can reach any wording: a key, a label and versions, dates, counts, a choice, an email. Used by the forbidden-claims and em-dash walks. */
const WIDE_PROBES: unknown[][] = [
  ["customer-terms", "3"],
  ["Customer terms", "3", "4"],
  ["2026-11-04T10:42:00Z"],
  ["2026-11-14"],
  [12],
  [1000, 1000],
  ["founder-acceptance-record"],
  ["unknown-key"],
  ["constructor"],
  [],
];
/** Probes that cannot contain a ban word themselves, so the ban regex is applied to the deck's own words only (CTO C7). */
const NEUTRAL_PROBES: unknown[][] = [["Policy text", "3", "4"], ["2026-11-04T10:42:00Z"], ["2026-11-14"], [12], [1000, 1000], ["decline"], ["request_changes"], [null], []];

/** Every string reachable from an export, calling function-valued entries with the given probes. */
function collect(v: unknown, probes: unknown[][] = WIDE_PROBES, out: string[] = []): string[] {
  if (typeof v === "string") out.push(v);
  else if (typeof v === "function") {
    for (const args of probes) {
      try {
        const r = (v as (...a: unknown[]) => unknown)(...args);
        collect(r, probes, out);
      } catch {
        /* wrong arity for this probe */
      }
    }
  } else if (v && typeof v === "object") Object.values(v).forEach((x) => collect(x, probes, out));
  return out;
}

/** Words that presume an accepted set of terms. The acknowledgement wording and the shared deck must not contain any. */

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
const ackStrings = collect(copy.LEGAL_KIND_COPY.acknowledgement, NEUTRAL_PROBES);
const termsStrings = collect(copy.LEGAL_KIND_COPY.terms, NEUTRAL_PROBES);
const sharedStrings = collect(copy.LEGAL_COPY, NEUTRAL_PROBES);

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

  it("(c-2) the card-level notice matches byte for byte, states the ruled period and the rights sentence, and has no placeholder", () => {
    expect(copy.LEGAL_COPY.cardNotice).toBe(noticeFromNote("## (c-2) Card-level notice"));
    expect(copy.LEGAL_COPY.cardNotice).toBe(
      "Your decision is saved with your account identifier, the text's version and fingerprint, the time, and (for Yes) the time you confirmed the emailed code. Jikigai keeps this record to be able to show later what was decided, even if you delete your account, for 5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open). You can ask what we hold, ask for erasure or restriction, or object by writing to <legal@jikigai.com>, and you can complain to the CNIL.",
    );
    expect(copy.LEGAL_COPY.cardNotice).not.toContain("[period to be confirmed by counsel]");
  });

  it("the Request changes notice states the same period", () => {
    expect(copy.LEGAL_COPY.requestChangesNotice).toBe(
      "Say only what you want changed in the text. Please do not write names, email addresses or private details about yourself or anyone else here: this note is saved with your decision, up to 1000 characters, and is kept for 5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open), even if you later delete your account.",
    );
  });
});

describe("the deck is PROVISIONAL (CLO-agent v1 stand-in for counsel; CPO sign-off outstanding)", () => {
  it("is flagged provisional; the CLO field records the stand-in, the CPO field stays empty", () => {
    expect(copy.LEGAL_COPY.PROVISIONAL).toBe(true);
    expect(copy.LEGAL_COPY.signOff).toEqual({ cpo: null, clo: "Ruled by CLO agent, 2026-11-07: v1 internal sign-off, not external counsel" });
  });
});

describe("the exact-text heading and the code sentence (CLO C)", () => {
  it("the heading says what the answer covers (only the fingerprint is stored)", () => {
    expect(copy.LEGAL_COPY.exactTextHeading).toBe("The exact text your answer covers");
  });

  it("the code sentence says the code is checked, for both kinds", () => {
    expect(copy.LEGAL_COPY.dialog.codeBody).toBe(
      "The code works for about 10 minutes. The email may say the code is for signing in: use it here. Nothing is recorded until your code is checked.",
    );
    expect(copy.LEGAL_KIND_COPY.terms.answerDetail("L", "V")).toMatch(/Nothing is recorded until your code is checked\.$/);
    expect(copy.LEGAL_KIND_COPY.acknowledgement.answerDetail("L", "V")).toMatch(/Nothing is recorded until your code is checked\.$/);
  });
});

describe("wording that must not claim more than happened", () => {
  it("the accepted line says how the answer was given, with the UTC time", () => {
    expect(copy.confirmedWithCodeLine("2026-11-04T10:42:00Z")).toBe("Confirmed with an email code, Wed 4 Nov 2026, 10:42 UTC");
    expect(copy.LEGAL_COPY.signedInLine).toBe("Signed in with your account.");
  });

  it("an answer is final and the way to change it is a new version (task 6.10): declined and changes requested say so, no undo", () => {
    for (const kc of Object.values(copy.LEGAL_KIND_COPY)) {
      for (const t of [kc.declinedBody, kc.changesRequestedBody, copy.LEGAL_COPY.finalNote]) expect(t, t).toMatch(/new version/i);
    }
    expect(copy.LEGAL_COPY.finalNote).toMatch(/final/i);
    expect(all.join("\n")).not.toMatch(/\bundo\b(?! it)/i);
  });

  it("never promises a delivery of the note or a reply that nothing in the product performs yet", () => {
    const joined = all.join("\n");
    expect(joined).not.toMatch(/goes to your team|will come back to you|back to you for a fresh answer|your note to your team/i);
    for (const kc of Object.values(copy.LEGAL_KIND_COPY)) {
      expect(kc.changesBody).toMatch(/saved with your decision/i);
      expect(kc.changesRequestedBody).not.toMatch(/will come back|new version will/i);
    }
    // the ban bites
    expect(/goes to your team|will come back to you/i.test("Your note goes to your team.")).toBe(true);
  });

  it("the locked wording is accurate and neutral: wait, then ask again; no promise of a time or that a new code helps right away (a per-challenge lock and the per-user ceiling both answer locked)", () => {
    const t = copy.LEGAL_COPY.dialog.verifyError.locked;
    expect(t).toMatch(/wait a few minutes/i);
    expect(t).not.toMatch(/\d+ minutes/);
    expect(t).not.toMatch(/send a new code/i);
  });

  it("the rate-limited send reason says about 15 minutes (the database window); the changes badge does not promise a revision", () => {
    expect(copy.LEGAL_COPY.dialog.sendError.rate_limited).toMatch(/about 15 minutes/);
    expect(copy.LEGAL_COPY.changesRequested.badge).toBe("Change requested");
    expect(copy.LEGAL_COPY.changesRequested.badge).not.toMatch(/revision|waiting/i);
  });

  it("has copy for a code that no longer counts and for the resend wait", () => {
    expect(copy.LEGAL_COPY.dialog.reverify).toMatch(/ask for a new code and try again/i);
    expect(copy.LEGAL_COPY.dialog.reverify).toMatch(/nothing was recorded/i);
    // neutral about the cause: it must not blame the code or claim a reason
    expect(copy.LEGAL_COPY.dialog.reverify).not.toMatch(/no longer counts|expired|wrong|too old/i);
    expect(copy.LEGAL_COPY.dialog.resendWait).not.toMatch(/\bminute\b/i);
  });

  it("format helpers", () => {
    expect(copy.legalTextLabel("customer-terms")).toBe("Customer terms");
    expect(copy.formatLegalUtc("not a date")).toBe("");
  });
});

const EXPECTED_FIELDS = [
  "acceptedBadge", "acceptedBody", "acceptedTitle", "answerDetail", "changesBody", "changesFooter", "changesRequestedBody", "declinedBody",
  "declinedTitle", "expiredBody", "indexAccepted", "noBody", "pendingNotAvailable", "pendingNothing", "pendingTitle", "yesBody",
];

/** Every field of both kinds, word for word (CLO C; the terms-kind answerDetail tail is the one deliberate deviation, "checked"). */
const WORDING: Record<"terms" | "acknowledgement", Record<string, string>> = {
  terms: {
    pendingTitle: "Accept the L?",
    yesBody: "Soleur treats these terms as accepted by you, starting today. Clicking again does not undo it. To change it later you would ask for a new version.",
    noBody: "Nothing changes. Nothing is accepted. Final once recorded.",
    changesBody: "Your note is saved with your decision. Nothing is accepted by asking for changes. Final once recorded.",
    changesFooter: "Nothing is accepted by saving this. Your note is saved with your decision.",
    pendingNothing: "Nothing has been accepted.",
    pendingNotAvailable: "Answering is not available yet. Nothing has been accepted.",
    acceptedBadge: "Accepted",
    acceptedTitle: "You accepted the L",
    acceptedBody: "Soleur now treats this version as accepted by you. To change this later, ask for a new version.",
    declinedTitle: "You said No to the L",
    declinedBody: "Nothing changed. Nothing was accepted. This answer is final: to change it, your team sends a new version of the text.",
    changesRequestedBody: "Nothing is accepted. Your note is saved with your decision. This answer is final: to change it, your team sends a new version of the text.",
    expiredBody: "Nothing was accepted. Ask your team to send it again if you still want it.",
    answerDetail: "Accept the L, version V. Nothing is recorded until your code is checked.",
    indexAccepted: "You accepted it",
  },
  acknowledgement: {
    pendingTitle: 'Acknowledge "L"?',
    yesBody: "Your Yes is recorded as your acknowledgement that you were shown this text. That is all it means: it is not consent and it agrees to nothing. Clicking again does not undo it. To change it later you would ask for a new version.",
    noBody: "Your No is recorded as your answer. The text stays as it is and nothing is acknowledged. Final once recorded.",
    changesBody: "Your note is saved with your decision. Nothing is acknowledged by asking for changes. Final once recorded.",
    changesFooter: "Nothing is acknowledged by saving this. Your note is saved with your decision.",
    pendingNothing: "Nothing has been acknowledged.",
    pendingNotAvailable: "Answering is not available yet. Nothing has been acknowledged.",
    acceptedBadge: "Acknowledged",
    acceptedTitle: 'You acknowledged "L"',
    acceptedBody: "Your Yes is recorded as your acknowledgement that you were shown this version. That is all it means: it is not consent and it agrees to nothing. To change this later, ask for a new version.",
    declinedTitle: 'You said No to "L"',
    declinedBody: "Nothing changed. Your No is recorded and the text stays as it is. This answer is final: to change it, your team sends a new version of the text.",
    changesRequestedBody: "Nothing is acknowledged. Your note is saved with your decision. This answer is final: to change it, your team sends a new version of the text.",
    expiredBody: "Nothing was acknowledged. Ask your team to send it again if you still want it.",
    answerDetail: 'Acknowledge "L", version V. Nothing is recorded until your code is checked.',
    indexAccepted: "You acknowledged it",
  },
};

/** Render a kind's field the way the pin table spells it: functions are called with the label "L" and the version "V". */
function render(kc: copy.LegalKindCopy, field: string): string {
  const v = (kc as unknown as Record<string, unknown>)[field];
  if (typeof v === "function") return (v as (...a: string[]) => string)("L", "V");
  return v as string;
}

describe("kind-keyed card copy (#12344)", () => {
  it("there are exactly two kinds, and LEGAL_KIND_COPY has exactly those", () => {
    expect([...copy.LEGAL_TEXT_KINDS]).toEqual(["terms", "acknowledgement"]);
    expect(Object.keys(copy.LEGAL_KIND_COPY).sort()).toEqual([...copy.LEGAL_TEXT_KINDS].sort());
  });

  it("both kinds define the same 16 fields, each a non-empty string or a function returning one", () => {
    for (const kind of copy.LEGAL_TEXT_KINDS) {
      const kc = copy.LEGAL_KIND_COPY[kind];
      expect(Object.keys(kc).sort(), kind).toEqual(EXPECTED_FIELDS);
      for (const f of EXPECTED_FIELDS) {
        const out = render(kc, f);
        expect(typeof out, `${kind}.${f}`).toBe("string");
        expect(out.length, `${kind}.${f}`).toBeGreaterThan(0);
      }
    }
  });

  it("every field of both kinds is worded exactly as ruled (CLO C, second round)", () => {
    for (const kind of copy.LEGAL_TEXT_KINDS) {
      for (const f of EXPECTED_FIELDS) expect(render(copy.LEGAL_KIND_COPY[kind], f), `${kind}.${f}`).toBe(WORDING[kind][f]);
    }
  });

  it("the members that moved into the kinds are gone from the shared deck", () => {
    const d = copy.LEGAL_COPY as unknown as Record<string, Record<string, unknown> | undefined>;
    expect(d.yesRow && "body" in d.yesRow).toBeFalsy();
    expect(d.noRow && "body" in d.noRow).toBeFalsy();
    expect(d.changesRow && "body" in d.changesRow).toBeFalsy();
    expect(d.changes && "footer" in d.changes).toBeFalsy();
    expect(d.pending && ("title" in d.pending || "nothingAccepted" in d.pending || "notAvailable" in d.pending)).toBeFalsy();
    expect(d.accepted).toBeUndefined();
    expect(d.declined && ("title" in d.declined || "body" in d.declined)).toBeFalsy();
    expect(d.changesRequested && "body" in d.changesRequested).toBeFalsy();
    expect(d.expired && "body" in d.expired).toBeFalsy();
    expect(d.dialog && "answerDetail" in d.dialog).toBeFalsy();
    expect(d.index && d.index.state && "accepted" in (d.index.state as object)).toBeFalsy();
  });

  it("the walk is not vacuous: the shared deck has a healthy number of unique strings and each kind a handful", () => {
    expect(new Set(sharedStrings).size).toBeGreaterThanOrEqual(120);
    expect(all.length).toBeGreaterThan(150);
    expect(ackStrings.length).toBeGreaterThan(8);
    expect(termsStrings.length).toBeGreaterThan(8);
  });

  it("the acknowledgement wording and the shared deck presume no terms: zero ban matches, no allowlist, no negation stripping", () => {
    for (const s of ackStrings) expect(s, s).not.toMatch(TERMS_PRESUMING);
    for (const s of sharedStrings) expect(s, s).not.toMatch(TERMS_PRESUMING);
  });

  it("the ban bites, and the terms wording is the one that presumes terms (non-vacuity)", () => {
    expect(TERMS_PRESUMING.test("Soleur treats these terms as accepted by you")).toBe(true);
    expect(TERMS_PRESUMING.test("Accept the updated X")).toBe(true);
    expect(TERMS_PRESUMING.test("It does not accept any terms")).toBe(true);
    expect(TERMS_PRESUMING.test("You acknowledged it")).toBe(false);
    // one probe per alternative of the shared regex (terms-presuming.ts), each worded to trip that alternative alone, so deleting any
    // alternative reds this row
    const probes: Record<string, string> = {
      "term": "Read your term sheet",
      "terms": "Read the terms",
      "accept": "You accept it",
      "accepted": "It was accepted",
      "accepts": "Soleur accepts it",
      "acceptance": "Your acceptance is noted",
      "updated": "The updated text is here",
    };
    for (const [alt, probe] of Object.entries(probes)) expect(TERMS_PRESUMING.test(probe), `${alt}: ${probe}`).toBe(true);
    expect(termsStrings.some((s) => TERMS_PRESUMING.test(s))).toBe(true);
  });

  it("both kinds pass the forbidden-claims and em-dash walks (they are part of the wide walk)", () => {
    for (const s of [...termsStrings, ...ackStrings]) {
      expect(s, s).not.toMatch(FORBIDDEN);
      expect(s, s).not.toContain("\u2014");
    }
    for (const s of all) expect(s, s).not.toMatch(FORBIDDEN);
  });

  it("an acknowledgement string quotes its label and says nothing about consent being given", () => {
    expect(copy.LEGAL_KIND_COPY.acknowledgement.pendingTitle("My title")).toBe('Acknowledge "My title"?');
    expect(copy.LEGAL_KIND_COPY.acknowledgement.yesBody).toContain("it is not consent");
  });
});

describe("code lifetime wording (#12366 item 2, CLO ruling 6)", () => {
  it("the dialog and the wrong-code error say about 10 minutes, and the code line neutralises the sign-in sentence of the shared email", () => {
    expect(copy.LEGAL_COPY.dialog.codeBody).toContain("about 10 minutes");
    expect(copy.LEGAL_COPY.dialog.codeBody).toContain("The email may say the code is for signing in: use it here.");
    expect(copy.LEGAL_COPY.dialog.verifyError.wrong_code).toBe(
      "That code is wrong or has expired. Codes only work for about 10 minutes. Check it, or send a new one. Nothing was recorded.",
    );
  });

  it("no code-lifetime string says 'a few minutes' any more; the lockout wording keeps it (a lockout, not a lifetime)", () => {
    for (const s of [copy.LEGAL_COPY.dialog.codeBody, copy.LEGAL_COPY.dialog.verifyError.wrong_code]) expect(s, s).not.toMatch(/a few minutes/i);
    expect(copy.LEGAL_COPY.dialog.verifyError.locked).toMatch(/wait a few minutes/i);
    expect(copy.LEGAL_COPY.dialog.codeHint).toBe("6 to 8 digits");
  });

  // Repo-intent pins, NOT proof of the live lifetime: the live project value (mailer_otp_exp) was not measured by this test. The
  // template is shared with the sign-in email, so editing it breaks the card pin on purpose: change the card wording with it.
  it("the shared sign-in template still says the code expires in 10 minutes (the lifetime the card claims)", () => {
    const tpl = readFileSync(join(__dirname, "..", "..", "supabase", "templates", "magic-link.html"), "utf8");
    expect(tpl).toContain("expires in 10 minutes");
    expect(tpl).toContain("Enter this code to sign in to your Soleur account");
  });

  it("the auth config script still sets mailer_otp_exp to 600 seconds (10 minutes)", () => {
    const sh = readFileSync(join(__dirname, "..", "..", "supabase", "scripts", "configure-auth.sh"), "utf8");
    expect(sh).toContain('"mailer_otp_exp": 600');
  });
});

describe("terms wording is true for a first-ever text and for an update (#12366 item 1, CLO ruling 7)", () => {
  const t = copy.LEGAL_KIND_COPY.terms;
  /** Words that presume an earlier text exists. Narrower than TERMS_PRESUMING: the terms kind legitimately says "accept". */
  const PRESUMES_EARLIER = /\bupdated\b|\bcurrent terms\b|\bstay in place\b/i;

  it("no terms string presumes an earlier text", () => {
    for (const s of termsStrings) expect(s, s).not.toMatch(PRESUMES_EARLIER);
    for (const f of EXPECTED_FIELDS) expect(render(t, f), f).not.toMatch(PRESUMES_EARLIER);
  });

  it("the presumption check bites (the old wording is caught)", () => {
    for (const old of ["Accept the updated L?", "Nothing changes. The current terms stay in place. Final once recorded."]) expect(PRESUMES_EARLIER.test(old), old).toBe(true);
  });

  it("the ruled titles, details and bodies", () => {
    expect(t.pendingTitle("L")).toBe("Accept the L?");
    expect(t.acceptedTitle("L")).toBe("You accepted the L");
    expect(t.declinedTitle("L")).toBe("You said No to the L");
    expect(t.answerDetail("L", "V")).toBe("Accept the L, version V. Nothing is recorded until your code is checked.");
    expect(t.noBody).toBe("Nothing changes. Nothing is accepted. Final once recorded.");
    expect(t.declinedBody).toBe("Nothing changed. Nothing was accepted. This answer is final: to change it, your team sends a new version of the text.");
  });

  it("the terms strings still pass the forbidden-claims walk", () => {
    for (const s of termsStrings) expect(s, s).not.toMatch(FORBIDDEN);
  });
});

describe("the acknowledgement kind is byte-identical in behavior (the founder's card is untouched)", () => {
  it("the full set of strings it can render, with the label L and the version V, is exactly the pinned set", () => {
    const rendered = collect(copy.LEGAL_KIND_COPY.acknowledgement, [["L", "V"]]).sort();
    expect(rendered).toEqual(Object.values(WORDING.acknowledgement).sort());
    expect(rendered).toMatchInlineSnapshot(`
      [
        "Acknowledge "L", version V. Nothing is recorded until your code is checked.",
        "Acknowledge "L"?",
        "Acknowledged",
        "Answering is not available yet. Nothing has been acknowledged.",
        "Nothing changed. Your No is recorded and the text stays as it is. This answer is final: to change it, your team sends a new version of the text.",
        "Nothing has been acknowledged.",
        "Nothing is acknowledged by saving this. Your note is saved with your decision.",
        "Nothing is acknowledged. Your note is saved with your decision. This answer is final: to change it, your team sends a new version of the text.",
        "Nothing was acknowledged. Ask your team to send it again if you still want it.",
        "You acknowledged "L"",
        "You acknowledged it",
        "You said No to "L"",
        "Your No is recorded as your answer. The text stays as it is and nothing is acknowledged. Final once recorded.",
        "Your Yes is recorded as your acknowledgement that you were shown this text. That is all it means: it is not consent and it agrees to nothing. Clicking again does not undo it. To change it later you would ask for a new version.",
        "Your Yes is recorded as your acknowledgement that you were shown this version. That is all it means: it is not consent and it agrees to nothing. To change this later, ask for a new version.",
        "Your note is saved with your decision. Nothing is acknowledged by asking for changes. Final once recorded.",
      ]
    `);
  });
});

describe("the kind lookup has no default (CTO 1)", () => {
  it("founder-acceptance-record is declared an acknowledgement; every unknown key, and the object-prototype names, give null", () => {
    expect(copy.legalTextKind("founder-acceptance-record")).toBe("acknowledgement");
    for (const k of ["customer-terms", "unknown-key", "zzz", "constructor", "__proto__", "toString", "hasOwnProperty", "valueOf"]) {
      expect(copy.legalTextKind(k), k).toBeNull();
      expect(copy.legalKindCopy(k), k).toBeNull();
    }
  });

  it("a declared key returns a member of LEGAL_KIND_COPY itself (identity), never a new object", () => {
    const members = Object.values(copy.LEGAL_KIND_COPY);
    expect(members).toContain(copy.legalKindCopy("founder-acceptance-record"));
    expect(copy.legalKindCopy("founder-acceptance-record")).toBe(copy.LEGAL_KIND_COPY.acknowledgement);
    expect(copy.legalKindCopy("a-terms-key", { "a-terms-key": "terms" })).toBe(copy.LEGAL_KIND_COPY.terms);
  });

  it("a declared map is honoured by own property only (an inherited name is not a declaration)", () => {
    expect(copy.legalTextKind("constructor", {})).toBeNull();
    expect(copy.legalTextKind("toString", Object.create({ toString: "terms" }))).toBeNull();
  });

  it("the declared map holds only real kinds", () => {
    for (const [k, v] of Object.entries(copy.LEGAL_TEXT_KIND)) expect(copy.LEGAL_TEXT_KINDS as readonly string[], k).toContain(v);
  });

  it("the leaf has no runtime import: every import line is type-only (a runtime import would drag server code into the client bundle)", () => {
    const src = readFileSync(join(__dirname, "..", "..", "lib", "legal-acceptance-copy.ts"), "utf8");
    const imports = src.split("\n").filter((l) => /^\s*import[\s{*]/.test(l) || /^\s*import\(/.test(l) || /\brequire\(/.test(l));
    for (const l of imports) expect(l, l).toMatch(/^import type /);
  });
});

describe("the index state and the display label", () => {
  const ack = copy.LEGAL_KIND_COPY.acknowledgement;
  const terms = copy.LEGAL_KIND_COPY.terms;

  it("an accepted row reads the kind's wording; the other states read the shared deck", () => {
    expect(copy.legalIndexState(ack, "accepted")).toBe("You acknowledged it");
    expect(copy.legalIndexState(terms, "accepted")).toBe("You accepted it");
    expect(copy.legalIndexState(ack, "pending")).toBe(copy.LEGAL_COPY.index.state.pending);
    expect(copy.legalIndexState(terms, "declined")).toBe(copy.LEGAL_COPY.index.state.declined);
    expect(copy.legalIndexState(ack, "changes_requested")).toBe(copy.LEGAL_COPY.index.state.changes_requested);
  });

  it("terms keep the key-derived label (pinned wording unchanged)", () => {
    expect(copy.legalDisplayLabel("terms", "customer-terms", "Anything\nmore")).toBe("Customer terms");
  });

  it("an acknowledgement text is labelled by its own first non-empty line", () => {
    expect(copy.legalDisplayLabel("acknowledgement", "founder-acceptance-record", "How your decisions are recorded and kept\n\nBody")).toBe("How your decisions are recorded and kept");
    expect(copy.legalDisplayLabel("acknowledgement", "founder-acceptance-record", "\n\n  Padded title  \nBody")).toBe("Padded title");
  });

  it("an unsafe first line falls back to the key-derived label: leading # - * > +, a double quote, a control character, non-ASCII, over 120 characters, empty", () => {
    const fallback = "Founder acceptance record";
    for (const first of ["# Heading", "- item", "* item", "> quote", "+ plus", 'He said "no"', "tab\there", "caf\u00e9 notes", "a".repeat(121)]) {
      expect(copy.legalDisplayLabel("acknowledgement", "founder-acceptance-record", `${first}\nBody`), JSON.stringify(first)).toBe(fallback);
    }
    expect(copy.legalDisplayLabel("acknowledgement", "founder-acceptance-record", "a".repeat(120))).toBe("a".repeat(120));
    expect(copy.legalDisplayLabel("acknowledgement", "founder-acceptance-record", "\n  \n")).toBe(fallback);
  });

  it("the real text gives the real title (anchor)", () => {
    expect(copy.legalDisplayLabel("acknowledgement", "founder-acceptance-record", getLegalText("founder-acceptance-record").body)).toBe("How your decisions are recorded and kept");
  });
});
