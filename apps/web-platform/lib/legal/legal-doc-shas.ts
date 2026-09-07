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
    "c0ce0911d4c031f5075c2ef4a996a485a1e948ce3a4f5eb82db84b941dde1a12",
  "data-protection-disclosure":
    "9fc83e5a73894c86ad5bab40cb1baeceea67c785144d50288bb2f3a6cf111142",
  "disclaimer":
    "ea66cca071771aad58b151ad022649326bcedf8b734d6afcffcd4ce1bcb44d7e",
  "gdpr-policy":
    "7579d41844341b574d5989b3700a94ad26d2aef6a125f42d2fff1f7fbaa0bbf3",
  "individual-cla":
    "822a45cfd99c2da3d89e62f990c9bcde92606c81a6b220c21952884699337615",
  "privacy-policy":
    "b93f71ce8b7a4b34d31f1860bba4e6b9dc85babb7e0482b90b3d21a95a075d5b",
};
