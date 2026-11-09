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
  "(Status as of November 8, 2026: the approval queue has been switched on in production since November 2026 (see the status notice at the head of ";
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
const MONITORING_NEW = [
  "each event carries the name of the text and, depending on the event, some of these:",
  "only the event for a record that fails its checksum and the event for a record with no marker carry the text fingerprint",
];
const MONITORING_OLD = "the event carries the text name, version, choice, record age";
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
    expect(count(body, NOTICE_HEAD)).toBe(1);
    expect(count(body, SWITCHED_ON)).toBe(SWITCHED_ON_COUNT[doc]);
    const live = body.split("\n").filter((l) => !isHistory(l));
    for (const l of live) {
      expect(l).not.toContain(FALSE_CLAIM);
      for (const o of OVERTAKEN) expect(l).not.toContain(o);
    }
  });

  it.each(both)("%s names the counts reader once and lists monitoring fields truthfully", (_label, body) => {
    expect(count(body, COUNTS_READER)).toBe(1);
    for (const m of MONITORING_NEW) expect(count(body, m)).toBe(1);
    expect(body).not.toContain(MONITORING_OLD);
    expect(body).not.toContain("choice, text fingerprint, record age");
  });

  if (doc === "privacy-policy") {
    it.each(both)("%s points 4.17 at its own Sections 5.10 and 5.14", (_label, body) => {
      expect(body).toContain("Sections 5.10 and 5.14 of this Privacy Policy state 90 days");
      expect(body).not.toContain("our Privacy Policy states 90 days");
    });
  }

  it.each(both)("%s marks the Last Updated chain as superseded for the write-path claim", (_label, body) => {
    expect(body).toContain('[Superseded November 9, 2026, as to "nothing writes to it until the write path ships"');
  });
});
