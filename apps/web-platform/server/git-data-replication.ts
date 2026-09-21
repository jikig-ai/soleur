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
import { createHash } from "crypto";
import { createChildLogger } from "./logger";
import { isGitDataStoreEnabled } from "./workspace-resolver";
import { gitWithPrivateKeyAuth, sshWithPrivateKeyAuth } from "./git-auth";
import { hashUserId, reportSilentFallback } from "./observability";
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

// --- (#7226 / #5914, ADR-237) git-data SSH host-key pin ---------------------------------
//
// The pin is the git-data host's Terraform-minted ED25519 public key, published to Doppler
// prd as GIT_DATA_SSH_HOST_KEY by the birth/replace job and loaded into this container at
// deploy time. It is passed to BOTH git-auth helpers, which pin the host under the alias
// `git-data` when it is non-null.
//
// Exactly one key of the expected algorithm: no host pattern, marker, comment or newline.
// The value is trimmed first, and the regex has NO `m` flag, so an embedded second line
// can never half-match. 68 base64 characters, no padding (a 51-byte ED25519 wire blob).
// # twin: apps/web-platform/infra/git-data-flag-precheck.sh and
// #       .github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh carry the same shape
// #       check (and the HCL `regex()` for web-1's ECDSA pin). Change them together.
const GIT_DATA_HOST_KEY_PIN_RE = /^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}$/;

type GitDataHostKeyPinState =
  | { state: "present"; pin: string }
  | { state: "absent" }
  | { state: "invalid" };

/** Classify GIT_DATA_SSH_HOST_KEY without side effects and without echoing its value. */
function inspectGitDataHostKeyPin(): GitDataHostKeyPinState {
  const raw = process.env.GIT_DATA_SSH_HOST_KEY?.trim();
  if (!raw) return { state: "absent" };
  return GIT_DATA_HOST_KEY_PIN_RE.test(raw) ? { state: "present", pin: raw } : { state: "invalid" };
}

// Module state: the transitional "no pin, store disabled" report fires once per process.
let pinAbsentReported = false;

/**
 * Resolve the git-data host-key pin for one SSH invocation.
 *
 *   - valid pin → the pin;
 *   - wrong shape → THROWS (never dial on a pin we cannot trust);
 *   - absent while `isGitDataStoreEnabled()` → THROWS (the store never runs unpinned);
 *   - absent while the store is disabled → `null` (the helpers' transitional fallback
 *     arm), reported to Sentry once per process under `pin_absent_store_disabled`.
 *
 * Callers resolve it in a DEDICATED guard before their ssh `try`: a throw inside the try
 * would be sorted by `e.code` and misread as `unreachable`.
 *
 * The `null` arm exists only until the first replace publishes the pin (erasure SSH is
 * live today and is deliberately not flag-gated — see removeGitDataRepo). "Pin present in
 * prd AND #5914 closed (this arm deleted)" is a hard precondition for ever setting
 * GIT_DATA_STORE_ENABLED.
 */
export function resolveGitDataHostKeyPin(): string | null {
  const s = inspectGitDataHostKeyPin();
  if (s.state === "present") return s.pin;
  if (s.state === "invalid") {
    // Never interpolate the value: it is only a public key, but a malformed secret can be
    // anything (a pasted private key included).
    throw new Error(
      "git-data: GIT_DATA_SSH_HOST_KEY is malformed — expected exactly one " +
        "`ssh-ed25519 <base64>` key with no host pattern, marker, comment or newline. " +
        "Refusing to dial the git-data host.",
    );
  }
  if (isGitDataStoreEnabled()) {
    throw new Error(
      "git-data: GIT_DATA_SSH_HOST_KEY is unset while GIT_DATA_STORE_ENABLED=true — " +
        "refusing unpinned SSH to the git-data host. The replace job publishes it to Doppler prd.",
    );
  }
  if (!pinAbsentReported) {
    pinAbsentReported = true;
    reportSilentFallback(new Error("git-data host-key pin absent (store disabled)"), {
      feature: "git_data_host_key_pin",
      op: "pin_absent_store_disabled",
      message:
        "GIT_DATA_SSH_HOST_KEY is absent; git-data SSH (erasure) uses the transitional " +
        "unpinned fallback until the first replace publishes the pin (#5914)",
    });
  }
  return null;
}

/** OpenSSH-style `SHA256:<base64, no padding>` fingerprint of a validated pin. */
function gitDataHostKeyFingerprint(pin: string): string {
  const blob = Buffer.from(pin.split(" ")[1], "base64");
  return `SHA256:${createHash("sha256").update(blob).digest("base64").replace(/=+$/, "")}`;
}

