/**
 * #12365: the published Privacy Policy, GDPR Policy and Data Protection Disclosure must state the same retention
 * period for the founder decision record as the committed text (`founder-acceptance-record.md`), and must not
 * keep the earlier unconfirmed proposal. A published "proposal, up to 10 years" would overstate the 5 years the
 * committed text commits to (Article 13(2)(a) GDPR).
 *
 * The Eleventy mirrors under plugins/soleur/docs/pages/legal/ are checked too: they are the pages the public reads.
 */
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const REPO_ROOT = path.resolve(__dirname, "../../../..");
const DOCS = ["privacy-policy", "gdpr-policy", "data-protection-disclosure"] as const;

const read = (rel: string): string => readFileSync(path.join(REPO_ROOT, rel), "utf8");

const PERIOD = "5 years from the date of the decision";
const NOT_BUILT = /not yet built the step that deletes a record/;
const OLD_PROPOSAL = "life of the legal text plus 5";
const OLD_NO_PERIOD = /no retention period is confirmed/i;

// Round 2 (CLO ruling 2026-11-09): exact strings the published pages must carry, counted per page.
const HOLD =
  "If a legal claim, a complaint or an official inquiry about the record is open when the 5 years end, we keep it until that matter is closed.";
const NOT_BUILT_FULL =
  "We have not yet built the step that deletes a record at the end of this period (the application cannot delete the record today); we will build it before any record reaches that age, and until then records are kept as they are.";
const STATUS_START =
  "(Status as of November 8, 2026: the screens and the write path that record a decision are on for the Jikigai operator's account only, because they answer only for one configured account, and a record about that account exists. For the approval queue itself, see the status notice at the head of ";
const STATUS_ABSENT = "switched on in production since November 2026";
const NOTICE_HEAD =
  "(Status as of November 9, 2026: the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own.";
const SWITCHED_ON =
  "As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own.";
// Per page: one in the section site(s) plus one in the Amended entry.
const SWITCHED_ON_COUNT: Record<string, number> = {
  "privacy-policy": 2,
  "gdpr-policy": 5,
  "data-protection-disclosure": 3,
};
const COUNTS_READER =
  "A second protected internal address, read with the same protected credential, counts the decision records for one named legal text:";
const COUNTS_PRESENT = [
  "it returns the name of the text, the current text's fingerprint, the total number of records, for each text fingerprint how many records carry it, and whether every record carries the current text's fingerprint.",
  "Unlike the status check, which answers only about the one configured account and only for a text fingerprint that the caller supplies, it is not limited to one account and it shows which text fingerprints the records carry",
];
const COUNTS_ABSENT = ["and nothing else", "which the status check already gives to the same reader"];
const MONITORING_NEW = [
  "which of the following an event carries depends on the event, and no event carries all of them: the name of the text, the version,",
  "when a stored decision record fails its checksum, when a check or the email-code step fails",
  "an error code (a database error code, or a code saying what is wrong with a legal text file) or the name of the function that failed (never an error message)",
  "the name of a protected setting that is missing or malformed (never its value)",
  "only the event for a stored decision record that fails its checksum and the event for a record with no marker carry the text fingerprint, which is not secret",
];
const MONITORING_OLD = [
  "each event carries the name of the text",
  "a database error code or the name of the database function that failed",
  "the event carries the text name, version, choice, record age",
];
// Section-specific notices (CLO round 4): each document says only what it itself promised.
const NOTICE_BY_DOC: Record<string, { present: string[]; absent: string[] }> = {
  "privacy-policy": {
    present: [
      "This differs from what this Section said before this notice. The GDPR Policy names a data protection impact screening and a standalone legitimate-interest assessment as steps to come first; neither has been completed.",
    ],
    absent: ["This is earlier than this Section said it would be"],
  },
  "gdpr-policy": {
    present: ["the steps it named as coming first (a data protection impact screening and a standalone legitimate-interest assessment) have not been completed"],
    absent: [],
  },
  "data-protection-disclosure": {
    present: [
      "the step it named as coming first (a data protection impact screening) has not been completed. The GDPR Policy also names a standalone legitimate-interest assessment as coming first; it has not been completed either.",
    ],
    absent: ["the steps it named as coming first"],
  },
};
// Markers: the superseded-marker and DRAFT-marker populations are pinned by count so a stray one cannot hide.
const SUPERSEDED_NOV9 = "Superseded November 9, 2026";
const FURTHER_MARKER_PRESENT = [
  "as to the first sentence of the bold passage",
  "is not superseded and is restated in the November 9, 2026 entry",
];
const FURTHER_MARKER_ABSENT = ["the whole bold sentence", "no longer owed"];
const LAST_UPDATED_PRESENT = "a record existed for the Jikigai operator's account when last read on November 8, 2026";
const DRAFT_WITH_ISSUE = "[DRAFT — pending CLO/counsel review per #12011]";
const DRAFT_WITH_ISSUE_COUNT: Record<string, number> = {
  "privacy-policy": 4,
  "gdpr-policy": 4,
  "data-protection-disclosure": 5,
}; // equals origin/main: the new entries add none (CLO round 4 (g))
const DRAFT_PLAIN = "[DRAFT — pending CLO/counsel review]";
// The old claim survives on history lines only: Oct 29 Amended entry, its Superseded blockquote, the Nov 9 Amended entry.
const FALSE_CLAIM_OCCURRENCES = 3;
// Whole-sentence pins (CLO round 4): a clause appended to or edited inside these cannot hide behind fragment pins.
const RETENTION_CORE =
  "5 years from the date of the decision, and then we delete the record. This covers the whole record, including any note and the marker in the third table, which is kept and deleted with the decision record it names. If a legal claim, a complaint or an official inquiry about the record is open when the 5 years end, we keep it until that matter is closed. We have not yet built the step that deletes a record at the end of this period (the application cannot delete the record today); we will build it before any record reaches that age, and until then records are kept as they are.";
