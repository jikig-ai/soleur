/**
 * The hardened-push argv and environment (#11636). A leaf module: it imports only the shared git-hardening constants
 * (themselves import-free), so `git-auth.ts` and `push-branch.ts` can both take it without a cycle or a mock-export hazard.
 *
 * Why: the cc push runs `git` in the dispatch process, outside the sandbox, in a workspace directory the agent can write.
 * Everything in that directory that git trusts is therefore agent-controlled: `.git/hooks/*`, `.git/config`, replace refs, and
 * (via the environment) whatever the server process holds. The hardened form
 *   - reuses `GIT_HARDENING_ARGS` / `GIT_HARDENING_ENV` (hooks path, fsmonitor, attributes, replace objects, global/system
 *     config), the SAME constants the Inngest handler steps use (never a second copy);
 *   - clears every HTTP proxy / extra-header knob the repo config could set to divert or observe the credential exchange;
 *   - builds the child environment from an ALLOWLIST (never `process.env`), so no server secret reaches the child;
 *   - pins `GIT_DIR` to `<workspace>/.git` and `GIT_CEILING_DIRECTORIES` to the workspace parent, so discovery cannot walk
 *     elsewhere.
 * Opt-in: callers that do not set `hardened` keep their exact legacy argv and environment.
 *
 * NOT covered here (deferred, recorded in the ADR-309 addendum): neutralising `url.<base>.insteadOf` / `remote.*.pushurl`.
 */

import { dirname } from "node:path";

import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "./inngest/functions/_git-hardening";

/** The only variables copied from the server environment into a hardened child. */
export const HARDENED_ENV_ALLOWLIST: readonly string[] = [
  "PATH",
  "HOME",
  "TMPDIR",
  "LANG",
  "LC_ALL",
  "SSL_CERT_FILE",
  "SSL_CERT_DIR",
];

/** Global git options for a hardened invocation: the shared hardening plus the proxy / extra-header resets. */
export const HARDENED_GIT_ARGS: readonly string[] = [
  ...GIT_HARDENING_ARGS,
  "-c",
  "http.proxy=",
  "-c",
  "http.https://github.com/.proxy=",
  "-c",
  "http.extraHeader=",
];

/**
 * The hardened child environment for a git run in `workspacePath`. `extra` carries the per-call variables (the askpass
 * wiring); it is applied last. Never reads or spreads `process.env` wholesale.
 */
export function buildHardenedGitEnv(
  workspacePath: string,
  extra: Readonly<Record<string, string>> = {},
): NodeJS.ProcessEnv {
  const env: Record<string, string> = {};
  for (const key of HARDENED_ENV_ALLOWLIST) {
    const value = process.env[key];
    if (value !== undefined) env[key] = value;
  }
  Object.assign(env, GIT_HARDENING_ENV);
  env.GIT_DIR = `${workspacePath.replace(/\/+$/, "")}/.git`;
  env.GIT_CEILING_DIRECTORIES = dirname(workspacePath.replace(/\/+$/, ""));
  Object.assign(env, extra);
  return env as NodeJS.ProcessEnv;
}
