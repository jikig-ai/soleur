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
    "49b1cfc4f7d4a89696aa530ca1376f813f4f754346f41737fd5c3dad197a8142",
  "disclaimer":
    "ea66cca071771aad58b151ad022649326bcedf8b734d6afcffcd4ce1bcb44d7e",
  "gdpr-policy":
    "dec04c34d6fc340479d6e0d9c84322d92547dee637eca2793c5a0d2e17ee73dc",
  "individual-cla":
    "16b64913a58064dcd4103500a15a21b982c3052ec63760e91e68d1e945f687f2",
  "privacy-policy":
    "46750f074e46df05ac71dcfcb6ab7721181769b2ebecaec163c338422dfc888d",
};
