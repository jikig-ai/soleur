/**
 * The hardened-push argv and environment (#11636, ADR-309 flip item 9b). A leaf module: it imports only `node:path` and the
 * shared git-hardening constants (themselves import-free), so `git-auth.ts` and `push-branch.ts` can both take it without a
 * cycle or a mock-export hazard. It must never import the creator (`git-isolated-push-dir.ts`), which uses `fs`.
 *
 * Why: the cc push runs `git` in the dispatch process, outside the sandbox, with an installation token in the child's
 * environment, for a workspace directory the agent can write. Everything git reads from `<workspace>/.git` (config, hooks,
 * refs, `commondir`, grafts, ...) is therefore agent-controlled. Layering `-c` resets on top of that directory can never close
 * it (git picks the MOST specific `http.<url>.*` key, so a more specific key in the repo config beats a broader `-c` reset,
 * and `http.sslVerify`, `http.<url>.sslVerify`, `http.sslCAInfo`, `http.curloptResolve` and `url.<base>.insteadOf` have no
 * `-c` reset at all). The 9b closure is structural: the hardened child never runs against the workspace `.git`.
 *
 * The hardened child runs with
 *   - `GIT_DIR` = a bare directory the SERVER created and whose `config` it wrote (`createIsolatedPushDir`), so the only
 *     repository-level configuration git reads is a file the agent never wrote;
 *   - `GIT_ALTERNATE_OBJECT_DIRECTORIES` = `<workspace>/.git/objects`, the one workspace path it can read: object bytes only
 *     (the creator refuses an object store that redirects elsewhere);
 *   - `HOME` = the isolated directory (not the server's), so `~/.netrc`, `~/.gitconfig` and `$XDG_CONFIG_HOME/git/*` are
 *     never read and the askpass script written inside it is the only credential path;
 *   - an ALLOWLISTED environment (never `process.env`), so no server secret reaches the child;
 *   - `GIT_ALLOW_PROTOCOL=https` (the environment beats any repo `protocol.*.allow`), so a rewritten push URL cannot reach
 *     `ext::<command>` or `file` transports;
 *   - `GIT_HARDENING_ARGS` / `GIT_HARDENING_ENV` (the SAME constants the Inngest handler steps use, never a second copy) plus the
 *     proxy / extra-header resets and `push.followTags=false`. With the config no longer read from the workspace these are
 *     defence in depth: they still apply to anything the child could read from the server-written file or the command line.
 * Pins for `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY` and `GIT_CEILING_DIRECTORIES` are deliberately absent: a fresh bare
 * directory has no `commondir` file, its object directory defaults to `<GIT_DIR>/objects`, and discovery never runs once
 * `GIT_DIR` is set. (The earlier claim that pinning `GIT_COMMON_DIR` stops a planted `commondir` from redirecting ref
 * resolution was measured false on git 2.56: the control is never running git against the workspace `.git`.)
 *
 * Still not covered here: a swap of the workspace object store AFTER the creator's check (non-atomic) exposes object bytes
 * of another repository for a sha the agent already knows; whether the cc sandbox can write `<workspace>/.git` at all is
 * UNVERIFIED. `remote.*.pushurl` is not a vector: the push names a literal URL and the isolated config has no remotes.
 * Opt-in: callers that do not set `hardened` keep their exact legacy argv and environment.
 */

import { isAbsolute } from "node:path";

import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "./inngest/functions/_git-hardening";

/**
 * The only variables copied from the server environment into a hardened child. `HOME` is listed for the explicit contract but
 * is always OVERRIDDEN with the isolated directory (see `buildIsolatedGitEnv`). `HTTPS_PROXY` and friends are deliberately
 * absent: a future proxied egress would fail a hardened push closed.
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
 * `https://github.com/` only) and `push.followTags=false` (no unapproved tag refs ride along).
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

/** Brand set only by `createIsolatedPushDir`; `assertIsolatedPushDir` is the runtime check callers run before a token is minted. */
export const ISOLATED_PUSH_DIR_BRAND: unique symbol = Symbol("soleur.isolatedPushDir");

/** A server-created isolated bare GIT_DIR plus the one workspace object directory it may read as an alternate. */
export interface IsolatedPushDir {
  readonly gitDir: string;
  readonly alternateObjectDirectory: string;
  readonly [ISOLATED_PUSH_DIR_BRAND]: true;
}

/**
 * A path that is safe to hand to git as `GIT_DIR` or inside `GIT_ALTERNATE_OBJECT_DIRECTORIES`: absolute, and free of the
 * characters that split or quote the variable (`:` is the list separator; `"` and `\` start git's quoted form; newline and
 * NUL end the entry). The creator and the builder enforce this one rule.
 */
export function isSafeGitPath(p: string): boolean {
  return typeof p === "string" && p.length > 0 && isAbsolute(p) && !/[:"\\\n\0]/.test(p);
}

/** Throws unless `value` is a branded handle whose two paths are safe. A stray `true`, an `as any` object or a relative path refuses. */
export function assertIsolatedPushDir(value: unknown): asserts value is IsolatedPushDir {
  const v = value as Partial<IsolatedPushDir> | null | undefined;
  if (
    typeof v !== "object" ||
    v === null ||
    (v as Record<symbol, unknown>)[ISOLATED_PUSH_DIR_BRAND] !== true ||
    typeof v.gitDir !== "string" ||
    typeof v.alternateObjectDirectory !== "string" ||
    !isSafeGitPath(v.gitDir) ||
    !isSafeGitPath(v.alternateObjectDirectory)
  ) {
    throw new Error("hardened git invocation requires an isolated push directory");
  }
}

/**
 * The hardened child environment for a git run from an isolated directory. `extra` carries the per-call variables (the
 * askpass wiring); it is applied last. Never reads or spreads `process.env` wholesale.
 */
export function buildIsolatedGitEnv(
  dir: IsolatedPushDir,
  extra: Readonly<Record<string, string>> = {},
): NodeJS.ProcessEnv {
  assertIsolatedPushDir(dir);
  const env: Record<string, string> = {};
  for (const key of HARDENED_ENV_ALLOWLIST) {
    const value = process.env[key];
    if (value !== undefined) env[key] = value;
  }
  Object.assign(env, GIT_HARDENING_ENV);
  env.GIT_DIR = dir.gitDir;
  env.GIT_ALTERNATE_OBJECT_DIRECTORIES = dir.alternateObjectDirectory;
  env.GIT_ALLOW_PROTOCOL = HARDENED_ALLOW_PROTOCOL;
  env.HOME = dir.gitDir;
  Object.assign(env, extra);
  return env as NodeJS.ProcessEnv;
}
