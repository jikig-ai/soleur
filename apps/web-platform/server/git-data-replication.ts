// Git-data replication transport — epic #5274 Phase 2 PR B part 2 / ADR-068
// (#5817). The app-server-side push of a workspace's refs to the shared git-data
// bare store over the private net, fenced by the git-data host's `pre-receive`
// CAS hook (ADR-068 §3). Every export here is a NO-OP when
// `isGitDataStoreEnabled()` is false — the whole transport is dark-launched and
// inert at flag-off (the flag ships OFF; PR C flips it at cutover).
//
// Two credentials, two authorities (ADR-068 §6 + the 2026-07-01 "bare-repo
// provisioning" amendment):
//   - GIT_PROVISION_SSH_PRIVATE_KEY → the FIXED forced command `git-data-provision.sh`
//     that idempotently `git init --bare`s the per-workspace repo (bare repos are
//     NOT auto-created by `git-receive-pack`, so provisioning MUST precede the
//     first push);
//   - GIT_TRANSPORT_SSH_PRIVATE_KEY → the git-shell transport that carries the
//     `git push` the fence guards.
// The push-options (`lease-gen`, `worktree-id`) attach to the git-data push ONLY,
// never to the GitHub `origin`/`syncPush` push (GitHub runs no fence hook).

import { execFileSync } from "child_process";
import { createChildLogger } from "./logger";
import { isGitDataStoreEnabled } from "./workspace-resolver";
import { gitWithPrivateKeyAuth, sshWithPrivateKeyAuth } from "./git-auth";
import { reportSilentFallback } from "./observability";
import { WORKTREE_ID_PRIMARY } from "./worktree-write-lease";

const log = createChildLogger("git-data-replication");

// The bare-repo root the git-data host exposes to the git-shell transport. The
// bootstrap symlinks `/home/git/repositories → /mnt/git-data/repositories`, so a
// URL path of `/repositories/<id>.git` resolves — through the transport (relative
// to /home/git) AND the provision wrapper (absolute /mnt/...) — to the identical
// `$GIT_DIR` the fence keys on (git-data-bootstrap.sh + the ADR provisioning
// amendment's "repo-root reconcile" note).
const GIT_DATA_REPO_PATH_PREFIX = "/repositories";

// workspace_id names a repo path + a fence sidecar file on the git-data host, so
// it must be an opaque safe token. It is an app-generated UUID
// (`basename(workspacePath)`), but every boundary re-validates — the resource
// server never trusts the client (CWE-22, mirrors git-data-pre-receive.sh:92-96
// and git-data-provision.sh).
const WORKSPACE_ID_RE = /^[A-Za-z0-9._-]+$/;

/**
 * The web host's view of the git-data host address (private net). Surfaced as
 * app config (`GIT_DATA_SSH_HOST`) — the address otherwise lives only in
 * `infra/network.tf`. FAIL-LOUD in production when unset (mirrors
 * {@link resolveHostId} in host-identity.ts): silently defaulting could push a
 * workspace's objects at the wrong host. Dev/test returns the stable private-net
 * default so local runs need no env.
 */
export function resolveGitDataSshHost(): string {
  const host = process.env.GIT_DATA_SSH_HOST?.trim();
  if (host) return host;
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "GIT_DATA_SSH_HOST is unset in production — the git-data bare store " +
        "requires the git-data host's private-net address (10.0.1.20). Set it via " +
        "the Doppler prd secret; refusing to guess a replication target.",
    );
  }
  return "10.0.1.20"; // stable private-net default (network.tf); non-prod only
}

/**
 * Assert `workspaceId` is a safe opaque token before it names a remote-URL path
 * or an `SSH_ORIGINAL_COMMAND` argument. Throws (fail-loud) on any unsafe value —
 * defense-in-depth at the app boundary, on top of the host-side validation.
 */
export function assertSafeWorkspaceId(workspaceId: string): void {
  if (
    workspaceId === "" ||
    workspaceId === "." ||
    workspaceId === ".." ||
    workspaceId.includes("/") ||
    !WORKSPACE_ID_RE.test(workspaceId)
  ) {
    throw new Error(
      `git-data: refusing unsafe workspace_id '${workspaceId}' (must match ` +
        `${WORKSPACE_ID_RE} and not be a dot/slash path — CWE-22).`,
    );
  }
}

/** The `ssh://` URL of a workspace's bare repo on the git-data host. */
export function gitDataRemoteUrl(workspaceId: string): string {
  assertSafeWorkspaceId(workspaceId);
  const host = resolveGitDataSshHost();
  return `ssh://git@${host}${GIT_DATA_REPO_PATH_PREFIX}/${workspaceId}.git`;
}

function requireEnvKey(name: string): string {
  const key = process.env[name]?.trim();
  if (!key) {
    throw new Error(
      `git-data: ${name} is unset — cannot reach the git-data host. ` +
        `It is delivered to the container from Doppler prd.`,
    );
  }
  return key;
}

