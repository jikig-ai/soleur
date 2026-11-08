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

  it.each([
    ["canonical", canonical],
    ["mirror", mirror],
  ])("%s states the 5-year period and that the deletion step is not yet built", (_label, body) => {
    expect(body).toContain(PERIOD);
    expect(body).toMatch(NOT_BUILT);
  });

  it.each([
    ["canonical", canonical],
    ["mirror", mirror],
  ])("%s no longer carries the earlier unconfirmed proposal", (_label, body) => {
    expect(body).not.toContain(OLD_PROPOSAL);
    expect(body).not.toMatch(/the life of the legal text plus 5 years/i);
    // The `**Last Updated:**` line is a frozen history chain (the CLO ruled it stays untouched); its November 6 note
    // still says "no retention period is confirmed", which was true then. Every other line must not.
    const withoutHistoryChain = body.split("\n").filter((l) => !l.startsWith("**Last Updated:**")).join("\n");
    expect(withoutHistoryChain).not.toMatch(OLD_NO_PERIOD);
  });

  it.each([
    ["canonical", canonical],
    ["mirror", mirror],
  ])("%s no longer says the decision record is written ahead of the processing", (_label, body) => {
    expect(body).not.toContain("This is written ahead of the processing it describes. From the date the database migration that creates them");
    expect(body).not.toContain("it is not switched on at the date of this amendment (November 6, 2026)");
  });

  it("the monitoring list no longer names the text fingerprint for the decision event", () => {
    expect(canonical).not.toContain("choice, text fingerprint, record age");
  });
});
