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
    "bc2c38315b6669a1186151cdbffe8b39ca3223903da89a7db0f2c2a9b382eb92",
  "cookie-policy":
    "ff889cbc7937d207374781dca15894292d1f6eaf63c66e6b6f1575f653c4e3c5",
  "corporate-cla":
    "03cbf51b1543cdb3699ec71fbfa2946ff28d264ef574ae7252eac17b89ab6bad",
  "data-protection-disclosure":
    "ed1ee1384c53e5b56fae877bae5ef726f561f00eef2849a5c5b721836ac21d37",
  "disclaimer":
    "8b9373e78afa1aa67126b901e60d040167116bf423d262449e6c4cc6096f09c2",
  "gdpr-policy":
    "6d36e37d99f64d753595df24d989ac829d8a2de6a3d7c7c3385035895ef28b45",
  "individual-cla":
    "43836d36d4c8c96a9d0363ac70b2fe3d349c121b8ad030099f82189409830f25",
  "privacy-policy":
    "4d43da43b6e0aa010cfb2e264ec9a33bfa18011221684b159b60202d0bce77d0",
};
