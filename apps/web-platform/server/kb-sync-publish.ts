// ---------------------------------------------------------------------------
// KB sync publish: the push half of the post-session sync (#12600, CTO ruling R6).
//
// Guard 1 (KB-only publish gate, plan "Guard Contract"): every ref update the post-session sync sends (the default
// branch or `soleur/kb-sync`) names a commit the server built, whose root tree equals the hash-verified remote base's
// root tree in every entry except `knowledge-base`, whose message and identity are Soleur's, and which never drops
// knowledge-base content the remote holds and the workspace never saw. Every sync push call site lives in this module.
// ---------------------------------------------------------------------------

import { mirrorWarnWithDebounce } from "@/server/observability";
import { validateBranchFormat } from "./branch-validation";
import { gitWithInstallationAuth } from "./git-auth";
import { runIsolatedGitLocal, verifyObject } from "./git-isolated-local";
import { createIsolatedPushDir, type IsolatedPushDirHandle } from "./git-isolated-push-dir";
import { createChildLogger } from "./logger";
import { AGENT_AUTHOR_EMAIL, AGENT_AUTHOR_NAME, disposeIsolated } from "./push-branch";

const log = createChildLogger("session-sync");

// #5426 — push-error classification for the protected-branch fallback.
// `protected_branch` routes to the side-branch + PR fallback; `persistent_other`
// is a non-protection reject that must NOT silently retry-loop (notably
// `shallow update not allowed` — these are shallow clones); `other` keeps the
// existing best-effort retry-next-session behaviour (auth/network/transient).
export type PushErrorClass = "protected_branch" | "persistent_other" | "other";

/** GitHub's protected-branch reject, as the first token of a `remote:` line (R2, R16). */
const GH006_LINE_RE = /^remote: error: GH006:/m;

/**
 * Classify a failed `git push` error from git's STDERR only (#12600, CTO rulings R2, R16). The protected-branch
 * fallback keys on the line-anchored `remote: error: GH006:` GitHub prints, so neither a ref name inside git's own
 * status line nor `err.message` (which embeds argv: the URL and the pushed refspec) can steer it. `GH013` (rulesets)
 * stays `other` (follow-up #12734). Narrow by design: auth/network rejections fall through to `other`.
 */
export function classifyPushError(err: unknown): PushErrorClass {
  if (!(err instanceof Error)) return "other";
  const raw = (err as { stderr?: unknown }).stderr;
  const stderr = Buffer.isBuffer(raw) ? raw.toString("utf8") : typeof raw === "string" ? raw : "";
  if (GH006_LINE_RE.test(stderr.replace(/\r/g, ""))) return "protected_branch";
  if (stderr.includes("shallow update not allowed")) return "persistent_other";
  return "other";
}

// #5426 — protected-branch fallback. When the user's default branch is
// protected, the post-session KB commit can't be pushed onto it; instead we
// accrete the latest KB tree onto a durable side branch in the user's OWN repo
// and open/update a never-auto-merged PR into their default branch.
const KB_SYNC_SIDE_BRANCH = "soleur/kb-sync";
const KB_SYNC_SIDE_COMMIT_MSG = "Soleur: sync knowledge-base";
const KB_SYNC_PR_TITLE = "Soleur: knowledge-base sync";

// GitHub owner/repo charset (mirrors agent-runner.ts:1525-1538 GITHUB_NAME_RE).
const GITHUB_NAME_RE = /^[a-zA-Z0-9._-]+$/;

function kbSyncPrBody(defaultBranch: string): string {
  return [
    "Soleur keeps your knowledge-base in sync after every session.",
    "",
    `Your default branch (\`${defaultBranch}\`) is protected, so these`,
    `knowledge-base updates were routed to the \`${KB_SYNC_SIDE_BRANCH}\` branch`,
    "instead of being pushed directly.",
    "",
    "Merge this PR whenever you're ready — Soleur will never auto-merge it.",
    "Future sessions accrete onto this same branch and PR.",
  ].join("\n");
}

