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
    "eb8f4dd62418b7d58d43200bb45171e3113c323fdd44614c1412851aed49028a",
  "cookie-policy":
    "3c3d57a9227069bccf2c7f671b389d2f2ac79980481647fb029793a957020cc8",
  "corporate-cla":
    "d41147d94cf53c9340cdf39d751b91b4140991ddbab092451308a1398eb00826",
  "data-protection-disclosure":
    "3579746add92fbb6db2725443e54ce95eb3171a64c63fe884958e24bb3e83fa3",
  "disclaimer":
    "f02375aadf0b0aeb6f60718bbca3f75135bb6a949b2cded1bbfabbf704b117c2",
  "gdpr-policy":
    "31360b28b72108837a6de6b6c78d80b8fbd597ac478bb99b9ed51b214ea91a2b",
  "individual-cla":
    "8d773e4331fd82e4b27a506eac2f968ad319adcef624d8f6115c0b71deb5e538",
  "privacy-policy":
    "cc760b88e687176aa1253475edd94c19ea377633b8a65038d950124734492b0b",
};
