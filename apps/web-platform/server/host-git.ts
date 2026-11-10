// Shared invocation for host-side git: git that the SERVER runs (outside the agent sandbox, with its own
// process environment) in a workspace whose `.git` an agent session can author. Ref #9601; follow-on to the
// git-read hardening. See the ADR-050 2026-11-09 amendment for what this does and does not close.
//
// A LEAF on purpose: it imports `node:os`, `node:fs`, `node:path` and the hardening constants only, so every consumer
// (session-sync, ensure-workspace-repo, git-data replication, git-auth, inflight-checkpoint, workspace provisioning,
// context queries) can take it without dragging observability, cron or agent-env modules into its graph.
//
// What it closes (measured, git 2.56): fsmonitor / hooks / `config.worktree` / `core.attributesFile` / commit signing /
// a `core.worktree` redirect / a `.git` that is a gitfile, a symlink or carries `commondir` (refused) / the local-exec
// transports (`uploadpack` on a local-path or promisor remote, `ext::`, `core.alternateRefsCommand`). The scrubbed
// environment hides secrets from a helper that reads ONLY ITS OWN environment; it gives no secrecy against a helper
// that reads the server's `/proc/<pid>/environ` (same uid), so any executing carrier is a full same-uid compromise.
// What it does NOT close: `filter.*` and `merge.*.driver` helpers, `.git/info/attributes`, repo-config remote / proxy /
// TLS rewriting, and a consumer's own auth variable. Those are pinned by RESIDUAL rows in
// test/host-git-consumers-real-git.test.ts. It does not isolate host-side git from the workspace `.git`; the only
// structural closure is the isolated-GIT_DIR path, which this file does not touch.
//
// Only `-c key=value` pairs and environment are used, never a new global option: the built image's git version is
// not measured here and an unknown global option exits 129 on git 2.38/2.39.
import { lstatSync } from "node:fs";
import { tmpdir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";
import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "./inngest/functions/_git-hardening";

/**
 * The image-owned, identity-only global gitconfig (created by the Dockerfile; the agent sandbox binds it read-only).
 * It rides `GIT_CONFIG_GLOBAL` instead of `/dev/null` so a workspace with no local identity can still commit; a
 * workspace's own local identity still beats it (local > global).
 */
export const AGENT_GIT_GLOBAL_CONFIG = "/usr/local/share/soleur/agent.gitconfig";

export type BaseEnv = Readonly<Record<string, string | undefined>>;

/** `GIT_ALLOW_PROTOCOL` for a call that must never open a network or local-exec transport (local-only consumers). */
export const ALLOW_PROTOCOL_NONE = "none";

/** Thrown when a call is refused before git runs. The message never carries a path (it is mirrored to Sentry). */
export class HostGitRefusedError extends Error {
  constructor(readonly reason: "git-dir-shape" | "cwd" | "extra-env") {
    super(`host git refused: ${reason}`);
    this.name = "HostGitRefusedError";
  }
}

// The only variables a call-site may add. Anything else (a protected helper-owned name, an unknown GIT_ name, a
// secret-shaped name) is refused, so a caller cannot undo `GIT_CONFIG_GLOBAL`, `GIT_DIR`, `GIT_ALLOW_PROTOCOL` etc.
const ALLOWED_EXTRA_ENV: ReadonlySet<string> = new Set([
  "GIT_ASKPASS",
  "GIT_INSTALLATION_TOKEN",
  "GIT_USERNAME",
  "GIT_SSH_COMMAND",
  "GIT_TERMINAL_PROMPT",
  "GIT_TERMINAL_PROGRESS",
  "GIT_INDEX_FILE",
  "GIT_AUTHOR_NAME",
  "GIT_AUTHOR_EMAIL",
  "GIT_AUTHOR_DATE",
  "GIT_COMMITTER_NAME",
  "GIT_COMMITTER_EMAIL",
  "GIT_COMMITTER_DATE",
]);

// Names an extra may never carry: anything secret-shaped, a GitHub/Anthropic/Doppler credential namespace, or a git
// location variable (a git child honours GIT_DIR over cwd and -C).
const FORBIDDEN_EXTRA_RE = /TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|API_?KEY|PRIVATE|^GH_|^GITHUB_|^ANTHROPIC|^DOPPLER|^GIT_/i;
const EXTRA_NAME_RE = /^[A-Z][A-Z0-9_]*$/;

/**
 * The environment of a scrubbed child. An ALLOWLIST from the base environment (PATH, LANG, LC_ALL, TMPDIR, HOME)
 * plus explicit extras; nothing else is inherited, so no installation token, API key or Doppler credential can
 * reach a helper that runs in a clone. HOME is NOT the real home (no `~/.config/gh`, no git config): it is the
 * temp dir.
 */
export function buildScrubbedEnv(extra: Readonly<Record<string, string>>, base: BaseEnv = process.env): Record<string, string> {
  const env: Record<string, string> = {
    PATH: base.PATH ?? "/usr/bin:/bin",
    LANG: base.LANG ?? "C.UTF-8",
    LC_ALL: "C.UTF-8",
    TMPDIR: tmpdir(),
    HOME: tmpdir(),
  };
  for (const [name, value] of Object.entries(extra)) {
    if (!EXTRA_NAME_RE.test(name) || FORBIDDEN_EXTRA_RE.test(name) || typeof value !== "string" || value.includes("\u0000")) {
      throw new Error("scrubbed env: refused an extra variable");
    }
    env[name] = value;
  }
  return env;
}

// Passed through only on the https arm and only when SET in the server's environment (it is not agent-writable).
// Production sets none of them today, so this is a no-op there; it keeps TLS / proxy behaviour unchanged if one is ever set.
const PASSTHROUGH_KEYS = [
  "SSL_CERT_FILE",
  "SSL_CERT_DIR",
  "GIT_SSL_CAINFO",
  "HTTPS_PROXY",
  "https_proxy",
  "NO_PROXY",
  "no_proxy",
] as const;

/** Drop empty and non-absolute PATH entries: an empty entry means the current directory, which is the workspace. */
function absolutePath(path: string): string {
  const kept = path.split(":").filter((entry) => entry.startsWith("/"));
  return kept.length > 0 ? kept.join(":") : "/usr/bin:/bin";
}

// Helper-only arguments (the shared `GIT_HARDENING_ARGS` is not edited):
//  - `safe.bareRepository=explicit`: a bare repository committed into a workspace is a working config carrier;
//  - `protocol.ext.allow=never`: repo config can switch the `ext::` transport on, which runs a shell on fetch;
//  - signing off: a planted `gpg.program` runs on `commit` under the shared arguments (measured);
//  - `core.alternateRefsCommand=` (empty): with `objects/info/alternates`, a planted command runs on fetch (measured).
const HOST_GIT_EXTRA_ARGS: readonly string[] = [
  "-c",
  "safe.bareRepository=explicit",
  "-c",
  "protocol.ext.allow=never",
  "-c",
  "commit.gpgsign=false",
  "-c",
  "tag.gpgsign=false",
  "-c",
  "core.alternateRefsCommand=",
];

export interface HostGitOpts {
  /**
   * The workspace root, for every working-tree command (omit for `clone` and `init`; a `cwd` with those is refused).
   * Must be absolute. Sets `GIT_WORK_TREE`, `GIT_DIR` and `GIT_COMMON_DIR` to the workspace itself: a `core.worktree`
   * in the repo config otherwise points git at ANOTHER directory (measured: `-c core.worktree=` does not undo it, the
   * environment variable does), and a `.git` gitfile, symlink or `commondir` points it at another repository's store.
   * Those three shapes are refused (see {@link HostGitRefusedError}); an absent `.git` is not refused here, git fails
   * closed on the missing `GIT_DIR`.
   */
  cwd?: string;
  /**
   * Merged AFTER the scrub: the call-site's own auth variables (`GIT_ASKPASS`, `GIT_INSTALLATION_TOKEN`,
   * `GIT_SSH_COMMAND`, author identity, a temp `GIT_INDEX_FILE`). Code-authored, never agent-authored. Only the names in
   * the allowlist above are accepted; any other name throws.
   */
  extraEnv?: Readonly<Record<string, string>>;
  /**
   * `GIT_ALLOW_PROTOCOL`, REQUIRED on every call: `https` for the installation-auth arm, `ssh` for the key-auth arm,
   * {@link ALLOW_PROTOCOL_NONE} for every local-only consumer. Blocks a repo-config-switched local-exec transport,
   * including a promisor remote or a `file` remote reached from a local verb. It does not stop an https rewrite toward
   * an attacker host (a RESIDUAL).
   */
  allowProtocol: string;
  /** The global gitconfig (identity). Tests only; defaults to {@link AGENT_GIT_GLOBAL_CONFIG}. */
  globalConfig?: string;
}

export interface HostGitInvocation {
  args: string[];
  env: NodeJS.ProcessEnv;
}

function firstSubcommand(args: readonly string[]): string | undefined {
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "-C" || a === "-c") {
      i++;
      continue;
    }
    if (a.startsWith("-")) continue;
    return a;
  }
  return undefined;
}

