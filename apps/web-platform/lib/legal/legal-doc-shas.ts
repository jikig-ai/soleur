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
    "d369d44755936b7fcae7662e1a40bbc5cf67ca9884f335f94a9e2114d66bd3fb",
  "cookie-policy":
    "3c3d57a9227069bccf2c7f671b389d2f2ac79980481647fb029793a957020cc8",
  "corporate-cla":
    "d41147d94cf53c9340cdf39d751b91b4140991ddbab092451308a1398eb00826",
  "data-protection-disclosure":
    "8ee3197ef9acd3d8ff00cee80233c304fee3963f2d0670ce391051d8717e7a4c",
  "disclaimer":
    "f02375aadf0b0aeb6f60718bbca3f75135bb6a949b2cded1bbfabbf704b117c2",
  "gdpr-policy":
    "607bc74cf21ed828047ae09d0180d4f4f3e632a5563799ad79488dfb351f3123",
  "individual-cla":
    "8d773e4331fd82e4b27a506eac2f968ad319adcef624d8f6115c0b71deb5e538",
  "privacy-policy":
    "bddc5f57feb5aa9def2e97e8d3aec8f834b3df73844fbd506df6e7f8bd087fd5",
};
