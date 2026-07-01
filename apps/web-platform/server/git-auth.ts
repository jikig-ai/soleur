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
 * Write the fixed-body askpass script to a unique path UNDER `dir`,
 * mode `0o700`, returning the absolute path. The caller owns cleanup via
 * `cleanupAskpassScript`.
 *
 * The script body is byte-identical across invocations (single-sourced from
 * `ASKPASS_SCRIPT_BODY`) — the token is read from the child process's
 * `GIT_INSTALLATION_TOKEN` env var, NOT interpolated into the file, so no
 * shell escaping is required regardless of token contents and the token never
 * lands on disk.
 *
 * `filename` defaults to a dot-prefixed `.askpass-<uuid>.sh` (the server-side
 * `$HOME` path uses this — unique per invocation, never collides). The cc
 * in-sandbox path passes a FIXED name and writes into the repo's `.git/`
 * directory so the helper is reused per workspace (no per-dispatch
 * accumulation, concurrency-safe — the body is identical and token-free) and
 * can never be staged by `git add` (`.git/` is outside the working tree). The
 * server-side `gitWithInstallationAuth` path writes to `$HOME` via
 * `writeAskpassScript()` below, which delegates here so the body stays
 * single-sourced (drift-free).
 */
export function writeAskpassScriptTo(dir: string, filename?: string): string {
  const scriptPath = join(dir, filename ?? `.askpass-${randomUUID()}.sh`);
  writeFileSync(scriptPath, ASKPASS_SCRIPT_BODY, { mode: 0o700 });
  return scriptPath;
}

/**
 * Write a fixed-body askpass script to a unique path in $HOME (server-side
 * `gitWithInstallationAuth` path). Delegates to `writeAskpassScriptTo` so the
 * body is single-sourced. Returns the absolute path; caller owns cleanup.
 */
