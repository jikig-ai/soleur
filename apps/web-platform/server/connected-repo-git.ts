// ---------------------------------------------------------------------------
// Connected-repo git: the ONE host-side git wrapper for the user's workspace (`runConnectedRepoGit`, its argv-shape guard)
// and the workspace writers built on it (`kbWorkspaceWriter` for the push, `kbPullWriter` for the session-start pull and the
// self-heal), plus the shared merge-in-progress check.
//
// A leaf (#12718 review, Phase 0 of the D34-D47 rulings): moved verbatim out of server/session-sync.ts so the self-heal
// (server/workspace-sync.ts) reaches the guarded writer without importing session-sync (and through it the push). It
// imports the push module for a TYPE only (`KbWorkspaceWriter`, erased at runtime).
//
// Review fix round 1 (WP1): every child is async (`execFile`, D38(1)), so a large checkout never blocks the shared event
// loop; the pull writer's merge checks for a merge in progress first (D37(1)), runs the untracked/ignored collision check
// against the verified target (D35), and reads its outcome fail-closed (D36(a)(b)); an interrupted merge's autostash is
// pinned under `refs/soleur/autostash/` (D36(c)); `withWorkspaceGitLock` serializes one workspace's writers (D38(6)).
// ---------------------------------------------------------------------------

import { closeSync, constants as fsConstants, fstatSync, lstatSync, openSync, readSync, realpathSync } from "fs";
import { join } from "path";
import { mirrorWarnWithDebounce, reportSilentFallback } from "@/server/observability";
import { HEX40 } from "./approval/workspace-head";
import { validateBranchFormat } from "./branch-validation";
import { ALLOW_PROTOCOL_NONE, HostGitRefusedError, hostGitInvocation } from "./host-git";
import type { KbWorkspaceWriter } from "./kb-sync-publish";
import { DIRECTORY_RENAMES_PIN } from "./kb-sync-objects";
import { AUTO_MERGE_MSG_PULL, AUTO_MERGE_MSG_SELF_HEAL, type KbMergeOutcome, type KbPullWriter } from "./kb-sync-pull";
import { createChildLogger } from "./logger";
import { hasUntrackedCollision } from "./workspace-collision";

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
  // Review WP1 (D35, D36(a)): the writer's read-only checks, each ONE exact argv (`assertReadArgv`).
  "diff",
  "ls-files",
  "rev-parse",
]);

/**
 * D26(2): the config pins of the session-start merge. Each closes a workspace-config route to a host-side program or a
 * silent content change: signature verification and its gpg programs, renormalization, directory-rename relocation onto an
 * ignored path (R2-B, `DIRECTORY_RENAMES_PIN`), a configured merge default, rerere (a replayed resolution), the diffstat,
 * auto-maintenance and gc, and hooks. `filter.*` and an attribute-selected merge
 * driver still run on the host (D26(3), same-uid residual; the closure is an isolated `merge-tree`, a follow-up).
 */
export const MERGE_CONFIG_PINS: readonly string[] = [
  "merge.verifySignatures=false",
  "gpg.program=/bin/false",
  "gpg.ssh.program=/bin/false",
  "gpg.x509.program=/bin/false",
  "merge.renormalize=false",
  DIRECTORY_RENAMES_PIN,
  "merge.default=text",
  "rerere.enabled=false",
  "rerere.autoUpdate=false",
  "merge.stat=false",
  "maintenance.auto=false",
  "gc.auto=0",
  "core.hooksPath=/dev/null",
].flatMap((pin) => ["-c", pin]);

/**
 * The pinned merge argv for `target` (a 40-hex id the caller verified, D26(5)). Two shapes (D37(2)): the session-start pull
 * (`--autostash`, `AUTO_MERGE_MSG_PULL`) and the self-heal (`autostash: false`: no `--autostash`, `AUTO_MERGE_MSG_SELF_HEAL`),
 * so a path dirtied after the self-heal's clean gate makes git refuse the merge; git never stashes and never resets.
 * `--no-overwrite-ignore` stays in both: it still guards a fast-forward (a non-ff merge ignores it; D35's check guards that).
 */
export function mergeArgv(target: string, opts: { readonly autostash?: boolean } = {}): string[] {
  return opts.autostash === false
    ? [...MERGE_CONFIG_PINS, "merge", "--no-edit", "--no-overwrite-ignore", "-m", AUTO_MERGE_MSG_SELF_HEAL, target]
    : [...MERGE_CONFIG_PINS, "merge", "--no-edit", "--autostash", "--no-overwrite-ignore", "-m", AUTO_MERGE_MSG_PULL, target];
}

