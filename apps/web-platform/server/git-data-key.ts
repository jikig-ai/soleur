// The git-data SSH private keys as the container receives them (#8211 PR-G).
//
// Doppler stores GIT_TRANSPORT_SSH_PRIVATE_KEY / GIT_PROVISION_SSH_PRIVATE_KEY /
// GIT_REMOVE_SSH_PRIVATE_KEY as multi-line values. ci-deploy.sh loads prd with
// `doppler secrets download --format docker` + `docker --env-file`, which collapses each
// to ONE line holding literal backslash-n pairs (rehearsal-2 flip run 40305860011: the
// container probe read `auth_refused` because ssh got an unparseable key). This module is
// the single place the app reads those three variables, so the repair cannot be skipped
// by a new call site: the source sweep in test/git-data-key-sweep.test.ts fails on any
// other read. The container probe (infra/git-data-container-probe.sh) applies the SAME
// transform in POSIX sh; test/git-data-key.test.ts and the CPX rows pin the two together.

export const GIT_DATA_KEY_ENV_NAMES = [
  "GIT_TRANSPORT_SSH_PRIVATE_KEY",
  "GIT_PROVISION_SSH_PRIVATE_KEY",
  "GIT_REMOVE_SSH_PRIVATE_KEY",
] as const;

export type GitDataKeyEnvName = (typeof GIT_DATA_KEY_ENV_NAMES)[number];

// Exactly the four characters the container probe trims (infra/git-data-container-probe.sh
// trim_key: space, tab, CR, LF). NOT String.prototype.trim(): that also strips form feed, NBSP,
// the BOM and other Unicode space, which the probe's POSIX sh does not, so the two would write
// different bytes for the same value.
const KEY_END_WS = /^[ \t\r\n]+|[ \t\r\n]+$/g;

function trimKeyEnds(v: string): string {
  return v.replace(KEY_END_WS, "");
}

/**
 * Repair the docker-env-file form of a key. The ends are trimmed (space, tab, CR, LF only);
 * a value with NO real newline that contains a literal backslash-n pair then has each pair
 * replaced by a real newline and is trimmed again; any other value (already multi-line, or
 * single-line without the pair) is returned as trimmed. A multi-line key is never touched
 * inside: a `\n` in its comment is the comment's own text. Absent or blank reads as ""
 * (not configured). The probe applies the same transform; the agreement rows in
 * test/git-data-key.test.ts hold the two to the same bytes for the same value.
 */
export function normalizeGitDataKey(raw: string | undefined | null): string {
  const trimmed = trimKeyEnds(raw ?? "");
  if (!trimmed) return "";
  if (!trimmed.includes("\n") && trimmed.includes("\\n")) {
    return trimKeyEnds(trimmed.replace(/\\n/g, "\n"));
  }
  return trimmed;
}

/** Read one of the three key variables, normalised. "" when unset or blank. */
export function readGitDataKeyEnv(name: GitDataKeyEnvName): string {
  return normalizeGitDataKey(process.env[name]);
}

/**
 * The bytes written to a 0600 key file: the normalised key plus the final LF OpenSSH
 * requires. Idempotent over an already-normalised key, so the file writers apply it to
 * whatever they are handed.
 */
export function gitDataKeyFileContents(privateKey: string): string {
  return `${normalizeGitDataKey(privateKey)}\n`;
}
