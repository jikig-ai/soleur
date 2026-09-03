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
    "8384674ea9821acb42f10e7bdbdfa51b7c0977e2528b63f48530d8579628633d",
  "data-protection-disclosure":
    "3d6eb62563c5b2927dbd414c2a9dc370928d17be9666473da71cca1e393ac925",
  "disclaimer":
    "ea66cca071771aad58b151ad022649326bcedf8b734d6afcffcd4ce1bcb44d7e",
  "gdpr-policy":
    "ca4741f44f6f10a278aba7b842b5afa3b51a50a768c6a771521c8346b5e66735",
  "individual-cla":
    "16b64913a58064dcd4103500a15a21b982c3052ec63760e91e68d1e945f687f2",
  "privacy-policy":
    "a0b4750f3fde08b579979df15bda2d508bd5f2467aeab7257f5e03dd61f3983d",
};
