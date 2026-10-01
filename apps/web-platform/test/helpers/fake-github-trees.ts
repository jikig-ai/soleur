// In-memory fake of the three GitHub REST read surfaces the C4 re-render stages
// from (Contents, Git Trees, Git Blobs) plus the Contents PUT the writer
// commits through (#8623). Served to the SUT via
// `vi.mock("@/server/github-api", …)` — see c4-stage-sources.test.ts.
//
// The quirks below are MEASURED, not assumed (`gh api` against the public
// jikig-ai/soleur repo at commit ca83c8ed, 2026-09-24):
//   gh api 'repos/jikig-ai/soleur/contents/.grok?ref=ca83c8ed'
//     → a DIRECTORY symlink (.grok/plugins/soleur) is listed as {"type":"symlink"}
//     → a FILE symlink (.grok/commands/go.md, mode 120000) is listed as {"type":"file"}
//   gh api 'repos/jikig-ai/soleur/contents/.grok/plugins/soleur/skills?ref=ca83c8ed'
//     → 404 (a path THROUGH a directory symlink)
//   gh api 'repos/jikig-ai/soleur/git/trees/<sha>?recursive=1'
//     → true modes: symlink {"mode":"120000","type":"blob"}
// Submodules: none in that repo; GitHub's docs say a directory listing reports
// a submodule as {"type":"file"} (with a null download_url). Encoded that way.
//
// Blob shas are real git blob hashes (sha1 of `blob <n>\0<bytes>`), and
// `git/blobs` serves by sha only, so a path/sha mix-up in the SUT shows.
// Synthesized fixtures only (cq-test-fixtures-synthesized-only).
import { createHash } from "node:crypto";

export class FakeGitHubApiError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number,
  ) {
    super(message);
    this.name = "GitHubApiError";
  }
}

export type FakeEntry =
  | { mode: "100644" | "100755"; content: string | Buffer; reportedSize?: number }
  | { mode: "120000"; target: string }
  | { mode: "160000" };

/** Repo-relative path → entry. Directories are implied by the paths. */
export type FakeTree = Record<string, FakeEntry>;

export function gitBlobSha(bytes: Buffer): string {
  return createHash("sha1")
    .update(Buffer.concat([Buffer.from(`blob ${bytes.length}\0`), bytes]))
    .digest("hex");
}

function bytesOf(e: FakeEntry): Buffer {
  if (e.mode === "120000") return Buffer.from(e.target);
  if (e.mode === "160000") return Buffer.alloc(0);
  return Buffer.isBuffer(e.content) ? e.content : Buffer.from(e.content, "utf8");
}

function entrySha(e: FakeEntry, path: string): string {
  if (e.mode === "160000") return createHash("sha1").update(`gitlink:${path}`).digest("hex");
  return gitBlobSha(bytesOf(e));
}

type Commit = { sha: string; tree: FakeTree };

export type FakeGitHubOptions = {
  /** Report `truncated: true` on every recursive tree listing. */
  truncated?: boolean;
  /** Repo paths whose Contents GET 404s this many times before succeeding. */
  notFoundTimes?: Record<string, number>;
  /** Blob GETs never resolve (until the caller's signal aborts). */
  stallBlobs?: boolean;
  /** Blob GETs fail with this HTTP status (and optional GitHub message). */
  blobStatus?: number;
  blobMessage?: string;
  /** Blob GETs IGNORE the abort signal and resolve after this many ms — models
   *  a response already on the wire when the caller gives up. */
  lateBlobsMs?: number;
  /** Requests must target exactly this repo + installation, else 404 (the fake
   *  can reject a cross-repo read). Defaults to o/r @ 1. */
  expect?: { owner: string; repo: string; installationId: number };
};