/**
 * Startup evidence for the pin (post-merge steps 3 and 5). Logs ONE line:
 * `git_data_pin=present fp=SHA256:<fp>`, `git_data_pin=absent` or `git_data_pin=invalid`.
 * Only the public-key fingerprint ever leaves the process. Never throws — an invalid pin
 * must not crash startup; it fails closed at the call sites instead.
 *
 * Deliberately `warn` (pino level 40), not `info`: Vector's `app_container_warn_filter`
 * (infra/vector.toml) ships only lines at level >= 40 to Better Stack, so an info line
 * would never arrive. Read back with
 * `scripts/betterstack-query.sh --since 30m --grep git_data_pin=`.
 */
export function logGitDataHostKeyPinAtStartup(): void {
  try {
    const s = inspectGitDataHostKeyPin();
    const line =
      s.state === "present"
        ? `git_data_pin=present fp=${gitDataHostKeyFingerprint(s.pin)}`
        : `git_data_pin=${s.state}`;
    log.warn({ gitDataPin: s.state }, line);
  } catch {
    // Observability must never take down startup.
  }
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
  // Guard: resolved before any ssh. A throw (store enabled + absent/invalid pin) reaches
  // the caller's existing failure report; nothing is dialed unpinned.
  const hostKeyPin = resolveGitDataHostKeyPin();
  // The forced command receives `workspaceId` as SSH_ORIGINAL_COMMAND (one opaque
  // argv element); the requested command word is irrelevant.
  await sshWithPrivateKeyAuth(host, workspaceId, provisionKey, hostKeyPin, { timeout: 30_000 });
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
export type GitDataErasureOutcome =
  /**
   * No REMOVE key AND no sibling git-data inputs — this env never had git-data.
   * The only outcome besides `erased` that is honest to report as "nothing owed".
   */
  | { status: "skipped" }
  /**
   * The remote forced command ran and exited 0.
   *
   * Scoped claim: rc 0 proves *a* mounted store was acted on, not *which* — the
   * wrong-store gap is tracked separately (#8101, Art. 30 register TOM (g)(4)).
   */
  | { status: "erased" }
  /** The host LOOKED and declined (non-zero from the remote command). Carries its own words. */
  | { status: "refused"; exitCode: number; detail: string }
  /**
   * ssh presented a key and the host DECLINED it (255 + an auth signature in stderr).
   *
   * Split out of `unreachable` deliberately. The REMOVE public key is baked into
   * `cloud-init-git-data.yml` authorized_keys, and `user_data` is ForceNew — so rotating
   * GIT_REMOVE_SSH_PRIVATE_KEY in Doppler WITHOUT a host replace yields `Permission
   * denied (publickey)` on every deletion, permanently. That is the opposite of "we
   * never got an answer": the host answered, refused the credential, and every repo is
   * definitively un-erased. Folding it into `unreachable` made the one failure mode that
   * is permanent, reproducible and fleet-wide read as a transient blip.
   */
  | { status: "unauthorized"; detail: string }
  /**
   * The REMOVE key is absent while the sibling git-data inputs ARE set — a partial
   * birth or a half-applied rotation, not a non-git-data env.
   *
   * Without this, `skipped` silently absorbed it and reported "nothing to erase" for a
   * host that is actively provisioning repos: the #8094 defect through a second door.
   */
  | { status: "unconfigured"; detail: string }
  /** ssh never established a session at all. Says NOTHING about the repo's fate. */
  | { status: "unreachable"; detail: string }
  /**
   * (#7226) ssh reached a host whose key does not match the pin (255 + a host-key
   * signature in stderr: changed key, no key known under the alias, or no common host-key
   * algorithm). The repo is definitively NOT erased, and the remedy is not a key rotation:
   * the web app holds a stale or wrong pin (redeploy), or git-data was re-keyed outside the
   * replace job. Split from `unauthorized`, whose remedy (re-bake authorized_keys) is wrong
   * here.
   */
  | { status: "host_key_mismatch"; detail: string };

/**
 * Scrub the identifiers out of remote stderr before it is shipped anywhere.
 *
 * `workspace_id === auth.users.id` (mig-053 N2), and `git-data-remove.sh`'s `reject()`
 * interpolates it verbatim into its messages ("workspace_id has unsafe characters:
 * '<uuid>'", lock paths under /mnt/git-data/repositories/…). Node's own
 * `Command failed: …` fallback carries it too, because the remote command IS the raw id.
 *
 * Shipping that raw would route around two contracts at once: `reportSilentFallback`
 * pseudonymizes `extra.userId` by policy (ADR-029, Recital 26), and the git-data host's
 * own emitter redacts this exact byte class before it leaves the box. An event that both
 * pseudonymizes and de-pseudonymizes the same identifier is worse than one that does
 * neither, because it reads as compliant.
 */
function scrubErasureDetail(raw: string, workspaceId: string): string {
  // The id we are scrubbing is the one we were called with, so remove it BY VALUE first
  // rather than trusting it to match a canonical UUID shape. The regex below is the net
  // for ids this function was not handed (a lock path naming a different repo); it is not
  // the primary mechanism, because a workspace id that is not canonically formatted would
  // slip straight through a shape-based scrub.
  const byValue = workspaceId
    ? raw.split(workspaceId).join("WORKSPACE_ID_REDACTED")
    : raw;
  return byValue
    .replace(
      /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g,
      "UUID_REDACTED",
    )
    .replace(/\/[^\s'"]*\/[^\s'"]*/g, "<path>")
    .slice(0, 2000);
}

/** ssh's own 255 covers both "could not connect" and "you may not in". Only stderr tells them apart. */
const SSH_AUTH_FAILURE = /permission denied|publickey|too many authentication failures|load key|invalid format/i;

/**
 * (#7226, H4) Host identity failures, checked BEFORE {@link SSH_AUTH_FAILURE} on a 255, in
 * the same order as git-data-cutover.sh `_access_reason`: no common host-key algorithm
 * (alg), no key known under the alias (unknown), then a changed key / failed verification
 * (changed).
 */
const SSH_HOST_KEY_MISMATCH =
  /no matching host key type found|no \S+ host key is known for|remote host identification has changed|host key verification failed/i;

/**
 * (#8094) WHY THIS RETURNS AN OUTCOME INSTEAD OF void.
 *
 * After #8043 F8 the host-side `git-data-remove.sh` REFUSES — named message, non-zero
 * exit — on an unmounted store, rather than reporting `not present (no-op)` and exiting
 * 0. The host stopped lying. This function kept the lie alive one level up: it was
 * `Promise<void>`, so "the repo is gone" and "the host refused to touch it" were the
 * same value to every caller, and the only caller treated both as done.
 *
 * `refused` and `unreachable` are split rather than folded into one failure, because
 * they warrant different responses and collapsing them is how a transport blip comes to
 * read as a compliance event (and vice versa). The discriminator is ssh's own
 * convention: 255 is ssh failing to establish the session; any other non-zero is the
 * REMOTE command's exit status, relayed through ssh.
 *
 * Erasure is still best-effort at the call site — a blip must not strand the auth-user
 * deletion — but "best-effort" now means the caller KNOWS the effort failed and can say
 * so, instead of reporting a success it never observed. See #8094.
 */
export async function removeGitDataRepo(workspaceId: string): Promise<GitDataErasureOutcome> {
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
  if (!removeKey) {
    // "Never in play" is only supportable when the SIBLING arming inputs are absent too.
    // Provisioning arms on a DIFFERENT variable (GIT_PROVISION_SSH_PRIVATE_KEY), so a
    // half-applied rotation or a partial birth can leave repos being created while the
    // remove key is missing — and reporting that as `skipped` tells the user their data
    // is gone while their bare repo sits on the host.
    const provisionKey = process.env.GIT_PROVISION_SSH_PRIVATE_KEY?.trim();
    const sshHost = process.env.GIT_DATA_SSH_HOST?.trim();
    if (provisionKey || sshHost) {
      return {
        status: "unconfigured",
        detail:
          "GIT_REMOVE_SSH_PRIVATE_KEY is absent while the provision key and/or GIT_DATA_SSH_HOST are set",
      };
    }
    return { status: "skipped" };
  }
  const host = resolveGitDataSshHost();
  // Guard OUTSIDE the ssh try (#7226): the catch below sorts by `e.code`, so a resolver
  // throw inside it would read as `unreachable`. An absent-while-enabled or malformed pin
  // is a configuration fault, and nothing is dialed.
  let hostKeyPin: string | null;
  try {
    hostKeyPin = resolveGitDataHostKeyPin();
  } catch (e) {
    return { status: "unconfigured", detail: e instanceof Error ? e.message : String(e) };
  }
  try {
    await sshWithPrivateKeyAuth(host, workspaceId, removeKey, hostKeyPin, { timeout: 30_000 });
    return { status: "erased" };
  } catch (err) {
    // execFileAsync rejects with the child's exit status on `code` and its stderr on
    // `stderr`. sshWithPrivateKeyAuth does not catch (its `finally` only shreds the temp
    // key), so both reach us unchanged. Read them defensively anyway: a timeout rejects
    // with a `killed` error whose `code` is null, and that is an `unreachable`, not a
    // refusal by a host that never answered.
    const e = err as { code?: unknown; stderr?: unknown };
    const exitCode = typeof e.code === "number" ? e.code : null;
    const detail = scrubErasureDetail(
      String(
        typeof e.stderr === "string" && e.stderr.trim()
          ? e.stderr.trim()
          : err instanceof Error
            ? err.message
            : err,
      ),
      workspaceId,
    );
    // 255 is ssh's own status and covers two very different facts. Read the stderr to
    // tell them apart before defaulting to the benign one.
    if (exitCode === 255 && SSH_HOST_KEY_MISMATCH.test(detail)) {
      return { status: "host_key_mismatch", detail };
    }
    if (exitCode === 255 && SSH_AUTH_FAILURE.test(detail)) {
      return { status: "unauthorized", detail };
    }
    if (exitCode === null || exitCode === 255) return { status: "unreachable", detail };
    return { status: "refused", exitCode, detail };
  }
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
/**
 * What actually happened to a replication attempt.
 *
 * B13 (#6982 review): this function used to return bare `void`, and BOTH callers `await` it
 * inside a `catch {}`. That made the three outcomes indistinguishable at the call site — a
 * completed push, a disabled-by-flag no-op, and a SHED all looked identical. The shed is the
 * one that matters: it means this session's delta was never replicated, and because
 * replication is session-end-coupled, "later" never comes for that delta. A caller that
 * cannot tell it happened cannot count it, retry it, or decide not to.
 *
 * The shed is already reported to Sentry and the app log; this makes it legible to CODE as
 * well, without changing any control flow — `void` was structurally incapable of carrying it.
 */
export type GitDataReplicationOutcome =
  | { status: "replicated" }
  | { status: "disabled" }
  | { status: "shed"; slotsBusy: number; queueTimeoutMs: number };

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
}): Promise<GitDataReplicationOutcome> {
  if (!isGitDataStoreEnabled()) return { status: "disabled" };
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
    // PSEUDONYMISED, never the raw ids (#6982 review). workspace_id === auth.users.id
    // (mig-053 N2), so a bare workspaceId here is a raw user identifier on the app log
    // sink — and Vector's `pii_scrub_string` does not scrub a bare UUID in free text.
    // That is the same reasoning that put a UUID redactor in the git-data HOST emitter in
    // this PR; this module was the app-side outlier. Matches the sibling git-data-client.ts,
    // which already logs `workspaceIdHash`. worktreeId rides the same treatment: it is a
    // stable PER-USER identifier, so leaving it bare would defeat the point.
    log.warn(
      {
        workspaceIdHash: hashUserId(workspaceId),
        worktreeIdHash: hashUserId(worktreeId),
        limit: GIT_DATA_MAX_CONCURRENT,
      },
      "git-data replication shed — queue timeout; session end is not blocked",
    );
    return {
      status: "shed",
      slotsBusy: GIT_DATA_MAX_CONCURRENT,
      queueTimeoutMs: GIT_DATA_QUEUE_TIMEOUT_MS,
    };
  }

  try {
    // (#7226) Resolved first, so a store-enabled run without a valid pin performs NO ssh
    // (neither the provision below nor the push) and lands in this catch's existing report.
    const hostKeyPin = resolveGitDataHostKeyPin();
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
      hostKeyPin,
      { cwd: workspacePath, timeout: 60_000 },
    );
    log.info(
      {
        workspaceIdHash: hashUserId(workspaceId),
        worktreeIdHash: hashUserId(worktreeId),
        leaseGeneration,
      },
      "git-data replication push complete",
    );

    return { status: "replicated" };
  } catch (err) {
    reportSilentFallback(err, {
      feature: "worktree_lease",
      op: "git_data_replication_push",
      // Hashed here too. `hashExtraUserId` renames `userId` ONLY, so a bare workspaceId
      // (=== auth.users.id) reached BOTH sinks reportSilentFallback mirrors to. The commit
      // that hashed the two log.* calls above stopped one site short of its own title.
      extra: {
        workspaceIdHash: hashUserId(workspaceId),
        worktreeIdHash: hashUserId(worktreeId),
        leaseGeneration,
        userId,
      },
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
