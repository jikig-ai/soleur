// ---------------------------------------------------------------------------
// Connected-repo git: the ONE host-side git wrapper for the user's workspace (`runConnectedRepoGit`, its argv-shape guard)
// and the workspace writers built on it (`kbWorkspaceWriter` for the push, `kbPullWriter` for the session-start pull and the
// self-heal), plus the shared merge-in-progress check.
//
// A leaf (#12718 review, Phase 0 of the D34-D47 rulings): moved verbatim out of server/session-sync.ts so the self-heal
// (server/workspace-sync.ts) reaches the guarded writer without importing session-sync (and through it the push). It
// imports the push module for a TYPE only (`KbWorkspaceWriter`, erased at runtime).
// ---------------------------------------------------------------------------

import { execFileSync, type ExecFileSyncOptions } from "child_process";
import { lstatSync } from "fs";
import { join } from "path";
import { reportSilentFallback } from "@/server/observability";
import { HEX40 } from "./approval/workspace-head";
import { validateBranchFormat } from "./branch-validation";
import { ALLOW_PROTOCOL_NONE, HostGitRefusedError, hostGitInvocation } from "./host-git";
import type { KbWorkspaceWriter } from "./kb-sync-publish";
import { AUTO_MERGE_MSG_PULL, type KbMergeOutcome, type KbPullWriter } from "./kb-sync-pull";
import { createChildLogger } from "./logger";

// The moved lines keep the log context they had in session-sync.ts (no behaviour change in the move).
const log = createChildLogger("session-sync");

// Allowlist of git subcommands the connected-repo writer may invoke.
// Anything destructive (rm, reset, clean, branch -D, checkout -- ...) is
// rejected at the wrapper. See #2905 for the failure-class this prevents.
const ALLOWED_GIT_SUBCOMMANDS = new Set([
  "status",
  "add",
  "commit",
  "remote",
  "rev-list",
  // #12600 (CTO rulings R12, R19, R20): the KB sync's only two workspace WRITE verbs, each behind the exact-argv guard
  // in `assertConnectedRepoArgv`. Decision verbs (hash checks, tree and commit builds) never run here: they run token-free
  // in the isolated GIT_DIR (server/git-isolated-local.ts).
  "update-ref",
  "unpack-objects",
  // #12718 (rulings X1, D26(2)): the session-start merge of the verified remote tip, ONE exact argv (`assertMergeArgv`).
  "merge",
]);

/**
 * D26(2): the config pins of the session-start merge. Each closes a workspace-config route to a host-side program or a
 * silent content change: signature verification and its gpg programs, renormalization, a configured merge default, rerere
 * (a replayed resolution), the diffstat, auto-maintenance and gc, and hooks. `filter.*` and an attribute-selected merge
 * driver still run on the host (D26(3), same-uid residual; the closure is an isolated `merge-tree`, a follow-up).
 */
export const MERGE_CONFIG_PINS: readonly string[] = [
  "merge.verifySignatures=false",
  "gpg.program=/bin/false",
  "gpg.ssh.program=/bin/false",
  "gpg.x509.program=/bin/false",
  "merge.renormalize=false",
  "merge.default=text",
  "rerere.enabled=false",
  "rerere.autoUpdate=false",
  "merge.stat=false",
  "maintenance.auto=false",
  "gc.auto=0",
  "core.hooksPath=/dev/null",
].flatMap((pin) => ["-c", pin]);

/** The pinned merge argv for `target` (a 40-hex id the caller verified, D26(5)). */
export function mergeArgv(target: string): string[] {
  return [...MERGE_CONFIG_PINS, "merge", "--no-edit", "--autostash", "--no-overwrite-ignore", "-m", AUTO_MERGE_MSG_PULL, target];
}

/**
 * Shape only (D26(5)): a `-c`-led argv must be exactly the pins then the merge, and the merge exactly
 * `merge --no-edit --autostash --no-overwrite-ignore -m <AUTO_MERGE_MSG_PULL> <40hex>`. No `--ff-only`, no `--abort`, no
 * second target. That the target is the in-memory `T` is checked in server/kb-sync-pull.ts, not here.
 */
function assertMergeArgv(argv: readonly string[]): void {
  const refuse = (): never => {
    throw new Error("connected-repo git: 'merge' argv is not the pinned session-start merge");
  };
  const target = argv[argv.length - 1];
  if (argv.length !== MERGE_CONFIG_PINS.length + 7 || !guardedSha(target)) refuse();
  const expected = mergeArgv(target);
  if (!expected.every((a, i) => argv[i] === a)) refuse();
}

