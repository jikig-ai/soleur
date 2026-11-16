// Leaf module: `git pull --ff-only` workspace reconcile + gated self-heal,
// extracted from kb-route-helpers so it can be imported by surfaces that must
// stay OUT of the App-Router `next/headers` graph — specifically `c4-writer`,
// which is bundled into the WS/custom server (cc-dispatcher). kb-route-helpers
// re-exports `syncWorkspace`/`SyncWorkspaceResult` so its existing callers are
// unaffected.
//
// Deliberately imports NOTHING from `@/lib/supabase/server` (next/headers).
// Deps: observability (clean), a type-only KbSyncErrorClass, pino's Logger
// type, the token-free local runner (a host-git leaf), node:fs/promises and
// node:path, and a LAZY `@/server/git-auth` import inside syncWorkspace.
import { lstat } from "node:fs/promises";
import {
  mirrorWarnWithDebounce,
  mirrorWithDebounce,
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import type { KbSyncErrorClass } from "@/server/session-sync";
import { runWorkspaceLocalGit, type WorkspaceLocalGitRunner } from "@/server/workspace-local-git";
import type { Logger } from "pino";

// Re-declared as local constants typed by the shared union (the union is the
// source of truth; these are the literal members, NOT a new union). Kept local
// so this module stays free of a runtime session-sync import.
const ERROR_CLASS_NON_FAST_FORWARD: KbSyncErrorClass = "non_fast_forward";
const ERROR_CLASS_SYNC_FAILED: KbSyncErrorClass = "sync_failed";

/**
 * The designed holds of the self-heal (#12600, CTO ruling D16): the workspace keeps local state that is not on GitHub
 * yet, so it was deliberately not updated. Set ONLY by the three refusals (`self-heal-aborted-held-commits`,
 * `-dirty-tracked`, `-untracked-collision`); the branch aborts and `self-heal-failed` leave it unset. A KB write route
 * that sees it answers success plus `workspace_sync: "pending"` (the write already landed on GitHub).
 */
export type SyncWorkspaceHeld = "held_commits" | "dirty_tracked" | "untracked_collision";

export type SyncWorkspaceResult =
  | { ok: true; recovered?: boolean }
  | { ok: false; error: unknown; errorClass: KbSyncErrorClass; held?: SyncWorkspaceHeld };

/**
 * Classify a failed-git error into a {@link KbSyncErrorClass}. Two distinct
 * `git pull --ff-only` aborts (diverged clone, dirty working tree) are
 * self-healable via the same gated `reset --keep refs/remotes/origin/<default>`,
 * so both map to `non_fast_forward`; everything else is `sync_failed`.
 */
function classifyGitSyncError(err: unknown): KbSyncErrorClass {
  const text =
    err instanceof Error
      ? `${err.message}\n${(err as { stderr?: string }).stderr ?? ""}`
      : String(err);
  if (
    text.includes("Not possible to fast-forward") ||
    text.includes("would be overwritten by merge") ||
    text.includes("commit your changes or stash")
  ) {
    return ERROR_CLASS_NON_FAST_FORWARD;
  }
  return ERROR_CLASS_SYNC_FAILED;
}

/**
 * `git status --porcelain -z --untracked-files=no` output names at least one tracked change, `knowledge-base/` included
 * (#12600, CTO ruling D6b: the R18 KB exemption is gone, since a hard reset erases an in-flight KB edit exactly as it
 * erases a code edit). Untracked files are not listed, and survive a reset unless an incoming tracked path collides.
 */
function hasTrackedChange(out: Buffer | string): boolean {
  return out.toString().split("\0").some((entry) => entry.length >= 4);
}

/** Exit status of a `diff --quiet` (0 = no difference, 1 = difference); any other outcome throws (fail closed). */
async function diffQuietExit(
  runLocal: WorkspaceLocalGitRunner,
  args: string[],
  opts: { cwd: string; timeout: number },
): Promise<0 | 1> {
  try {
    await runLocal(args, opts);
    return 0;
  } catch (err) {
    if ((err as { code?: unknown }).code === 1) return 1;
    throw err;
  }
}

/**
 * Resolve the workspace clone's default branch (e.g. `main`) from `git symbolic-ref refs/remotes/origin/HEAD`, a LOCAL
 * read, so it runs token-free through `runLocal` (#12600, CTO ruling D15(d), amending D6(d)). The FULL target refname is
 * parsed, never `--short`: an agent-made `refs/heads/origin/main` makes `origin/main` ambiguous and `--short` then prints
 * `remotes/origin/main`. Falls back to `main` when the symbolic ref is missing or names something else.
 */
async function resolveDefaultBranch(runLocal: WorkspaceLocalGitRunner, workspacePath: string): Promise<string> {
  try {
    const out = await runLocal(["symbolic-ref", "refs/remotes/origin/HEAD"], { cwd: workspacePath, timeout: 30_000 });
    const ref = out.toString().trim(); // e.g. "refs/remotes/origin/main"
    const prefix = "refs/remotes/origin/";
    return (ref.startsWith(prefix) && ref.slice(prefix.length)) || "main";
  } catch {
    return "main";
  }
}

/**
 * Pull the workspace to sync local files with the remote repo after a
 * successful GitHub mutation. On a `non_fast_forward` (diverged clone OR dirty
 * working tree) it attempts a GATED, OBSERVABLE self-heal on the default
 * branch: a `reset --keep refs/remotes/origin/<default>` that runs only when it
 * loses no tracked, committed, untracked or ignored file (a clean tracked tree,
 * local commits whose content is already upstream, which are first branched
 * aside to a durable ref, and nothing on disk in the reset's way). Anything else
 * refuses (see {@link selfHealNonFastForward}). Returns a
 * {@link SyncWorkspaceResult}; the three designed holds set `held` (D16).
 *
 * Reporting is split by recoverability so a self-healed abort does NOT page the
 * operator: the self-healable `non_fast_forward` class logs only an info
 * breadcrumb here and lets the self-heal branches own Sentry escalation
 * (op:self-heal-aborted-dirty / -detached-head / op:self-heal-failed at error,
 * the designed holds op:self-heal-aborted-dirty-tracked / -held-commits /
 * -untracked-collision at warning, op:self-heal-reset warn on recovery); only the non-self-healable `sync_failed`
 * class emits the error-level `log.error`+`reportSilentFallback` mirror. See
 * Sentry 9ccf1d86… — the unconditional pre-self-heal `log.error({ err })`
 * pino-mirrored to Sentry on every push for a benign, recovered dirty-tree
 * abort (historically the c4 re-render published model.likec4.json into the
 * tracked tree; that source was removed in #4976, but the self-heal stays as
 * general defense against any other dirty-tree cause).
 */
export async function syncWorkspace(
  installationId: number,
  workspacePath: string,
  log: Logger,
  context: {
    userId: string;
    op: "delete" | "rename" | "upload" | "push" | "manual";
  },
): Promise<SyncWorkspaceResult> {
  const { gitWithInstallationAuth } = await import("@/server/git-auth");
  try {
    await gitWithInstallationAuth(["pull", "--ff-only"], installationId, {
      cwd: workspacePath,
      timeout: 30_000,
    });
    return { ok: true };
  } catch (syncError) {
    const errorClass = classifyGitSyncError(syncError);

    if (errorClass === ERROR_CLASS_NON_FAST_FORWARD) {
      // Self-healable: a diverged clone OR a dirty working tree (e.g. a
      // spurious mirror edit; historically also the c4 re-render's tracked-path
      // write to model.likec4.json, removed in #4976). A blocked ff-only pull
      // that the gated `reset --keep`
      // recovers is BENIGN churn — do NOT emit an error-level mirror here. The
      // pino `log.error({ err })` path mirrors to Sentry (logger.ts →
      // captureException, tag feature:"pino-mirror", level error), which paged
      // the operator on every push for a condition that self-heals (Sentry
      // 9ccf1d86…). Record an info breadcrumb only (Better Stack drain; below
      // the WARN+ Sentry-mirror threshold, and no `err` key so nothing is
      // captured) and let selfHealNonFastForward own escalation: it mirrors
      // op:self-heal-aborted-dirty (feature-branch) /
      // op:self-heal-aborted-detached-head (detached) / op:self-heal-failed
      // at error and op:self-heal-aborted-dirty-tracked /
      // op:self-heal-aborted-held-commits /
      // op:self-heal-aborted-untracked-collision at warning when recovery does NOT
      // happen, and warns op:self-heal-reset (phantom zero-commit reset) /
      // op:self-heal-recovered-diverged (upstream-equivalent default-branch
      // commits branched aside + reset) on success.
      log.info(
        { userId: context.userId, op: context.op, errorClass },
        `kb/${context.op}: ff-only pull blocked — attempting gated self-heal`,
      );
      return await selfHealNonFastForward(
        gitWithInstallationAuth,
        runWorkspaceLocalGit,
        installationId,
        workspacePath,
        log,
        context,
      );
    }

    // Non-self-healable (`sync_failed`) — a genuine failure worth paging.
    log.error(
      { err: syncError, userId: context.userId, op: context.op, errorClass },
      `kb/${context.op}: workspace sync failed`,
    );
    reportSilentFallback(syncError, {
      feature: "kb-route-helpers",
      op: `workspace-sync-${context.op}`,
      // workspacePath omitted — the path embeds raw userId
      // (workspacePath = `<root>/<userId>`) and bypasses the
      // hashExtraUserId top-level rename (Recital 26).
      extra: { userId: context.userId },
      message: `kb/${context.op}: workspace sync failed`,
    });
    return { ok: false, error: syncError, errorClass };
  }
}

/** Interim `reason` of `self-heal-aborted-held-commits` until the Phase 9 hardened pull-merge (#12718) is called here. */
const HELD_COMMITS_REASON_INTERIM = "merge_not_attempted";

/**
 * The full remote-tracking refname of the default branch: never `@{u}` (resolved from the agent-writable
 * `branch.<D>.remote` / `.merge`, CTO ruling D15(b)) and never a bare `origin/<D>` (DWIM resolves `refs/heads/origin/<D>`
 * and tags before `refs/remotes/`, D15(c)). Used in the rev-list, both content diffs, the precheck and the reset.
 */
const remoteTrackingRef = (defaultBranch: string): string => `refs/remotes/origin/${defaultBranch}`;

const APP_FRAME_DIRS = ["server", "app", "lib"] as const;
const APP_ROOT_ANCHOR = "apps/web-platform/";
const FRAME_RE = /^[\w./-]+:\d+$/;
const STACK_AT_RE = /^\s*at (?:.*?\()?([^()\s]+?):(\d+)(?::\d+)?\)?\s*$/;

/**
 * The first stack frame of `err` under the app's `server/`, `app/` or `lib/`, as a repo-relative `file:line` matching
 * `[\w./-]+:\d+` (CTO ruling D20, amending D8), or undefined when none matches. Only the stack's `at` lines AFTER the
 * `<name>: <message>` header are read, so the message (git argv, stderr) never reaches the frame; `node:` internals and
 * `node_modules` are skipped. A code location carries no argv or user data, and it splits an otherwise unlocalisable
 * `self-heal-failed` group by the line that threw.
 */
export function firstAppFrame(err: unknown): string | undefined {
  if (!(err instanceof Error) || typeof err.stack !== "string") return undefined;
  const header = `${err.name}: ${err.message}`;
  const frames = err.stack.startsWith(header) ? err.stack.slice(header.length) : err.stack;
  for (const line of frames.split("\n")) {
    const m = STACK_AT_RE.exec(line);
    if (!m) continue;
    const file = m[1].replace(/\\/g, "/");
    if (file.startsWith("node:") || file.includes("/node_modules/")) continue;
    const anchor = file.lastIndexOf(APP_ROOT_ANCHOR);
    let rel: string;
    if (anchor >= 0) {
      rel = file.slice(anchor + APP_ROOT_ANCHOR.length);
    } else {
      const idx = Math.max(...APP_FRAME_DIRS.map((d) => file.lastIndexOf(`/${d}/`)));
      if (idx < 0) continue;
      rel = file.slice(idx + 1);
    }
    if (!APP_FRAME_DIRS.some((d) => rel.startsWith(`${d}/`))) continue;
    const frame = `${rel}:${m[2]}`;
    if (FRAME_RE.test(frame)) return frame;
  }
  return undefined;
}

/** `diff --name-status -z` output as raw added and deleted path bytes (a filename is bytes, not UTF-8). */
function parseNameStatusZ(out: Buffer): { added: Buffer[]; deleted: Buffer[] } {
  const fields: Buffer[] = [];
  let start = 0;
  for (let i = 0; i < out.length; i++) {
    if (out[i] === 0) {
      fields.push(out.subarray(start, i));
      start = i + 1;
    }
  }
  if (start !== out.length || fields.length % 2 !== 0) throw new Error("untracked-collision precheck: malformed diff output");
  const added: Buffer[] = [];
  const deleted: Buffer[] = [];
  for (let i = 0; i < fields.length; i += 2) {
    const status = fields[i].toString("latin1");
    if (status === "A") added.push(fields[i + 1]);
    else if (status === "D") deleted.push(fields[i + 1]);
    else throw new Error("untracked-collision precheck: unexpected diff status");
  }
  return { added, deleted };
}

/** `lstat` without following a symlink; null when nothing is there (or a leading component is not a directory). */
async function lstatOrNull(path: Buffer): Promise<Awaited<ReturnType<typeof lstat>> | null> {
  try {
    return await lstat(path);
  } catch (err) {
    const code = (err as { code?: unknown }).code;
    if (code === "ENOENT" || code === "ENOTDIR") return null;
    throw err;
  }
}

const SLASH = 0x2f;

/** Every proper leading directory of `p` (`a`, `a/b` for `a/b/c`), as subarrays of `p`. */
function leadingDirs(p: Buffer): Buffer[] {
  const out: Buffer[] = [];
  for (let i = p.indexOf(SLASH); i > 0; i = p.indexOf(SLASH, i + 1)) out.push(p.subarray(0, i));
  return out;
}

/**
 * CTO ruling D15(a): true when the reset to `target` would replace or remove an on-disk entry that HEAD does not track.
 * The tracked tree is already clean (D6b), so the index equals HEAD and every entry the reset can touch is a path that
 * `diff --name-status -z --no-renames --diff-filter=AD HEAD <target>` lists (`--name-status` rather than `--name-only`
 * so one call tells an added path from a deleted one). Three shapes refuse:
 *  1. an existing entry (lstat, no symlink follow) at an added path, unless it is a tracked directory the target turns
 *     into a file, which is shape 3;
 *  2. an existing non-directory at a leading directory of an added path that is not itself a deleted tracked path;
 *  3. an untracked OR IGNORED entry under a tracked directory an added path turns into a file:
 *     `ls-files -z --others -- :(literal)<p>/` with no `--exclude-standard`, so ignored files are listed too.
 * `reset --keep` refuses shapes 1-2 for untracked files by itself but overwrites an IGNORED file (measured, git 2.56),
 * which is why this precheck, not `--keep`, is the guard; a `--keep` refusal reaching the catch means a missed shape.
 * A path that is not valid UTF-8 cannot be passed as an argv pathspec, so shape 3 on such a path refuses (fail closed).
 */
async function hasUntrackedCollision(
  runLocal: WorkspaceLocalGitRunner,
  workspacePath: string,
  target: string,
  gitOpts: { cwd: string; timeout: number },
): Promise<boolean> {
  const listing = await runLocal(
    ["diff", "--name-status", "-z", "--no-renames", "--diff-filter=AD", "HEAD", target, "--"],
    gitOpts,
  );
  const { added, deleted } = parseNameStatusZ(Buffer.isBuffer(listing) ? listing : Buffer.from(String(listing)));
  if (added.length === 0) return false;
  const deletedPaths = new Set(deleted.map((p) => p.toString("latin1")));
  const deletedDirs = new Set(deleted.flatMap((p) => leadingDirs(p).map((d) => d.toString("latin1"))));
  const onDisk = (rel: Buffer): Buffer => Buffer.concat([Buffer.from(`${workspacePath}/`), rel]);

  for (const p of added) {
    const at = await lstatOrNull(onDisk(p));
    if (at) {
      if (!(at.isDirectory() && deletedDirs.has(p.toString("latin1")))) return true; // shape 1
      const name = p.toString("utf8");
      if (!Buffer.from(name, "utf8").equals(p)) return true;
      const others = await runLocal(["ls-files", "-z", "--others", "--", `:(literal)${name}/`], gitOpts);
      if (others.length > 0) return true; // shape 3
      continue;
    }
    for (const dir of leadingDirs(p)) {
      const lead = await lstatOrNull(onDisk(dir));
      if (!lead) break;
      if (lead.isDirectory()) continue;
      if (deletedPaths.has(dir.toString("latin1"))) break; // a tracked file the reset removes first
      return true; // shape 2
    }
  }
  return false;
}

/**
 * Gated self-heal for a `non_fast_forward` clone (#12600, CTO rulings D6-D8, D15, D16, D20). The `reset --keep` runs only
 * when it loses no tracked, committed, untracked or ignored file. In order:
 *  1. `symbolic-ref` (token-free, D15d), `fetch origin <default>` (token-bearing, X3), then `rev-parse --abbrev-ref HEAD`
 *     and `status --porcelain -z --untracked-files=no` ONCE, above the zero/non-zero commit split, so both arms are gated.
 *  2. `rev-list --count refs/remotes/origin/<D>..HEAD` (D15b), then the branch check, on both arms (D6f): a detached
 *     HEAD aborts as op:self-heal-aborted-detached-head; a feature branch (tag head=non_default) or an un-countable count
 *     (tag head=uncountable, its own message) as op:self-heal-aborted-dirty. Both at error, debounced per workspace
 *     (D15e). The `-dirty` slug is a MISNOMER kept for continuity (4 test consumers, no alert keys on it): it never means
 *     a dirty tree, which is `-dirty-tracked`.
 *  3. ANY tracked change, `knowledge-base/` included -> refuse (op:self-heal-aborted-dirty-tracked, held dirty_tracked).
 *  4. With local commits: refuse unless their content is upstream - `diff --quiet refs/remotes/origin/D...HEAD -- .
 *     ':(exclude)knowledge-base/'` exits 0 AND the `knowledge-base` trees of HEAD and the remote-tracking ref are equal
 *     (the squash-merged side-PR case); else op:self-heal-aborted-held-commits, tags `held_kind` = nonkb | kb and
 *     `reason`, debounce class `<op>:<held_kind>` (D20), held held_commits.
 *  5. The untracked-collision precheck ({@link hasUntrackedCollision}) on both arms, BEFORE the branch-aside so a refusal
 *     leaves no recovery branch: op:self-heal-aborted-untracked-collision, tag `arm` = phantom | diverged, no paths in
 *     tags or extra, held untracked_collision.
 *  6. With local commits, the branch-aside to `soleur/recovered-kb-sync-*`; then `reset --keep refs/remotes/origin/<D>`
 *     (op:self-heal-recovered-diverged, or op:self-heal-reset on the phantom arm).
 * Every local verb runs token-free through `runLocal`; only `fetch origin` and the `pull --ff-only` carry the token. Every
 * emit passes a null error and carries its details in tags / extra (D8, the #8629 Error-path tag loss); `self-heal-failed`
 * adds `extra.frame` (D20). The three refusals are designed holds the next session-start pull resolves, so they warn,
 * debounced per workspace (D7, D6e). Payloads OMIT workspacePath (raw userId) per the Recital 26 omission above; the
 * debounce key is in-process only.
 */
async function selfHealNonFastForward(
  gitWithInstallationAuth: (
    args: string[],
    installationId: number,
    opts: { cwd: string; timeout: number },
  ) => Promise<Buffer | string>,
  runLocal: WorkspaceLocalGitRunner,
  installationId: number,
  workspacePath: string,
  log: Logger,
  context: { userId: string; op: string },
): Promise<SyncWorkspaceResult> {
  const gitOpts = { cwd: workspacePath, timeout: 30_000 };
  const extra = { userId: context.userId };
  const refuse = (reason: string, held?: SyncWorkspaceHeld): SyncWorkspaceResult => ({
    ok: false,
    error: new Error(reason),
    errorClass: ERROR_CLASS_NON_FAST_FORWARD,
    ...(held ? { held } : {}),
  });
  try {
    const defaultBranch = await resolveDefaultBranch(runLocal, workspacePath);
    const target = remoteTrackingRef(defaultBranch);

    await gitWithInstallationAuth(
      ["fetch", "origin", defaultBranch],
      installationId,
      gitOpts,
    );

    // D6a: both reads hoisted above the zero/non-zero commit split. `--abbrev-ref HEAD` emits the branch's short name,
    // or the literal "HEAD" when detached. A failing read throws into the catch below (fail closed: no reset).
    const headRef = (await runLocal(["rev-parse", "--abbrev-ref", "HEAD"], gitOpts)).toString().trim();
    const statusOut = await runLocal(["status", "--porcelain", "-z", "--untracked-files=no"], gitOpts);

    // Local-commit count against the remote-tracking ref (D15b). Read before the branch check so an un-countable count
    // (NaN) aborts like a feature branch.
    let localCommits = Number.NaN;
    if (headRef !== "HEAD") {
      localCommits = parseInt((await runLocal(["rev-list", "--count", `${target}..HEAD`], gitOpts)).toString().trim(), 10);
    }

    // D6f: recover ONLY on the default branch, on BOTH arms. A phantom reset on a feature branch would move that branch
    // onto the default branch. A detached HEAD gets a DISTINCT, queryable slug so it is never bucketed into the
    // feature-branch abort; an un-countable count keeps the `-dirty` slug with its own tag and message (D15e).
    if (headRef === "HEAD" || headRef !== defaultBranch || Number.isNaN(localCommits)) {
      const head = headRef === "HEAD" ? "detached" : headRef !== defaultBranch ? "non_default" : "uncountable";
      const abortOp = head === "detached" ? "self-heal-aborted-detached-head" : "self-heal-aborted-dirty";
      const what =
        head === "detached" ? "detached HEAD" : head === "non_default" ? "not on the default branch" : "local-commit count unreadable";
      log.error({ userId: context.userId, op: context.op, localCommits, head }, `kb/${context.op}: self-heal aborted — ${what}`);
      mirrorWithDebounce(
        null,
        { feature: "kb-route-helpers", op: abortOp, tags: { head }, extra, message: `kb/${context.op}: self-heal aborted (${what})` },
        workspacePath,
        abortOp,
      );
      return refuse(`non-fast-forward clone ${what}`);
    }

    // D6b: any tracked change refuses, knowledge-base/ included. The stall ends at the next session-start
    // `pull --no-rebase --autostash`; #5221 keeps the broader recovery-and-lock work.
    if (hasTrackedChange(statusOut)) {
      const op = "self-heal-aborted-dirty-tracked";
      log.warn({ userId: context.userId, op: context.op, localCommits }, `kb/${context.op}: self-heal aborted — tracked changes in the working tree`);
      mirrorWarnWithDebounce(
        null,
        { feature: "kb-route-helpers", op, extra, message: `kb/${context.op}: self-heal aborted (tracked changes in the working tree)` },
        workspacePath,
        op,
      );
      return refuse("non-fast-forward with tracked changes in the working tree", "dirty_tracked");
    }

    if (localCommits > 0) {
      // D6c: reset only when the local commits' content is already upstream. Tree-to-tree diffs: no worktree read, no
      // clean/smudge filter; `--no-ext-diff --no-textconv` keep any configured diff helper out. The KB check compares
      // the two `knowledge-base` trees (equal trees <=> no diff under that pathspec, both-absent included).
      const nonKbHeld =
        (await diffQuietExit(
          runLocal,
          ["diff", "--quiet", "--no-ext-diff", "--no-textconv", `${target}...HEAD`, "--", ".", ":(exclude)knowledge-base/"],
          gitOpts,
        )) === 1;
      const kbHeld =
        !nonKbHeld &&
        (await diffQuietExit(
          runLocal,
          ["diff", "--quiet", "--no-ext-diff", "--no-textconv", target, "HEAD", "--", "knowledge-base/"],
          gitOpts,
        )) === 1;
      if (nonKbHeld || kbHeld) {
        // Phase 9 (D6c): call the hardened pull-merge routine (X1) here; on any X1 refusal emit this op with its reason.
        const op = "self-heal-aborted-held-commits";
        const heldKind = nonKbHeld ? "nonkb" : "kb";
        log.warn(
          { userId: context.userId, op: context.op, localCommits, heldKind },
          `kb/${context.op}: self-heal aborted — local commits hold content upstream lacks`,
        );
        mirrorWarnWithDebounce(
          null,
          {
            feature: "kb-route-helpers",
            op,
            tags: { held_kind: heldKind, reason: HELD_COMMITS_REASON_INTERIM },
            extra: { ...extra, localCommits },
            message: `kb/${context.op}: self-heal aborted (held ${heldKind} commits)`,
          },
          workspacePath,
          `${op}:${heldKind}`,
        );
        return refuse("non-fast-forward with held local commits", "held_commits");
      }
    }

    // D15(a): nothing the reset can replace may be an entry HEAD does not track (untracked or ignored). Both arms; before
    // the branch-aside, so a refusal leaves no recovery branch behind.
    if (await hasUntrackedCollision(runLocal, workspacePath, target, gitOpts)) {
      const op = "self-heal-aborted-untracked-collision";
      const arm = localCommits > 0 ? "diverged" : "phantom";
      log.warn(
        { userId: context.userId, op: context.op, localCommits, arm },
        `kb/${context.op}: self-heal aborted — an untracked or ignored file is in the reset's way`,
      );
      mirrorWarnWithDebounce(
        null,
        { feature: "kb-route-helpers", op, tags: { arm }, extra, message: `kb/${context.op}: self-heal aborted (an untracked or ignored file is in the reset's way)` },
        workspacePath,
        op,
      );
      return refuse("non-fast-forward with an untracked or ignored file in the reset's way", "untracked_collision");
    }

    // `recoveryBranch` is set ONLY when un-pushed commits are branched aside; it distinguishes the recovered-diverged
    // path from the phantom (zero-commit) reset for observability below. The local commits' content is upstream (a
    // squash-merged side PR): keep the commit objects on a durable named ref (recoverable without SSH), then reset. The
    // timestamp avoids clobbering a prior recovery branch.
    let recoveryBranch: string | null = null;
    if (localCommits > 0) {
      recoveryBranch = `soleur/recovered-kb-sync-${Date.now()}`;
      await runLocal(["branch", recoveryBranch, "HEAD"], gitOpts);
    }

    // Reached by the phantom (zero-commit) divergence OR after the branch-aside above, on a clean tracked tree with nothing
    // untracked in the way. `--keep` (D15a) is the structural backstop: it refuses rather than overwrite an untracked
    // file at a path it must write, and on a clean tracked tree it changes nothing else versus `--hard`.
    await runLocal(["reset", "--keep", target], gitOpts);

    if (recoveryBranch) {
      log.warn(
        { userId: context.userId, op: context.op, defaultBranch, localCommits, recoveryBranch },
        `kb/${context.op}: self-heal recovered diverged default-branch clone — branched ${localCommits} commit(s) aside to ${recoveryBranch}, reset to origin/${defaultBranch}`,
      );
      warnSilentFallback(null, {
        feature: "kb-route-helpers",
        op: "self-heal-recovered-diverged",
        extra: { ...extra, localCommits },
        message: `kb/${context.op}: diverged clone recovered (branched ${localCommits} commit(s) aside, reset to origin/${defaultBranch})`,
      });
      return { ok: true, recovered: true };
    }

    // Phantom divergence (upstream force-push / corrupted ref). Safe reset, no commits were stranded.
    log.warn(
      { userId: context.userId, op: context.op, defaultBranch },
      `kb/${context.op}: self-heal reset clone to origin/${defaultBranch}`,
    );
    warnSilentFallback(null, {
      feature: "kb-route-helpers",
      op: "self-heal-reset",
      extra,
      message: `kb/${context.op}: workspace clone self-healed (reset to origin/${defaultBranch})`,
    });
    return { ok: true, recovered: true };
  } catch (healError) {
    // No `err` key (the pino error mirror would capture it untagged first, #8629) and no message (argv): the name and,
    // when one exists, the first app code frame (D20).
    const errName = healError instanceof Error ? healError.name : typeof healError;
    const frame = firstAppFrame(healError);
    log.error({ userId: context.userId, op: context.op, errName, ...(frame ? { frame } : {}) }, `kb/${context.op}: self-heal failed`);
    reportSilentFallback(null, {
      feature: "kb-route-helpers",
      op: "self-heal-failed",
      extra: { ...extra, errName, ...(frame ? { frame } : {}) },
      message: `kb/${context.op}: self-heal failed`,
    });
    return {
      ok: false,
      error: healError,
      errorClass: ERROR_CLASS_NON_FAST_FORWARD,
    };
  }
}
