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
    "928f94d30c0b35e4374650fd12a5b5f1434018b903517d47a013ebe726d08910",
  "data-protection-disclosure":
    "00017fa6dcb8d54c9cd856d58356c024e9faa103acf92989c39aa2cd77c03459",
  "disclaimer":
    "ea66cca071771aad58b151ad022649326bcedf8b734d6afcffcd4ce1bcb44d7e",
  "gdpr-policy":
    "e2e9d32501d8263fac3f99a76ba786c98291fbea4b0cac7de07e0514ea243a64",
  "individual-cla":
    "8b7092c11861011006e8abab75a83b2edfae5f508f54c359617eaa5fdd16902b",
  "privacy-policy":
    "4926dfb6cfeec374ec6503eb7edfd4b4201d2a13fcaf69a5ed0da4343a34b7e3",
};