/**
 * Idempotently provision the per-workspace bare repo on the git-data host via the
 * dedicated provision key's forced command (`git-data-provision.sh`). The wrapper
 * ignores the requested command and reads `workspace_id` from
 * `SSH_ORIGINAL_COMMAND`; a re-provision is a server-side no-op. MUST run before
 * the first push (`git-receive-pack` never auto-creates its target).
 */
export async function provisionGitDataRepo(workspaceId: string): Promise<void> {
  if (!isGitDataStoreEnabled()) return;
  assertSafeWorkspaceId(workspaceId);
  const host = resolveGitDataSshHost();
  const provisionKey = requireEnvKey("GIT_PROVISION_SSH_PRIVATE_KEY");
  // The forced command receives `workspaceId` as SSH_ORIGINAL_COMMAND (one opaque
  // argv element); the requested command word is irrelevant.
  await sshWithPrivateKeyAuth(host, workspaceId, provisionKey, { timeout: 30_000 });
}

/**
 * Additively add (or re-point) the `git-data` remote on the workspace clone,
 * retaining `origin`→GitHub untouched (orphaning GitHub would collapse the
 * rehydration story — ADR-068 §1). Local-only git config; no network.
 */
export function ensureGitDataRemote(
  workspacePath: string,
  workspaceId: string,
): void {
  if (!isGitDataStoreEnabled()) return;
  const url = gitDataRemoteUrl(workspaceId);
  const opts = { cwd: workspacePath, stdio: "pipe" as const };
  try {
    // Idempotent: add if absent, else re-point (host address may change during
    // Phase-2 fence iteration).
    const existing = execFileSync("git", ["-C", workspacePath, "remote"], opts)
      .toString()
      .split("\n")
      .map((s) => s.trim());
    if (existing.includes("git-data")) {
      execFileSync("git", ["-C", workspacePath, "remote", "set-url", "git-data", url], opts);
    } else {
      execFileSync("git", ["-C", workspacePath, "remote", "add", "git-data", url], opts);
    }
  } catch (err) {
    // Surface (fail-loud) — an unconfigurable remote means the push below cannot
    // run; do not swallow.
    throw new Error(
      `git-data: failed to configure the git-data remote for ${workspaceId}: ` +
        `${err instanceof Error ? err.message : String(err)}`,
    );
  }
}

/**
 * Replicate the workspace's refs to the shared git-data bare store: provision →
 * ensure remote → fenced force-push carrying the lease generation. Called at the
 * session-end sync points on BOTH lineages (agent-runner `unregisterSession`
 * finally; cc `handleCcCloseQuery`). NO-OP at flag-off.
 *
 * FAIL-LOUD: a push failure — most importantly a **fence reject** (stale
 * `lease-gen < stored max`), which at replicas=1 can never arise but becomes
 * load-bearing at Phase 3's second writer — is mirrored to Sentry at ERROR under
 * `feature: "worktree_lease"`, never silently swallowed (cq-silent-fallback-must-
 * mirror-to-sentry). The error is re-thrown so the caller can decide; call sites
 * on the session-end path catch it so a replication failure never breaks the turn.
 */
export async function replicateToGitData(params: {
  workspacePath: string;
  workspaceId: string;
  leaseGeneration: number;
  userId?: string;
}): Promise<void> {
  if (!isGitDataStoreEnabled()) return;
  const { workspacePath, workspaceId, leaseGeneration, userId } = params;
  assertSafeWorkspaceId(workspaceId);

  try {
    await provisionGitDataRepo(workspaceId);
    ensureGitDataRemote(workspacePath, workspaceId);

    const transportKey = requireEnvKey("GIT_TRANSPORT_SSH_PRIVATE_KEY");
    // The git-data store is a REPLICA of the workspace refs — force so a
    // non-fast-forward on the shared store never blocks replication; the fence's
    // monotonic gen (NOT ref ancestry) is the ordering authority. Push-options
    // ride THIS push only, never origin/syncPush.
    await gitWithPrivateKeyAuth(
      [
        "push",
        "--force",
        "git-data",
        "refs/heads/*:refs/heads/*",
        `--push-option=lease-gen=${leaseGeneration}`,
        `--push-option=worktree-id=${WORKTREE_ID_PRIMARY}`,
      ],
      transportKey,
      { cwd: workspacePath, timeout: 60_000 },
    );
    log.info({ workspaceId, leaseGeneration }, "git-data replication push complete");
  } catch (err) {
    reportSilentFallback(err, {
      feature: "worktree_lease",
      op: "git_data_replication_push",
      extra: { workspaceId, leaseGeneration, ...(userId ? { userId } : {}) },
      message:
        "git-data replication push failed — a fence reject (stale lease-gen) or " +
        "transport error; the workspace's objects were NOT replicated to the shared store",
    });
    throw err instanceof Error ? err : new Error(String(err));
  }
}
