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
    "3bf58d97e24be527b36b268fa7a78c139ace6866e6854bf60fc568a5323769d3",
  "cookie-policy":
    "ff889cbc7937d207374781dca15894292d1f6eaf63c66e6b6f1575f653c4e3c5",
  "corporate-cla":
    "03cbf51b1543cdb3699ec71fbfa2946ff28d264ef574ae7252eac17b89ab6bad",
  "data-protection-disclosure":
    "d63e05bbee6aafcc18f49dc0387f51cfc50e9c9890bec0c8bb0b782163527ea3",
  "disclaimer":
    "19c9069f166d17c179e91e9747d816d25de81156e74752cf1d67ee210f3935d6",
  "gdpr-policy":
    "488ef39d305328515b70f698182ef5cc306bbacbca1e70cccc513f0bccd07d3c",
  "individual-cla":
    "43836d36d4c8c96a9d0363ac70b2fe3d349c121b8ad030099f82189409830f25",
  "privacy-policy":
    "418a3836443d2845f0581c05b3e9f900a4fc5e19c473eec1a977ab9bd0cbda94",
};