/**
 * Shape only (D26(5), D37(2)): a `-c`-led argv must be exactly the pins then one of the two merges of `mergeArgv`, never a
 * mix (`--autostash` with the self-heal message, or the pull message without it). No `--ff-only`, no `--abort`, no second
 * target. That the target is the in-memory `T` (or the verified side tip) is checked in server/kb-sync-pull.ts, not here.
 */
function assertMergeArgv(argv: readonly string[]): void {
  const target = argv[argv.length - 1];
  const same = (expected: readonly string[]): boolean => expected.length === argv.length && expected.every((a, i) => argv[i] === a);
  if (!guardedSha(target) || !(same(mergeArgv(target)) || same(mergeArgv(target, { autostash: false })))) {
    throw new Error("connected-repo git: 'merge' argv is not the pinned session-start merge or the pinned self-heal merge");
  }
}

/** The collision listing against a verified target (D35): `HEAD` vs a 40-hex id, added and deleted paths, raw bytes. */
export const COLLISION_DIFF_ARGV = ["diff", "--name-status", "-z", "--no-renames", "--no-ext-diff", "--no-textconv", "--diff-filter=AD", "HEAD"] as const;
const LITERAL_PREFIX = ":(literal)";
const STASH_REF_ARGV = ["rev-parse", "-q", "--verify", "refs/stash"] as const;

/**
 * The exact argv shapes of the writer's read-only verbs (D35, D36(a)); any other argv for these verbs throws:
 *   - `diff --name-status -z --no-renames --no-ext-diff --no-textconv --diff-filter=AD HEAD <40hex> --` (the collision listing);
 *   - `ls-files -z --others --directory -- :(literal)<p>/` (shape 3: entries HEAD does not track under one directory);
 *   - `rev-parse -q --verify refs/stash` (the stash tip before and after the merge, full refname).
 */
