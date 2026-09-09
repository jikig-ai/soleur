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
    "df71b041fd960d3e5d0c15669173cc40dab61568360f8756875830a18e2bbdc2",
  "cookie-policy":
    "e2ac3ba184bf3e29d94a5702e48b85447748d749f28c00664ee94b170b84417e",
  "corporate-cla":
    "03cbf51b1543cdb3699ec71fbfa2946ff28d264ef574ae7252eac17b89ab6bad",
  "data-protection-disclosure":
    "7fe4ae5f452ca7f63b5c43784a08904ea5ec49a9df939b986351be5e3fe561bd",
  "disclaimer":
    "312432f3a536685d6a21e7720a4e925f8dcc24ddc1f178dc0ad67ff682679809",
  "gdpr-policy":
    "b209e299ac236e65d625af5cdb5bb9810b8d935c6cc662f795e8e650b9cfacee",
  "individual-cla":
    "43836d36d4c8c96a9d0363ac70b2fe3d349c121b8ad030099f82189409830f25",
  "privacy-policy":
    "abb3e5a308ad7a7d53b7f0c011bf86f89556d424fd1c0c10ae0c259323bf9bc5",
};
