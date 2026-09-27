// Derived staleness for GET /api/kb/c4/project (#8966).
//
// The stale-diagram banner used to be a losable client `useState` fed only by
// save outcomes and `c4_diagram_saved` frames: a dropped frame, a remount, or
// an out-of-band source push left the diagram stale with the banner gone. This
// module makes staleness a RECOMPUTED FACT on every read instead: the newest
// `model.likec4.json` commit's dir subtree is diffed — content-addressed, never
// date-ordered — against the Contents listing the route already fetched.
//
// The compare is sha/set equality over the likec4-relevant entries only:
// source files (`LIKEC4_SOURCE_EXTENSIONS`) by blob sha plus every subdirectory
// by tree sha (a tree sha changes iff a nested source changed, which covers
// likec4's whole-directory walk without extra calls). `.md`, `README.md`,
// `model.likec4.json` itself, and likec4's ignored dirs never participate —
// their churn can neither flag stale nor mask a stale source.
//
// Bounded calls: 1 (model-commit lookup) + 2 (root tree → dir subtree) on the
// clean path, +1 grace-window probe only when a diff exists. Every failure —
// transport, a truncated root tree that lost the dir entry, a dir with no
// model commit — resolves to `undefined` (ABSENT), never a false verdict, and
// is mirrored to Sentry as `op: "stale-derivation"`. The client treats absent
// as "no verdict" and falls back to frame/outcome state.
//
// The grace window covers the writer's own two-commit window: `c4-writer.ts`
// commits the `.c4` source first and the re-rendered model in a SECOND commit,
// so a GET landing between them diffs "new source, old model" during a save
// that is SUCCEEDING. A dir tip younger than STALE_GRACE_MS suppresses the
// verdict; the saver's own post-return reload re-reads once the model commit
// has landed, so the suppression self-corrects.

import { isSourceName, LIKEC4_IGNORED_DIRS } from "./c4-stage-sources";
import { reportSilentFallback } from "./observability";

/** Grace window suppressing `stale` while a save's two-commit window is open.
 *  Sized off `c4-render.ts`'s render budget — stage deadline 10 s + slot wait
 *  20 s + spawn timeout 25 s + kill grace/cleanup ~6 s ≈ 61 s worst case
 *  (stated beside `c4-render.ts`'s RENDER_TIMEOUT_MS); 120 s covers it with
 *  headroom for the source-commit → model-commit span and GitHub propagation. */
export const STALE_GRACE_MS = 120_000;

/** Minimal entry shape both GitHub surfaces normalize to. */
export type SnapshotEntry = {
  name: string;
  kind: "file" | "dir";
  sha: string;
};

type ContentsEntry = { name: string; type: string; sha: string };
type TreeEntry = { path: string; type: string; sha: string };
type CommitListItem = {
  sha?: string;
  commit?: {
    tree?: { sha?: string };
    committer?: { date?: string };
    author?: { date?: string };
  };
};

/** GitHub REST fetch — `server/github-api.ts`'s `githubApiGet`, injected so the
 *  derivation is testable without the module boundary. */
export type GhGet = <T>(installationId: number, path: string) => Promise<T>;

const IGNORED = new Set<string>(LIKEC4_IGNORED_DIRS);

/**
 * The likec4-relevant content of ONE directory listing level.
 *
 * Keyed `f:<name>` for source files (likec4 reads any of
 * `LIKEC4_SOURCE_EXTENSIONS`, at any depth) and `d:<name>` for subdirectories
 * — a subdir's tree sha is content-addressed, so a nested source edit changes
 * it and the compare stays exact with no recursion. Everything else (the
 * model JSON itself, `.md` pages, ignored dirs) cannot move the verdict.
 */
export function sourceSnapshot(entries: SnapshotEntry[]): Map<string, string> {
  const snap = new Map<string, string>();
  for (const e of entries) {
    if (e.kind === "dir") {
      if (!IGNORED.has(e.name)) snap.set(`d:${e.name}`, e.sha);
    } else if (isSourceName(e.name)) {
      snap.set(`f:${e.name}`, e.sha);
    }
  }
  return snap;
}

/** Set+sha equality over two snapshots. */
export function snapshotsEqual(
  a: Map<string, string>,
  b: Map<string, string>,
): boolean {
  if (a.size !== b.size) return false;
  for (const [k, v] of a) if (b.get(k) !== v) return false;
  return true;
}

/** Contents API listing entry → SnapshotEntry. `dir`/`submodule` collapse to
 *  the dir kind — both are tree-addressed. */
