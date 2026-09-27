// Derived staleness for GET /api/kb/c4/project (#8966).
//
// The stale-diagram banner used to be a losable client `useState` fed only by
// save outcomes and `c4_diagram_saved` frames: a dropped frame, a remount, or
// an out-of-band source push left the diagram stale with the banner gone. This
// module makes staleness a RECOMPUTED FACT on every read instead: the dir
// listing at the newest `model.likec4.json` commit — fetched via the Contents
// API's `?ref=<commitSha>` (the pattern `listInner` already uses, so one API
// surface serves both sides) — is diffed, content-addressed and never
// date-ordered, against the listing the route already fetched at HEAD.
//
// The compare is sha/set equality over the likec4-relevant entries only:
// source files (`LIKEC4_SOURCE_EXTENSIONS`) by blob sha, plus every
// subdirectory by tree sha — a tree sha moves iff ANYTHING under it moved, so
// a nested source edit can never be missed. Where a subdir pair differs the
// compare recurses once per side (`git/trees/{subSha}?recursive=1`) and keys
// only `isSourceName`/`!underIgnoredDir` paths — so a `.md` edit, a nested
// node_modules, or a config file inside a subdir cannot produce a false
// stale, and likec4's ignored dirs apply at every depth exactly as its crawl
// does. `model.likec4.json` itself and top-level `.md`/`README.md` never
// participate.
//
// Bounded calls on the clean path: 1 (model-commit lookup) + 1 (at-commit dir
// listing) = 2, +2 per differing subdir, +1 grace probe only when a diff
// exists. Every failure — transport, a >1000-entry dir (Contents caps), a
// truncated recursive tree, a dir with no model commit — resolves to
// `undefined` (ABSENT), never a false verdict, and is reported
// (`feature=c4-project-read`, `op=stale-derivation`, debounced per dir so a
// persistently failing derivation is not a Sentry event per page load). The
// client treats absent as "no verdict" and falls back to frame/outcome state.
//
// A soft deadline (STALE_DEADLINE_MS) bounds the leg: the route's Promise.all
// waits for this derivation, so a slow GitHub day must not delay the sources,
// dump, and diagnostics the read already has. Overrun answers ABSENT.
//
// The grace window covers the writer's own two-commit window: `c4-writer.ts`
// commits the `.c4` source first and the re-rendered model in a SECOND
// commit, so a GET landing between them diffs "new source, old model" during
// a save that is SUCCEEDING — a user-actionable false positive. A dir tip
// younger than STALE_GRACE_MS suppresses the verdict; the saver's own
// post-return reload re-reads once the model commit has landed, so the
// suppression self-corrects. The trade, stated: suppression also delays a
// genuine out-of-band push by up to the window (its dir tip is equally
// young), and the probe keys on ANY dir-touching commit — a young `.md` or
// model commit masks an older source diff within the same window. Both bounds
// are 120 s plus time-to-next-read; before this module those pushes were
// never detected at all.

import { isSourceName, underIgnoredDir, LIKEC4_IGNORED_DIRS } from "./c4-stage-sources";
import { mirrorWarnWithDebounce, reportSilentFallback } from "./observability";

/** Grace window suppressing `stale` while a save's two-commit window is open.
 *  Sized off `c4-render.ts`'s render budget — stage deadline 10 s + slot wait
 *  20 s + spawn timeout 25 s + kill grace/cleanup ~6 s ≈ 61 s worst case
 *  (stated beside `c4-render.ts`'s RENDER_TIMEOUT_MS); 120 s covers it with
 *  headroom for the source-commit → model-commit span and GitHub propagation. */
export const STALE_GRACE_MS = 120_000;

/** Soft deadline on the whole derivation (#8966 F6): the route folds this leg
 *  into the GET's Promise.all, so an unbounded derivation delays every field
 *  of the read on a slow GitHub day. ABSENT is already the designed answer —
 *  cap the leg well under the route's practical timeout. */
export const STALE_DEADLINE_MS = 10_000;

/** Contents API entry (one listing level). `type: "dir" | "submodule"`
 *  collapses to the dir kind — both are tree-addressed. */