export function writeAskpassScript(): string {
  return writeAskpassScriptTo(getAskpassDir());
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
 * Unwrap a `users.repo_error` cell into a `{ errorMessage, errorCode }` pair.
 *
 * New writes (`/api/repo/setup`) store a JSON string of
 * `{ code, message, timestamp }` where `message` is already sanitized
 * (`sanitizeGitStderr` is applied at the write boundary). Legacy rows
 * (pre-errorCode migration) hold plain stderr — those return
 * `{ errorMessage: <raw>, errorCode: undefined }` so the UI falls back to its
 * generic copy. The `code` is allowlist-validated via `isGitErrorCode` so an
 * unknown/typo'd value coerces to `undefined` rather than rendering a blank
 * headline from a missing ERROR_COPY key.
 *
 * Shared by the `/api/repo/status` read route AND the Concierge dispatch
 * readiness gate (`server/repo-readiness.ts`) so both consume ONE sanitizer —
 * no inline re-derivation, no drift in the allowlist (#5394).
 */
export function parseErrorPayload(raw: string | null | undefined): {
  errorMessage: string | null;
  errorCode: GitErrorCode | undefined;
} {
  if (!raw) return { errorMessage: null, errorCode: undefined };
  try {
    const parsed = JSON.parse(raw) as {
      code?: unknown;
      message?: unknown;
    };
    const code = isGitErrorCode(parsed.code) ? parsed.code : undefined;
    const message =
      typeof parsed.message === "string" ? parsed.message : raw;
    return { errorMessage: message, errorCode: code };
  } catch {
    // Legacy row: plain stderr string.
    return { errorMessage: raw, errorCode: undefined };
  }
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

/**
 * Run `git` with a private SSH key — the transport for the git-data bare store
 * over the private net (epic #5274 Phase 2, ADR-068 §1 amendment 2026-07-01).
 *
 * The SSH transport sibling of {@link gitWithInstallationAuth} (which is HTTPS +
 * GitHub-App token). Used for the `git push git-data` replication push (carrying
 * the `--push-option=lease-gen` fence options) and the git-data clone, both gated
 * behind `isGitDataStoreEnabled()`. The web host reads the key from Doppler `prd`
 * (`GIT_TRANSPORT_SSH_PRIVATE_KEY`) and passes the material in; the git-data host
 * accepts it under a `git-shell`-restricted forced-command.
 *
 * Key handling mirrors the askpass discipline:
 *   - the key NEVER appears in argv — it is delivered via `GIT_SSH_COMMAND -i`
 *     pointing at a 0600 temp file, removed in `finally`;
 *   - `StrictHostKeyChecking=accept-new` + a per-invocation throwaway
 *     `UserKnownHostsFile` is the Phase-2 private-net trust floor (TOFU; the host
 *     may be replaced during fence iteration, so cross-invocation host-key pinning
 *     is deliberately NOT used — per-`workspace_id` mTLS is the Phase-3 control,
 *     ADR-068 §6). `BatchMode=yes` so a host-key/auth problem fails deterministically
 *     instead of hanging on a prompt.
 *
 * @param args  git subcommand + flags (helper resets are prepended automatically)
 * @param privateKey  the OpenSSH-format private key material (from Doppler)
 * @param opts  cwd + timeout passthrough
 * @returns the stdout Buffer from the git invocation
 */
export async function gitWithPrivateKeyAuth(
  args: string[],
  privateKey: string,
  opts: GitExecOptions = {},
): Promise<Buffer> {
  const dir = getAskpassDir();
  const keyPath = join(dir, `.git-transport-${randomUUID()}.key`);
  const knownHostsPath = join(dir, `.git-transport-${randomUUID()}.known_hosts`);

  try {
    // 0600 + a trailing newline (OpenSSH rejects a key file missing the final LF).
    // BOTH writes live inside the try so a throw on the SECOND write still reaches
    // the finally cleanup for the first (0600 key) file (#5817 security review P3).
    writeFileSync(keyPath, privateKey.endsWith("\n") ? privateKey : `${privateKey}\n`, {
      mode: 0o600,
    });
    writeFileSync(knownHostsPath, "", { mode: 0o600 });

    const sshCommand = [
      "ssh",
      "-i",
      keyPath,
      "-o",
      "IdentitiesOnly=yes",
      "-o",
      "StrictHostKeyChecking=accept-new",
      "-o",
      `UserKnownHostsFile=${knownHostsPath}`,
      "-o",
      "BatchMode=yes",
    ].join(" ");

    const fullArgs = [...HELPER_RESET, ...args];
    const env: NodeJS.ProcessEnv = {
      ...process.env,
      GIT_SSH_COMMAND: sshCommand,
      GIT_TERMINAL_PROMPT: "0",
      GIT_TERMINAL_PROGRESS: "0",
      GIT_CONFIG_NOSYSTEM: "1",
      GIT_CONFIG_GLOBAL: "/dev/null",
    };

    const { stdout } = await execFileAsync("git", fullArgs, {
      ...opts,
      env,
      maxBuffer: 10 * 1024 * 1024,
    });
    return Buffer.isBuffer(stdout) ? stdout : Buffer.from(stdout);
  } finally {
    for (const p of [keyPath, knownHostsPath]) {
      try {
        unlinkSync(p);
      } catch {
        // best-effort cleanup; a leaked 0600 temp key is bounded by the
        // throwaway filename and the runtime user's $HOME.
      }
    }
  }
}

/**
 * Run a raw `ssh` command against the git-data host with a private SSH key — the
 * transport for the **bare-repo provisioning** path (epic #5274 Phase 2, ADR-068
 * amendment 2026-07-01 "PR B bare-repo provisioning").
 *
 * Distinct from {@link gitWithPrivateKeyAuth} in two ways: (1) it invokes `ssh`
 * directly (not `git`), because the git-data host's PROVISION key is bound to a
 * FIXED forced command (`/usr/local/bin/git-data-provision.sh`) that ignores the
 * requested command and reads its single argument from `SSH_ORIGINAL_COMMAND`;
 * (2) it uses the SEPARATE provision key (`GIT_PROVISION_SSH_PRIVATE_KEY`), never
 * the git-shell transport key — provisioning authority and ref-write authority are
 * separate credentials with separate blast radii (ADR-068 §6: never a cluster-wide
 * cred). The forced command validates the arg server-side (never `eval`'d), so
 * `remoteCommand` is passed as ONE opaque argv element.
 *
 * Key handling mirrors {@link gitWithPrivateKeyAuth}: the key NEVER appears in
 * argv (delivered via `-i` at a 0600 temp file, removed in `finally`);
 * `StrictHostKeyChecking=accept-new` + a per-invocation throwaway
 * `UserKnownHostsFile` is the Phase-2 private-net trust floor (TOFU); `BatchMode=yes`
 * so an auth/host-key problem fails deterministically instead of hanging.
 *
 * @param host  the git-data host (private-net address, e.g. `10.0.1.20`)
 * @param remoteCommand  the single opaque argument delivered as `SSH_ORIGINAL_COMMAND`
 *   (the validated `workspace_id` — the forced command ignores the command word)
 * @param privateKey  the OpenSSH-format provision private key (from Doppler)
 * @param opts  cwd + timeout passthrough
 * @returns the stdout Buffer from the ssh invocation
 */
export async function sshWithPrivateKeyAuth(
  host: string,
  remoteCommand: string,
  privateKey: string,
  opts: GitExecOptions = {},
): Promise<Buffer> {
  const dir = getAskpassDir();
  const keyPath = join(dir, `.git-provision-${randomUUID()}.key`);
  const knownHostsPath = join(dir, `.git-provision-${randomUUID()}.known_hosts`);

  try {
    // 0600 + a trailing newline (OpenSSH rejects a key file missing the final LF).
    // BOTH writes live inside the try so a throw on the SECOND write still reaches
    // the finally cleanup for the first (0600 key) file (#5817 security review P3).
    writeFileSync(keyPath, privateKey.endsWith("\n") ? privateKey : `${privateKey}\n`, {
      mode: 0o600,
    });
    writeFileSync(knownHostsPath, "", { mode: 0o600 });

    const sshArgs = [
      "-i",
      keyPath,
      "-o",
      "IdentitiesOnly=yes",
      "-o",
      "StrictHostKeyChecking=accept-new",
      "-o",
      `UserKnownHostsFile=${knownHostsPath}`,
      "-o",
      "BatchMode=yes",
      `git@${host}`,
      // ONE opaque argv element → SSH_ORIGINAL_COMMAND. The forced command
      // validates it server-side and never eval's it (no shell-injection surface).
      remoteCommand,
    ];

    const { stdout } = await execFileAsync("ssh", sshArgs, {
      ...opts,
      env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
      maxBuffer: 10 * 1024 * 1024,
    });
    return Buffer.isBuffer(stdout) ? stdout : Buffer.from(stdout);
  } finally {
    for (const p of [keyPath, knownHostsPath]) {
      try {
        unlinkSync(p);
      } catch {
        // best-effort cleanup; a leaked 0600 temp key is bounded by the
        // throwaway filename and the runtime user's $HOME.
      }
    }
  }
}
