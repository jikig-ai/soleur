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
    "e2ac3ba184bf3e29d94a5702e48b85447748d749f28c00664ee94b170b84417e",
  "corporate-cla":
    "03cbf51b1543cdb3699ec71fbfa2946ff28d264ef574ae7252eac17b89ab6bad",
  "data-protection-disclosure":
    "cf2a1acba67b75cff75289108b66c12dc1ab5d051d47e202911977e83c5b9663",
  "disclaimer":
    "312432f3a536685d6a21e7720a4e925f8dcc24ddc1f178dc0ad67ff682679809",
  "gdpr-policy":
    "8a879987bd18d8f49b3f94cec9b7058201f6ad82fd0eb700dfee525a1b0da397",
  "individual-cla":
    "43836d36d4c8c96a9d0363ac70b2fe3d349c121b8ad030099f82189409830f25",
  "privacy-policy":
    "6a872fff105eebb39764cb9b2fff85e20790eb49e7da07f7e2c33183fd307ce2",
};
