// ---------------------------------------------------------------------------
// GIT_ASKPASS-based authenticated git invocation.
//
// Replaces the legacy `credential.helper=!<path>` pattern that silently
// fell through to a terminal prompt when the helper could not be exec'd
// (e.g., /tmp mounted noexec), producing the user-facing "could not read
// Username for 'https://github.com': No such device or address" error.
//
// Key design choices:
//   * Askpass script body is FIXED (no interpolation). Token is passed via
//     the `GIT_INSTALLATION_TOKEN` env var and `printf`'d from the script.
//     Eliminates shell-injection regardless of token format drift.
//   * `-c credential.helper=` prefix on every invocation clears inherited
//     helpers so GIT_ASKPASS is the authoritative credential path.
//   * `GIT_TERMINAL_PROMPT=0` converts silent fall-through into a
//     deterministic "terminal prompts disabled" stderr — pattern-matchable.
//   * Script file lives in $HOME (writeable by the runtime user per our
//     Dockerfile's `useradd -m soleur`), falling back to /tmp only for
//     local-dev ergonomics.
// ---------------------------------------------------------------------------

import { accessSync, constants, unlinkSync, writeFileSync } from "fs";
import { randomUUID } from "crypto";
import { join } from "path";
import { execFile } from "child_process";
import { promisify } from "util";
import { createChildLogger } from "./logger";
import { generateInstallationToken } from "./github-app";

const execFileAsync = promisify(execFile);

const log = createChildLogger("git-auth");

const ASKPASS_SCRIPT_BODY = `#!/bin/sh
case "$1" in
  Username*) printf '%s' "\${GIT_USERNAME:-x-access-token}" ;;
  Password*) printf '%s' "\${GIT_INSTALLATION_TOKEN}" ;;
esac
`;

// Permissive installation-token format check. GitHub does not document the
// exact charset/length, so we log-warn (never throw) on mismatch — a strict
// validator is a latent outage class the day GitHub extends the format.
const TOKEN_FORMAT_RE = /^ghs_[A-Za-z0-9_-]{30,128}$/;

// Prepended to every `git` invocation so inherited `credential.helper`
// configurations (system, global, or per-repo) can never win over
// `GIT_ASKPASS`. Per `man gitcredentials`, credential helpers are tried
// BEFORE GIT_ASKPASS — clearing the list here makes the askpass
// authoritative. Git ≥ 2.9 treats `credential.helper=` (empty) as the
// clear sentinel; the node:22-slim runtime ships git ≥ 2.39.
const HELPER_RESET: readonly string[] = ["-c", "credential.helper="];

