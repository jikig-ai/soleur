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
    "c58c4b5cc1738a9a2a7914abe743f40dcaf03743c446364fca2b0cc5b742afcf",

  "cookie-policy":
    "ff889cbc7937d207374781dca15894292d1f6eaf63c66e6b6f1575f653c4e3c5",
  "corporate-cla":
    "03cbf51b1543cdb3699ec71fbfa2946ff28d264ef574ae7252eac17b89ab6bad",
  "data-protection-disclosure":
    "48e6c7ccbed241f15f4c107e597f17612454438c64e9c65dc895c8c37e860ca0",
  "disclaimer":
    "19c9069f166d17c179e91e9747d816d25de81156e74752cf1d67ee210f3935d6",
  "gdpr-policy":
    "9a4a2bf08f32980ecf5a1133a72f4aaa6b27ac155662454c201930866cccdc1e",
  "individual-cla":
    "43836d36d4c8c96a9d0363ac70b2fe3d349c121b8ad030099f82189409830f25",
  "privacy-policy":
    "a78c75993cf50493fd7b5376ba56eda486271a818947c7dec47d9a3a2075cc95",
};