function enoent(err: unknown): boolean {
  return typeof err === "object" && err !== null && (err as { code?: string }).code === "ENOENT";
}

/**
 * Refuse a workspace whose `.git` is not a plain directory (a gitfile or a symlink points at another repository) or
 * carries a `commondir` (objects, refs and config then come from another repository). An absent `.git` passes: the
 * pinned `GIT_DIR` then names a path that does not exist and git fails closed. A preflight, not a structural control:
 * a write between this check and the git call is not covered.
 */
export function assertWorkspaceGitShape(cwd: string): void {
  const gitDir = join(cwd, ".git");
  try {
    const st = lstatSync(gitDir);
    if (st.isSymbolicLink() || !st.isDirectory()) throw new HostGitRefusedError("git-dir-shape");
  } catch (err) {
    if (err instanceof HostGitRefusedError) throw err;
    if (enoent(err)) return;
    throw new HostGitRefusedError("git-dir-shape");
  }
  try {
    lstatSync(join(gitDir, "commondir"));
  } catch (err) {
    if (enoent(err)) return;
    throw new HostGitRefusedError("git-dir-shape");
  }
  throw new HostGitRefusedError("git-dir-shape");
}

/**
 * The argv and environment for one host-side git invocation. `args` is the hardening block followed by the
 * caller's own `args` (a caller that needs `-c credential.helper=` passes it inside `args`, after the block).
 */