function isWriteable(dir: string): boolean {
  try {
    accessSync(dir, constants.W_OK | constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function getAskpassDir(): string {
  const home = process.env.HOME;
  if (home && isWriteable(home)) return home;
  return "/tmp";
}

/**
 * Write a fixed-body askpass script to a unique path in $HOME.
 * Returns the absolute path. The caller is responsible for cleanup
 * via `cleanupAskpassScript`.
 *
 * The script body is byte-identical across invocations — the token
 * is read from the child process's `GIT_INSTALLATION_TOKEN` env var,
 * not interpolated into the file, so no shell escaping is required
 * regardless of token contents.
 */
export function writeAskpassScript(): string {
  const dir = getAskpassDir();
  const scriptPath = join(dir, `askpass-${randomUUID()}.sh`);
  writeFileSync(scriptPath, ASKPASS_SCRIPT_BODY, { mode: 0o700 });
  return scriptPath;
}

/**
 * Best-effort unlink. Swallows ENOENT and permission errors so callers
 * can use this inside a `finally` without a nested try/catch.
 */
export function cleanupAskpassScript(scriptPath: string): void {
  try {
    unlinkSync(scriptPath);
  } catch {
    // Best-effort — a leaked 0o700 file is low-severity because the path
    // is unpredictable and the token TTL is 1h.
  }
}

export interface GitExecOptions {
  cwd?: string;
  timeout?: number;
}

/**
 * Classify git stderr into a stable error code so UI and API layers can
 * render actionable copy instead of raw stderr. Codes are preserved verbatim
 * between the error-wrapping site and the UX map in FailedState.
 */
export type GitErrorCode =
  | "AUTH_FAILED"
  | "REPO_NOT_FOUND"
  | "REPO_ACCESS_REVOKED"
  | "CLONE_NETWORK_ERROR"
  | "CLONE_TIMEOUT"
  | "CLONE_UNKNOWN";

/**
 * Runtime allowlist of known error codes. Used by the read path
 * (`/api/repo/status/route.ts#parseErrorPayload`) to coerce unknown
 * codes to `undefined` so the UI falls back to generic copy rather
 * than a blank headline.
 */
export const GIT_ERROR_CODES: readonly GitErrorCode[] = [
  "AUTH_FAILED",
  "REPO_NOT_FOUND",
  "REPO_ACCESS_REVOKED",
  "CLONE_NETWORK_ERROR",
  "CLONE_TIMEOUT",
  "CLONE_UNKNOWN",
] as const;

export function isGitErrorCode(value: unknown): value is GitErrorCode {
  return (
    typeof value === "string" &&
    (GIT_ERROR_CODES as readonly string[]).includes(value)
  );
}

/**
 * Thrown by authenticated git operations on failure. Carries both a
 * machine-readable `errorCode` for UX routing and the sanitized `rawStderr`
 * for support-use collapsibles.
 */
export class GitOperationError extends Error {
  public readonly errorCode: GitErrorCode;
  public readonly rawStderr: string;

  constructor(errorCode: GitErrorCode, rawStderr: string, userMessage?: string) {
    super(userMessage ?? `Git ${errorCode.toLowerCase().replace(/_/g, " ")}`);
    this.name = "GitOperationError";
    this.errorCode = errorCode;
    this.rawStderr = rawStderr;
  }
}

/**
 * Classify a git stderr buffer into a GitErrorCode. Returns CLONE_UNKNOWN
 * when no pattern matches — callers preserve the raw stderr for support.
 * Uses case-insensitive substring matching; git emits stable English
 * stderr strings even with the user's locale set.
 */
export function classifyGitError(stderr: string): GitErrorCode {
  const s = stderr;
  if (
    /terminal prompts disabled|could not read Username|could not read Password|Authentication failed|HTTP 401|HTTP 403/i.test(
      s,
    )
  ) {
    return "AUTH_FAILED";
  }
  if (/repository .* not found|HTTP 404/i.test(s)) {
    return "REPO_NOT_FOUND";
  }
  if (
    /Could not resolve host|Connection timed out|Network is unreachable|Connection refused|Operation timed out/i.test(
      s,
    )
  ) {
    return "CLONE_NETWORK_ERROR";
  }
  if (/timeout exceeded|signal SIGTERM/i.test(s)) {
    return "CLONE_TIMEOUT";
  }
  return "CLONE_UNKNOWN";
}

/**
 * Strip absolute filesystem paths from git stderr before it is returned
 * to the client, so server-side layout (workspace root, helper path) is
 * not leaked through `repo_error`.
 */
export function sanitizeGitStderr(raw: string): string {
  return raw.replace(/\/[^\s:]+/g, "<path>");
}

/**
 * Run `git` with installation-scoped credentials via GIT_ASKPASS.
 *
 * The token never appears in argv. It is delivered through the
 * child process's environment and consumed by the fixed askpass script.
 * Inherited `credential.helper` values are reset so they cannot shadow
 * the askpass. Interactive prompts are disabled, so auth failures
 * produce deterministic stderr instead of `could not read Username …
 * No such device or address`.
 *
 * @param args    git subcommand + flags (helper resets are prepended automatically)
 * @param installationId  GitHub App installation ID for token generation
 * @param opts    cwd + timeout passthrough to `execFileSync`
 * @returns the stdout Buffer from the git invocation
 */
export async function gitWithInstallationAuth(
  args: string[],
  installationId: number,
  opts: GitExecOptions = {},
): Promise<Buffer> {
  const token = await generateInstallationToken(installationId);

  if (!TOKEN_FORMAT_RE.test(token)) {
    // Log-warn only — NEVER throw. Token format has no documented spec.
    log.warn(
      { installationId, lengthBucket: Math.round(token.length / 10) * 10 },
      "Installation token does not match expected format — proceeding",
    );
  }

  const scriptPath = writeAskpassScript();

  try {
    const fullArgs = [...HELPER_RESET, ...args];
    const env: NodeJS.ProcessEnv = {
      ...process.env,
      GIT_ASKPASS: scriptPath,
      GIT_INSTALLATION_TOKEN: token,
      GIT_USERNAME: "x-access-token",
      GIT_TERMINAL_PROMPT: "0",
      GIT_TERMINAL_PROGRESS: "0",
      GIT_CONFIG_NOSYSTEM: "1",
      // Defense-in-depth: ignore any attacker-controlled user gitconfig
      // that could slip a `credential.helper` past HELPER_RESET if an
      // unexpected `$HOME` sibling ever becomes writeable.
      GIT_CONFIG_GLOBAL: "/dev/null",
    };

    // Async exec (non-blocking) — critical for Next.js route handlers
    // that invoke this helper on the request path (kb/upload pull,
    // session-sync pull, workspace clone all share this entry point).
    // A sync exec here would stall the Node event loop for the full
    // git RTT, queueing all other requests on the instance.
    const { stdout } = await execFileAsync("git", fullArgs, {
      ...opts,
      env,
      // Cap stdout to prevent memory spikes on verbose git output.
      maxBuffer: 10 * 1024 * 1024,
    });
    return Buffer.isBuffer(stdout) ? stdout : Buffer.from(stdout);
  } finally {
    cleanupAskpassScript(scriptPath);
  }
}