/**
 * Parse `{owner, repo}` from a connected-repo URL using the same shape as
 * agent-runner.ts (URL pathname split + GITHUB_NAME_RE guard, ADR-044 canonical
 * workspace read). `getCurrentRepoUrl` already strips a trailing `.git` via
 * `normalizeRepoUrl`; the defensive strip here tolerates an un-normalized row.
 * Returns empty strings when the URL is null/malformed — the caller treats that
 * as a fallback abort (writes preserved).
 */
function parseOwnerRepo(repoUrl: string | null): {
  owner: string;
  repo: string;
} {
  if (!repoUrl) return { owner: "", repo: "" };
  let owner = "";
  let repo = "";
  try {
    const segments = new URL(repoUrl).pathname.split("/").filter(Boolean);
    owner = segments[0] ?? "";
    repo = (segments[1] ?? "").replace(/\.git$/i, "");
  } catch {
    return { owner: "", repo: "" };
  }
  if (!GITHUB_NAME_RE.test(owner) || !GITHUB_NAME_RE.test(repo)) {
    return { owner: "", repo: "" };
  }
  return { owner, repo };
}

/**
 * Resolve the remote default branch (mirrors `workspace-sync.ts`'s
 * `resolveDefaultBranch`: `symbolic-ref --short refs/remotes/origin/HEAD`,
 * stripping the `origin/` prefix). Falls back to `main` on any error so the
 * fallback never hard-fails on a missing origin/HEAD ref.
 */
