/**
 * SHA-256 hashes of each legal document's canonical source file. These
 * are compared at build/CI time by `apps/web-platform/scripts/check-tc-document-sha.sh` to
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
    "133508693d94a12af2cf71a585de24123b0c0a2039fbd7418d868aad59165683",
  "cookie-policy":
    "e2ac3ba184bf3e29d94a5702e48b85447748d749f28c00664ee94b170b84417e",
  "corporate-cla":
    "3a29a64cf1be210e273176682a930f16872b09bcf256d32b1f4490cda17c7270",
  "data-protection-disclosure":
    "6e648c7f669f58786472d2887b1902a2cde6873f14eaca10b8a318c3a34b040c",
  "disclaimer":
    "ea66cca071771aad58b151ad022649326bcedf8b734d6afcffcd4ce1bcb44d7e",
  "gdpr-policy":
    "06228fe8d823e77d7d462e4a3fb3445cc35c5f85b11a1733190e281cac021385",
  "individual-cla":
    "fbc42498e5a763a730662f169de21cf4030a7e8dc980a02c6b067a10ef7a2bb1",
  "privacy-policy":
    "d6580fae9309d019adead2364e780e0d159e39e4616458ec08c8ecc6369960fe",
};