type ContentsEntry = { name: string; type: string; sha: string };
type TreeEntry = { path: string; type: string; sha: string };
type CommitListItem = {
  sha?: string;
  commit?: { committer?: { date?: string }; author?: { date?: string } };
};

/** GitHub REST fetch — `server/github-api.ts`'s `githubApiGet`, injected so the
 *  derivation is testable without the module boundary. */
export type GhGet = <T>(installationId: number, path: string) => Promise<T>;

const IGNORED = new Set<string>(LIKEC4_IGNORED_DIRS);

/** The likec4-relevant content of ONE directory listing level: `f:<name>` for
 *  source files and `d:<name>` for subdirectories (a subdir's tree sha changes
 *  iff anything under it changed — completeness cover for nested sources; the
 *  exactness refinement lives in `nestedSourceMap`). Non-source entries — the
 *  model JSON, `.md` pages, ignored dirs — cannot move the verdict. */
export function sourceSnapshot(entries: ContentsEntry[]): Map<string, string> {
  const snap = new Map<string, string>();
  for (const e of entries) {
    if (e.type === "dir" || e.type === "submodule") {
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

/** Keys present in one map but not the other, or with different shas. */
function differingKeys(a: Map<string, string>, b: Map<string, string>): string[] {
  const diff: string[] = [];
  for (const [k, v] of a) if (b.get(k) !== v) diff.push(k);
  for (const k of b.keys()) if (!a.has(k)) diff.push(k);
  return diff;
}

/**
 * Whether the committed `model.likec4.json` under `githubDir` predates the
 * dir's current source set. Returns `true`/`false` on a produced verdict and
 * `undefined` (ABSENT) on every failure or non-answer — no model commit yet,
 * a capped listing, a truncated tree, a transport error, a deadline overrun,
 * or the in-flight grace window.
 */
export async function deriveDiagramStale(args: {
  get: GhGet;
  installationId: number;
  owner: string;
  repo: string;
  /** Encoded `knowledge-base/…` path — the URL form for `path=`/`contents`. */
  githubDir: string;
  /** The Contents listing the caller already fetched for `githubDir` at HEAD. */
  currentEntries: ContentsEntry[];
  /** Clock seam for tests. */
  now?: () => number;
  /** Observability sink seam for tests (defaults to reportSilentFallback). */
  report?: typeof reportSilentFallback;
  /** Soft deadline override for tests. */
  deadlineMs?: number;
}): Promise<boolean | undefined> {
  const now = args.now ?? Date.now;
  const deadlineMs = args.deadlineMs ?? STALE_DEADLINE_MS;
  // Debounced per (installation, dir): a persistently failing derivation must
  // not be a Sentry event per page load.
  const report = args.report ?? ((err: unknown, ctx: Parameters<typeof reportSilentFallback>[1]) =>
    mirrorWarnWithDebounce(
      err,
      ctx,
      `${args.installationId}:${args.githubDir}`,
      "stale-derivation",
    ));

  const fail = (err: unknown, message: string, extra?: Record<string, unknown>) => {
    report(
      err instanceof Error ? err : null,
      {
        feature: "c4-project-read",
        op: "stale-derivation",
        message,
        extra: { dir: args.githubDir, ...extra },
      },
    );
    return undefined as undefined;
  };

  const work = async (): Promise<boolean | undefined> => {
    // 1. The newest commit touching the model — the commit sha is both the
    //    `?ref=` for the at-commit listing and the provenance anchor. Empty
    //    list = never rendered (a dir can hold sources with no model commit)
    //    → no verdict.
    const modelCommits = await args.get<CommitListItem[]>(
      args.installationId,
      `/repos/${args.owner}/${args.repo}/commits?path=${args.githubDir}/model.likec4.json&per_page=1`,
    );
    const modelSha = Array.isArray(modelCommits) ? modelCommits[0]?.sha : undefined;
    if (!modelSha) return undefined;

    // 2. The dir listing AT the model commit — Contents accepts a commit sha
    //    (the `listInner` pattern); one call, same entry shape as the HEAD
    //    listing the route already holds. A non-array answer means the dir was
    //    a file/symlink at that commit → derivation failure, not a verdict.
    const atCommitListing = await args.get<ContentsEntry[] | unknown>(
      args.installationId,
      `/repos/${args.owner}/${args.repo}/contents/${args.githubDir}?ref=${modelSha}`,
    );
    if (!Array.isArray(atCommitListing)) {
      return fail(null, "c4 stale derivation: at-commit dir listing is not a directory");
    }
    const atCommit = sourceSnapshot(atCommitListing);
    const current = sourceSnapshot(args.currentEntries);
    if (snapshotsEqual(atCommit, current)) return false;

    // 3. A diff exists. `f:` diffs are already exact (source blob changed /
    //    added / removed). `d:` diffs mean the nested subtree changed — which
    //    could be non-source churn (.md, nested node_modules). Recurse ONLY
    //    the differing subdir pairs and compare their likec4 source sets.
    const diffs = differingKeys(atCommit, current);
    if (!diffs.some((k) => k.startsWith("f:"))) {
      // Only subdir keys differ: prove a nested SOURCE moved, else fresh.
      // (A `d:` sha also moves on non-source churn — .md, nested node_modules.)
      for (const k of diffs) {
        const aSha = atCommit.get(k);
        const cSha = current.get(k);
        const [aSet, cSet] = await Promise.all([
          aSha ? nestedSourceMap(args, aSha) : Promise.resolve(new Map<string, string>()),
          cSha ? nestedSourceMap(args, cSha) : Promise.resolve(new Map<string, string>()),
        ]);
        if (!aSet || !cSet) {
          return fail(null, "c4 stale derivation: subdir tree listing truncated", { subdir: k.slice(2) });
        }
        if (!snapshotsEqual(aSet, cSet)) return trueAfterGrace(args, now);
      }
      return false;
    }

    return trueAfterGrace(args, now);
  };

  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      work(),
      new Promise<undefined>((resolve) => {
        timer = setTimeout(
          () => resolve(fail(null, "c4 stale derivation: deadline exceeded", { deadlineMs })),
          deadlineMs,
        );
      }),
    ]);
  } catch (err) {
    return fail(err, "c4 stale derivation failed");
  } finally {
    if (timer) clearTimeout(timer);
  }
}