async function resolveDefaultBranchForFallback(
  installationId: number,
  workspacePath: string,
): Promise<string> {
  try {
    const out = await gitWithInstallationAuth(
      ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
      installationId,
      { cwd: workspacePath, timeout: 30_000 },
    );
    const branch = out.toString().trim().replace(/^origin\//, "");
    return branch || "main";
  } catch {
    return "main";
  }
}

/**
 * Protected-branch fallback for `syncPush`. Accretes the latest KB tree onto a
 * durable `soleur/kb-sync` side branch via TREE-OVERLAY (not cherry-pick, not
 * `checkout -B` from default — both would lose the side branch's prior commits;
 * see plan R1/AC4) and opens/updates a non-draft, never-auto-merged PR into the
 * user's default branch.
 *
 * Ordering is load-bearing: the local default branch is reset to
 * `origin/<default>` ONLY AFTER the side-branch push + PR succeed. On any
 * failure the un-pushed commit stays on default (default NOT reset) and HEAD is
 * restored to the default branch, so next session retries with no data loss
 * (AC6). All git runs via `gitWithInstallationAuth` — `runConnectedRepoGit`
 * forbids checkout/branch/reset/push.
 *
 * Returns `{ ok: false }` on any failure (the caller emits the failure op);
 * never throws.
 */
export async function runProtectedFallback(
  userId: string,
  workspacePath: string,
  installationId: number,
): Promise<{ ok: boolean; prUrl?: string; commitCount?: number }> {
  const git = (args: string[]) =>
    gitWithInstallationAuth(args, installationId, {
      cwd: workspacePath,
      timeout: 60_000,
    });

  let defaultBranch = "main";
  let restoredClean = false;
  try {
    defaultBranch = await resolveDefaultBranchForFallback(
      installationId,
      workspacePath,
    );

    const { getCurrentRepoUrl } = await import("./current-repo-url");
    const repoUrl = await getCurrentRepoUrl(userId);
    const { owner, repo } = parseOwnerRepo(repoUrl);
    if (!owner || !repo) {
      throw new Error(
        "protected-fallback: could not resolve owner/repo from repo_url",
      );
    }

    // Capture the stranded default tip — its KB tree is what we overlay onto
    // the side branch. Captured BEFORE any branch switch.
    const defaultHead = (await git(["rev-parse", "HEAD"])).toString().trim();

    let commitCount = 0;
    try {
      commitCount =
        parseInt(
          (
            await git([
              "rev-list",
              "--count",
              `origin/${defaultBranch}..HEAD`,
            ])
          )
            .toString()
            .trim(),
          10,
        ) || 0;
    } catch {
      commitCount = 0;
    }

    // Bring origin/<default> and the side branch (may not exist yet) up to date.
    await git(["fetch", "origin", defaultBranch]);
    let sideExists = false;
    try {
      await git(["fetch", "origin", KB_SYNC_SIDE_BRANCH]);
      sideExists = true;
    } catch {
      sideExists = false;
    }
    if (!sideExists) {
      try {
        await git([
          "rev-parse",
          "--verify",
          "--quiet",
          `refs/remotes/origin/${KB_SYNC_SIDE_BRANCH}`,
        ]);
        sideExists = true;
      } catch {
        sideExists = false;
      }
    }

    // Tree-overlay accretion. Base the local side branch on the EXISTING side
    // branch (preserving its prior commits) when present, else branch it from
    // origin/<default>. Never base it on the stranded default tip.
    //
    // `-f`: the auto-commit allowlist (ALLOWED_AUTOCOMMIT_PATHS) deliberately
    // leaves non-`knowledge-base/` tracked files dirty. Without -f, this
    // branch switch aborts ("local changes would be overwritten") whenever a
    // dirty tracked non-KB file differs in the side branch's tree — silently
    // stranding the fallback every session. Forcing discards only those
    // never-synced working-tree edits (they are never committed, never pushed,
    // and the success-path `reset --hard origin/<default>` below already
    // discards them), so -f loses nothing the fallback wouldn't drop anyway.
    await git([
      "checkout",
      "-f",
      "-B",
      KB_SYNC_SIDE_BRANCH,
      sideExists
        ? `origin/${KB_SYNC_SIDE_BRANCH}`
        : `origin/${defaultBranch}`,
    ]);
    // Overlay the latest KB tree from the captured default tip.
    await git(["checkout", defaultHead, "--", "knowledge-base"]);

    // Commit only when the overlay introduced changes (idempotent re-entry, AC7).
    let hasStaged = true;
    try {
      await git(["diff", "--cached", "--quiet"]);
      hasStaged = false;
    } catch {
      hasStaged = true;
    }
    if (hasStaged) {
      await git(["commit", "-m", KB_SYNC_SIDE_COMMIT_MSG]);
    }

    // Push the side branch fast-forward (no --force). A non-fast-forward reject
    // (concurrent co-member push, R3) throws → caught below → default NOT reset.
    await git(["push", "origin", `HEAD:refs/heads/${KB_SYNC_SIDE_BRANCH}`]);

    // Create-or-update the PR in the user's OWN repo. Dynamic import keeps
    // github-app out of session-sync's static graph (sibling tests mock
    // git-auth but not github-app).
    const { createPullRequest, findOpenPullRequest } = await import(
      "./github-app"
    );
    const existing = await findOpenPullRequest(
      installationId,
      owner,
      repo,
      KB_SYNC_SIDE_BRANCH,
      defaultBranch,
    );
    let prUrl: string | undefined;
    if (existing) {
      prUrl = existing.htmlUrl;
    } else {
      const pr = await createPullRequest(
        installationId,
        owner,
        repo,
        KB_SYNC_SIDE_BRANCH,
        defaultBranch,
        KB_SYNC_PR_TITLE,
        kbSyncPrBody(defaultBranch),
      );
      prUrl = pr.htmlUrl;
    }

    // SUCCESS — only now drop the orphan commit from default so it ends `==
    // origin/<default>` (selfHeal then stays cold; AC3/R2).
    await git(["checkout", defaultBranch]);
    await git(["reset", "--hard", `origin/${defaultBranch}`]);
    restoredClean = true;

    return { ok: true, prUrl, commitCount };
  } catch (err) {
    // Failure preserves writes: do NOT reset default. Restore HEAD to the
    // default branch (without reset) so the un-pushed commit survives there for
    // next-session retry and the workspace isn't left parked on the side branch.
    if (!restoredClean) {
      try {
        await git(["checkout", defaultBranch]);
      } catch {
        // best-effort
      }
    }
    log.warn({ err, userId }, "Protected-branch fallback failed");
    return { ok: false };
  }
}

// ---------------------------------------------------------------------------
// The KB-only publish (#12600, CTO ruling R14): the sync pushes only a commit the server built.
// ---------------------------------------------------------------------------

const KB_ENTRY = "knowledge-base";
const TREE_MODE = "40000";
const HEX40_RE = /^[0-9a-f]{40}$/;
const SIDE_REF = `refs/heads/${KB_SYNC_SIDE_BRANCH}`;
const LS_REMOTE_TIMEOUT_MS = 30_000;
const PUSH_TIMEOUT_MS = 60_000;

/** Every reason a turn's KB push is held (R7). Warning-level reasons carry a static Sentry message; the rest log only. */
export type KbPushHeldReason =
  | "merge_in_progress"
  | "detached_head"
  | "non_default_branch"
  | "remote_branch_absent"
  | "remote_unknown_tip"
  | "remote_ahead"
  | "hash_mismatch"
  | "kb_not_tree"
  | "guard_failed"
  | "head_moved"
  | "ref_update_failed"
  | "unpack_failed"
  | "side_ahead"
  | "held_foreign"
  | "synthetic_pushed";

export type KbPushOutcome = "pushed" | "side_pushed" | "held";

const HELD_WARN_MESSAGES: Partial<Record<KbPushHeldReason, string>> = {
  merge_in_progress: "KB sync held: a merge is in progress in the workspace",
  detached_head: "KB sync held: the workspace HEAD is detached",
  non_default_branch: "KB sync held: the workspace is not on the default branch",
  remote_branch_absent: "KB sync held: the remote has no default branch",
  hash_mismatch: "KB sync held: a git object failed its hash check",
  kb_not_tree: "KB sync held: knowledge-base is not a directory",
  guard_failed: "KB sync held: the built commit failed the KB-only guard",
  head_moved: "KB sync held: the local branch moved during the sync",
  ref_update_failed: "KB sync held: the local branch update failed",
  unpack_failed: "KB sync held: the object hand-over to the workspace failed",
  side_ahead: "KB sync held: soleur/kb-sync holds knowledge-base content the workspace has not seen",
};

export interface KbSyncContext {
  readonly userId: string;
  readonly workspaceId: string;
}

/**
 * The ONE outcome report of a turn's KB push (R7): an unconditional info line (Better Stack, every turn), then, for the
 * anomaly reasons only, a debounced warning per workspace and reason. No path, sha, URL or branch name.
 */
export function reportPushHeld(reason: KbPushHeldReason, outcome: KbPushOutcome, ctx: KbSyncContext): void {
  log.info({ op: "kb-sync.push-held", reason, outcome }, "KB sync push outcome");
  const message = HELD_WARN_MESSAGES[reason];
  if (!message) return;
  mirrorWarnWithDebounce(
    null,
    { feature: "session-sync", op: "kb-sync.push-held", message, tags: { reason, outcome }, extra: { userId: ctx.userId } },
    ctx.workspaceId,
    `kb-sync-push-held:${reason}`,
  );
}

/** A failed sync step, with a closed reason and a static message: never the git error, whose argv names the URL and shas. */
export type KbSyncErrorReason =
  | "ls_remote_failed"
  | "fetch_failed"
  | "push_rejected"
  | "push_transient"
  | "isolated_refused"
  | "remote_state_invalid"
  | "local_git_failed"
  | "head_unreadable";

export class KbSyncError extends Error {
  constructor(
    readonly reason: KbSyncErrorReason,
    readonly pushClass?: PushErrorClass,
  ) {
    super(`KB sync step failed (${reason})`);
    this.name = "KbSyncError";
  }
}

/** Internal control flow: the turn is held for `reason` (reported once, by the orchestrator). */
class KbHeld extends Error {
  constructor(readonly reason: KbPushHeldReason) {
    super(`KB sync held (${reason})`);
    this.name = "KbHeld";
  }
}

export interface RemoteState {
  readonly defaultBranch: string;
  readonly tip: string;
  readonly sideTip: string | null;
}

/**
 * Parse `ls-remote --symref <url> HEAD refs/heads/soleur/kb-sync` (R2, R17): exactly one `ref: refs/heads/<D>\tHEAD`
 * line, one `<sha>\tHEAD` line, at most one exact `refs/heads/soleur/kb-sync` line. Other refs the tail-matching
 * patterns may return (`refs/x/HEAD`) are ignored; a duplicate or malformed line of the three throws. `null` = the remote
 * has no resolvable HEAD (`remote_branch_absent`).
 */
export function parseRemoteState(out: string): RemoteState | null {
  let defaultBranch: string | null = null;
  let tip: string | null = null;
  let sideTip: string | null = null;
  let seenSide = false;
  for (const line of out.split("\n")) {
    if (line === "") continue;
    const tab = line.indexOf("\t");
    if (tab < 0) throw new KbSyncError("remote_state_invalid");
    const left = line.slice(0, tab);
    const name = line.slice(tab + 1);
    if (left.startsWith("ref: ")) {
      if (name !== "HEAD") continue;
      if (defaultBranch !== null) throw new KbSyncError("remote_state_invalid");
      const target = left.slice("ref: ".length);
      if (!target.startsWith("refs/heads/")) throw new KbSyncError("remote_state_invalid");
      const branch = target.slice("refs/heads/".length);
      try {
        validateBranchFormat(branch);
      } catch {
        throw new KbSyncError("remote_state_invalid");
      }
      defaultBranch = branch;
      continue;
    }
    if (!HEX40_RE.test(left)) throw new KbSyncError("remote_state_invalid");
    if (name === "HEAD") {
      if (tip !== null) throw new KbSyncError("remote_state_invalid");
      tip = left;
    } else if (name === SIDE_REF) {
      if (seenSide) throw new KbSyncError("remote_state_invalid");
      seenSide = true;
      sideTip = left;
    }
  }
  if (defaultBranch === null || tip === null) return null;
  return { defaultBranch, tip, sideTip };
}

/** One hardened `ls-remote --symref` against the literal URL; no agent-chosen name in argv. */
export async function readRemoteState(
  isolated: IsolatedPushDirHandle,
  installationId: number,
  url: string,
): Promise<RemoteState | null> {
  let out: Buffer;
  try {
    out = await gitWithInstallationAuth(["ls-remote", "--symref", url, "HEAD", SIDE_REF], installationId, {
      hardened: isolated,
      timeout: LS_REMOTE_TIMEOUT_MS,
    });
  } catch {
    throw new KbSyncError("ls_remote_failed");
  }
  return parseRemoteState(out.toString("utf8"));
}

interface TreeEntry {
  readonly mode: string;
  /** latin1, so the bytes round-trip exactly into `mktree -z`. */
  readonly name: string;
  readonly id: string;
}

/** Parse raw tree object bytes (`<mode> <name>\0<20-byte id>`, repeated); `null` on any malformed entry. */
function parseTree(bytes: Buffer): TreeEntry[] | null {
  const out: TreeEntry[] = [];
  let i = 0;
  while (i < bytes.length) {
    const sp = bytes.indexOf(0x20, i);
    if (sp < 0) return null;
    const nul = bytes.indexOf(0x00, sp + 1);
    if (nul < 0 || nul + 21 > bytes.length) return null;
    const mode = bytes.toString("latin1", i, sp);
    if (!/^[0-7]{5,6}$/.test(mode)) return null;
    out.push({ mode, name: bytes.toString("latin1", sp + 1, nul), id: bytes.toString("hex", nul + 1, nul + 21) });
    i = nul + 21;
  }
  return out;
}

interface CommitHeader {
  readonly tree: string;
  readonly parents: readonly string[];
  readonly author: string;
  readonly committer: string;
  readonly message: string;
}

function parseCommit(bytes: Buffer): CommitHeader | null {
  const text = bytes.toString("latin1");
  const end = text.indexOf("\n\n");
  if (end < 0) return null;
  let tree = "";
  let author = "";
  let committer = "";
  const parents: string[] = [];
  for (const line of text.slice(0, end).split("\n")) {
    if (line.startsWith("tree ")) tree = line.slice(5);
    else if (line.startsWith("parent ")) parents.push(line.slice(7));
    else if (line.startsWith("author ")) author = line.slice(7);
    else if (line.startsWith("committer ")) committer = line.slice(10);
  }
  if (!HEX40_RE.test(tree) || !parents.every((p) => HEX40_RE.test(p))) return null;
  return { tree, parents, author, committer, message: text.slice(end + 2) };
}

/** A commit with its hash-verified root tree. */
interface VerifiedCommit {
  readonly id: string;
  readonly commit: CommitHeader;
  readonly root: readonly TreeEntry[];
}

/** Hash-verify a commit and its root tree (R14, R15); the parse reads exactly the verified bytes. */
async function readVerified(isolated: IsolatedPushDirHandle, id: string): Promise<VerifiedCommit | null> {
  const commitBytes = await verifyObject(isolated, "commit", id);
  const commit = commitBytes ? parseCommit(commitBytes) : null;
  if (!commit) return null;
  const treeBytes = await verifyObject(isolated, "tree", commit.tree);
  const root = treeBytes ? parseTree(treeBytes) : null;
  return root ? { id, commit, root } : null;
}

const kbOf = (root: readonly TreeEntry[]): TreeEntry | undefined => root.find((e) => e.name === KB_ENTRY);
const entryKey = (e: TreeEntry): string => `${e.mode} ${e.id}\t${e.name}`;

/** `cat-file -t` says `commit`: the object is present (its bytes are verified separately). */
async function isCommitPresent(isolated: IsolatedPushDirHandle, id: string): Promise<boolean> {
  const r = await runIsolatedGitLocal(isolated, ["cat-file", "-t", id]);
  return r.code === 0 && r.stdout.toString("utf8").trim() === "commit";
}

/** `merge-base --is-ancestor`: 0 yes, 1 no, anything else a local git failure. */
async function isAncestor(isolated: IsolatedPushDirHandle, ancestor: string, of: string): Promise<boolean> {
  const r = await runIsolatedGitLocal(isolated, ["merge-base", "--is-ancestor", ancestor, of]);
  if (r.code === 0) return true;
  if (r.code === 1) return false;
  throw new KbSyncError("local_git_failed");
}

const IDENTITY_ARGS = ["-c", `user.name=${AGENT_AUTHOR_NAME}`, "-c", `user.email=${AGENT_AUTHOR_EMAIL}`] as const;
const IDENTITY_PREFIX = `${AGENT_AUTHOR_NAME} <${AGENT_AUTHOR_EMAIL}> `;

function mktreeInput(entries: readonly TreeEntry[]): Buffer {
  return Buffer.concat(
    entries.map((e) => {
      const type = e.mode === TREE_MODE ? "tree" : e.mode === "160000" ? "commit" : "blob";
      return Buffer.from(`${e.mode.padStart(6, "0")} ${type} ${e.id}\t${e.name}\0`, "latin1");
    }),
  );
}

async function commitTree(
  isolated: IsolatedPushDirHandle,
  tree: string,
  parents: readonly string[],
  message: string,
): Promise<string> {
  const r = await runIsolatedGitLocal(isolated, [
    ...IDENTITY_ARGS,
    "commit-tree",
    tree,
    ...parents.flatMap((p) => ["-p", p]),
    "-m",
    message,
  ]);
  const sha = r.stdout.toString("utf8").trim();
  if (r.code !== 0 || !HEX40_RE.test(sha)) throw new KbSyncError("local_git_failed");
  return sha;
}

/**
 * The ONLY builder of a commit the sync pushes (R14): `baseRoot` (a verified root) with the `knowledge-base` entry
 * replaced by `kb`, the fixed message and the Soleur identity, parents as given. Built token-free in the isolated dir.
 */
export async function buildKbOverlay(
  isolated: IsolatedPushDirHandle,
  baseRoot: readonly TreeEntry[],
  kb: TreeEntry,
  parents: readonly string[],
): Promise<string> {
  const entries = [...baseRoot.filter((e) => e.name !== KB_ENTRY), { mode: TREE_MODE, name: KB_ENTRY, id: kb.id }];
  const mk = await runIsolatedGitLocal(isolated, ["mktree", "-z"], { input: mktreeInput(entries) });
  const tree = mk.stdout.toString("utf8").trim();
  if (mk.code !== 0 || !HEX40_RE.test(tree)) throw new KbSyncError("local_git_failed");
  return commitTree(isolated, tree, parents, KB_SYNC_SIDE_COMMIT_MSG);
}

/**
 * Guard 1: `sha`'s verified root equals `baseRoot` in every entry except `knowledge-base` (present, a tree), and its
 * message and identity are Soleur's. Compared on the parsed entry lists; no history walk.
 */
export async function assertRootDiffersOnlyInKb(
  isolated: IsolatedPushDirHandle,
  sha: string,
  baseRoot: readonly TreeEntry[],
): Promise<boolean> {
  const built = await readVerified(isolated, sha);
  if (!built) return false;
  const { commit, root } = built;
  if (!commit.author.startsWith(IDENTITY_PREFIX) || !commit.committer.startsWith(IDENTITY_PREFIX)) return false;
  if (commit.message !== `${KB_SYNC_SIDE_COMMIT_MSG}\n`) return false;
  const kb = kbOf(root);
  if (!kb || kb.mode !== TREE_MODE) return false;
  const a = root.filter((e) => e.name !== KB_ENTRY).map(entryKey).sort();
  const b = baseRoot.filter((e) => e.name !== KB_ENTRY).map(entryKey).sort();
  return a.length === b.length && a.every((k, i) => k === b[i]);
}

export interface VerifiedPush {
  readonly isolated: IsolatedPushDirHandle;
  readonly installationId: number;
  readonly url: string;
  readonly baseRoot: readonly TreeEntry[];
  readonly sha: string;
  /** `refs/heads/<D>` or `refs/heads/soleur/kb-sync`, nothing else. */
  readonly ref: string;
  readonly defaultBranch: string;
}

/**
 * The ONE push of the post-session sync (R6): re-runs Guard 1 on the exact sha against its verified base, then pushes
 * `<sha>:<ref>` non-force from the isolated directory through the hardened arm. Throws `KbHeld("guard_failed")` or a
 * `KbSyncError` carrying the stderr class.
 */
export async function pushVerifiedKbOnly(p: VerifiedPush): Promise<void> {
  if (p.ref !== `refs/heads/${p.defaultBranch}` && p.ref !== SIDE_REF) throw new KbSyncError("remote_state_invalid");
  if (!HEX40_RE.test(p.sha)) throw new KbSyncError("remote_state_invalid");
  if (!(await assertRootDiffersOnlyInKb(p.isolated, p.sha, p.baseRoot))) throw new KbHeld("guard_failed");
  try {
    await gitWithInstallationAuth(["push", p.url, `${p.sha}:${p.ref}`], p.installationId, {
      hardened: p.isolated,
      timeout: PUSH_TIMEOUT_MS,
    });
  } catch (err) {
    const pushClass = classifyPushError(err);
    const raw = (err as { stderr?: unknown } | null)?.stderr;
    const stderr = Buffer.isBuffer(raw) ? raw.toString("utf8") : typeof raw === "string" ? raw : "";
    const rejected = pushClass !== "other" || /^\s*! \[(rejected|remote rejected)\]/m.test(stderr);
    throw new KbSyncError(rejected ? "push_rejected" : "push_transient", pushClass);
  }
}

/** The literal `https://github.com/<owner>/<repo>.git` push URL (R2): never `remote.origin.url`. */
async function resolvePushUrl(userId: string, workspaceId: string): Promise<{ url: string; owner: string; repo: string }> {
  const { getCurrentRepoUrl } = await import("./current-repo-url");
  const { owner, repo } = parseOwnerRepo(await getCurrentRepoUrl(userId, workspaceId));
  if (!owner || !repo) throw new KbSyncError("remote_state_invalid");
  return { url: `https://github.com/${owner}/${repo}.git`, owner, repo };
}

export type KbPublishResult =
  | { readonly kind: "pushed" }
  | { readonly kind: "held"; readonly reason: KbPushHeldReason }
  | { readonly kind: "noop" }
  | { readonly kind: "protected"; readonly pushErr: KbSyncError };

export interface KbPublishInput extends KbSyncContext {
  readonly workspacePath: string;
  readonly installationId: number;
  /** Frozen HEAD (`readWorkspaceHeadRef`), read before any git child. */
  readonly headSha: string;
  readonly refName: string;
}

/**
 * Steps 2-3 of the post-session sync (#12600): authoritative remote state, the refusals, the hash checks, the build of
 * `S`, Guard 1 and the push. One isolated directory per turn, disposed in `finally`.
 */
export async function publishKbOnly(input: KbPublishInput): Promise<KbPublishResult> {
  const { headSha, installationId } = input;
  let isolated: IsolatedPushDirHandle | undefined;
  try {
    const { url } = await resolvePushUrl(input.userId, input.workspaceId);
    try {
      isolated = createIsolatedPushDir(input.workspacePath);
    } catch {
      throw new KbSyncError("isolated_refused");
    }
    const remote = await readRemoteState(isolated, installationId, url);
    if (!remote) throw new KbHeld("remote_branch_absent");
    const D = remote.defaultBranch;
    if (input.refName !== `refs/heads/${D}`) throw new KbHeld("non_default_branch");
    const T = remote.tip;
    if (T === headSha) return { kind: "noop" };
    if (!(await isCommitPresent(isolated, T))) throw new KbHeld("remote_unknown_tip");
    if (!(await isAncestor(isolated, T, headSha))) throw new KbHeld("remote_ahead");

    const tV = await readVerified(isolated, T);
    const hV = await readVerified(isolated, headSha);
    if (!tV || !hV) throw new KbHeld("hash_mismatch");
    const headKb = kbOf(hV.root);
    if (!headKb || headKb.mode !== TREE_MODE) throw new KbHeld("kb_not_tree");
    const tKb = kbOf(tV.root);
    if (tKb && tKb.mode === TREE_MODE && tKb.id === headKb.id) {
      if (hV.commit.tree !== tV.commit.tree) throw new KbHeld("held_foreign");
      return { kind: "noop" };
    }

    const S = await buildKbOverlay(isolated, tV.root, headKb, [T]);
    if (!(await assertRootDiffersOnlyInKb(isolated, S, tV.root))) throw new KbHeld("guard_failed");

    try {
      await pushVerifiedKbOnly({ isolated, installationId, url, baseRoot: tV.root, sha: S, ref: `refs/heads/${D}`, defaultBranch: D });
    } catch (err) {
      if (err instanceof KbSyncError && err.pushClass === "protected_branch") return { kind: "protected", pushErr: err };
      throw err;
    }
    reportPushHeld("synthetic_pushed", "pushed", input);
    return { kind: "pushed" };
  } catch (err) {
    if (err instanceof KbHeld) {
      reportPushHeld(err.reason, "held", input);
      return { kind: "held", reason: err.reason };
    }
    throw err;
  } finally {
    disposeIsolated(isolated);
  }
}