/** An object id the guarded `update-ref` shapes accept: 40 lowercase hex, never all-zero (git reads it as "delete" / "must not exist"). */
function guardedSha(sha: string | undefined): boolean {
  return typeof sha === "string" && HEX40.test(sha) && !/^0+$/.test(sha);
}

/** A branch name the guarded `update-ref` shapes accept (git's ref-format rules; throws a static error otherwise). */
function guardedBranch(name: string): boolean {
  try {
    validateBranchFormat(name);
    return true;
  } catch {
    return false;
  }
}

/**
 * The exact argv shapes of the two guarded write verbs (#12600):
 *   - `["update-ref", "--no-deref", "refs/heads/<b>", <40hex new>, <40hex old>]` (CAS mandatory, R1/R19), and
 *   - `["update-ref", "--no-deref", "refs/remotes/origin/<b>", <40hex>]` (the advisory tracking ref, R8/R17);
 *   - `["unpack-objects", "-q"]` (the pack arrives on stdin).
 * Any other argv for these verbs throws.
 */
function assertGuardedWriteArgv(argv: readonly string[]): void {
  const refuse = (): never => {
    throw new Error(`connected-repo git: '${argv[0]}' argv is not one of the guarded shapes`);
  };
  if (argv[0] === "unpack-objects") {
    if (argv.length !== 2 || argv[1] !== "-q") refuse();
    return;
  }
  if (argv[0] !== "update-ref") return;
  // R19: a symref planted at the ref must be replaced, never followed to the branch it names.
  if (argv[1] !== "--no-deref") throw new Error("connected-repo git: 'update-ref' requires --no-deref");
  const ref = argv[2] ?? "";
  if (ref.startsWith("refs/heads/")) {
    if (argv.length !== 5 || !guardedBranch(ref.slice("refs/heads/".length))) refuse();
    if (!guardedSha(argv[3]) || !guardedSha(argv[4])) refuse();
    return;
  }
  if (ref.startsWith("refs/remotes/origin/")) {
    if (argv.length !== 4 || !guardedBranch(ref.slice("refs/remotes/origin/".length))) refuse();
    if (!guardedSha(argv[3])) refuse();
    return;
  }
  refuse();
}

// Forbidden flags — applied across ANY allowed subcommand. Reject in argv,
// not just at the start, so `commit --amend` or `push --force` (if either
// ever reaches this wrapper) gets blocked regardless of position.
const FORBIDDEN_GIT_FLAGS = new Set([
  "--force",
  "-f",
  "--hard",
  "--amend",
  "--no-verify",
]);

/**
 * The argv-shape guard of `runConnectedRepoGit`, exported for its unit rows: the subcommand allowlist, the forbidden
 * flags on every allowed subcommand, and the exact shapes of the guarded write verbs. Throws before any git runs.
 */
export function assertConnectedRepoArgv(argv: readonly string[]): void {
  if (argv.length === 0) {
    throw new Error("connected-repo git: argv must include a subcommand");
  }
  // Only the session-start merge may carry `-c` pins, and only exactly them (D26(2)).
  if (argv[0] === "-c" || argv[0] === "merge") {
    assertMergeArgv(argv);
    return;
  }
  const subcmd = argv[0];
  if (!ALLOWED_GIT_SUBCOMMANDS.has(subcmd)) {
    throw new Error(
      `connected-repo git: subcommand '${subcmd}' is not allowed (allowed: ${[...ALLOWED_GIT_SUBCOMMANDS].join(", ")})`,
    );
  }
  for (const arg of argv) {
    if (FORBIDDEN_GIT_FLAGS.has(arg)) {
      throw new Error(
        `connected-repo git: flag '${arg}' is forbidden (subcommand: ${subcmd})`,
      );
    }
  }
  assertGuardedWriteArgv(argv);
}

/**
 * Connected-repo git wrapper. Runs `execFileSync("git", ...)` through the shared host-git invocation
 * (hardening arguments, scrubbed environment, `GIT_WORK_TREE=<cwd>`) with
 * an argv-shape guard that rejects:
 *   - subcommands outside the allowlist (`rm`, `reset`, `clean`, `checkout`,
 *     `branch`, `tag`, `cherry-pick`, ...) — categorically destructive or
 *     branch-switching surfaces the auto-commit sweep has no business in.
 *   - forbidden flags (`--force`, `--hard`, `--amend`, `--no-verify`) on
 *     any allowed subcommand.
 *
 * Throws a descriptive Error on rejection so the caller's try/catch logs
 * a meaningful warning rather than silently swallowing the violation.
 */
