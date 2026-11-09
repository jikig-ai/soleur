// Shared invocation for host-side git: git that the SERVER runs (outside the agent sandbox, with its own
// process environment) in a workspace whose `.git` an agent session can author. Ref #9601; follow-on to the
// git-read hardening. See the ADR-050 2026-11-09 amendment for what this does and does not close.
//
// A LEAF on purpose: it imports `node:os` and the hardening constants only, so every consumer (session-sync,
// ensure-workspace-repo, git-data replication, git-auth, inflight-checkpoint) can take it without dragging
// observability, cron or agent-env modules into its graph.
//
// What it closes (measured, git 2.56): fsmonitor / hooks / `config.worktree` / attribute-file sources / commit
// signing / a `core.worktree` redirect / the local-exec transports (`uploadpack` on a local-path remote, `ext::`)
// and server-secret exposure to any helper that runs. What it does NOT close: `filter.*` and `merge.*.driver`
// helpers, repo-config remote / proxy / TLS rewriting, and a consumer's own auth variable. Those are pinned by
// RESIDUAL rows in test/host-git-consumers-real-git.test.ts. It does not isolate host-side git from the
// workspace `.git`; the only structural closure is the isolated-GIT_DIR path, which this file does not touch.
//
// Only `-c key=value` pairs and environment are used, never a new global option: the built image's git version is
// not measured here and an unknown global option exits 129 on git 2.38/2.39.
import { tmpdir } from "node:os";
import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "./inngest/functions/_git-hardening";

/**
 * The image-owned, identity-only global gitconfig (created by the Dockerfile; the agent sandbox binds it read-only).
 * It rides `GIT_CONFIG_GLOBAL` instead of `/dev/null` so a workspace with no local identity can still commit; a
 * workspace's own local identity still beats it (local > global).
 */
export const AGENT_GIT_GLOBAL_CONFIG = "/usr/local/share/soleur/agent.gitconfig";

export type BaseEnv = Readonly<Record<string, string | undefined>>;

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

// Passed through only when SET in the server's environment (it is not agent-writable). Production sets none of
// them today, so this is a no-op there; it keeps TLS / proxy behaviour unchanged if one is ever set.
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
//  - signing off: a planted `gpg.program` runs on `commit` under the shared arguments (measured).
const HOST_GIT_EXTRA_ARGS: readonly string[] = [
  "-c",
  "safe.bareRepository=explicit",
  "-c",
  "protocol.ext.allow=never",
  "-c",
  "commit.gpgsign=false",
  "-c",
  "tag.gpgsign=false",
];

export interface HostGitOpts {
  /**
   * The workspace root, for every working-tree command (omit for `clone` and `init`). Sets `GIT_WORK_TREE`: a
   * `core.worktree` in the repo config otherwise points git at ANOTHER directory (measured: `-c core.worktree=` does
   * not undo it, the environment variable does).
   */
  cwd?: string;
  /**
   * Merged AFTER the scrub: the call-site's own auth variables (`GIT_ASKPASS`, `GIT_INSTALLATION_TOKEN`,
   * `GIT_SSH_COMMAND`, author identity, a temp `GIT_INDEX_FILE`). Code-authored, never agent-authored.
   */
  extraEnv?: Readonly<Record<string, string>>;
  /**
   * `GIT_ALLOW_PROTOCOL`, REQUIRED by the two network arms (`https` for the installation-auth arm, `ssh` for the
   * key-auth arm) and omitted by the local-only consumers. Blocks a repo-config-switched local-exec transport.
   * It does not stop an https rewrite toward an attacker host (a RESIDUAL).
   */
  allowProtocol?: string;
  /** The global gitconfig (identity). Tests only; defaults to {@link AGENT_GIT_GLOBAL_CONFIG}. */
  globalConfig?: string;
}

export interface HostGitInvocation {
  args: string[];
  env: NodeJS.ProcessEnv;
}

/**
 * The argv and environment for one host-side git invocation. `args` is the hardening block followed by the
 * caller's own `args` (a caller that needs `-c credential.helper=` passes it inside `args`, after the block).
 */
export function hostGitInvocation(args: readonly string[], opts: HostGitOpts = {}): HostGitInvocation {
  const scrubbed = buildScrubbedEnv({}, process.env);
  const env: Record<string, string> = {
    ...scrubbed,
    PATH: absolutePath(scrubbed.PATH),
    ...GIT_HARDENING_ENV,
    GIT_CONFIG_GLOBAL: opts.globalConfig ?? AGENT_GIT_GLOBAL_CONFIG,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_TERMINAL_PROMPT: "0",
  };
  if (opts.cwd !== undefined) env.GIT_WORK_TREE = opts.cwd;
  if (opts.allowProtocol !== undefined) env.GIT_ALLOW_PROTOCOL = opts.allowProtocol;
  for (const key of PASSTHROUGH_KEYS) {
    const value = process.env[key];
    if (value !== undefined && value !== "") env[key] = value;
  }
  Object.assign(env, opts.extraEnv);
  return { args: [...GIT_HARDENING_ARGS, ...HOST_GIT_EXTRA_ARGS, ...args], env: env as NodeJS.ProcessEnv };
}