const MONITORING_FULL =
  "which of the following an event carries depends on the event, and no event carries all of them: the name of the text, the version, the choice, a reason or the name of the step that failed, an error class, an error code (a database error code, or a code saying what is wrong with a legal text file) or the name of the function that failed (never an error message), the name of a protected setting that is missing or malformed (never its value), the age and status of the record, and an account identifier pseudonymised before it is sent (only events raised from a signed-in session carry it; the events raised by the status check and the counts check carry none); only the event for a stored decision record that fails its checksum and the event for a record with no marker carry the text fingerprint, which is not secret; no event carries the note, the code, your email address or the text; and one line is written to our logs, which are copied to our log provider (Better Stack), for each event.";
const NOV9_ENTRY_PREFIX = "**Amended:** November 9, 2026";
const YEARS_TOKEN = /\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+years?\b/gi;
const FALSE_CLAIM = "The approval queue is not switched on for any workspace that Jikigai does not own";
const OVERTAKEN = [
  "may be switched on for workspaces that Jikigai itself owns",
  "conditional on Jikigai switching it on",
  "stated ahead of any processing",
  "before the feature is switched on for any workspace",
  "since the approval queue was switched on for the operator",
];
const count = (body: string, needle: string): number => body.split(needle).length - 1;
// History lines quote superseded wording by design (append-only records).
const isHistory = (l: string): boolean =>
  l.startsWith("**Amended:**") || l.startsWith("> **Superseded") || l.startsWith("**Last Updated");

describe("committed text states the period the trio must repeat", () => {
  const text = read("apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md");
  it("carries the 5-year period and the not-yet-built statement", () => {
    expect(text).toContain(PERIOD);
    expect(text).toMatch(NOT_BUILT);
  });
});

