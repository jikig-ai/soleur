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
    "0361d1d493586f9af7d751564ec0d58c8bc3b27ec0626df730f09d43dd6e529d",
  "disclaimer":
    "ea66cca071771aad58b151ad022649326bcedf8b734d6afcffcd4ce1bcb44d7e",
  "gdpr-policy":
    "ba42ad202d89170e36d099fa165cc85dde729aeda095cb971b1f3a2a4fce3ecf",
  "individual-cla":
    "822a45cfd99c2da3d89e62f990c9bcde92606c81a6b220c21952884699337615",
  "privacy-policy":
    "8ddc60a019b2036b80de1f48d342c4037ced1404849972ff060b3831890c1e72",
};