/**
 * Upper bound of one connected-repo git child (D13; lowered to 30 s by D21): a stalled `.lock` or a wedged filesystem costs at
 * most this long. The child is synchronous, so the bound is also how long it can block the event loop; running the workspace
 * writers async with a process-group kill (a filter grandchild) is the follow-up.
 */
export const CONNECTED_REPO_GIT_TIMEOUT_MS = 30_000;

export function runConnectedRepoGit(
  argv: string[],
  // No `env`: the environment is the helper's (scrubbed, hardened), never a caller's.
  opts: Omit<ExecFileSyncOptions, "env"> & { cwd: string },
): Buffer {
  assertConnectedRepoArgv(argv);
  // Host-side git in a workspace an agent session may have authored: shared hardening arguments + a scrubbed env
  // (ADR-050 amendment; see server/host-git.ts for what that does and does not close).
  const h = hostGitInvocation(argv, { cwd: opts.cwd, allowProtocol: ALLOW_PROTOCOL_NONE });
  return execFileSync("git", h.args, { timeout: CONNECTED_REPO_GIT_TIMEOUT_MS, ...opts, env: h.env }) as Buffer;
}

/** One `git status --porcelain=v1 -z` entry: the two XY status columns and the (destination) path. */
export interface PorcelainEntry {
  readonly xy: string;
  readonly path: string;
}

/**
 * Parse `git status --porcelain=v1 -z` output (D21: the ONE parser, shared by the unmerged scan and the allowlist).
 *
 * The `-z` flag emits NUL-separated entries with no C-quoting, so paths
 * containing tabs, newlines, quotes, or non-ASCII characters round-trip
 * cleanly to `git add --`. For renames (R) and copies (C), git emits the
 * destination path first, then the source path as a separate NUL entry —
 * this parser skips the source.
 */
export function parsePorcelainZ(output: string): PorcelainEntry[] {
  const entries: PorcelainEntry[] = [];
  const tokens = output.split("\0");
  for (let i = 0; i < tokens.length; i++) {
    const entry = tokens[i];
    if (entry.length < 4) continue; // status (2 chars) + space + path
    entries.push({ xy: entry.slice(0, 2), path: entry.slice(3) });
    if (entry[0] === "R" || entry[0] === "C") i++; // the SOURCE path of a rename / copy
  }
  return entries;
}

/** The working tree's status, ONE run in the mode the auto-commit needs (untracked files included); null when it could not run. */
export function readStatus(workspacePath: string, gate: string): PorcelainEntry[] | null {
  try {
    return parsePorcelainZ(runConnectedRepoGit(["status", "--porcelain=v1", "-z"], { cwd: workspacePath, stdio: "pipe" }).toString());
  } catch (err) {
    mirrorGitRefusal(err, gate);
    return null;
  }
}

/**
 * A refused `.git` (a gitfile, a symlink, `commondir`, a redirecting entry) stops EVERY sync for that workspace at the
 * first gate below, so it must not look like "no remote" or "nothing changed": mirror it once, with the reason only (no
 * path, no user id in the message). Returns true when `err` was a refusal.
 */
export function mirrorGitRefusal(err: unknown, gate: string): boolean {
  if (!(err instanceof HostGitRefusedError)) return false;
  log.warn({ reason: err.reason, gate }, "Host git refused the workspace .git; sync skipped");
  reportSilentFallback(new Error(`session-sync refused: ${err.reason}`), {
    feature: "session-sync",
    op: "git-refused",
    extra: { gate },
    message: "Host git refused the workspace .git shape",
  });
  return true;
}

/** The KB sync's workspace writes (#12600): only the guarded verbs of `runConnectedRepoGit`. */
export function kbWorkspaceWriter(workspacePath: string): KbWorkspaceWriter {
  const opts = { cwd: workspacePath, stdio: "pipe" as const };
  return {
    unpack: (pack) => {
      runConnectedRepoGit(["unpack-objects", "-q"], { ...opts, input: pack });
    },
    casBranch: (branch, next, prev) => {
      runConnectedRepoGit(["update-ref", "--no-deref", `refs/heads/${branch}`, next, prev], opts);
    },
    setTracking: (branch, sha) => {
      runConnectedRepoGit(["update-ref", "--no-deref", `refs/remotes/origin/${branch}`, sha], opts);
    },
  };
}

/** Upper bound of the session-start merge child (a large checkout is slower than the other guarded writes). */
const MERGE_TIMEOUT_MS = 60_000;

