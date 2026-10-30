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
    "b38d30f8b6c4be3e57ebc7396ee5a07f2abb4d953afc2cdb506f2e879f6dd4d8",

  "cookie-policy":
    "ff889cbc7937d207374781dca15894292d1f6eaf63c66e6b6f1575f653c4e3c5",
  "corporate-cla":
    "03cbf51b1543cdb3699ec71fbfa2946ff28d264ef574ae7252eac17b89ab6bad",
  "data-protection-disclosure":
    "b4ebfa9dbbc7cf7832f19adb2df40632e18ab91f5764810f728231f37c8a9e28",
  "disclaimer":
    "19c9069f166d17c179e91e9747d816d25de81156e74752cf1d67ee210f3935d6",
  "gdpr-policy":
    "d616dd1465e0cd299d9ff58154e64f6e50ec2d201aee65b85a0e11d68b78ec46",
  "individual-cla":
    "43836d36d4c8c96a9d0363ac70b2fe3d349c121b8ad030099f82189409830f25",
  "privacy-policy":
    "540cad4b8d6758cd2ad5fbdebc5cf500bf5902ef953e465c454aaa71d0628b39",
};
