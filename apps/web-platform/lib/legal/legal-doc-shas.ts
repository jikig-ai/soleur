/**
 * SHA-256 hashes of each legal document's canonical source file. These
 * are compared at build/CI time by `scripts/check-tc-document-sha.sh` to
 * detect content changes that require a TC_VERSION bump assessment.
 *
 * When you edit a legal document (docs/legal/*.md), regenerate the hash:
 *   sha256sum docs/legal/<doc>.md
 * and update the corresponding entry here in the same commit.
 *
 * The hash is computed on the file's raw bytes (UTF-8) including
 * frontmatter, whitespace, and trailing newlines.
 */
export const LEGAL_DOC_SHAS: Readonly<Record<string, string>> = {
  "acceptable-use-policy":
    "d6824e4073e650bbf36b9b83e2808b37fef38884edb50b554977977b0e6a21ba",
  "cookie-policy":
    "3c3d57a9227069bccf2c7f671b389d2f2ac79980481647fb029793a957020cc8",
  "corporate-cla":
    "d41147d94cf53c9340cdf39d751b91b4140991ddbab092451308a1398eb00826",
  "data-protection-disclosure":
    "15c28e8b7539b328baedc617655cb8e41de1a7f2c7c6ce095be8dc138f429772",
  "disclaimer":
    "9a31290a5d691c5ddaecaf073b5db00a6d5b77f560c8c6589e84ce887e3c5384",
  "gdpr-policy":
    "c2c6f1481b7abee61db9675c1935d24bba42cfaae2bdc2203c127f6ee1a9cc6c",
  "individual-cla":
    "8d773e4331fd82e4b27a506eac2f968ad319adcef624d8f6115c0b71deb5e538",
  "privacy-policy":
    "6b4df04bbd16294b9cab8b2688670449ab937e95bdd72c9e7d1ae19fa9991e65",
};
