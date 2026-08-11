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
    "32e0c97a0d1b189dd6d7c19782eaf283dd992d97981fab5e2e3c5f58f0540952",
  "cookie-policy":
    "c40439d1413772fcc145d8bbe4bcd16227649123d710310e896d9f7bd6c18d77",
  "corporate-cla":
    "d41147d94cf53c9340cdf39d751b91b4140991ddbab092451308a1398eb00826",
  "data-protection-disclosure":
    "924dffc823cf17f36916e7d65d69ec1f987ccac2de4d1ecb429cbc0cf0cf1c1a",
  "disclaimer":
    "7ecde149945c901fdde3ae4964b43eb0d1a536fd3db12eed16c9c8a140c84c18",
  "gdpr-policy":
    "02e648961a621fcef6f9880c2eb2b5f8aa5f7d0e386cebaeeeedeffa38f0a556",
  "individual-cla":
    "8d773e4331fd82e4b27a506eac2f968ad319adcef624d8f6115c0b71deb5e538",
  "privacy-policy":
    "1eba1eb1933dd78bed668b3429868ad9ff8accb15d4f2471dcb6213dd28aa4e0",
};
