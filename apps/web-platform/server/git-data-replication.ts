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
import { assertSafeWorktreeId } from "./worktree-write-lease";
// D2 write-boundary sentinel (ADR-068 §6, epic #5274 Sub-PR 3.C). The membership
// authority is shared with the fetch side (git-data-client.ts) so a single check
// gates both directions. Imported for call-time use only — the two modules form a
// runtime-safe ESM cycle (git-data-client → gitDataRemoteUrl/assertSafeWorkspaceId
// here; here → authorizeGitDataAccess there); neither is referenced at module-eval.
import { authorizeGitDataAccess, GitDataAuthorizationError } from "./git-data-client";

const log = createChildLogger("git-data-replication");

// The bare-repo root the git-data host exposes to the git-shell transport. The
// bootstrap symlinks `/home/git/repositories → /mnt/git-data/repositories`, so a
// URL path of `/repositories/<id>.git` resolves — through the transport (relative
// to /home/git) AND the provision wrapper (absolute /mnt/...) — to the identical
// `$GIT_DIR` the fence keys on (git-data-bootstrap.sh + the ADR provisioning
// amendment's "repo-root reconcile" note).
const GIT_DATA_REPO_PATH_PREFIX = "/repositories";

// --- (#6982, W6) Client-side concurrency limiter -------------------------------------
//
// The git-data host is 2 vCPU / 4 GB with no swap, and every session end fires a
// provision+push pair at it. sshd there is now bounded (MaxStartups/MaxSessions), but a
// server-side bound expresses itself as REFUSED CONNECTIONS — the client should not be
// the thing that discovers that. This caps what we send.
//
// `server/concurrency.ts`'s `acquireSlot` is deliberately NOT reused: it is a DB-backed
// workspace-slot primitive with its own lease semantics, not an in-process semaphore, and
// borrowing it would put a database round-trip on the session-end path to solve a
// process-local problem.
//
// FAIL-SOFT ON TIMEOUT, and that is the whole design. git-data is an OVERLAY
// (ensure-workspace-repo.ts: "an OVERLAY, not a hard dependency"), so a queue that BLOCKS
// session end would convert a capacity limit into a user-visible hang — strictly worse
// than the replication lag it is trying to prevent. On timeout we SHED, and the shed is
// reported so it is a measurable event rather than a silent gap.
const _mc = Number(process.env.GIT_DATA_MAX_CONCURRENT ?? "2");
const GIT_DATA_MAX_CONCURRENT = Math.max(1, Number.isFinite(_mc) ? _mc : 2);
// `?? "120000"` then Number(), with NO `|| default`: `Number("0")` is 0, which is falsy, so
// a `||` fallback makes 0 UNSETTABLE — in production and in tests, where "use a zero-length
// window" silently ran the full production timeout instead.
//
// 120 s, not 10 s. A slot is held for the whole provision+push (30 s + 60 s worst case), so
// a 10 s queue window meant the third concurrent session-end shed with near-certainty — the
// queue could essentially never grant a slot. That matters more here than latency: git-data
// holds the SOLE copy of the delta between a user's last GitHub push and their worktree, and
// replication is session-end-coupled, so a shed is not lag — it is that delta never being
// written unless the same user happens to open another session.
const _qt = Number(process.env.GIT_DATA_QUEUE_TIMEOUT_MS ?? "120000");
const GIT_DATA_QUEUE_TIMEOUT_MS = Number.isFinite(_qt) && _qt >= 0 ? _qt : 120_000;

let gitDataInFlight = 0;
const gitDataWaiters: Array<() => void> = [];

/** Test-only view of the live counter, so a test can assert the bound rather than infer it. */
export function __gitDataInFlightForTest(): number {
  return gitDataInFlight;
}

/**
 * Acquire a replication slot. Resolves `true` when a slot was taken, `false` when the
 * caller should SHED (queue timed out). Never rejects and never blocks indefinitely.
 */
async function acquireGitDataSlot(): Promise<boolean> {
  if (gitDataInFlight < GIT_DATA_MAX_CONCURRENT) {
    gitDataInFlight++;
    return true;
  }
  return await new Promise<boolean>((resolve) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      // Drop our waiter so a later release does not hand a slot to a caller that has
      // already given up — that would leak the counter and permanently shrink the pool.
      const i = gitDataWaiters.indexOf(grant);
      if (i !== -1) gitDataWaiters.splice(i, 1);
      resolve(false);
    }, GIT_DATA_QUEUE_TIMEOUT_MS);
    function grant() {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      gitDataInFlight++;
      resolve(true);
    }
    gitDataWaiters.push(grant);
  });
}