function assertReadArgv(argv: readonly string[]): void {
  const refuse = (): never => {
    throw new Error(`connected-repo git: '${argv[0]}' argv is not one of the pinned read shapes`);
  };
  if (argv[0] === "diff") {
    const n = COLLISION_DIFF_ARGV.length;
    if (argv.length !== n + 2 || !COLLISION_DIFF_ARGV.every((a, i) => argv[i] === a) || !guardedSha(argv[n]) || argv[n + 1] !== "--") refuse();
    return;
  }
  if (argv[0] === "ls-files") {
    const p = argv[5] ?? "";
    const ok =
      argv.length === 6 &&
      ["ls-files", "-z", "--others", "--directory", "--"].every((a, i) => argv[i] === a) &&
      p.startsWith(LITERAL_PREFIX) &&
      p.endsWith("/") &&
      p.length > LITERAL_PREFIX.length + 1 &&
      !p.includes("\0");
    if (!ok) refuse();
    return;
  }
  if (argv[0] === "rev-parse") {
    if (argv.length !== STASH_REF_ARGV.length || !STASH_REF_ARGV.every((a, i) => argv[i] === a)) refuse();
  }
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
 *   - `["update-ref", "--no-deref", "refs/soleur/autostash/<40hex>", <the same 40hex>]` (the autostash pin, D36(c):
 *     idempotent, the ref is named by its own value);
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
  if (ref.startsWith(AUTOSTASH_PIN_PREFIX)) {
    if (argv.length !== 4 || !guardedSha(argv[3]) || ref !== `${AUTOSTASH_PIN_PREFIX}${argv[3]}`) refuse();
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
  assertReadArgv(argv);
}

/**
 * Upper bound of one connected-repo git child (D13; lowered to 30 s by D21): a stalled `.lock` or a wedged filesystem costs at
 * most this long. The child is async (D38(1)) and killed with SIGKILL at the bound, so a planted filter that traps SIGTERM
 * cannot outlive it; it never blocks the event loop.
 */
export const CONNECTED_REPO_GIT_TIMEOUT_MS = 30_000;

/** Options of one connected-repo git child. No `env`: the environment is the helper's (scrubbed, hardened), never a caller's. */
export interface ConnectedRepoGitOptions {
  readonly cwd: string;
  /** Bytes written to the child's stdin (then closed). */
  readonly input?: Buffer;
  readonly timeoutMs?: number;
  readonly maxBuffer?: number;
}

/** A failed child: git's exit status (null when killed), its signal, and stderr; the message is static (no argv). */
export class ConnectedRepoGitError extends Error {
  constructor(
    readonly status: number | null,
    readonly signal: string | null,
    readonly stdout: Buffer,
    readonly stderr: Buffer,
  ) {
    super(`connected-repo git failed (${status === null ? `signal ${signal ?? "unknown"}` : `exit ${status}`})`);
    this.name = "ConnectedRepoGitError";
  }
}

/**
 * Connected-repo git wrapper (D38(1): the ONE runner; the synchronous one is gone). Runs one `execFile("git", ...)` through
 * the shared host-git invocation (hardening arguments, scrubbed environment, `GIT_WORK_TREE=<cwd>`) behind the argv-shape
 * guard, which rejects (before any child runs):
 *   - subcommands outside the allowlist (`rm`, `reset`, `clean`, `checkout`, `branch`, `tag`, `cherry-pick`, ...) —
 *     categorically destructive or branch-switching surfaces the auto-commit sweep has no business in;
 *   - forbidden flags (`--force`, `--hard`, `--amend`, `--no-verify`) on any allowed subcommand;
 *   - any argv of a guarded verb that is not one of its exact shapes.
 * Resolves with stdout; rejects with a `ConnectedRepoGitError` (exit status, signal, stdout, stderr), a `HostGitRefusedError`
 * (a refused `.git` shape), or the guard's descriptive Error, so the caller's try/catch logs a meaningful warning.
 * `child_process` is imported lazily (sibling suites mock it with factories that lack `execFile`).
 */
export async function runConnectedRepoGitAsync(argv: string[], opts: ConnectedRepoGitOptions): Promise<Buffer> {
  assertConnectedRepoArgv(argv);
  // Host-side git in a workspace an agent session may have authored: shared hardening arguments + a scrubbed env
  // (ADR-050 amendment; see server/host-git.ts for what that does and does not close).
  const h = hostGitInvocation(argv, { cwd: opts.cwd, allowProtocol: ALLOW_PROTOCOL_NONE });
  const { execFile } = await import("child_process");
  return new Promise<Buffer>((resolve, reject) => {
    const asBuffer = (v: unknown): Buffer => (Buffer.isBuffer(v) ? v : Buffer.from(String(v ?? "")));
    const child = execFile(
      "git",
      h.args,
      {
        cwd: opts.cwd,
        env: h.env,
        timeout: opts.timeoutMs ?? CONNECTED_REPO_GIT_TIMEOUT_MS,
        killSignal: "SIGKILL",
        encoding: "buffer",
        ...(opts.maxBuffer === undefined ? {} : { maxBuffer: opts.maxBuffer }),
      },
      (err, stdout, stderr) => {
        if (!err) return resolve(asBuffer(stdout));
        const e = err as { code?: unknown; signal?: unknown };
        reject(
          new ConnectedRepoGitError(
            typeof e.code === "number" ? e.code : null,
            typeof e.signal === "string" ? e.signal : null,
            asBuffer(stdout),
            asBuffer(stderr),
          ),
        );
      },
    );
    const stdin = (child as { stdin?: NodeJS.WritableStream | null } | undefined)?.stdin;
    if (stdin) {
      // A child that exits before reading its input (a refused argv) must not crash the process with EPIPE.
      stdin.on("error", () => {});
      if (opts.input !== undefined) stdin.end(opts.input);
      else stdin.end();
    }
  });
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
export async function readStatus(workspacePath: string, gate: string): Promise<PorcelainEntry[] | null> {
  try {
    return parsePorcelainZ((await runConnectedRepoGitAsync(["status", "--porcelain=v1", "-z"], { cwd: workspacePath })).toString());
  } catch (err) {
    mirrorGitRefusal(err, gate);
    return null;
  }
}

/**
 * The writer's own status run (verify-coverage P3-1): tracked entries only (`--untracked-files=no`), so a workspace with
 * many untracked paths never overflows the runner's buffer into a refused or unverified merge. Enough for what the writer
 * reads from it: unmerged entries are tracked by definition. Untracked and ignored entries in the merge's way are the
 * collision check's (`hasUntrackedCollision`: lstat and its own `ls-files` reads), never this run's. Null when it could not run.
 */
async function readTrackedStatus(workspacePath: string): Promise<PorcelainEntry[] | null> {
  try {
    const out = await runConnectedRepoGitAsync(["status", "--porcelain=v1", "-z", "--untracked-files=no"], { cwd: workspacePath });
    return parsePorcelainZ(out.toString());
  } catch (err) {
    mirrorGitRefusal(err, "kbPullWriter-merge");
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

/** The KB sync's workspace writes (#12600): only the guarded verbs of `runConnectedRepoGitAsync`, each awaited (D38(1)). */
export function kbWorkspaceWriter(workspacePath: string): KbWorkspaceWriter {
  return {
    unpack: async (pack) => {
      await runConnectedRepoGitAsync(["unpack-objects", "-q"], { cwd: workspacePath, input: pack });
    },
    casBranch: async (branch, next, prev) => {
      await runConnectedRepoGitAsync(["update-ref", "--no-deref", `refs/heads/${branch}`, next, prev], { cwd: workspacePath });
    },
    setTracking: async (branch, sha) => {
      await runConnectedRepoGitAsync(["update-ref", "--no-deref", `refs/remotes/origin/${branch}`, sha], { cwd: workspacePath });
    },
  };
}

/**
 * Upper bound of the merge child (a large checkout is slower than the other guarded writes). A started merge keeps this
 * bound whatever the caller's budget (D38(3)): killing it mid-checkout is the stranded D36(c) state by design.
 */
export const MERGE_TIMEOUT_MS = 60_000;

/** `refs/stash` now: its id, `null` when there is none, `undefined` when it could not be read (fail closed). */
async function readStashTip(workspacePath: string): Promise<string | null | undefined> {
  try {
    const out = (await runConnectedRepoGitAsync([...STASH_REF_ARGV], { cwd: workspacePath })).toString("utf8").trim();
    return HEX40.test(out) ? out : undefined;
  } catch (err) {
    return (err as { status?: unknown } | null)?.status === 1 ? null : undefined;
  }
}

/**
 * The pull's workspace writes (#12718, D25(2)): the push writer's three guarded verbs plus the pinned merge. Exported for the
 * self-heal (server/workspace-sync.ts imports it lazily), which passes `{ autostash: false }` (D37(2)). `merge(target)`:
 *   1. D37(1): a merge in progress (`MERGE_HEAD` / `MERGE_AUTOSTASH` by lstat, fail closed, or an unmerged entry in ONE fresh
 *      tracked-only status run, R2-B) is `in_progress` before any write, and the interrupted autostash is pinned (D36(c));
 *   2. D35: the untracked/ignored collision check (`hasUntrackedCollision`, shapes 1-3) against the in-memory, verified
 *      target is `collision`; a non-ff merge ignores `--no-overwrite-ignore` (measured), so this check, not the flag, guards;
 *   3. the merge child; exit 1 with `MERGE_HEAD` is a content `conflict`; anything else that fails (an unrelated history, a
 *      refusal, a timeout, a signal) is `refused`; both pin a `MERGE_AUTOSTASH` the merge left (D36(c), R2-B);
 *   4. D36(a)(b): after exit 0, a status run that cannot be read is `unverified`; an unmerged entry, or a `refs/stash` that
 *      moved (git parked an autostash it could not re-apply), is `autostash_conflict` (D26(4)); else `clean`.
 * A status or stash read that cannot run before the merge refuses it (`refused`): nothing was written.
 */
export function kbPullWriter(workspacePath: string, opts: { readonly autostash?: boolean } = {}): KbPullWriter {
  const autostash = opts.autostash !== false;
  const base = kbWorkspaceWriter(workspacePath);
  const run = (argv: string[]): Promise<Buffer> => runConnectedRepoGitAsync(argv, { cwd: workspacePath });
  return {
    unpack: base.unpack,
    setTracking: base.setTracking,
    casBranch: base.casBranch,
    merge: async (target): Promise<KbMergeOutcome> => {
      const before = await readTrackedStatus(workspacePath);
      if (before === null) return "refused";
      if (mergeInProgress(workspacePath, before)) {
        await pinInterruptedAutostash(workspacePath);
        return "in_progress";
      }
      try {
        if (await hasUntrackedCollision(run, workspacePath, target)) return "collision";
      } catch {
        return "refused"; // a listing or lstat that could not run: fail closed, nothing written
      }
      const stashBefore = await readStashTip(workspacePath);
      if (stashBefore === undefined) return "refused";
      try {
        await runConnectedRepoGitAsync(mergeArgv(target, { autostash }), {
          cwd: workspacePath,
          timeoutMs: MERGE_TIMEOUT_MS,
          maxBuffer: 16 * 1024 * 1024,
        });
      } catch (err) {
        const code = (err as { status?: unknown } | null)?.status;
        // R2-B (data P2-1): a content conflict on the `--autostash` merge leaves MERGE_HEAD + MERGE_AUTOSTASH; the
        // autostash commit is then reachable from no ref until the user resolves, so it is pinned on this return too.
        await pinInterruptedAutostash(workspacePath);
        return code === 1 && mergeHeadPresent(workspacePath) ? "conflict" : "refused";
      }
      const after = await readTrackedStatus(workspacePath);
      if (after === null) return "unverified";
      const stashAfter = await readStashTip(workspacePath);
      if (stashAfter === undefined) return "unverified";
      if (stashAfter !== stashBefore || after.some((e) => UNMERGED_XY.has(e.xy))) return "autostash_conflict";
      return "clean";
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
 * namespaces (`refs/soleur/worktrees/<id>/`, `soleur-store-tip-*`), and kept by `gc`.
 */
export const AUTOSTASH_PIN_PREFIX = "refs/soleur/autostash/";

/** The largest `MERGE_AUTOSTASH` the pin reads: a 40-hex id and a newline, with room to spare. */
const AUTOSTASH_FILE_MAX_BYTES = 64;

type AutostashRead = { readonly sha: string } | { readonly cause: "unreadable" | "not_regular" | "too_large" | "malformed" } | null;

/** `.git/MERGE_AUTOSTASH`: lstat-checked regular file of at most 64 B, opened O_NOFOLLOW, first line HEX40; null when absent. */
function readMergeAutostash(workspacePath: string): AutostashRead {
  const path = join(workspacePath, ".git", "MERGE_AUTOSTASH");
  let fd: number | undefined;
  try {
    const st = lstatSync(path);
    if (!st.isFile()) return { cause: "not_regular" };
    if (st.size > AUTOSTASH_FILE_MAX_BYTES) return { cause: "too_large" };
    fd = openSync(path, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
    const opened = fstatSync(fd);
    if (!opened.isFile()) return { cause: "not_regular" };
    if (opened.size > AUTOSTASH_FILE_MAX_BYTES) return { cause: "too_large" };
    const buf = Buffer.alloc(AUTOSTASH_FILE_MAX_BYTES + 1);
    const n = readSync(fd, buf, 0, buf.length, 0);
    if (n > AUTOSTASH_FILE_MAX_BYTES) return { cause: "too_large" };
    const first = buf.toString("latin1", 0, n).split("\n")[0] ?? "";
    return guardedSha(first) ? { sha: first } : { cause: "malformed" };
  } catch (err) {
    const code = (err as { code?: unknown } | null)?.code;
    if (code === "ENOENT" || code === "ENOTDIR") return null;
    return { cause: code === "ELOOP" ? "not_regular" : "unreadable" };
  } finally {
    if (fd !== undefined) {
      try {
        closeSync(fd);
      } catch {
        /* nothing to do */
      }
    }
  }
}

/**
 * D36(c): whenever `.git/MERGE_AUTOSTASH` exists, pin the autostash commit as `refs/soleur/autostash/<sha>` so `gc` cannot
 * prune the only copy of the user's uncommitted edits: a merge child killed or refused after it stashed (no `MERGE_HEAD`),
 * AND a content-conflicted `--autostash` merge (`MERGE_HEAD` too, R2-B / data P2-1: the stash stays unreferenced until the
 * user resolves, which can outlast `gc.pruneExpire`). Additive and idempotent (the ref is named by its own value), so `git
 * commit` / `merge --abort` still apply the autostash as usual. `MERGE_AUTOSTASH` itself is never moved or deleted (recovery
 * is #12719). Anything but a small regular file whose first line is 40 hex, or a failed `update-ref`, is no pin and one
 * warning (debounced per workspace and cause). Never throws. Run by the writer (its conflict and refused returns, its entry
 * check), at every `mergeInProgress` refusal of syncPull and syncPush, and at the top of the self-heal's checks.
 */
export async function pinInterruptedAutostash(workspacePath: string): Promise<void> {
  const read = readMergeAutostash(workspacePath);
  if (read === null) return;
  let cause: string;
  if ("sha" in read) {
    try {
      await runConnectedRepoGitAsync(["update-ref", "--no-deref", `${AUTOSTASH_PIN_PREFIX}${read.sha}`, read.sha], { cwd: workspacePath });
      return;
    } catch {
      cause = "pin_failed";
    }
  } else {
    cause = read.cause;
  }
  log.warn({ op: "kb-sync.autostash-pin", cause }, "KB sync: an interrupted merge's autostash could not be pinned");
  mirrorWarnWithDebounce(
    null,
    {
      feature: "session-sync",
      op: "kb-sync.autostash-pin",
      message: "KB sync: an interrupted merge's autostash could not be pinned",
      tags: { cause },
    },
    workspacePath,
    `kb-sync-autostash-pin:${cause}`,
  );
}

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

/** The tail of each workspace's lock queue, keyed on its real path (in-process; the cross-host lease is separate). */
const workspaceGitLocks = new Map<string, Promise<void>>();

/** What `withWorkspaceGitLock` resolves to when its bounded wait expired before the lock was free (`fn` never ran). */
export const WORKSPACE_GIT_LOCK_TIMEOUT = "lock_timeout" as const;
export type WorkspaceGitLockTimeout = typeof WORKSPACE_GIT_LOCK_TIMEOUT;

/** Resolves true when `prev` settles within `waitMs`, false when the wait expires first (a non-finite wait never expires). */
function waitFor(prev: Promise<void>, waitMs: number | undefined): Promise<boolean> {
  if (waitMs === undefined || !Number.isFinite(waitMs)) return prev.then(() => true);
  let timer: ReturnType<typeof setTimeout> | undefined;
  const expired = new Promise<boolean>((resolve) => {
    timer = setTimeout(() => resolve(false), Math.max(0, Math.min(waitMs, 2_147_483_647)));
    (timer as { unref?: () => void }).unref?.();
  });
  return Promise.race([prev.then(() => true), expired]).finally(() => clearTimeout(timer));
}

/**
 * Same-host serialization of the workspace git writers (D38(6)): syncPull, the syncPush publish and the self-heal (its
 * `pull --ff-only`, merge, branch-aside and reset, R2-B) run `fn` under one in-process lock keyed on the workspace's real
 * path (the path itself when it cannot be resolved), so a sibling never reads another's in-flight `MERGE_AUTOSTASH` as an
 * unfinished merge (arch F12). FIFO; a throwing `fn` releases the lock.
 *
 * `waitMs` (verify-coverage P2-1) bounds the wait by what is left of the caller's budget: when the lock is not free in time
 * the call resolves `WORKSPACE_GIT_LOCK_TIMEOUT` and `fn` never runs (syncPull answers `pull_deadline`, the self-heal its
 * route's `pending`). The timed-out caller gives up its place without letting anyone past the holder: the queue tail it
 * appended still waits for the holder, so FIFO holds. A running holder is never interrupted (its git children keep their
 * own bounds; the holders bound their own starts). Without `waitMs` the wait is unbounded, as before.
 */
export function withWorkspaceGitLock<T>(workspacePath: string, fn: () => Promise<T>): Promise<T>;
export function withWorkspaceGitLock<T>(
  workspacePath: string,
  fn: () => Promise<T>,
  opts: { readonly waitMs?: number },
): Promise<T | WorkspaceGitLockTimeout>;
export async function withWorkspaceGitLock<T>(
  workspacePath: string,
  fn: () => Promise<T>,
  opts: { readonly waitMs?: number } = {},
): Promise<T | WorkspaceGitLockTimeout> {
  let key = workspacePath;
  try {
    key = realpathSync(workspacePath);
  } catch {
    /* an unresolvable path keys on itself */
  }
  const prev = workspaceGitLocks.get(key) ?? Promise.resolve();
  let release!: () => void;
  const mine = new Promise<void>((resolve) => {
    release = resolve;
  });
  const tail = prev.then(() => mine);
  workspaceGitLocks.set(key, tail);
  // The entry is dropped only once the tail itself settles (after the holder AND this caller), never on a timeout while
  // the holder still runs: a later caller must still queue behind the holder.
  void tail.then(() => {
    if (workspaceGitLocks.get(key) === tail) workspaceGitLocks.delete(key);
  });
  try {
    if (!(await waitFor(prev, opts.waitMs))) return WORKSPACE_GIT_LOCK_TIMEOUT;
    return await fn();
  } finally {
    release();
  }
}