/** The exact likec4 source set under one subdir tree: recursive `git/trees`,
 *  blobs only, `isSourceName` basenames, ignored dirs filtered at EVERY depth.
 *  `path:sha` keyed — a content diff, an add, and a remove all move the set.
 *  `undefined` on a truncated response (a derivation failure, not a verdict). */
async function nestedSourceMap(
  args: { get: GhGet; installationId: number; owner: string; repo: string },
  subSha: string,
): Promise<Map<string, string> | undefined> {
  const t = await args.get<{ truncated?: boolean; tree?: TreeEntry[] }>(
    args.installationId,
    `/repos/${args.owner}/${args.repo}/git/trees/${subSha}?recursive=1`,
  );
  if (t.truncated === true) return undefined;
  const map = new Map<string, string>();
  for (const e of t.tree ?? []) {
    if (e.type !== "blob") continue;
    if (underIgnoredDir(e.path)) continue;
    if (isSourceName(e.path)) map.set(e.path, e.sha);
  }
  return map;
}

/** A diff exists — run the in-flight grace probe before answering true. */
async function trueAfterGrace(
  args: {
    get: GhGet;
    installationId: number;
    owner: string;
    repo: string;
    githubDir: string;
  },
  now: () => number,
): Promise<boolean | undefined> {
  // 4. In-flight window: the writer commits the source first and the model
  //    second, so a dir tip younger than the render budget is a save
  //    mid-flight, not staleness — suppress rather than false-flag. The probe
  //    keys on ANY dir-touching commit (a young `.md`/model commit also
  //    suppresses — bounded, self-correcting; see file header).
  const dirCommits = await args.get<CommitListItem[]>(
    args.installationId,
    `/repos/${args.owner}/${args.repo}/commits?path=${args.githubDir}&per_page=1`,
  );
  const tip = Array.isArray(dirCommits) ? dirCommits[0] : undefined;
  const tipDate = tip?.commit?.committer?.date ?? tip?.commit?.author?.date;
  if (tipDate) {
    const age = now() - Date.parse(tipDate);
    if (Number.isFinite(age) && age < STALE_GRACE_MS) return undefined;
  }
  return true;
}
