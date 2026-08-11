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
    "a357fe7a26ce73544516e71d15bf7f1550c02b5a79df7c2ad6a80c7d1dfc7cab",
  "disclaimer":
    "f02375aadf0b0aeb6f60718bbca3f75135bb6a949b2cded1bbfabbf704b117c2",
  "gdpr-policy":
    "1abfc0c30fb528a3204ff2a339801bccd8b5cf7164804e017533a00fbb67cafc",
  "individual-cla":
    "8d773e4331fd82e4b27a506eac2f968ad319adcef624d8f6115c0b71deb5e538",
  "privacy-policy":
    "dc2df0ce37ad1bbec032b8a79ebba3a81152ef342121bacb2789976dab8c4495",
};
