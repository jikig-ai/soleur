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
    "e4070c4b25d3b24c57c1745f5f15bd29584f7758216a4afc449d4cbb24d98477",
  "disclaimer":
    "9a31290a5d691c5ddaecaf073b5db00a6d5b77f560c8c6589e84ce887e3c5384",
  "gdpr-policy":
    "a470b985bdcdc91fb0d1807145c79d8416c9366b49b1955d06ae27466c1eb08b",
  "individual-cla":
    "8d773e4331fd82e4b27a506eac2f968ad319adcef624d8f6115c0b71deb5e538",
  "privacy-policy":
    "8da5833998a616b5e5aae87ec9d44ac4bf30f6ad5aefcd398c5c93a4990de7fa",
};