export function snapshotFromListing(entries: ContentsEntry[]): Map<string, string> {
  return sourceSnapshot(
    entries.map((e) => ({
      name: e.name,
      kind: e.type === "dir" || e.type === "submodule" ? ("dir" as const) : ("file" as const),
      sha: e.sha,
    })),
  );
}

/** One tree level (non-recursive `git/trees/{sha}`) → SnapshotEntry. Direct
 *  children carry a single-segment `path`; `tree`/`commit` collapse to dir. */
export function snapshotFromTreeLevel(entries: TreeEntry[]): Map<string, string> {
  return sourceSnapshot(
    entries.map((e) => ({
      name: e.path,
      kind: e.type === "tree" || e.type === "commit" ? ("dir" as const) : ("file" as const),
      sha: e.sha,
    })),
  );
}

/**
 * Whether the committed `model.likec4.json` under `githubDir` predates the
 * dir's current source set. Returns `true`/`false` on a produced verdict and
 * `undefined` (ABSENT) on every failure or non-answer — no model commit yet,
 * a truncated tree, a transport error, or the in-flight grace window.
 */
export async function deriveDiagramStale(args: {
  get: GhGet;
  installationId: number;
  owner: string;
  repo: string;
  /** Encoded `knowledge-base/…` path — the URL form used in `path=` params. */
  githubDir: string;
  /** Raw `knowledge-base/…` path — `git/trees` entries carry paths verbatim. */
  githubDirRaw: string;
  /** The Contents listing the caller already fetched for `githubDir`. */
  currentEntries: ContentsEntry[];
  /** Clock seam for tests. */
  now?: () => number;
  /** Observability sink seam for tests (defaults to reportSilentFallback). */
  report?: typeof reportSilentFallback;
}): Promise<boolean | undefined> {
  const report = args.report ?? reportSilentFallback;
  const now = args.now ?? Date.now;
  const { get, installationId, owner, repo } = args;
  try {
    // 1. The newest commit touching the model — its root tree is the model's
    //    "as rendered" view of the repo. Empty list = never rendered (a dir can
    //    hold sources with no model commit) → no verdict.
    const modelCommits = await get<CommitListItem[]>(
      installationId,
      `/repos/${owner}/${repo}/commits?path=${args.githubDir}/model.likec4.json&per_page=1`,
    );
    const modelCommit = Array.isArray(modelCommits) ? modelCommits[0] : undefined;
    const rootSha = modelCommit?.commit?.tree?.sha;
    if (!rootSha) return undefined;

    // 2. Locate the dir subtree in the commit's root tree (recursive listing —
    //    one call regardless of depth). A truncated response that lost the dir
    //    entry is a derivation failure, not a verdict.
    const rootTree = await get<{ truncated?: boolean; tree?: TreeEntry[] }>(
      installationId,
      `/repos/${owner}/${repo}/git/trees/${rootSha}?recursive=1`,
    );
    const dirEntry = (rootTree.tree ?? []).find(
      (e) => e.type === "tree" && e.path === args.githubDirRaw,
    );
    if (!dirEntry) {
      report(null, {
        feature: "c4-project-read",
        op: "stale-derivation",
        message: "c4 stale derivation: dir subtree missing from model commit tree",
        extra: { dir: args.githubDirRaw, truncated: rootTree.truncated === true },
      });
      return undefined;
    }

    // 3. The dir's source set at model-commit time vs. NOW. Equal ⇒ fresh.
    const subtree = await get<{ truncated?: boolean; tree?: TreeEntry[] }>(
      installationId,
      `/repos/${owner}/${repo}/git/trees/${dirEntry.sha}`,
    );
    const atCommit = snapshotFromTreeLevel(subtree.tree ?? []);
    const current = snapshotFromListing(args.currentEntries);
    if (snapshotsEqual(atCommit, current)) return false;

    // 4. A diff exists. In-flight window: the writer commits the source first
    //    and the model second, so a dir tip younger than the render budget is
    //    a save mid-flight, not staleness — suppress rather than false-flag.
    const dirCommits = await get<CommitListItem[]>(
      installationId,
      `/repos/${owner}/${repo}/commits?path=${args.githubDir}&per_page=1`,
    );
    const tip = Array.isArray(dirCommits) ? dirCommits[0] : undefined;
    const tipDate = tip?.commit?.committer?.date ?? tip?.commit?.author?.date;
    if (tipDate) {
      const age = now() - Date.parse(tipDate);
      if (Number.isFinite(age) && age < STALE_GRACE_MS) return undefined;
    }
    return true;
  } catch (err) {
    report(err instanceof Error ? err : null, {
      feature: "c4-project-read",
      op: "stale-derivation",
      message: "c4 stale derivation failed",
      extra: { dir: args.githubDirRaw },
    });
    return undefined;
  }
}