function releaseGitDataSlot(): void {
  gitDataInFlight = Math.max(0, gitDataInFlight - 1);
  const next = gitDataWaiters.shift();
  if (next) next();
}

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
 * Art. 17 (right to erasure) — tear down the per-workspace bare repo on the
 * git-data host (epic #5274 Sub-PR 3.D, CLO DL-1 / Kieran P0-1 / AC9). Dials the
 * dedicated REMOVE forced command (`git-data-remove.sh`, shipped by 3.A cloud-init)
 * with its own key — a THIRD authority distinct from provision/transport, so a
 * transport-key compromise cannot delete repos. The wrapper reads `workspaceId`
 * from `SSH_ORIGINAL_COMMAND` (one opaque argv element) and canonicalizes it
 * host-side (CWE-22). NO-OP when the store is disabled — at flag-off there is no
 * git-data repo to erase (the working tree is purged by `deleteWorkspace`).
 *
 * Called from the account/workspace deletion path (best-effort, mirroring the
 * chat-attachments purge) so the shared-store copy is erased alongside the
 * host-local working tree — closing the DL-1 bare-repo erasure gap.
 */
export async function removeGitDataRepo(workspaceId: string): Promise<void> {
  assertSafeWorkspaceId(workspaceId);
  // NOT gated on isGitDataStoreEnabled() (data-integrity review LOW): a bare repo
  // provisioned during a flag-ON window PERSISTS on the git-data host after a
  // rollback flips the flag OFF (dual-existence). Gating erasure on the LIVE flag
  // would silently strand that user's PII — an Art. 17 gap in exactly the
  // rollback/cutover window this epic introduces. Gate instead on whether the
  // REMOVE key is configured: absent ⇒ this env never had git-data (nothing to
  // erase, skip silently — no Sentry noise on every delete in a non-git-data env);
  // present ⇒ the store is (or was) in play, so attempt the erase regardless of the
  // flag. The host-side wrapper is idempotent — a remove of a non-existent repo is
  // a no-op — so an over-eager call is harmless.
  const removeKey = process.env.GIT_REMOVE_SSH_PRIVATE_KEY?.trim();
  if (!removeKey) return;
  const host = resolveGitDataSshHost();
  await sshWithPrivateKeyAuth(host, workspaceId, removeKey, { timeout: 30_000 });
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
 * Replicate the workspace's branch + tag refs to the shared git-data bare store:
 * provision → ensure remote → fenced force-push carrying the lease generation.
 * Called at the session-end sync points on BOTH lineages (agent-runner
 * `unregisterSession` finally; cc `handleCcCloseQuery`). NO-OP at flag-off.
 *
 * Session-end-coupled, NOT drain-coupled: the SIGTERM lease-drain deliberately
 * skips replication (it must fit the 8s shutdown budget). A crash/shutdown mid-
 * session leaves git-data at most one turn behind; the next session force-pushes
 * every head + tag, so the replica self-heals. Safe because git-data is a
 * write-only replica here (the read-source flag defaults to the volume until PR C).
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
  /**
   * The PER-USER worktree id (ADR-068 D0 amendment) that owns this push's ref
   * namespace + fence generation stream. Each user pushes ONLY to
   * `refs/soleur/worktrees/<worktreeId>/…`, so `--force` never clobbers a peer
   * user's commits under a 2nd writer. Required — a missing/hardcoded worktree
   * id would re-pin the workspace to one fence stream (Sharp Edge).
   */
  worktreeId: string;
  leaseGeneration: number;
  /**
   * The session user on whose behalf the push runs. MANDATORY + authorizing when
   * `isGitDataStoreEnabled()` (D2 resolution, `hr-write-boundary-sentinel-sweep-all-write-sites`):
   * the push is refused unless this user is a member of `workspaceId`, keyed on the
   * EXACT `workspaceId` that builds the push URL (no re-derivation). Closes the
   * logic-bug cross-tenant WRITE (TS-1). Both call sites (agent-runner,
   * cc-dispatcher) already thread the session userId.
   */
  userId: string;
}): Promise<void> {
  if (!isGitDataStoreEnabled()) return;
  const { workspacePath, workspaceId, worktreeId, leaseGeneration, userId } = params;
  assertSafeWorkspaceId(workspaceId);
  assertSafeWorktreeId(worktreeId);

  // D2 write-boundary sentinel — authorize BEFORE any provision/remote/push so a
  // cross-tenant write never touches the transport. Fail-closed: a non-member,
  // an indeterminate RPC, or a missing userId denies. The deny telemetry (security
  // vs error) is emitted inside authorizeGitDataAccess; throw here so the push is
  // skipped. Placed OUTSIDE the push try/catch below so a DENY is not mislabeled
  // as a generic "git_data_replication_push" transport failure.
  const authorized = await authorizeGitDataAccess({ userId, workspaceId, op: "write" });
  if (!authorized) {
    throw new GitDataAuthorizationError(
      "write",
      "not-member",
      `git-data push refused for workspace ${workspaceId} (membership denied — D2)`,
    );
  }

  // (#6982, W6) Bound what we send at a 2 vCPU host. Acquired AFTER the authorization
  // check so a denied write never consumes a slot, and released in `finally` below so a
  // throwing push cannot leak one.
  const slot = await acquireGitDataSlot();
  if (!slot) {
    // SHED — do not block session end. Reported rather than silently dropped: a shed is a
    // real capacity signal, and a gap nobody can see is indistinguishable from a bug
    // (cq-silent-fallback-must-mirror-to-sentry).
    reportSilentFallback(
      new Error(
        `git-data replication shed: ${GIT_DATA_MAX_CONCURRENT} slots busy for ` +
          `${GIT_DATA_QUEUE_TIMEOUT_MS}ms`,
      ),
      {
        feature: "git_data_replication",
        op: "queue_shed",
        tags: { limit: String(GIT_DATA_MAX_CONCURRENT) },
      },
    );
    log.warn(
      { workspaceId, limit: GIT_DATA_MAX_CONCURRENT },
      "git-data replication shed — queue timeout; session end is not blocked",
    );
    return;
  }

  try {
    await provisionGitDataRepo(workspaceId);
    ensureGitDataRemote(workspacePath, workspaceId);

    const transportKey = requireEnvKey("GIT_TRANSPORT_SSH_PRIVATE_KEY");
    // PER-USER NAMESPACED REFSPEC (ADR-068 D0-ref, epic #5274 Phase 3). Heads +
    // tags land under `refs/soleur/worktrees/<worktreeId>/` — this worktree is the
    // SOLE writer of its namespace, so `--force` never clobbers a PEER user's
    // commits under a 2nd writer (the pre-#3.B `refs/heads/*:refs/heads/*` --force
    // was safe only at replicas=1; under a 2nd writer it silently overwrote one
    // user's commits — the per-worktree fence guards monotonicity WITHIN a gen
    // stream, not last-writer-wins ACROSS streams). Cross-user visibility is
    // `git fetch <peer namespace>`; GitHub `origin/main` stays canonical
    // (rehydration intact). The git-data host's pre-receive enforces that
    // worktree-id=W may only write `refs/soleur/worktrees/W/` (namespace ownership).
    //
    // --force so a non-fast-forward WITHIN the user's own namespace never blocks
    // replication; the fence's monotonic gen (NOT ref ancestry) is the ordering
    // authority. Both heads + tags are carried so a local-only tag (never pushed
    // to GitHub origin, so uncovered by GitHub rehydration) still reaches the
    // durable replica — the ref-completeness the cutover's ref-set-equality check
    // depends on (#5817 review F1). NOT `--mirror`. Push-options ride THIS push
    // only, never origin/syncPush.
    await gitWithPrivateKeyAuth(
      [
        "push",
        "--force",
        "git-data",
        `refs/heads/*:refs/soleur/worktrees/${worktreeId}/heads/*`,
        `refs/tags/*:refs/soleur/worktrees/${worktreeId}/tags/*`,
        `--push-option=lease-gen=${leaseGeneration}`,
        `--push-option=worktree-id=${worktreeId}`,
      ],
      transportKey,
      { cwd: workspacePath, timeout: 60_000 },
    );
    log.info(
      { workspaceId, worktreeId, leaseGeneration },
      "git-data replication push complete",
    );
  } catch (err) {
    reportSilentFallback(err, {
      feature: "worktree_lease",
      op: "git_data_replication_push",
      extra: { workspaceId, leaseGeneration, userId },
      message:
        "git-data replication push failed — a fence reject (stale lease-gen) or " +
        "transport error; the workspace's objects were NOT replicated to the shared store",
    });
    throw err instanceof Error ? err : new Error(String(err));
  } finally {
    // `finally`, not the end of `try`: the push above RE-THROWS on a fence reject or a
    // transport error, and a slot leaked on that path would permanently shrink the pool
    // until the process restarted — the failure mode being that replication silently
    // stops after N failures.
    releaseGitDataSlot();
  }
}
