/**
 * The hardened-push argv and environment (#11636). A leaf module: it imports only the shared git-hardening constants
 * (themselves import-free), so `git-auth.ts` and `push-branch.ts` can both take it without a cycle or a mock-export hazard.
 *
 * Why: the cc push runs `git` in the dispatch process, outside the sandbox, in a workspace directory the agent can write.
 * Everything in that directory that git trusts is therefore agent-controlled: `.git/hooks/*`, `.git/config`, replace refs, and
 * (via the environment) whatever the server process holds. The hardened form
 *   - reuses `GIT_HARDENING_ARGS` / `GIT_HARDENING_ENV` (hooks path, fsmonitor, attributes, replace objects, global/system
 *     config), the SAME constants the Inngest handler steps use (never a second copy);
 *   - resets the UNSCOPED proxy / extra-header keys and the `https://github.com/`-scoped proxy key. That is all `-c` can do: git
 *     picks the most specific `http.<url>.*` match, so a more specific key the repo config sets (for example
 *     `http.https://github.com/<owner>/.proxy`) still wins over these resets, and `http.sslVerify`, `http.<url>.sslVerify`,
 *     `http.curloptResolve` and the like are not reset at all;
 *   - clamps the transport set with `GIT_ALLOW_PROTOCOL=https` (the environment beats any repo `protocol.*.allow`), so a
 *     rewritten push URL cannot reach `ext::<command>` or `file` transports; `push.followTags=false` keeps tags off the
 *     one approved ref;
 *   - builds the child environment from an ALLOWLIST (never `process.env`), so no server secret reaches the child;
 *   - pins `GIT_DIR` to `<workspace>/.git`, `GIT_COMMON_DIR` to the same directory (a `commondir` file cannot redirect), and
 *     `GIT_OBJECT_DIRECTORY` to its `objects`, and `GIT_CEILING_DIRECTORIES` to the workspace parent, so discovery cannot walk
 *     elsewhere.
 * Opt-in: callers that do not set `hardened` keep their exact legacy argv and environment.
 *
 * NOT covered here (deferred, recorded as ADR-309 flip item 9b): the repo config can still divert the installation token to
 * another https host through `url.<base>.insteadOf` / `url.<base>.pushInsteadOf`, a URL-scoped `http.<url>.proxy` /
 * `extraHeader` / `sslVerify` / `sslCAInfo`, or `http.curloptResolve`. `remote.*.pushurl` is not a vector for this push (the
 * push names a literal URL). The structural closure is a push from an isolated, server-written GIT_DIR.
 */

import { dirname } from "node:path";

import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "./inngest/functions/_git-hardening";

/**
 * The only variables copied from the server environment into a hardened child. `HOME` is the real one (unlike the scrubbed env in
 * `compound-promote-create-gates.ts`, which points it at a tmpdir) because the askpass helper script lives under it; git itself
 * ignores it for config (`GIT_CONFIG_GLOBAL=/dev/null`). `HTTPS_PROXY` and friends are deliberately absent: a future proxied egress
 * would fail a hardened push closed.
 */
export const HARDENED_ENV_ALLOWLIST: readonly string[] = [
  "PATH",
  "HOME",
  "TMPDIR",
  "LANG",
  "LC_ALL",
  "SSL_CERT_FILE",
  "SSL_CERT_DIR",
];

/**
 * Global git options for a hardened invocation: the shared hardening, the proxy / extra-header resets (unscoped and
 * `https://github.com/` only, see the header) and `push.followTags=false` (no unapproved tag refs ride along).
 */
export const HARDENED_GIT_ARGS: readonly string[] = [
  ...GIT_HARDENING_ARGS,
  "-c",
  "http.proxy=",
  "-c",
  "http.https://github.com/.proxy=",
  "-c",
  "http.extraHeader=",
  "-c",
  "push.followTags=false",
];

/** The only transport a hardened push may use. An environment variable beats every repo-level `protocol.*.allow`. */
export const HARDENED_ALLOW_PROTOCOL = "https";

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
  const gitDir = `${workspacePath.replace(/\/+$/, "")}/.git`;
  env.GIT_DIR = gitDir;
  env.GIT_COMMON_DIR = gitDir;
  env.GIT_OBJECT_DIRECTORY = `${gitDir}/objects`;
  env.GIT_ALLOW_PROTOCOL = HARDENED_ALLOW_PROTOCOL;
  env.GIT_CEILING_DIRECTORIES = dirname(workspacePath.replace(/\/+$/, ""));
  Object.assign(env, extra);
  return env as NodeJS.ProcessEnv;
}