/**
 * The pull's workspace writes (#12718, D25(2)): the push writer's three guarded verbs plus the pinned merge. The merge's
 * outcome is read from its exit status, `MERGE_HEAD` and one status run: exit 0 with an unmerged entry is an autostash pop
 * that conflicted (`autostash_conflict`, D26(4)); exit 1 with `MERGE_HEAD` is a content conflict; anything else (an
 * unrelated history, an ignored file in the way, a refused argv) is `refused`. Exported for the self-heal
 * (server/workspace-sync.ts imports it lazily).
 */
export function kbPullWriter(workspacePath: string, _opts?: { readonly autostash?: boolean }): KbPullWriter {
  // Phase 0 (frozen signature): `opts.autostash` is accepted and not yet read; the merge argv is the one pinned shape
  // (`--autostash` included) for every caller until WP2 adds the self-heal's second shape (D37(2)).
  const base = kbWorkspaceWriter(workspacePath);
  // The verbs are async (frozen contract); each still runs its one synchronous child at call time, as before.
  return {
    unpack: async (pack) => base.unpack(pack),
    setTracking: async (branch, sha) => base.setTracking(branch, sha),
    casBranch: async (branch, next, prev) => base.casBranch(branch, next, prev),
    merge: async (target): Promise<KbMergeOutcome> => {
      try {
        runConnectedRepoGit(mergeArgv(target), {
          cwd: workspacePath,
          stdio: "pipe",
          timeout: MERGE_TIMEOUT_MS,
          maxBuffer: 16 * 1024 * 1024,
        });
      } catch (err) {
        const code = (err as { status?: unknown } | null)?.status;
        return code === 1 && mergeHeadPresent(workspacePath) ? "conflict" : "refused";
      }
      const after = readStatus(workspacePath, "syncPull-merge");
      return (after ?? []).some((e) => UNMERGED_XY.has(e.xy)) ? "autostash_conflict" : "clean";
    },
  };
}

/** `git status --porcelain=v1` XY codes of an unmerged (conflicted) index entry. */
const UNMERGED_XY = new Set(["DD", "AU", "UD", "UA", "DU", "AA", "UU"]);

/** The `.git/<name>` files whose presence means a merge is in progress (the one spelling of the list, simplicity F4). */
export const MERGE_STATE_FILES = ["MERGE_HEAD", "MERGE_AUTOSTASH"] as const;
export type MergeStateFile = (typeof MERGE_STATE_FILES)[number];

/**
 * The ref namespace that pins an interrupted merge's autostash commit (D36(c)): host-local, outside the git-data
 * namespaces, and kept by `gc`. Phase 0 exports the prefix only; the pin itself lands with WP1.
 */
export const AUTOSTASH_PIN_PREFIX = "refs/soleur/autostash/";

/** `.git/<name>` is present (lstat: a symlink counts and is never followed), or could not be checked (fail closed). */
function gitFilePresent(workspacePath: string, name: MergeStateFile): boolean {
  try {
    lstatSync(join(workspacePath, ".git", name));
    return true;
  } catch (err) {
    const code = (err as { code?: unknown } | null)?.code;
    return code !== "ENOENT" && code !== "ENOTDIR";
  }
}

const mergeHeadPresent = (workspacePath: string): boolean => gitFilePresent(workspacePath, "MERGE_HEAD");

/**
 * A merge is in progress, so no auto-commit, no pull and no push (R11, X4, D26(1)): `.git/MERGE_HEAD` or
 * `.git/MERGE_AUTOSTASH` present (any type, or unreadable), OR the index holds an unmerged entry without either (a
 * conflicted `stash pop`, `cherry-pick` or `rebase`; D13), which an auto-commit `add` would resolve by committing the
 * conflict markers. `entries` is the turn's one status run (D21); a status that could not run (`null`) is not a merge (the
 * auto-commit then has nothing to stage). The ONE check both `syncPull` and `syncPush` run before their auto-commit.
 */
export function mergeInProgress(workspacePath: string, entries: readonly PorcelainEntry[] | null): boolean {
  // MERGE_HEAD first, then MERGE_AUTOSTASH (the list's order), short-circuiting as before.
  if (MERGE_STATE_FILES.some((name) => gitFilePresent(workspacePath, name))) return true;
  return (entries ?? []).some((e) => UNMERGED_XY.has(e.xy));
}

/**
 * Same-host serialization of the workspace git writers (D38(6)): syncPull, the syncPush publish and the self-heal's
 * `mergeHeldCommits` run `fn` under one in-process lock keyed on the workspace's real path. Phase 0 (frozen signature):
 * no lock yet, `fn` runs directly; WP1 adds the keyed lock.
 */
export async function withWorkspaceGitLock<T>(_workspacePath: string, fn: () => Promise<T>): Promise<T> {
  return fn();
}
