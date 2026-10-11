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
    "813d5bf2f469a94d45a7156bbcb23e23419f20f36e04ee1fc3238c567efa2a44",

  "cookie-policy":
    "ff889cbc7937d207374781dca15894292d1f6eaf63c66e6b6f1575f653c4e3c5",
  "corporate-cla":
    "03cbf51b1543cdb3699ec71fbfa2946ff28d264ef574ae7252eac17b89ab6bad",
  "data-protection-disclosure":
    "dad1815374fd02407c56238aa2a29b9a818b5e0d652b9c01c79233a9f91e646e",
  "disclaimer":
    "19c9069f166d17c179e91e9747d816d25de81156e74752cf1d67ee210f3935d6",
  "gdpr-policy":
    "70a930389a9d2f2140bd90984bebe0f6c463f80dc604b30de21df21c03ff3013",
  "individual-cla":
    "43836d36d4c8c96a9d0363ac70b2fe3d349c121b8ad030099f82189409830f25",
  "privacy-policy":
    "29042cd9f8fafffb37a9d31bf6c942448e21690a1863f1adbdcc5048ef889e4a",
};
