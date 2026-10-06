// #5091 — deterministic safe-commit + PR pipeline for claude-spawn bot crons.
//
// Replaces the prompt-level mandatory-final-step shell blocks (destructive
// PR #5026: a blanket add staged 654 structural deletions produced by the
// ephemeral-workspace scaffolding). The prompt is a suggestion to a model;
// persistence is a platform responsibility — it runs HERE, node-level,
// after the eval, where it is deterministic, replay-tolerant, and outside
// the containment hook's jurisdiction. Each invariant is documented at its
// implementation site below; the #5091 plan carries the full design.

import { existsSync } from "node:fs";
import { lstat, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import type { Octokit } from "@octokit/core";
import { emitCronPersistResult } from "@/server/cron-liveness-marker";
import { reportSilentFallback } from "@/server/observability";
import { redactToken, REPO_OWNER, REPO_NAME, type HandlerArgs } from "./_cron-shared";
import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "./_git-hardening";

// 10: above incidental renames (a worktree rename = 1 deletion entry), far
// below the 654-file contamination class. Issue #5091 suggested 50 —
// divergence recorded in the plan + PR body.
export const DEFAULT_MAX_DELETIONS = 10;

// Workspace scaffolding the substrate writes on EVERY run (settings overlay,
// cron-allow.txt). Expected-dirty by construction and never staged —
// excluding them is silent by design; everything else dropped by the
// allowlist filter is mirrored to Sentry. PREFIX semantics (trailing slash
// required): a literal-entry exclusion would let deletions UNDER a scaffolded
// directory flow into the deletion guard on every run (#5091 plan review).
// Workspace scaffolding the substrate itself writes on EVERY run. These are
// excluded BEFORE the allowlist filter so they never reach the loud
// "paths-dropped" report -- that signal exists to catch a bot writing outside
// its allowlist, and a path that appears on every single run would drown it.
// `.soleur-collector-status/` is the #6695 collector-status sidecar, written by
// github-community.sh and read by cron-community-monitor before teardown.
export const STRUCTURAL_EXCLUSION_PREFIXES: readonly string[] = [
  ".claude/",
  ".soleur-collector-status/",
];

// #5111 — the bot-PR-with-synthetic-checks pattern: deterministic data-refresh
// PRs post these check-runs as completed/success so the integration-pinned
// required checks (infra/github/ruleset-ci-required.tf) are satisfied without
// running CI on knowledge-base-only diffs. Consolidated from 5 byte-identical
// per-cron copies (weekly-analytics, compound-promote, content-publisher,
// content-vendor-drift, rule-prune) — verified identical at #5111 deepen time.
//
// #8203 — `vendor-pin-required` is DELIBERATELY ABSENT from this list. The
// content-vendor-drift cron is the one synthetic consumer whose PRs DO touch
// the guarded surface (plugins/soleur/skills/** vendored NOTICE bundles); it
// pushes with an App token that triggers real CI (#8166), so the aggregator
// gate is EARNED by a real verify-upstream-blobs run. Adding the name here
// would fabricate the #8181 binding result on exactly the re-vendor diffs
// the gate exists to protect. See the two-arm note in
// scripts/required-checks.txt.
export const SYNTHETIC_CHECK_NAMES = [
  "test",
  "dependency-review",
  "e2e",
  "skill-security-scan PR gate",
  "enforce",
  "cla-check",
  "cla-evidence",
] as const;

const BOT_NAME = "github-actions[bot]";
const BOT_EMAIL = "41898282+github-actions[bot]@users.noreply.github.com";

// Sentry-extra / failed.message size bound, mirroring the stderrTail
// convention in _cron-shared (the step return is memoized by Inngest and
// must stay bounded; raw git stderr can reach maxBuffer otherwise).
const MESSAGE_CAP_CHARS = 4000;

export interface SafeCommitConfig {
  spawnCwd: string;
  /** Installation token — used only to build an Octokit when none is injected. */
  installationToken: string;
  cronName: string;
  /** Also the PR title stem: `<commitMessage> <YYYY-MM-DD from runStartedAt>`. */
  commitMessage: string;
  /**
   * Repo-root-relative path prefixes this cron is allowed to persist.
   * Directory entries MUST end with "/" — matching is bare startsWith, so a
   * bare "foo" would also match "foobar.md".
   */
  allowedPaths: readonly string[];
  /**
   * #7122 — repo-root-relative paths persisted by STRING EQUALITY (no prefix
   * matching), for a cron whose single output path is handler-authored and
   * known before the commit (the community digest). A path is allowed when it
   * matches `allowedPaths` (prefix) OR `exactPaths` (equality); a cron that
   * wants equality only passes `allowedPaths: []`. Setting this switches the
   * dropped-path PR-body marker to COUNT-ONLY: a stray file's name is
   * agent-chosen and the PR body is public, so names go to Sentry alone.
   *
   * It also switches the workspace to the UNTRUSTED posture (#7122 P1-B): the agent
   * that ran in it may have planted git state. Before any git command the handler
   * rewrites `.git/config` from scratch (only `remote.origin.url` survives), removes
   * `.git/hooks` and `.git/info/attributes`, refuses a `.git` that is not a plain
   * directory, stages each path as a filter-free blob of the file's own bytes
   * (`hash-object --no-filters` + `update-index`, never `git add`), refuses anything
   * but a regular file, and — on the replay-resume arm — pushes a pre-existing branch
   * only when it is exactly one commit touching only `exactPaths`.
   */
  exactPaths?: readonly string[];
  /**
   * #7122 P1-B — exactPaths mode only. Path -> the exact bytes (as a string) the
   * handler rendered for it. After staging and BEFORE the commit, the INDEX blob of
   * every key is read back and must equal the expected string byte-for-byte (on the
   * resume arm, the branch tip's blob). A mismatch refuses to commit: status
   * "failed", stage "integrity", a closed-vocabulary reason; neither the expected nor
   * the actual bytes appear in any message, comment or Sentry extra.
   */
  expectedContent?: Readonly<Record<string, string>>;
  /** The handler's MEMOIZED run-start ISO timestamp (never a fresh Date). */
  runStartedAt: string;
  /** Label of the cron's scheduled output issue — guard/fail visibility comment target. */
  scheduledIssueLabel: string;
  /** Injectable for tests/callers with an existing client; production
   *  callers may omit and the installation token is used. Structural type
   *  (the two members the helper uses) so injection sites need no cast. */
  octokit?: Pick<Octokit, "request" | "graphql">;
  logger?: HandlerArgs["logger"];
  // -- #5111 option surface (all optional; defaults preserve #5091 behavior) --
  /** Override the derived `ci/<name>-<ts>` branch (compound-promote's
   *  per-cluster `self-healing/auto-<hash>-<date>`). Must be refname-safe;
   *  the helper rejects `:` `.` whitespace at stage "checkout". */
  branchName?: string;
  /** Second `-m` paragraph (compound-promote provenance trailers). */
  commitBody?: string;
  /** Full PR title override (no date appended). Default stays
   *  `${commitMessage} ${YYYY-MM-DD}`. */
  prTitle?: string;
  /** PR body stem override. The dropped-path ⚠️ marker is appended
   *  regardless of override when the scan runs (the loud-truncation
   *  invariant survives overrides; a replay-resume skips the scan and
   *  relies on the original attempt's Sentry warn). */
  prBody?: string;
  prDraft?: boolean;
  /** Labels applied after PR create (best-effort: label failure mirrors to
   *  Sentry, never fails the run — labels are advisory metadata). */
  prLabels?: readonly string[];
  /** Post synthetic check-runs on the head SHA after PR create (the
   *  bot-pr-with-synthetic-checks pattern carried by the 5 legacy crons). */
  syntheticChecks?: { names: readonly string[]; summary: string };
  /** "auto" (default): enablePullRequestAutoMerge + clean-status direct
   *  fallback — #5091 behavior. "direct": PUT …/merge squash immediately
   *  (legacy live pipelines); on failure falls back to arming auto-merge,
   *  then to failure stage "auto-merge" (PR stays open + loud). "none":
   *  create only (compound-promote human-review draft PRs). */
  mergeMode?: "auto" | "direct" | "none";
}

export type SafeCommitResult =
  | {
      status: "committed";
      prNumber: number;
      branch: string;
      /**
       * Whether the PR actually reached the default branch in THIS call.
       *
       * `status: "committed"` alone cannot answer that. Under
       * `mergeMode: "direct"` a failed `PUT .../merge` falls back to ARMING
       * auto-merge and returns the same `committed` status, so a caller that
       * reads the status as "the artifact landed" is wrong on the expected
       * path — the bot self-signs only a subset of the required contexts, so
       * pending checks make the fallback ordinary rather than exceptional.
       * Armed auto-merge also disarms silently on conflict.
       *
       * `true` = merged in this call. `false` = a PR exists but is not merged
       * (armed auto-merge, or create-only).
       *
       * Optional rather than required because a future second `committed`
       * return would otherwise be forced to invent a value; a caller reading
       * `merged === true` treats an absent field as "not merged", which is
       * the fail-closed direction. Note the replay-resume arm DOES reach the
       * merge tail (it skips only the scan/commit block), so on today's code
       * this is always a boolean — an earlier revision of this comment
       * claimed otherwise (#7710 review).
       *
       * Do NOT key a health signal on this. The direct merge normally fails
       * with checks pending and the fallback arms auto-merge, which lands the
       * PR seconds after the run ends — measured on PRs #4083 / #3766 / #3468.
       */
      merged?: boolean;
      /** 0 on a replay-resume (counts are not recomputed for an existing commit). */
      fileCount: number;
      deletionCount: number;
      /**
       * Repo-relative paths that entered the commit, from the allowlist-matched
       * scan. **OPTIONAL, and `undefined` means "NOT DETERMINED" — never
       * "nothing was committed"** (#6714 R21): on the replay-resume branch the
       * scan never runs, so there is nothing to report even though the artifact
       * did land. A caller asserting "my artifact is in here" MUST treat
       * `undefined` as inconclusive and consult `resumed` before turning red.
       *
       * Optional rather than required because the replay-resume branch cannot
       * know a value to supply — it never runs the allowlist scan. (An earlier
       * draft justified this with "~38 consumers construct this arm"; that
       * number is the count of files REFERENCING safeCommitAndPr. Only 12 sites
       * across 7 files construct the committed arm, so the blast-radius claim
       * was ~5x overstated. The decision stands on the replay-resume leg.)
       */
      paths?: string[];
      /**
       * Set only on the replay-resume branch (a prior attempt already created
       * the commit). Its presence is what licenses a liveness check to stay
       * GREEN despite `paths` being undetermined.
       */
      resumed?: true;
    }
  | { status: "no-changes" }
  | {
      status: "failed";
      stage:
        | "workspace-lost"
        | "status"
        | "dirty-index"
        | "deletion-guard"
        | "checkout"
        | "add"
        | "commit"
        | "push"
        | "pr-create"
        | "auto-merge"
        // #7122 P1-B — the workspace or the staged bytes are not what the handler
        // produced. `message` is `integrity: <reason>`, a closed vocabulary.
        | "integrity"
        | "unexpected";
      message: string;
    };

interface StatusEntry {
  /** Staged (X) and worktree (Y) status columns. */
  x: string;
  y: string;
  /** Destination path (rename/copy entries report dest first under -z). */
  path: string;
}

/**
 * Parse `git status --porcelain=v1 -z` output. Each entry is
 * `XY <path>\0` — EXCEPT `R`/`C` entries which carry a second
 * NUL-terminated field: `XY <dest>\0<orig>\0` (destination FIRST).
 * Consuming both fields is load-bearing: a one-field parser misaligns
 * every subsequent entry (precedent: 2026-04-27 autoloop PR-quality fence).
 * Staged R/C entries cannot reach the commit path in practice (the
 * dirty-index precondition rejects any pre-staged index), so the orig
 * field needs no allowlist treatment here.
 */
export function parsePorcelainZ(raw: string): StatusEntry[] {
  const fields = raw.split("\0");
  const entries: StatusEntry[] = [];
  let i = 0;
  while (i < fields.length) {
    const field = fields[i];
    if (!field) {
      i++;
      continue;
    }
    const x = field[0] ?? " ";
    const y = field[1] ?? " ";
    const path = field.slice(3);
    entries.push({ x, y, path });
    // Rename/copy in either column → skip the trailing <orig> field.
    if (x === "R" || x === "C" || y === "R" || y === "C") {
      i += 2;
    } else {
      i += 1;
    }
  }
  return entries;
}

/** `ci/<cronName minus cron->-<YYYY-MM-DD-HHMMSS>` — refname-safe (no `:`/`.`). */
export function deriveBranchName(cronName: string, runStartedAt: string): string {
  const prefix = cronName.replace(/^cron-/, "");
  // "2026-06-10T11:00:03.123Z" → "2026-06-10-110003"
  const ts = runStartedAt.slice(0, 19).replace("T", "-").replace(/:/g, "");
  return `ci/${prefix}-${ts}`;
}

/**
 * The ONE persistence-allowlist predicate. Both the `matched` and `dropped`
 * partitions call it, so a path is on exactly one side by construction (a second
 * matcher is how a "dropped" path ends up committed). `allowedPaths` keeps its
 * bare `startsWith` prefix semantics; `exactPaths` is string equality on the
 * repo-relative path. `git status` never reports a `..` segment, a leading `/`
 * or an empty path, so the exact branch refuses them outright: an equality list
 * must never be able to name something outside the repo even if a caller builds
 * it from data. Empty/absent lists match nothing.
 */
export function isPathAllowed(
  path: string,
  cfg: { allowedPaths?: readonly string[]; exactPaths?: readonly string[] },
): boolean {
  if (cfg.allowedPaths?.some((p) => path.startsWith(p))) return true;
  if (!cfg.exactPaths?.length) return false;
  if (path === "" || path.startsWith("/") || path.split("/").some((seg) => seg === ".." || seg === ".")) {
    return false;
  }
  return cfg.exactPaths.includes(path);
}

/** Neutralize markdown-breaking chars in untrusted strings (paths) before
 * interpolating into issue-comment code spans (mirrors formatTailForIssue). */
function safeMd(s: string): string {
  return s.replace(/[`\r\n|]/g, "ʼ");
}

// #7122 P1-B — applied to EVERY git invocation this module makes (see _git-hardening.ts:
// no hooks, no fsmonitor, no attributes file, no replace refs). The workspace was the
// agent's: a hook it planted (`.git/hooks/*`), a `core.fsmonitor` command or a global
// attributes file would otherwise run inside the handler process with its environment
// and, after the origin re-point, with the write token. Filter drivers
// (`filter.<name>.clean`) cannot be wildcarded here; exactPaths mode removes them by
// rewriting the config instead (see sanitizeWorkspaceGit) and by never staging through
// a filter.

type GitResult = { ok: boolean; stdout: string; stderr: string };
/** A git runner bound to one workspace (and, in exactPaths mode, to its pinned GIT_DIR). */
type Git = (args: string[], extraEnv?: Record<string, string>) => Promise<GitResult>;

async function runGit(
  spawnCwd: string,
  args: string[],
  extraEnv?: Record<string, string>,
): Promise<GitResult> {
  // Lazy import: many sibling cron TEST files vi.mock("node:child_process")
  // with spawn-only factories; a top-level promisify(execFile) would crash
  // at module load in every file that imports a migrated cron. Importing at
  // call time keeps this module loadable under those mocks (runGit itself is
  // only exercised by cron-safe-commit.test.ts, which does not mock it).
  const { execFile } = await import("node:child_process");
  const execFileP = promisify(execFile);
  try {
    const { stdout, stderr } = await execFileP("git", [...GIT_HARDENING_ARGS, ...args], {
      cwd: spawnCwd,
      env: { ...process.env, ...GIT_HARDENING_ENV, ...extraEnv },
      maxBuffer: 32 * 1024 * 1024,
    });
    return { ok: true, stdout, stderr };
  } catch (err) {
    const e = err as Error & { stdout?: string; stderr?: string };
    return { ok: false, stdout: e.stdout ?? "", stderr: e.stderr ?? e.message };
  }
}

/** The raw bytes of a git object (`:<path>` = the index blob, `HEAD:<path>` = the tip's). */
async function gitObjectBytes(
  spawnCwd: string,
  spec: string,
  extraEnv?: Record<string, string>,
): Promise<Buffer | null> {
  const { execFile } = await import("node:child_process");
  const execFileP = promisify(execFile);
  try {
    const { stdout } = await execFileP("git", [...GIT_HARDENING_ARGS, "cat-file", "blob", spec], {
      cwd: spawnCwd,
      encoding: "buffer",
      env: { ...process.env, ...GIT_HARDENING_ENV, ...extraEnv },
      maxBuffer: 32 * 1024 * 1024,
    });
    return stdout as unknown as Buffer;
  } catch {
    return null;
  }
}

/** The origin default branch the exactPaths pipeline pins its commit to. */
const EXACT_BASE_REF = "refs/remotes/origin/main";

/**
 * The environment pinning every exactPaths git invocation to THIS workspace's own
 * `.git` and work tree (no upward discovery, no `commondir` indirection).
 */
function exactModeEnv(spawnCwd: string): Record<string, string> {
  return {
    GIT_DIR: join(spawnCwd, ".git"),
    GIT_WORK_TREE: spawnCwd,
    GIT_CEILING_DIRECTORIES: dirname(spawnCwd),
  };
}

/**
 * `.git` entries git READS OR WRITES THROUGH, any of which may be a symlink the agent
 * planted: writing the rewritten config through `config` overwrote an arbitrary file
 * (security round-1 E8), `rm info/attributes` through `info` deleted in another
 * directory, `objects/info/alternates` and `refs/replace` likewise. A symlink at any of
 * them is refused, not followed.
 */
const GIT_DIR_NO_SYMLINK_ENTRIES: readonly string[] = [
  "config",
  "info",
  "hooks",
  "objects",
  "objects/info",
  "refs",
  "refs/replace",
  "HEAD",
  "index",
  "packed-refs",
  "shallow",
];

/**
 * Files whose mere existence redirects or extends where git reads objects, refs and
 * config from. `shallow` is NOT here: the clone is `--depth=1` and the file is what
 * tells git so. Removing `commondir` first is load-bearing: with it present git reads
 * config, hooks, attributes, objects and refs from the directory it names, and none of
 * the in-gitdir clean-up below would touch what git actually uses (security round-1 E2).
 */
const GIT_DIR_REDIRECT_FILES: readonly string[] = [
  "commondir",
  "config.worktree",
  "objects/info/alternates",
  "objects/info/http-alternates",
  "info/grafts",
  "info/exclude",
  "info/attributes",
  "info/sparse-checkout",
];

/**
 * #7122 P1-B — put an agent-touched workspace's git state back to a known shape, in
 * place, BEFORE the first git command of the handler's own pipeline. Returns a
 * closed-vocabulary reason on refusal, or null.
 *
 * What an agent could have planted that `-c` cannot override: `filter.*` drivers (+
 * `.git/info/attributes` to select them), `url.<x>.insteadOf` / `remote.origin.pushurl`
 * (the push, with the write token, goes elsewhere), `core.sshCommand`,
 * `credential.helper`, aliases, `include.path`, `commit.gpgsign` + `gpg.program`,
 * a `commondir` / alternates / grafts / replace-ref redirection. The one trustworthy
 * fact is `remote.origin.url`, which `setOriginToken` wrote after the child exited. So
 * the redirections are removed, the config is REWRITTEN from nothing, and only that
 * value is carried over. A `.git` that is a symlink or a file (`gitdir:` indirection),
 * or any entry git writes through that is a symlink, is refused outright.
 */
async function sanitizeWorkspaceGit(spawnCwd: string, git: Git): Promise<string | null> {
  const gitDir = join(spawnCwd, ".git");
  try {
    const st = await lstat(gitDir);
    if (!st.isDirectory() || st.isSymbolicLink()) return "git-dir-not-directory";
  } catch {
    return "git-dir-not-directory";
  }
  for (const entry of GIT_DIR_NO_SYMLINK_ENTRIES) {
    try {
      if ((await lstat(join(gitDir, entry))).isSymbolicLink()) return "git-entry-symlink";
    } catch {
      // absent: nothing to follow
    }
  }
  try {
    // BEFORE the first git command: `commondir` would make the URL read below come from
    // the attacker's directory.
    for (const rel of GIT_DIR_REDIRECT_FILES) await rm(join(gitDir, rel), { force: true });
    await rm(join(gitDir, "refs", "replace"), { recursive: true, force: true });
  } catch {
    return "config-rewrite-failed";
  }
  const url = await git(["config", "--local", "--get", "remote.origin.url"]);
  const originUrl = url.ok ? url.stdout.trim() : "";
  if (!originUrl || /[\r\n]/.test(originUrl)) return "config-rewrite-failed";
  try {
    await rm(join(gitDir, "hooks"), { recursive: true, force: true });
    // Remove first, then create exclusively: a file that appears in between is refused
    // instead of being written through.
    await rm(join(gitDir, "config"), { force: true });
    await writeFile(join(gitDir, "config"), "[core]\n\trepositoryformatversion = 0\n", {
      encoding: "utf-8",
      flag: "wx",
    });
  } catch {
    return "config-rewrite-failed";
  }
  const setUrl = await git(["config", "--local", "remote.origin.url", originUrl]);
  const setFetch = await git([
    "config",
    "--local",
    "remote.origin.fetch",
    "+refs/heads/*:refs/remotes/origin/*",
  ]);
  if (!setUrl.ok || !setFetch.ok) return "config-rewrite-failed";
  // A packed replace ref survives the directory removal above; `--no-replace-objects`
  // already ignores it, deleting it keeps the repository honest for anything else.
  const replace = await git(["for-each-ref", "--format=%(refname)", "refs/replace/"]);
  if (replace.ok) {
    for (const ref of replace.stdout.split("\n").filter(Boolean)) await git(["update-ref", "-d", ref]);
  }
  return null;
}

/**
 * exactPaths staging: each path becomes a blob of the FILE'S OWN BYTES, with no
 * clean filter, no attribute-driven conversion and no `git add`. Anything but a
 * regular file (a symlink would commit its target's bytes), and any path whose parent
 * directory is a symlink, is refused. Returns a closed-vocabulary reason on refusal,
 * or null. The index is expected to hold the origin tip's tree already.
 */
async function stageExactPaths(
  spawnCwd: string,
  git: Git,
  paths: readonly string[],
): Promise<string | null> {
  for (const rel of paths) {
    try {
      const parts = rel.split("/");
      for (let i = 1; i < parts.length; i++) {
        if ((await lstat(join(spawnCwd, ...parts.slice(0, i)))).isSymbolicLink()) return "path-not-regular-file";
      }
      const st = await lstat(join(spawnCwd, rel));
      if (!st.isFile() || st.isSymbolicLink()) return "path-not-regular-file";
    } catch {
      return "path-not-regular-file";
    }
    const hashed = await git(["hash-object", "-w", "--no-filters", "--", rel]);
    const sha = hashed.stdout.trim();
    if (!hashed.ok || !/^[0-9a-f]{40,64}$/.test(sha)) return "stage-failed";
    const idx = await git(["update-index", "--add", "--cacheinfo", `100644,${sha},${rel}`]);
    if (!idx.ok) return "stage-failed";
  }
  return null;
}

/** Every key of `expected` must read back (from `treeish`, `:` for the index) byte-for-byte. */
async function contentMatches(
  spawnCwd: string,
  extraEnv: Record<string, string>,
  treeish: string,
  expected: Readonly<Record<string, string>>,
): Promise<boolean> {
  for (const [path, want] of Object.entries(expected)) {
    const got = await gitObjectBytes(spawnCwd, `${treeish}:${path}`, extraEnv);
    if (got === null || Buffer.compare(got, Buffer.from(want, "utf8")) !== 0) return false;
  }
  return true;
}

/**
 * exactPaths pre-push gate. Runs before EVERY push of an exactPaths run (a replay-resume
 * of a pre-existing branch AND the commit this call just made): the tip is pushed only
 * when it is exactly the one commit this handler would have made —
 *   - one commit ahead of the freshly fetched origin tip, with that tip as its only parent;
 *   - the diff against the tip (renames NOT detected, so a rename is a delete + add and
 *     fails) is only ADDED or MODIFIED regular files (mode 100644) at exact paths;
 *   - every blob equals the rendered bytes (`expectedContent`, required);
 *   - the commit is authored and committed by the bot with the handler's message.
 * Anything else may carry agent-authored content and is refused.
 */
async function pushTipReason(
  spawnCwd: string,
  git: Git,
  extraEnv: Record<string, string>,
  baseSha: string,
  config: Pick<SafeCommitConfig, "allowedPaths" | "exactPaths" | "expectedContent" | "commitMessage" | "commitBody">,
): Promise<string | null> {
  const count = await git(["rev-list", `${baseSha}..HEAD`, "--count"]);
  if (!count.ok || count.stdout.trim() !== "1") return "resume-unexpected-commit-count";
  const parents = await git(["rev-list", "--parents", "-n", "1", "HEAD"]);
  const chain = parents.stdout.trim().split(/\s+/);
  if (!parents.ok || chain.length !== 2) return "resume-unexpected-commit-count";
  const names = await git([
    "diff",
    "--no-renames",
    "--no-ext-diff",
    "--no-textconv",
    "--name-status",
    "-z",
    baseSha,
    "HEAD",
  ]);
  if (!names.ok) return "resume-unexpected-path";
  const fields = names.stdout.split("\0").filter(Boolean);
  if (fields.length === 0 || fields.length % 2 !== 0) return "resume-unexpected-path";
  const changed: string[] = [];
  for (let i = 0; i < fields.length; i += 2) {
    if (fields[i] !== "A" && fields[i] !== "M") return "resume-unexpected-path";
    if (!isPathAllowed(fields[i + 1], config)) return "resume-unexpected-path";
    changed.push(fields[i + 1]);
  }
  for (const path of changed) {
    const tree = await git(["ls-tree", "-z", "HEAD", "--", path]);
    if (!tree.ok || !tree.stdout.startsWith("100644 blob ")) return "resume-unexpected-mode";
  }
  if (!config.expectedContent) return "expected-content-missing";
  if (!changed.every((p) => Object.prototype.hasOwnProperty.call(config.expectedContent, p))) {
    return "expected-content-missing";
  }
  if (!(await contentMatches(spawnCwd, extraEnv, "HEAD", config.expectedContent))) {
    return "resume-content-mismatch";
  }
  const meta = await git(["log", "-1", "--format=%an%x00%ae%x00%cn%x00%ce%x00%B", "HEAD"]);
  const [an, ae, cn, ce, ...msg] = meta.stdout.split("\0");
  const wantMessage = config.commitBody ? `${config.commitMessage}\n\n${config.commitBody}` : config.commitMessage;
  if (
    !meta.ok ||
    an !== BOT_NAME ||
    ae !== BOT_EMAIL ||
    cn !== BOT_NAME ||
    ce !== BOT_EMAIL ||
    msg.join("\0").trimEnd() !== wantMessage.trimEnd()
  ) {
    return "resume-unexpected-commit-metadata";
  }
  return null;
}

/**
 * @internal Test seams. The exactPaths layers overlap by design (the config rewrite alone
 * also neutralises a planted filter, for instance), so a row driven through
 * `safeCommitAndPr` cannot tell whether EACH layer holds. These let the suite exercise
 * a layer on its own, against planted state the other layers would otherwise remove.
 */
export const __safeCommitInternals = { runGit, stageExactPaths, sanitizeWorkspaceGit, pushTipReason, exactModeEnv };

// GraphQL auto-merge enable, extracted from cron-bug-fixer (PR #5091) so both
// callers share one "already enabled" tolerance (expected under Inngest
// replay — callers MUST NOT page on it; `alreadyEnabled` lets them log the
// replay distinctly). The "clean status" case (no pending required checks —
// possible for path-filtered workflows on knowledge-base-only diffs, where
// arming auto-merge would otherwise hang forever) is signalled distinctly so
// callers can fall back to direct merge.
export async function enableAutoMergeSquash(
  octokit: Pick<Octokit, "graphql">,
  pullRequestId: string,
): Promise<{
  enabled: boolean;
  alreadyEnabled: boolean;
  cleanStatus: boolean;
  reason?: string;
}> {
  const mutation = `
    mutation EnableAutoMerge($pullRequestId: ID!) {
      enablePullRequestAutoMerge(input: {
        pullRequestId: $pullRequestId,
        mergeMethod: SQUASH
      }) {
        pullRequest { autoMergeRequest { enabledAt } }
      }
    }
  `;
  try {
    await octokit.graphql(mutation, { pullRequestId });
    return { enabled: true, alreadyEnabled: false, cleanStatus: false };
  } catch (err) {
    const message = ((err as Error).message ?? "").toLowerCase();
    if (
      message.includes("auto merge is already enabled") ||
      message.includes("auto-merge is already enabled") ||
      message.includes("already enabled auto merge") ||
      message.includes("already enabled auto-merge")
    ) {
      return { enabled: true, alreadyEnabled: true, cleanStatus: false };
    }
    if (message.includes("clean status")) {
      return { enabled: false, alreadyEnabled: false, cleanStatus: true };
    }
    return {
      enabled: false,
      alreadyEnabled: false,
      cleanStatus: false,
      reason: (err as Error).message,
    };
  }
}

async function resolveOctokit(
  config: SafeCommitConfig,
): Promise<Pick<Octokit, "request" | "graphql">> {
  if (config.octokit) return config.octokit;
  const { Octokit: OctokitCtor } = await import("@octokit/core");
  return new OctokitCtor({ auth: config.installationToken }) as unknown as Octokit;
}

/**
 * Best-effort operator visibility: a guard abort or persistence failure with
 * a green output issue is invisible to a non-technical operator ("the issue
 * says fixes were applied but there is no PR anywhere"). Comments on the
 * MOST RECENT open issue carrying the cron's label — if the run died before
 * creating its own issue, the comment lands on the previous run's issue
 * (accepted: still operator-visible, still labeled). A comment failure
 * mirrors to Sentry and never escalates.
 */
async function commentOnScheduledIssue(
  octokit: Pick<Octokit, "request" | "graphql">,
  config: SafeCommitConfig,
  body: string,
): Promise<void> {
  try {
    const issues = (await octokit.request("GET /repos/{owner}/{repo}/issues", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      labels: config.scheduledIssueLabel,
      state: "open",
      sort: "created",
      direction: "desc",
      per_page: 1,
      headers: { "X-GitHub-Api-Version": "2022-11-28" },
    })) as { data: Array<{ number: number }> };
    const issue = issues.data[0];
    if (!issue) {
      // No open issue carries the label — the comment channel is dead for
      // this cron (the 5 pure-TS pipelines pass their Sentry monitor slug,
      // which only the claude-spawn crons create issues under). Mirror the
      // drop so triage knows Sentry is the ONLY signal for this failure.
      reportSilentFallback(
        new Error(`no open issue labeled ${config.scheduledIssueLabel}`),
        {
          feature: config.cronName,
          op: "safe-commit-comment-no-target",
          message:
            "Safe-commit visibility comment had no labeled open issue to land on — Sentry is the only signal for this run's failure",
          extra: { fn: config.cronName, label: config.scheduledIssueLabel },
        },
      );
      return;
    }
    await octokit.request(
      "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        issue_number: issue.number,
        body,
      },
    );
  } catch (err) {
    reportSilentFallback(err, {
      feature: config.cronName,
      op: "safe-commit-issue-comment-failed",
      message: "Could not post safe-commit visibility comment on scheduled issue",
      extra: { fn: config.cronName, label: config.scheduledIssueLabel },
    });
  }
}

/**
 * Uniform failure exit: scrub + bound the message, mirror to Sentry, and
 * post the operator-visibility comment on the scheduled issue for EVERY
 * failed stage (the plan's "any stage" contract — an add/commit/status
 * failure is exactly as operator-invisible as a deletion-guard abort).
 * Callers may pass `comment` for stage-specific richer text. Never throws.
 */
async function failure(
  config: SafeCommitConfig,
  stage: Extract<SafeCommitResult, { status: "failed" }>["stage"],
  message: string,
  opts?: { extra?: Record<string, unknown>; comment?: string },
): Promise<SafeCommitResult> {
  const scrubbed = redactToken(message, config.installationToken)
    // Drift-proof remote-URL scrub: a delayed-replay push can echo a remote
    // URL embedding a token that no longer equals the memoized one.
    .replace(/x-access-token:[^@\s]+@/g, "x-access-token:[REDACTED]@")
    .slice(0, MESSAGE_CAP_CHARS);
  reportSilentFallback(new Error(`safeCommitAndPr ${stage}: ${scrubbed}`), {
    feature: config.cronName,
    op: stage === "deletion-guard" ? "safe-commit-deletion-guard" : "safe-commit-failed",
    message: `safeCommitAndPr failed at stage ${stage}`,
    extra: { fn: config.cronName, stage, ...opts?.extra },
  });
  try {
    const octokit = await resolveOctokit(config);
    await commentOnScheduledIssue(
      octokit,
      config,
      opts?.comment ??
        `PR withheld: safe-commit failed at stage \`${stage}\` for \`${config.cronName}\`. ` +
          `See Sentry op \`safe-commit-failed\` (fn=${config.cronName}) and the "PR withheld by safe-commit" ` +
          `section of knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md.`,
    );
  } catch (err) {
    reportSilentFallback(err, {
      feature: config.cronName,
      op: "safe-commit-issue-comment-failed",
      message: "failure() could not post the visibility comment",
      extra: { fn: config.cronName, stage },
    });
  }
  emitCronPersistResult({
    cron: config.cronName,
    status: "failed",
    files: 0,
    pr: null,
    stage,
  });
  return { status: "failed", stage, message: scrubbed };
}

/**
 * #7122 P1-B — the one refusal exit for "the workspace or the staged bytes are not
 * what the handler produced". `reason` is a closed vocabulary (never a path, never
 * content) so the message, the visibility comment and the Sentry extra can carry it
 * verbatim.
 */
function integrityFailure(config: SafeCommitConfig, reason: string): Promise<SafeCommitResult> {
  return failure(config, "integrity", `integrity: ${reason}`, {
    extra: { reason },
    comment:
      `PR withheld: safe-commit refused to publish for \`${config.cronName}\` (integrity: ${reason}). ` +
      `See Sentry op \`safe-commit-failed\` (fn=${config.cronName}).`,
  });
}

export async function safeCommitAndPr(
  config: SafeCommitConfig,
): Promise<SafeCommitResult> {
  const { spawnCwd, cronName, allowedPaths, exactPaths, runStartedAt, logger } = config;
  // #5111: a fast-fail SUBSET of git-check-ref-format (not exhaustive) —
  // rejects `:` `.` whitespace and option-shaped leading `-` at stage
  // "checkout" BEFORE any git mutation. Callers compute branch names from
  // dynamic data (cluster hashes) and a bad name must fail loudly, not
  // surface as an opaque git error (or an injected git flag) mid-pipeline.
  // Anything this subset misses still fails loudly at the real checkout.
  if (config.branchName && /^-|[:.\s]/.test(config.branchName)) {
    return failure(
      config,
      "checkout",
      `branchName override is not refname-safe (leading '-', ':', '.', or whitespace): ${config.branchName}`,
    );
  }
  const branch = config.branchName ?? deriveBranchName(cronName, runStartedAt);
  const prTitle = config.prTitle ?? `${config.commitMessage} ${runStartedAt.slice(0, 10)}`;
  const gitIdentityEnv: Record<string, string> = {
    GIT_AUTHOR_NAME: BOT_NAME,
    GIT_AUTHOR_EMAIL: BOT_EMAIL,
    GIT_COMMITTER_NAME: BOT_NAME,
    GIT_COMMITTER_EMAIL: BOT_EMAIL,
    // Pinned dates keep the commit SHA stable if the same tree is ever
    // re-committed (belt-and-suspenders; the replay-resume branch below is
    // the primary replay carrier) and make fixture SHAs deterministic.
    // Identity-via-env also avoids `git config`.
    GIT_AUTHOR_DATE: runStartedAt,
    GIT_COMMITTER_DATE: runStartedAt,
  };

  try {
    // -- 1. Workspace-lost check (replay after container restart: the
    //       memoized setup-workspace step points at a deleted directory).
    //       Distinct from no-changes — this run's work is GONE.
    if (!existsSync(join(spawnCwd, ".git"))) {
      return failure(config, "workspace-lost", `spawnCwd missing or not a git repo: ${spawnCwd}`);
    }

    // -- 1.5. #7122 P1-B — an exactPaths run treats the workspace as untrusted (the
    //         agent that used it may have planted git state, or committed to it). Runs
    //         before the first git command of this pipeline, and trusts NOTHING the
    //         agent could have influenced:
    //           (e) `expectedContent` is REQUIRED — an exactPaths run with no rendered
    //               bytes to compare against has nothing to prove the commit is ours;
    //           - the redirection files, config, hooks and replace refs are removed or
    //             rewritten (and a symlinked entry refused);
    //           (a) the base of the commit is the origin default-branch tip FETCHED NOW
    //               (the local `origin/main`, HEAD and any agent commit are not trusted).
    const exactMode = exactPaths !== undefined;
    const exactEnv = exactMode ? exactModeEnv(spawnCwd) : {};
    const git: Git = (args, extraEnv) => runGit(spawnCwd, args, { ...exactEnv, ...extraEnv });
    let baseRef = "origin/main";
    let baseSha = "";
    if (exactMode) {
      const expectedKeys = config.expectedContent ? Object.keys(config.expectedContent) : [];
      if (expectedKeys.length === 0) return integrityFailure(config, "expected-content-missing");
      const unsafe = await sanitizeWorkspaceGit(spawnCwd, git);
      if (unsafe) return integrityFailure(config, unsafe);
      const fetched = await git([
        "fetch",
        "--no-tags",
        "--no-recurse-submodules",
        "origin",
        `+refs/heads/main:${EXACT_BASE_REF}`,
      ]);
      if (!fetched.ok) return integrityFailure(config, "origin-fetch-failed");
      const tip = await git(["rev-parse", "--verify", `${EXACT_BASE_REF}^{commit}`]);
      baseSha = tip.stdout.trim();
      if (!tip.ok || !/^[0-9a-f]{40,64}$/.test(baseSha)) return integrityFailure(config, "origin-fetch-failed");
      baseRef = baseSha;
    }

    // -- 2. Replay-resume: a prior attempt already created the commit
    //       (crash between commit and push/PR). Branch-name match alone is
    //       NOT enough — a crash between `checkout -B` and `commit` leaves
    //       HEAD on the branch at main's tip, and skipping the scan there
    //       would push a commit-less branch and strand the run's work
    //       (multi-agent review P2). Require commits ahead of origin/main;
    //       otherwise fall through to the scan (idempotent from the branch).
    //       In an exactPaths run a pre-existing branch is NOT trusted to be ours:
    //       the pre-push gate below refuses to push anything but the one expected
    //       commit.
    const headRef = await git(["rev-parse", "--abbrev-ref", "HEAD"]);
    let resuming = false;
    if (headRef.ok && headRef.stdout.trim() === branch) {
      const ahead = await git(["rev-list", `${baseRef}..HEAD`, "--count"]);
      resuming = ahead.ok && Number(ahead.stdout.trim()) > 0;
    }

    let fileCount = 0;
    let deletionCount = 0;
    // Hoisted for the SAME reason as fileCount: `matched` is block-scoped inside
    // the `if (!resuming)` below and is NOT in scope at the return statement.
    // Stays `undefined` on the replay-resume branch — see the `paths` doc on
    // SafeCommitResult: undefined is "not determined", not "nothing committed".
    let paths: string[] | undefined;
    const prBodyExtras: string[] = [];

    if (!resuming) {
      // -- 3. Scan. --untracked-files=all is load-bearing: without it, new
      //       files inside an untracked directory collapse to one `dir/`
      //       entry, defeating per-file filtering and the deletion count.
      const status = await git([
        "status",
        "--porcelain=v1",
        "-z",
        "--untracked-files=all",
      ]);
      if (!status.ok) {
        return failure(config, "status", status.stderr);
      }
      const entries = parsePorcelainZ(status.stdout);

      // -- 3.5. Clean-index precondition. `git commit` commits the WHOLE
      //       index, so anything pre-staged would ride into the PR around
      //       the allowlist filter — including rename SOURCE paths the
      //       parser deliberately discards (multi-agent review P2: a staged
      //       rename out of an allowed dir would otherwise commit an
      //       unguarded deletion). Bot workspaces never legitimately
      //       pre-stage (the spawned model's git staging is hook-denied);
      //       a dirty index is an anomaly — refuse loudly.
      const staged = entries.filter((e) => e.x !== " " && e.x !== "?");
      if (staged.length > 0) {
        return failure(
          config,
          "dirty-index",
          `staged index is not clean (${staged.length} pre-staged entr${staged.length === 1 ? "y" : "ies"}) — refusing to commit`,
          { extra: { stagedCount: staged.length, sample: staged.slice(0, 10).map((e) => e.path) } },
        );
      }

      // -- 4. Structural exclusion (silent by design — recurs every run).
      const nonStructural = entries.filter(
        (e) => !STRUCTURAL_EXCLUSION_PREFIXES.some((p) => e.path.startsWith(p)),
      );

      // -- 5. Allowlist filter; non-structural drops are LOUD. One predicate
      //       (isPathAllowed) decides BOTH sides of the partition.
      const matched = nonStructural.filter((e) => isPathAllowed(e.path, config));
      const dropped = nonStructural.filter((e) => !isPathAllowed(e.path, config));
      if (dropped.length > 0) {
        reportSilentFallback(
          new Error(
            `safeCommitAndPr dropped ${dropped.length} changed path(s) outside the allowlist for ${cronName}`,
          ),
          {
            feature: cronName,
            op: "safe-commit-paths-dropped",
            message: "Bot run changed paths outside the cron's allowlist — committed subset may be incomplete",
            extra: {
              fn: cronName,
              droppedCount: dropped.length,
              sample: dropped.slice(0, 10).map((e) => e.path),
              allowedPaths,
              ...(exactPaths ? { exactPaths } : {}),
            },
          },
        );
      }

      // -- 6. Deletion guard (the #5026 class, bounded structurally). The
      //       sample below lists TRACKED paths only (a deletion needs a tracked
      //       file, which an agent cannot name into existence), so it stays on
      //       safeMd and is NOT subject to the exactPaths count-only rule.
      deletionCount = matched.filter((e) => e.x === "D" || e.y === "D").length;
      if (deletionCount > DEFAULT_MAX_DELETIONS) {
        const sample = matched
          .filter((e) => e.x === "D" || e.y === "D")
          .slice(0, 10)
          .map((e) => safeMd(e.path));
        return failure(
          config,
          "deletion-guard",
          `${deletionCount} staged-or-worktree deletions inside the allowlist exceed max ${DEFAULT_MAX_DELETIONS}`,
          {
            extra: { deletionCount, max: DEFAULT_MAX_DELETIONS, sample },
            comment:
              `PR withheld: deletion guard (${deletionCount} deletions > max ${DEFAULT_MAX_DELETIONS}). ` +
              `Sample: ${sample.map((p) => `\`${p}\``).join(", ")}. ` +
              `See the "PR withheld by safe-commit" section of knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md.`,
          },
        );
      }

      // -- 7. No changes — distinct from failure; logged for greppability.
      if (matched.length === 0) {
        logger?.info(
          { fn: cronName, op: "safe-commit-no-changes" },
          `safeCommitAndPr: no committable changes inside the allowlist for ${cronName}`,
        );
        emitCronPersistResult({
          cron: cronName,
          status: "no-changes",
          files: 0,
          pr: null,
          stage: null,
        });
        return { status: "no-changes" };
      }
      fileCount = matched.length;
      paths = matched.map((e) => e.path);

      // -- 8. Branch + scoped add + commit (identity + dates via env).
      if (exactMode) {
        // The commit is BUILT on the freshly fetched origin tip, not on whatever HEAD
        // the agent left (an agent commit, a reset or a forged ref cannot ride along):
        //   index := the tip's tree; the digest bytes are staged filter-free on top of
        //   it and read back against the rendered bytes; write-tree + commit-tree pin
        //   the tip as the ONLY parent; the branch ref is then pointed at the commit.
        const expected = config.expectedContent ?? {};
        const stagedPaths = matched.map((e) => e.path);
        if (!stagedPaths.every((p) => Object.prototype.hasOwnProperty.call(expected, p))) {
          return integrityFailure(config, "expected-content-missing");
        }
        const readTree = await git(["read-tree", baseSha]);
        if (!readTree.ok) return integrityFailure(config, "stage-failed");
        const unsafe = await stageExactPaths(spawnCwd, git, stagedPaths);
        if (unsafe) return integrityFailure(config, unsafe);
        if (!(await contentMatches(spawnCwd, exactEnv, "", expected))) {
          return integrityFailure(config, "index-content-mismatch");
        }
        const written = await git(["write-tree"]);
        const tree = written.stdout.trim();
        if (!written.ok || !/^[0-9a-f]{40,64}$/.test(tree)) return failure(config, "commit", written.stderr || "write-tree failed");
        const made = await git(
          [
            "commit-tree",
            tree,
            "-p",
            baseSha,
            "-m",
            config.commitMessage,
            ...(config.commitBody ? ["-m", config.commitBody] : []),
          ],
          gitIdentityEnv,
        );
        const commitSha = made.stdout.trim();
        if (!made.ok || !/^[0-9a-f]{40,64}$/.test(commitSha)) return failure(config, "commit", made.stderr || "commit-tree failed");
        const ref = await git(["update-ref", `refs/heads/${branch}`, commitSha]);
        if (!ref.ok) return failure(config, "checkout", `update-ref ${branch}: ${ref.stderr}`);
        const head = await git(["symbolic-ref", "HEAD", `refs/heads/${branch}`]);
        if (!head.ok) return failure(config, "checkout", `symbolic-ref HEAD ${branch}: ${head.stderr}`);
      } else {
        const checkout = await git(["checkout", "-B", branch]);
        if (!checkout.ok) {
          return failure(config, "checkout", `checkout -B ${branch}: ${checkout.stderr}`);
        }
        const add = await git([
          "add",
          "--",
          ...matched.map((e) => e.path),
        ]);
        if (!add.ok) {
          return failure(config, "add", add.stderr);
        }
        const commit = await git(
          [
            "commit",
            "-m",
            config.commitMessage,
            ...(config.commitBody ? ["-m", config.commitBody] : []),
          ],
          gitIdentityEnv,
        );
        if (!commit.ok) {
          return failure(config, "commit", commit.stderr);
        }
      }

      // PR body is derived here (not caller config): static stem plus a
      // LOUD marker when the allowlist dropped paths, so a truncated PR is
      // visible on the PR itself, not only in Sentry (review P2).
      // exactPaths mode (#7122) renders the COUNT only: names are agent-chosen
      // and this body is public. allowedPaths mode is byte-for-byte unchanged.
      if (dropped.length > 0) {
        const marker =
          `> ⚠️ ${dropped.length} changed path(s) outside the persistence allowlist were NOT committed ` +
          `(Sentry op \`safe-commit-paths-dropped\`)`;
        prBodyExtras.push(
          exactPaths
            ? marker
            : `${marker}: ${dropped
                .slice(0, 10)
                .map((e) => `\`${safeMd(e.path)}\``)
                .join(", ")}`,
        );
      }
    }

    // -- 8.5. #7122 P1-B — the pre-push gate. In an exactPaths run EVERY push (the
    //         commit made above and a replayed pre-existing branch alike) is preceded by
    //         the same check: one commit on the fetched origin tip, added/modified
    //         regular files at exact paths only (no rename pairing), the rendered bytes,
    //         the bot identity and message.
    if (exactMode) {
      const unsafe = await pushTipReason(spawnCwd, git, exactEnv, baseSha, config);
      if (unsafe) return integrityFailure(config, unsafe);
    }

    // -- 9. Push (re-push of an existing commit is a no-op).
    const push = await git(["push", "-u", "origin", branch]);
    if (!push.ok) {
      return failure(
        config,
        "push",
        `${push.stderr} (a 401/403 here can mean the memoized installation token expired across a delayed replay)`,
        {
          comment: `PR withheld: push failed for \`${branch}\`. See Sentry op safe-commit-failed (fn=${cronName}).`,
        },
      );
    }

    // -- 10. PR create; 422 "already exists" is replay success. The stem is
    //        caller-overridable (#5111) but the dropped-path ⚠️ marker is
    //        appended REGARDLESS — the loud-truncation invariant survives
    //        every override.
    const octokit = await resolveOctokit(config);
    const prBody =
      (config.prBody ??
        `Automated PR from \`${cronName}\` — committed handler-side via safeCommitAndPr (#5091).`) +
      (prBodyExtras.length ? `\n\n${prBodyExtras.join("\n")}` : "");
    let prNumber: number;
    let prNodeId: string;
    try {
      const created = (await octokit.request("POST /repos/{owner}/{repo}/pulls", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        title: prTitle,
        body: prBody,
        head: branch,
        base: "main",
        ...(config.prDraft ? { draft: true } : {}),
        headers: { "X-GitHub-Api-Version": "2022-11-28" },
      })) as { data: { number: number; node_id: string } };
      prNumber = created.data.number;
      prNodeId = created.data.node_id;
    } catch (err) {
      const e = err as Error & { status?: number };
      const alreadyExists =
        e.status === 422 && /pull request already exists/i.test(e.message ?? "");
      if (!alreadyExists) {
        return failure(config, "pr-create", e.message ?? String(err), {
          comment: `PR withheld: PR creation failed for \`${branch}\`. See Sentry op safe-commit-failed (fn=${cronName}).`,
        });
      }
      const existing = (await octokit.request("GET /repos/{owner}/{repo}/pulls", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        head: `${REPO_OWNER}:${branch}`,
        state: "open",
        per_page: 1,
        headers: { "X-GitHub-Api-Version": "2022-11-28" },
      })) as { data: Array<{ number: number; node_id: string }> };
      const pr = existing.data[0];
      if (!pr) {
        return failure(
          config,
          "pr-create",
          `PR-create returned 422 already-exists but no open PR found for head ${branch}`,
        );
      }
      prNumber = pr.number;
      prNodeId = pr.node_id;
    }

    // -- 10.5. Post-create extras (#5111): labels + synthetic check-runs.
    //          Both best-effort BY DESIGN (a deliberate downgrade from the
    //          legacy pipelines, where a check-run POST throw failed the
    //          step): labels are advisory metadata, and a failed check-run
    //          POST is Sentry-mirrored while the merge tail surfaces the
    //          consequence — except in direct-mode arm-fallback, where the
    //          fell-back op below is the signal.
    if (config.prLabels?.length) {
      try {
        await octokit.request(
          "POST /repos/{owner}/{repo}/issues/{issue_number}/labels",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: prNumber,
            labels: [...config.prLabels],
            headers: { "X-GitHub-Api-Version": "2022-11-28" },
          },
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: cronName,
          op: "safe-commit-label-failed",
          message: "Could not apply PR labels (advisory metadata — run continues)",
          extra: { fn: cronName, prNumber, labels: config.prLabels },
        });
      }
    }
    if (config.syntheticChecks) {
      const head = await git(["rev-parse", "HEAD"]);
      if (head.ok) {
        const headSha = head.stdout.trim();
        for (const name of config.syntheticChecks.names) {
          try {
            await octokit.request("POST /repos/{owner}/{repo}/check-runs", {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              name,
              head_sha: headSha,
              status: "completed",
              conclusion: "success",
              output: { title: "Bot PR", summary: config.syntheticChecks.summary },
              headers: { "X-GitHub-Api-Version": "2022-11-28" },
            });
          } catch (err) {
            reportSilentFallback(err, {
              feature: cronName,
              op: "safe-commit-check-run-failed",
              message:
                "Could not post a synthetic check-run — merge tail will surface the consequence loudly",
              extra: { fn: cronName, prNumber, checkName: name },
            });
          }
        }
      } else {
        reportSilentFallback(new Error(head.stderr), {
          feature: cronName,
          op: "safe-commit-check-run-failed",
          message: "Could not resolve head SHA for synthetic check-runs",
          extra: { fn: cronName, prNumber },
        });
      }
    }

    // -- 11. Merge tail, by mode (#5111). "auto" (default) preserves #5091
    //        behavior exactly: enablePullRequestAutoMerge with the
    //        "clean status" → direct-merge fallback. "direct" inverts the
    //        ladder for the legacy live pipelines: PUT …/merge first, arm
    //        auto-merge on failure, fail stage "auto-merge" when both lose
    //        (PR stays open + loud — the stage union is deliberately NOT
    //        widened; the runbook row covers both arming and execution
    //        failures). "none" stops after create (human-review drafts).
    //        Repo has delete_branch_on_merge=true, so branch cleanup is
    //        handled by GitHub in all merging paths.
    const mergeMode = config.mergeMode ?? "auto";
    let mergedInThisCall = false;
    if (mergeMode === "direct") {
      try {
        await octokit.request("PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge", {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          pull_number: prNumber,
          merge_method: "squash",
          headers: { "X-GitHub-Api-Version": "2022-11-28" },
        });
        mergedInThisCall = true;
      } catch (mergeErr) {
        const autoMerge = await enableAutoMergeSquash(octokit, prNodeId);
        if (!autoMerge.enabled) {
          return failure(
            config,
            "auto-merge",
            `direct merge failed (${(mergeErr as Error).message}); auto-merge arm also failed (${autoMerge.reason ?? "enablePullRequestAutoMerge failed"})`,
            {
              extra: { prNumber, mergeMode },
              comment: `PR #${prNumber} was created but could not be merged — it needs a manual merge. See Sentry op safe-commit-failed (fn=${cronName}).`,
            },
          );
        }
        // Fallback succeeded — the PR is parked on armed auto-merge instead
        // of merged. MUST be Sentry-visible (cq-silent-fallback-must-mirror):
        // armed auto-merge silently disarms on conflict, so this is the entry
        // into the stale-PR window the #5138 watchdog tracks — for LIVE
        // direct-mode pipelines, not just the Tier-2-dormant auto cohort.
        reportSilentFallback(mergeErr, {
          feature: cronName,
          op: "safe-commit-direct-merge-fell-back",
          message:
            "Direct merge failed; auto-merge was armed instead — PR merges when checks pass, or goes stale on conflict",
          extra: { fn: cronName, prNumber, mergeMode },
        });
      }
    } else if (mergeMode === "auto") {
      const autoMerge = await enableAutoMergeSquash(octokit, prNodeId);
      if (!autoMerge.enabled) {
        if (autoMerge.cleanStatus) {
          try {
            await octokit.request("PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge", {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              pull_number: prNumber,
              merge_method: "squash",
              headers: { "X-GitHub-Api-Version": "2022-11-28" },
            });
          } catch (err) {
            return failure(config, "auto-merge", (err as Error).message, {
              extra: { prNumber },
              comment: `PR #${prNumber} was created but auto-merge could not be armed — it needs a manual merge. See Sentry op safe-commit-failed (fn=${cronName}).`,
            });
          }
        } else {
          return failure(
            config,
            "auto-merge",
            autoMerge.reason ?? "enablePullRequestAutoMerge failed",
            {
              extra: { prNumber },
              comment: `PR #${prNumber} was created but auto-merge could not be armed — it needs a manual merge. See Sentry op safe-commit-failed (fn=${cronName}).`,
            },
          );
        }
      }
    }
    // mergeMode === "none": create-only — fall through to the success log.

    logger?.info(
      { fn: cronName, op: "safe-commit-pr", prNumber, branch, fileCount },
      `safeCommitAndPr: opened PR #${prNumber} from ${branch}`,
    );
    emitCronPersistResult({
      cron: cronName,
      status: "committed",
      files: fileCount,
      pr: prNumber,
      stage: null,
    });
    return {
      status: "committed",
      prNumber,
      branch,
      fileCount,
      deletionCount,
      merged: mergedInThisCall,
      // Spread-conditional so the replay-resume arm carries NEITHER key rather
      // than an explicit `paths: undefined` — callers discriminate on presence.
      ...(paths ? { paths } : {}),
      ...(resuming ? { resumed: true as const } : {}),
    };
  } catch (err) {
    // Belt-and-suspenders: the contract is non-throwing; anything that
    // escapes the per-stage handling above still resolves to a failure
    // result so the handler's heartbeat chain always runs.
    return failure(config, "unexpected", (err as Error).message ?? String(err));
  }
}