export function createFakeGitHub(initial: FakeTree, opts: FakeGitHubOptions = {}) {
  let seq = 0;
  const commits = new Map<string, Commit>();
  const blobs = new Map<string, Buffer>();
  const treeShas = new Map<string, { commit: string; dir: string }>();
  let head = "";

  function addCommit(tree: FakeTree): string {
    seq += 1;
    const sha = createHash("sha1").update(`commit:${seq}`).digest("hex");
    commits.set(sha, { sha, tree: { ...tree } });
    for (const [p, e] of Object.entries(tree)) blobs.set(entrySha(e, p), bytesOf(e));
    head = sha;
    return sha;
  }
  const firstCommit = addCommit(initial);

  const calls: string[] = [];
  let blobInFlight = 0;
  let maxBlobInFlight = 0;
  const notFound = { ...(opts.notFoundTimes ?? {}) };

  function treeShaFor(commit: string, dir: string): string {
    const sha = createHash("sha1").update(`tree:${commit}:${dir}`).digest("hex");
    treeShas.set(sha, { commit, dir });
    return sha;
  }

  function isDir(tree: FakeTree, dir: string): boolean {
    const prefix = dir === "" ? "" : `${dir}/`;
    return Object.keys(tree).some((p) => p.startsWith(prefix) && p !== dir);
  }

  function resolveTarget(from: string, target: string): string {
    const parts = from.split("/").slice(0, -1);
    for (const seg of target.split("/")) {
      if (seg === "..") parts.pop();
      else if (seg !== "." && seg !== "") parts.push(seg);
    }
    return parts.join("/");
  }

  /** A path "through" a symlinked ancestor: the Contents API 404s it. */
  function throughSymlink(tree: FakeTree, path: string): boolean {
    const segs = path.split("/");
    for (let i = 1; i < segs.length; i++) {
      const anc = segs.slice(0, i).join("/");
      if (tree[anc]?.mode === "120000") return true;
    }
    return false;
  }

  function listingType(tree: FakeTree, path: string, e: FakeEntry): string {
    if (e.mode === "120000") {
      return isDir(tree, resolveTarget(path, e.target)) ? "symlink" : "file";
    }
    return "file"; // regular blob, and a submodule (docs) alike
  }

  function contentsGet(commitSha: string, path: string) {
    const c = commits.get(commitSha);
    if (!c) throw new FakeGitHubApiError(`no commit ${commitSha}`, 404);
    if (notFound[path] && notFound[path] > 0) {
      notFound[path] -= 1;
      throw new FakeGitHubApiError(`GitHub API request failed: 404 ${path}`, 404);
    }
    if (throughSymlink(c.tree, path)) {
      throw new FakeGitHubApiError(`GitHub API request failed: 404 ${path}`, 404);
    }
    const e = c.tree[path];
    if (e) {
      if (e.mode === "120000") {
        const t = resolveTarget(path, e.target);
        if (isDir(c.tree, t)) return { type: "symlink", target: e.target, path };
        const te = c.tree[t];
        return { type: "file", target: null, path, sha: te ? entrySha(te, t) : entrySha(e, path) };
      }
      if (e.mode === "160000") return { type: "submodule", path, sha: entrySha(e, path) };
      return { type: "file", path, sha: entrySha(e, path), size: bytesOf(e).length };
    }
    if (!isDir(c.tree, path)) {
      throw new FakeGitHubApiError(`GitHub API request failed: 404 ${path}`, 404);
    }
    const prefix = `${path}/`;
    const names = new Map<string, Record<string, unknown>>();
    for (const [p, ent] of Object.entries(c.tree)) {
      if (!p.startsWith(prefix)) continue;
      const rest = p.slice(prefix.length);
      const name = rest.split("/")[0];
      const full = `${path}/${name}`;
      if (rest.includes("/")) {
        names.set(name, { name, path: full, type: "dir", sha: treeShaFor(commitSha, full) });
      } else {
        names.set(name, {
          name,
          path: full,
          type: listingType(c.tree, p, ent),
          sha: entrySha(ent, p),
          download_url: ent.mode === "160000" ? null : `https://raw.example/${full}`,
        });
      }
    }
    return [...names.values()];
  }

  function treeGet(treeSha: string, recursive: boolean) {
    const t = treeShas.get(treeSha);
    if (!t) throw new FakeGitHubApiError(`no tree ${treeSha}`, 404);
    const c = commits.get(t.commit)!;
    const prefix = `${t.dir}/`;
    const out: Array<Record<string, unknown>> = [];
    const dirs = new Set<string>();
    for (const [p, e] of Object.entries(c.tree)) {
      if (!p.startsWith(prefix)) continue;
      const rel = p.slice(prefix.length);
      const segs = rel.split("/");
      if (!recursive && segs.length > 1) continue;
      for (let i = 1; i < segs.length; i++) dirs.add(segs.slice(0, i).join("/"));
      const size = e.mode === "100644" || e.mode === "100755"
        ? (e.reportedSize ?? bytesOf(e).length)
        : bytesOf(e).length;
      out.push({
        path: rel,
        mode: e.mode,
        type: e.mode === "160000" ? "commit" : "blob",
        sha: entrySha(e, p),
        ...(e.mode === "160000" ? {} : { size }),
      });
    }
    for (const d of dirs) {
      out.push({ path: d, mode: "040000", type: "tree", sha: treeShaFor(t.commit, `${t.dir}/${d}`) });
    }
    out.sort((a, b) => String(a.path).localeCompare(String(b.path)));
    return { sha: treeSha, truncated: !!opts.truncated, tree: out };
  }

  async function blobGet(sha: string, signal?: AbortSignal) {
    blobInFlight += 1;
    maxBlobInFlight = Math.max(maxBlobInFlight, blobInFlight);
    try {
      // Yield so concurrent callers actually overlap.
      await new Promise((r) => setTimeout(r, 2));
      if (opts.lateBlobsMs !== undefined) {
        await new Promise((r) => setTimeout(r, opts.lateBlobsMs));
      } else if (opts.stallBlobs) {
        await new Promise((_, reject) => {
          const onAbort = () => reject(signal?.reason ?? new Error("aborted"));
          if (signal?.aborted) onAbort();
          signal?.addEventListener("abort", onAbort, { once: true });
        });
      }
      if (opts.blobStatus) {
        throw new FakeGitHubApiError(
          `GitHub API ${opts.blobStatus}${opts.blobMessage ? `: "${opts.blobMessage}"` : ""}`,
          opts.blobStatus,
        );
      }
      const b = blobs.get(sha);
      if (!b) throw new FakeGitHubApiError(`no blob ${sha}`, 404);
      return { sha, encoding: "base64", size: b.length, content: b.toString("base64") };
    } finally {
      blobInFlight -= 1;
    }
  }

  const want = opts.expect ?? { owner: "o", repo: "r", installationId: 1 };
  function checkTarget(installationId: number, path: string) {
    if (installationId !== want.installationId || !path.startsWith(`/repos/${want.owner}/${want.repo}/`)) {
      throw new FakeGitHubApiError(`fake: wrong repo/installation ${installationId} ${path}`, 404);
    }
  }

  async function get(installationId: number, path: string, o?: { signal?: AbortSignal }) {
    calls.push(`GET ${path}`);
    checkTarget(installationId, path);
    if (o?.signal?.aborted) throw o.signal.reason ?? new Error("aborted");
    const url = new URL(`https://api.github.test${path}`);
    const m = url.pathname.match(/^\/repos\/[^/]+\/[^/]+\/(contents|git\/trees|git\/blobs)\/(.*)$/);
    if (!m) throw new FakeGitHubApiError(`unhandled ${path}`, 404);
    const [, kind, rest] = m;
    if (kind === "contents") {
      const ref = url.searchParams.get("ref") ?? head;
      return contentsGet(ref, decodeURIComponent(rest));
    }
    if (kind === "git/trees") return treeGet(rest, url.searchParams.get("recursive") === "1");
    return blobGet(rest, o?.signal);
  }

  async function post(
    installationId: number,
    path: string,
    body: { content: string; sha?: string },
    method = "POST",
  ) {
    calls.push(`${method} ${path}`);
    checkTarget(installationId, path);
    const m = path.match(/^\/repos\/[^/]+\/[^/]+\/contents\/(.*)$/);
    if (method !== "PUT" || !m) throw new FakeGitHubApiError(`unhandled ${path}`, 404);
    const filePath = decodeURIComponent(m[1]);
    const cur = commits.get(head)!.tree;
    const existing = cur[filePath];
    if (existing && !body.sha) throw new FakeGitHubApiError("sha required", 422);
    if (existing && body.sha !== entrySha(existing, filePath)) {
      throw new FakeGitHubApiError("sha mismatch", 409);
    }
    if (!existing && body.sha) throw new FakeGitHubApiError("no such file", 409);
    const sha = addCommit({
      ...cur,
      [filePath]: { mode: "100644", content: Buffer.from(body.content, "base64") },
    });
    return { commit: { sha } };
  }

  return {
    get,
    post,
    firstCommit,
    head: () => head,
    /** Commit a new tree on top of HEAD (simulates another writer). */
    commit: (changes: FakeTree) => addCommit({ ...commits.get(head)!.tree, ...changes }),
    fileAt: (commit: string, p: string) => {
      const e = commits.get(commit)?.tree[p];
      return e ? bytesOf(e).toString("utf8") : undefined;
    },
    /** Flip one byte of the stored blob (same length): its bytes no longer hash to its sha. */
    corrupt: (sha: string) => {
      const b = blobs.get(sha);
      if (!b) throw new Error(`fake: no blob ${sha}`);
      const c = Buffer.from(b);
      c[0] ^= 1;
      blobs.set(sha, c);
    },
    calls,
    blobCalls: () => calls.filter((c) => c.includes("/git/blobs/")).length,
    maxBlobInFlight: () => maxBlobInFlight,
  };
}

export type FakeGitHub = ReturnType<typeof createFakeGitHub>;
