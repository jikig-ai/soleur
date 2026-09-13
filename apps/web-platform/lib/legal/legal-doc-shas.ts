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
    "896a401ab93b2f40f997a8187bf515633db2a68af592e7c258be31f9eccf7725",
  "cookie-policy":
    "e2ac3ba184bf3e29d94a5702e48b85447748d749f28c00664ee94b170b84417e",
  "corporate-cla":
    "03cbf51b1543cdb3699ec71fbfa2946ff28d264ef574ae7252eac17b89ab6bad",
  "data-protection-disclosure":
    "0afd109330be097e034d4f0ab9ffed305b1f6467f4d7f749933d10f9559e14f4",
  "disclaimer":
    "312432f3a536685d6a21e7720a4e925f8dcc24ddc1f178dc0ad67ff682679809",
  "gdpr-policy":
    "d82f2f84d62ed3fd465ee7f1c27ad5dd9c9fb13c465d2945a95967f980cdf19d",
  "individual-cla":
    "43836d36d4c8c96a9d0363ac70b2fe3d349c121b8ad030099f82189409830f25",
  "privacy-policy":
    "94ddb5b21a1c13db5c9e3a70c3d815e8f40cdbb62bca61810e2878f80c7125ab",
};