export function hostGitInvocation(args: readonly string[], opts: HostGitOpts): HostGitInvocation {
  const scrubbed = buildScrubbedEnv({}, process.env);
  const env: Record<string, string> = {
    ...scrubbed,
    PATH: absolutePath(scrubbed.PATH),
    ...GIT_HARDENING_ENV,
    GIT_CONFIG_GLOBAL: opts.globalConfig ?? AGENT_GIT_GLOBAL_CONFIG,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_TERMINAL_PROMPT: "0",
    GIT_ALLOW_PROTOCOL: opts.allowProtocol,
  };
  if (opts.cwd !== undefined) {
    if (opts.cwd === "" || !isAbsolute(opts.cwd)) throw new HostGitRefusedError("cwd");
    const sub = firstSubcommand(args);
    if (sub === "clone" || sub === "init") throw new HostGitRefusedError("cwd");
    const cwd = resolve(opts.cwd);
    assertWorkspaceGitShape(cwd);
    env.GIT_WORK_TREE = cwd;
    env.GIT_DIR = join(cwd, ".git");
    env.GIT_COMMON_DIR = join(cwd, ".git");
  }
  // TLS / proxy keys only on the https arm: nothing else dials a proxy or reads a CA bundle.
  if (opts.allowProtocol === "https") {
    for (const key of PASSTHROUGH_KEYS) {
      const value = process.env[key];
      if (value !== undefined && value !== "") env[key] = value;
    }
  }
  for (const [name, value] of Object.entries(opts.extraEnv ?? {})) {
    if (!ALLOWED_EXTRA_ENV.has(name) || typeof value !== "string" || value.includes("\u0000")) {
      throw new HostGitRefusedError("extra-env");
    }
    env[name] = value;
  }
  return { args: [...GIT_HARDENING_ARGS, ...HOST_GIT_EXTRA_ARGS, ...args], env: env as NodeJS.ProcessEnv };
}
