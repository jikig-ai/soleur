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
    "23c6c8e13f8dd0f622727d5b29d72b73ac2535159ca1949e4abb663c2cf1cef4",
  "disclaimer":
    "ea66cca071771aad58b151ad022649326bcedf8b734d6afcffcd4ce1bcb44d7e",
  "gdpr-policy":
    "ba42ad202d89170e36d099fa165cc85dde729aeda095cb971b1f3a2a4fce3ecf",
  "individual-cla":
    "822a45cfd99c2da3d89e62f990c9bcde92606c81a6b220c21952884699337615",
  "privacy-policy":
    "75c15c902d8fcdaeaf7493bc4988d6c502c4a4712674f925ae96706b4018ef13",
};