describe.each(DOCS)("published %s", (doc) => {
  const canonical = read(`docs/legal/${doc}.md`);
  const mirror = read(`plugins/soleur/docs/pages/legal/${doc}.md`);
  const both = [
    ["canonical", canonical],
    ["mirror", mirror],
  ] as const;

  it.each(both)("%s states the 5-year period and that the deletion step is not yet built", (_label, body) => {
    expect(body).toContain(PERIOD);
    expect(body).toMatch(NOT_BUILT);
  });

  it.each(both)("%s keeps the retention paragraph whole: period, hold clause and not-built clause together", (_label, body) => {
    const lines = body.split("\n").filter((l) => l.includes("5 years from the date of the decision, and then we delete"));
    expect(lines).toHaveLength(1);
    expect(lines[0]).toContain(HOLD);
    expect(lines[0]).toContain(NOT_BUILT_FULL);
    expect(count(body, HOLD)).toBe(1);
    expect(count(body, NOT_BUILT_FULL)).toBe(1);
    // The four ruled sentences, contiguous and verbatim; anything inserted between or around them moves this.
    expect(count(body, RETENTION_CORE)).toBe(1);
    expect(lines[0]).toContain(RETENTION_CORE);
    // No other period may be stated on the retention line: every "<n> years" token is the ruled "5 years".
    const years = (lines[0].match(YEARS_TOKEN) ?? []).map((t) => t.toLowerCase());
    expect(years.length).toBeGreaterThan(0);
    for (const t of years) expect(t).toBe("5 years");
  });

  it.each(both)("%s no longer carries the earlier unconfirmed proposal", (_label, body) => {
    expect(body).not.toContain(OLD_PROPOSAL);
    expect(body).not.toMatch(/the life of the legal text plus 5 years/i);
    const live = body.split("\n").filter((l) => !l.startsWith("**Last Updated:**")).join("\n");
    expect(live).not.toMatch(OLD_NO_PERIOD);
  });

  it.each(both)("%s no longer says the decision record is written ahead of the processing", (_label, body) => {
    expect(body).not.toContain("This is written ahead of the processing it describes. From the date the database migration that creates them");
    expect(body).not.toContain("it is not switched on at the date of this amendment (November 6, 2026)");
  });

  it.each(both)("%s states the switched-on status truthfully and keeps the false claim only in history lines", (_label, body) => {
    expect(count(body, STATUS_START)).toBe(1);
    expect(body).not.toContain(STATUS_ABSENT);
    expect(count(body, NOTICE_HEAD)).toBe(1);
    expect(count(body, SWITCHED_ON)).toBe(SWITCHED_ON_COUNT[doc]);
    const lines = body.split("\n");
    const live = lines.filter((l) => !isHistory(l));
    for (const l of live) {
      expect(l.toLowerCase()).not.toContain(FALSE_CLAIM.toLowerCase());
      for (const o of OVERTAKEN) expect(l).not.toContain(o);
    }
    // The history exemption is a prefix test, so pin its POPULATION: exactly these lines may quote the old claim,
    // and every one of them is a history line. A new "**Amended:**" line carrying it would raise the count.
    // Case-insensitive: the Nov 9 Amended entry quotes it mid-sentence in lower case. Count OCCURRENCES, not lines:
    // a second quote inside one history line must also move the number.
    const carriers = lines.filter((l) => l.toLowerCase().includes(FALSE_CLAIM.toLowerCase()));
    expect(count(body.toLowerCase(), FALSE_CLAIM.toLowerCase())).toBe(FALSE_CLAIM_OCCURRENCES);
    for (const l of carriers) expect(isHistory(l)).toBe(true);
    // The branch-only Nov 9 entry may quote the old claim once, as the thing it corrects, and none of the overtaken wording.
    const nov9 = lines.filter((l) => l.startsWith(NOV9_ENTRY_PREFIX));
    expect(nov9).toHaveLength(1);
    expect(count(nov9[0].toLowerCase(), FALSE_CLAIM.toLowerCase())).toBe(1);
    for (const o of OVERTAKEN) expect(nov9[0]).not.toContain(o);
  });

  it.each(both)("%s notices say only what this document itself promised", (_label, body) => {
    const n = NOTICE_BY_DOC[doc];
    for (const m of n.present) expect(count(body, m)).toBe(1);
    for (const m of n.absent) expect(body).not.toContain(m);
  });

  it.each(both)("%s names the counts reader once and lists monitoring fields truthfully", (_label, body) => {
    expect(count(body, COUNTS_READER)).toBe(1);
    expect(count(body, MONITORING_FULL)).toBe(1);
    for (const m of MONITORING_NEW) expect(count(body, m)).toBe(1);
    for (const o of MONITORING_OLD) expect(body).not.toContain(o);
    expect(body).not.toContain("choice, text fingerprint, record age");
    for (const m of COUNTS_PRESENT) expect(count(body, m)).toBe(1);
    for (const a of COUNTS_ABSENT) expect(body).not.toContain(a);
  });

  if (doc === "privacy-policy") {
    it.each(both)("%s points 4.17 at its own Sections 5.10 and 5.14", (_label, body) => {
      expect(body).toContain("Sections 5.10 and 5.14 of this Privacy Policy state 90 days");
      expect(body).not.toContain("our Privacy Policy states 90 days");
    });
  }

  it.each(both)("%s marks the Last Updated chain as superseded for the write-path claim", (_label, body) => {
    expect(body).toContain('[Superseded November 9, 2026, as to "nothing writes to it until the write path ships"');
    const lastUpdated = body.split("\n").filter((l) => l.startsWith("**Last Updated:**"));
    expect(lastUpdated).toHaveLength(1);
    expect(lastUpdated[0]).toContain(LAST_UPDATED_PRESENT);
  });

  it.each(both)("%s keeps the superseded and DRAFT marker populations at the ruled counts", (_label, body) => {
    // 2 blockquotes + 1 inline in the Last Updated line. The marker under the unpublished Nov 8 entry is gone.
    expect(count(body, SUPERSEDED_NOV9)).toBe(3);
    for (const m of FURTHER_MARKER_PRESENT) expect(count(body, m)).toBe(1);
    for (const a of FURTHER_MARKER_ABSENT) expect(body).not.toContain(a);
    // The issue-number DRAFT marker count equals origin/main: the two new entries add none.
    expect(count(body, DRAFT_WITH_ISSUE)).toBe(DRAFT_WITH_ISSUE_COUNT[doc]);
    expect(count(body, DRAFT_PLAIN)).toBe(2);
  });
});
