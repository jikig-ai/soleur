import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, test, expect } from "vitest";

// Plan AC8 / FR7 (downgraded per RC2): regression-prevention assertion
// that both the consent surfaces (signup page checkbox + standalone
// accept-terms page) name BOTH the Terms & Conditions AND the Privacy
// Policy with distinct linked anchors. GDPR Art. 7(2) "distinguishable"
// bar — the user must understand which documents they are accepting.
//
// Source-reading assertion (not behavioural) to keep the test cheap
// and avoid mocking React/Next router. If the copy regresses (e.g., a
// PR strips "Privacy Policy" or merges the two links), this test fires
// before the change reaches review.

const ACCEPT_TERMS_PAGE = resolve(
  __dirname,
  "../app/(auth)/accept-terms/page.tsx",
);
const SIGNUP_PAGE = resolve(__dirname, "../app/(auth)/signup/page.tsx");

const REQUIRED_LITERALS = [
  "Terms &amp; Conditions",
  "Privacy Policy",
  "terms-and-conditions.html",
  "privacy-policy.html",
] as const;

describe.each([
  ["accept-terms/page.tsx", ACCEPT_TERMS_PAGE],
  ["signup/page.tsx", SIGNUP_PAGE],
])("%s consent copy regression", (label, path) => {
  const src = readFileSync(path, "utf8");

  test.each(REQUIRED_LITERALS)(`${label} contains literal %s`, (literal) => {
    expect(
      src.includes(literal),
      `${label} is missing required literal "${literal}". ` +
        `The consent copy must name BOTH documents with distinct linked anchors.`,
    ).toBe(true);
  });
});
