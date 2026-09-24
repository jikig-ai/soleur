// Server-only: stage the INPUT of the C4 re-render (#8623).
//
// The tenant workspace (worktree AND `.git`) is untrusted input: a sandboxed
// agent can write it, including `.git/objects`, refs and HEAD. likec4 1.50.0
// executes a `likec4.config.{js,cjs,mjs,ts,cts,mts}` found under its cwd,
// honours `.likec4rc` / `likec4.config.json` `include.paths`, and follows
// symlinks. So the render never reads the workspace. Its only input is the
// regular-file `.c4` / `.likec4` / `.like-c4` blobs of the diagrams subtree of
// the commit GitHub returned for the write, fetched through the Contents /
// Trees / Blobs API (GitHub is trusted for the MODES and BYTES at a fixed sha,
// never for the content itself) into a private directory the caller owns.
//
// Security rests on the extension ALLOWLIST: nothing else is ever fetched or
// written. The refusals (configs, symlinks, submodules, oversize) exist so the
// user is told the diagram was not updated instead of silently getting a model
// that differs from what their repo declares (P3) — an incomplete config-name
// list is a fidelity bug, never a hole. Every refusal is decided from the full
// listing BEFORE any blob is fetched or any file is written.
//
// Mirrors the ADR-235 local resolver's STAGE block
// (plugins/soleur/scripts/resolve-regenerable-conflicts.sh). Differences:
//   - bytes come from GitHub, not the local object store (here the object store
//     is the tenant's; the resolver's is the operator's own);
//   - config names are the exact likec4@1.50.0 list (the resolver refuses the
//     glob `likec4.config.*`; the parity test pins every name here to it);
//   - sources under directories likec4 ignores (node_modules, .git, ...) are
//     skipped, as likec4 itself skips them;
//   - count/byte caps with a `too-large` refusal (the resolver has none);
//   - an unsafe tree path is an io_error rather than its own refusal class.
// Decision record: ADR-050 amendment 2026-09-24.
//
// No `import "server-only"` (same reason as c4-writer.ts / c4-render.ts).
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { join, resolve, sep } from "node:path";
import { githubApiGet } from "@/server/github-api";
import { C4_DIAGRAMS_DIR, C4_MODEL_JSON } from "@/lib/c4-constants";

// Copied from the installed likec4@1.50.0 dist (`_chunks/src.mjs`); the version
// is pinned across Dockerfile / ci.yml / render-c4-model.sh by
// test/c4-likec4-version-pin.test.ts, and the acceptance suite re-reads this
// list from the installed dist when the binary is present.
export const LIKEC4_CONFIG_NAMES: readonly string[] = Object.freeze([
  ".likec4rc",
  ".likec4.config.json",
  "likec4.config.json",
  "likec4.config.js",
  "likec4.config.cjs",
  "likec4.config.mjs",
  "likec4.config.ts",
  "likec4.config.cts",
  "likec4.config.mts",
]);
// likec4@1.50.0 `_chunks/binary.mjs`.
export const LIKEC4_SOURCE_EXTENSIONS: readonly string[] = Object.freeze([".c4", ".likec4", ".like-c4"]);
// Directories likec4's project crawl excludes (`_chunks/binary.mjs`, `ed`).
const LIKEC4_IGNORED_DIRS: readonly string[] = Object.freeze(["node_modules", ".git", ".svn", ".yarn", ".pnpm"]);

// Caps and concurrency: plan 2026-09-24 "Technical Considerations" (worst case
// ~53 API calls per save against the installation's shared 5,000/h budget and
// GitHub's 100-concurrent secondary limit).
export const MAX_STAGED_SOURCES = 50;
export const MAX_STAGED_SOURCE_BYTES = 4 * 1024 * 1024;
export const BLOB_CONCURRENCY = 8;
const NOT_FOUND_RETRIES = 2;
const GIT_SHA_RE = /^[0-9a-f]{40}$/;

/** The diagrams folder cannot be read at the commit — persistently. A path
 *  THROUGH a symlinked parent 404s on the Contents API (measured). */
export const DIAGRAMS_UNREADABLE_DETAIL = "fetch: diagrams folder unreadable";
/** 429, or a 403 whose GitHub message names a (secondary) rate limit. */
export const RATE_LIMITED_DETAIL = "fetch: rate-limited";
/** Any other 403: the installation cannot read the repo. Retrying won't help. */
export const FORBIDDEN_DETAIL = "fetch: forbidden";

export type RefusalClass =
  | "likec4-config"
  | "symlink"
  | "gitlink"
  | "too-large"
  // The diagrams folder itself, or a folder above it, is not a real directory
  // (a symbolic link or a submodule). `path` is absent: it is not a file IN the
  // diagrams folder the user could remove.
  | "diagrams-folder";

export type StageFailure =
  | {
      ok: false;
      reason: "unsafe_source";
      refusalClass: RefusalClass;
      /** First offender, relative to the diagrams folder (tenant-chosen text). */
      path?: string;
      /** How many further offenders the listing held. */
      more: number;
    }
  | { ok: false; reason: "io_error" | "timeout"; detail: string };

type Source = { path: string; sha: string; size: number };

export type ListResult =
  | {
      ok: true;
      sources: Source[];
      /** Blob sha of `model.likec4.json` at the listed commit; absent → create. */
      modelSha?: string;
      /** Canonical key of the source set: sorted `path\0sha` pairs. */
      sourceKey: string;
    }
  | StageFailure;

export type StageResult =
  | {
      ok: true;
      /** Relative paths written under destDir (the render re-verifies the set). */
      paths: string[];
      modelSha?: string;
      sourceKey: string;
    }
  | StageFailure;

type RepoRef = {
  installationId: number;
  owner: string;
  repo: string;
  signal?: AbortSignal;
  /** Backoff between read-after-write 404 retries (tests pass 1). */
  retryDelayMs?: number;
};

type ContentsEntry = { name?: string; type?: string; sha?: string; download_url?: string | null };
type TreeEntry = { path: string; mode: string; type: string; sha: string; size?: number };

/** HTTP status off a GitHubApiError (duck-typed so a mocked module still works). */
export function statusOf(err: unknown): number | undefined {
  const s = (err as { statusCode?: unknown } | null)?.statusCode;
  return typeof s === "number" ? s : undefined;
}

/** git's blob id: sha1 of `blob <len>\0<bytes>`. */
export function gitBlobSha(bytes: Buffer): string {
  return createHash("sha1").update(`blob ${bytes.length}\0`).update(bytes).digest("hex");
}

class StageAbort extends Error {
  constructor(readonly failure: StageFailure) {
    super("stage aborted");
  }
}

function abortedFailure(signal?: AbortSignal): StageFailure {
  const r = signal?.reason;
  const detail = r instanceof Error && r.message ? r.message : "stage: aborted";
  return { ok: false, reason: "timeout", detail };
}

/** Fixed-vocabulary detail for an unexpected error: never an fs message, which
 *  embeds the absolute staging path and the tenant-chosen file name. */
function errorDetail(prefix: string, err: unknown): string {
  const status = statusOf(err);
  if (status !== undefined) return `${prefix}: http ${status}`;
  const code = (err as NodeJS.ErrnoException | null)?.code;
  if (typeof code === "string" && /^[A-Z0-9_]{1,32}$/.test(code)) return `${prefix}: ${code}`;
  return `${prefix}: unexpected error`;
}

async function getWithRetry<T>(ref: RepoRef, path: string): Promise<T> {
  let attempt = 0;
  for (;;) {
    if (ref.signal?.aborted) throw new StageAbort(abortedFailure(ref.signal));
    try {
      return await githubApiGet<T>(ref.installationId, path, { signal: ref.signal });
    } catch (err) {
      if (ref.signal?.aborted) throw new StageAbort(abortedFailure(ref.signal));
      const status = statusOf(err);
      // A read right after a write can briefly 404 (GitHub docs).
      if (status === 404 && attempt < NOT_FOUND_RETRIES) {
        attempt += 1;
        await new Promise((r) => setTimeout(r, (ref.retryDelayMs ?? 300) * attempt));
        continue;
      }
      if (status === 429 || (status === 403 && /rate limit/i.test(err instanceof Error ? err.message : ""))) {
        throw new StageAbort({ ok: false, reason: "io_error", detail: RATE_LIMITED_DETAIL });
      }
      if (status === 403) {
        throw new StageAbort({ ok: false, reason: "io_error", detail: FORBIDDEN_DETAIL });
      }
      throw err;
    }
  }
}

function isSourceName(rel: string): boolean {
  const base = rel.slice(rel.lastIndexOf("/") + 1);
  // likec4 ignores a file named exactly like an extension (".c4").
  return LIKEC4_SOURCE_EXTENSIONS.some((ext) => base.endsWith(ext) && base !== ext);
}

function underIgnoredDir(rel: string): boolean {
  return rel.split("/").slice(0, -1).some((seg) => LIKEC4_IGNORED_DIRS.includes(seg));
}

/** A tree path we are willing to materialize: relative, no empty/./.. segments. */
function isSafeTreePath(rel: string): boolean {
  if (!rel || rel.startsWith("/") || rel.includes("\\") || rel.includes("\0")) return false;
  return rel.split("/").every((seg) => seg !== "" && seg !== "." && seg !== "..");
}

function sourceKeyOf(sources: Source[]): string {
  return sources
    .map((s) => `${s.path}\0${s.sha}`)
    .sort()
    .join("\n");
}

// Blob cache: blobs are immutable by sha, and each fetched blob is verified
// against its sha before use, so a cached entry is as trustworthy as a fresh
// fetch. Keyed per installation+repo anyway; bounded by total bytes (LRU).
const BLOB_CACHE_MAX_BYTES = 32 * 1024 * 1024;
const blobCache = new Map<string, Buffer>();
let blobCacheBytes = 0;

function cacheGet(key: string): Buffer | undefined {
  const b = blobCache.get(key);
  if (b) {
    blobCache.delete(key);
    blobCache.set(key, b);
  }
  return b;
}

function cachePut(key: string, b: Buffer): void {
  if (b.length > BLOB_CACHE_MAX_BYTES || blobCache.has(key)) return;
  blobCache.set(key, b);
  blobCacheBytes += b.length;
  for (const [k, v] of blobCache) {
    if (blobCacheBytes <= BLOB_CACHE_MAX_BYTES) break;
    blobCache.delete(k);
    blobCacheBytes -= v.length;
  }
}

/** Test-only: forget cached blobs. */
export function __clearBlobCacheForTests(): void {
  blobCache.clear();
  blobCacheBytes = 0;
}

/**
 * Classify the diagrams subtree of `ref` (a commit sha, or omitted for the
 * default branch's HEAD) from GitHub's listings alone — no blob is fetched.
 */
export async function listCommittedDiagrams(input: RepoRef & { ref?: string }): Promise<ListResult> {
  return listWith(input, LIKEC4_CONFIG_NAMES);
}

async function listWith(
  input: RepoRef & { ref?: string },
  configNames: readonly string[],
): Promise<ListResult> {
  try {
    return await listInner(input, configNames);
  } catch (err) {
    if (err instanceof StageAbort) return err.failure;
    return { ok: false, reason: "io_error", detail: errorDetail("fetch", err) };
  }
}

async function listInner(
  input: RepoRef & { ref?: string },
  configNames: readonly string[],
): Promise<ListResult> {
  const { owner, repo } = input;
  const diagramsRepoPath = `knowledge-base/${C4_DIAGRAMS_DIR}`;
  const parentPath = diagramsRepoPath.slice(0, diagramsRepoPath.lastIndexOf("/"));
  const dirName = diagramsRepoPath.slice(parentPath.length + 1);
  const refQuery = input.ref ? `?ref=${encodeURIComponent(input.ref)}` : "";

  // Step 1: the parent listing gives the diagrams folder's tree sha and its
  // TYPE. Only `type === "dir"` is trusted; Contents listings misreport file
  // symlinks and submodules as "file" (measured / documented).
  let parent: unknown;
  try {
    parent = await getWithRetry<unknown>(input, `/repos/${owner}/${repo}/contents/${parentPath}${refQuery}`);
  } catch (err) {
    if (statusOf(err) === 404) {
      return { ok: false, reason: "io_error", detail: DIAGRAMS_UNREADABLE_DETAIL };
    }
    throw err;
  }
  // The parent is not a directory listing (it is a symlink or a file): GitHub
  // answers a single object.
  if (!Array.isArray(parent)) {
    return { ok: false, reason: "unsafe_source", refusalClass: "diagrams-folder", more: 0 };
  }
  const entry = (parent as ContentsEntry[]).find((e) => e?.name === dirName);
  if (!entry) return { ok: false, reason: "io_error", detail: DIAGRAMS_UNREADABLE_DETAIL };
  if (entry.type !== "dir") {
    return { ok: false, reason: "unsafe_source", refusalClass: "diagrams-folder", more: 0 };
  }
  if (typeof entry.sha !== "string" || !GIT_SHA_RE.test(entry.sha)) {
    return { ok: false, reason: "io_error", detail: "fetch: diagrams tree sha missing" };
  }

  // Step 2: the full recursive listing carries TRUE modes.
  const tree = await getWithRetry<{ truncated?: boolean; tree?: TreeEntry[] }>(
    input,
    `/repos/${owner}/${repo}/git/trees/${entry.sha}?recursive=1`,
  );
  if (tree.truncated === true) {
    return { ok: false, reason: "unsafe_source", refusalClass: "too-large", more: 0 };
  }
  const entries = Array.isArray(tree.tree) ? tree.tree : [];

  const offenders: Array<{ path: string; cls: RefusalClass }> = [];
  const sources: Source[] = [];
  let modelSha: string | undefined;
  for (const e of entries) {
    if (!e || typeof e.path !== "string") continue;
    // likec4 never reads under these directories, so neither do we — not even
    // to refuse what is in them.
    if (underIgnoredDir(e.path) || LIKEC4_IGNORED_DIRS.includes(e.path)) continue;
    const base = e.path.slice(e.path.lastIndexOf("/") + 1);
    if (e.mode === "120000") {
      offenders.push({ path: e.path, cls: "symlink" });
      continue;
    }
    if (e.mode === "160000" || e.type === "commit") {
      offenders.push({ path: e.path, cls: "gitlink" });
      continue;
    }
    if (e.type !== "blob") {
      // A directory — including one NAMED like a config, which likec4 reads as
      // a source directory, never imports (measured O).
      if (e.path === C4_MODEL_JSON) {
        return { ok: false, reason: "io_error", detail: "listing: model path is not a regular file" };
      }
      continue;
    }
    if (configNames.includes(base)) {
      offenders.push({ path: e.path, cls: "likec4-config" });
      continue;
    }
    if (e.path === C4_MODEL_JSON) {
      modelSha = e.sha;
      continue;
    }
    if (e.mode !== "100644" && e.mode !== "100755") continue;
    if (!isSourceName(e.path)) continue;
    if (!isSafeTreePath(e.path) || typeof e.sha !== "string" || !GIT_SHA_RE.test(e.sha) || typeof e.size !== "number" || e.size < 0) {
      return { ok: false, reason: "io_error", detail: "listing: malformed source entry" };
    }
    sources.push({ path: e.path, sha: e.sha, size: e.size });
  }

  if (offenders.length > 0) {
    return {
      ok: false,
      reason: "unsafe_source",
      refusalClass: offenders[0].cls,
      path: offenders[0].path,
      more: offenders.length - 1,
    };
  }
  const total = sources.reduce((n, s) => n + s.size, 0);
  if (sources.length > MAX_STAGED_SOURCES || total > MAX_STAGED_SOURCE_BYTES) {
    return { ok: false, reason: "unsafe_source", refusalClass: "too-large", more: 0 };
  }
  return { ok: true, sources, modelSha, sourceKey: sourceKeyOf(sources) };
}

type StageInput = RepoRef & {
  commitSha: string;
  destDir: string;
  signal: AbortSignal;
  /** Bytes the caller already holds (the file it just committed): used instead
   *  of a blob GET when their git blob sha matches the listing. */
  known?: Buffer[];
};

/**
 * Stage the committed LikeC4 sources of `commitSha`'s diagrams subtree into
 * `destDir` (created here, NON-recursively — its parent must be the caller's
 * private `mkdtemp` dir). Never throws. Honours `signal`: aborting stops every
 * in-flight GET and every further write, and a late write cannot recreate a
 * removed directory.
 */
export async function stageCommittedC4Sources(input: StageInput): Promise<StageResult> {
  return stageWith(input, LIKEC4_CONFIG_NAMES);
}

/**
 * TEST-ONLY (Guard 1 row 3): stage with config offenders dropped instead of
 * refused, to prove the extension allowlist alone keeps configs out of the
 * stage. Not reachable from production code.
 */
export function __stageSkippingConfigRefusalForTests(input: StageInput): Promise<StageResult> {
  return stageWith(input, []);
}

async function stageWith(input: StageInput, configNames: readonly string[]): Promise<StageResult> {
  // First failure aborts the siblings; the caller's deadline aborts all.
  const inner = new AbortController();
  const onOuter = () => inner.abort(input.signal.reason);
  if (input.signal.aborted) onOuter();
  else input.signal.addEventListener("abort", onOuter, { once: true });
  const ref: RepoRef = { ...input, signal: inner.signal };

  try {
    if (!GIT_SHA_RE.test(input.commitSha)) {
      return { ok: false, reason: "io_error", detail: "stage: no commit sha" };
    }
    const listed = await listWith({ ...ref, ref: input.commitSha }, configNames);
    if (!listed.ok) return listed;

    const root = resolve(input.destDir);
    if (inner.signal.aborted) return abortedFailure(inner.signal);
    await mkdir(root, { mode: 0o700 });

    const known = new Map<string, Buffer>();
    for (const b of input.known ?? []) known.set(gitBlobSha(b), b);
    const cacheKey = (sha: string) => `${input.installationId}:${input.owner}/${input.repo}:${sha}`;

    const queue = [...listed.sources];
    let firstError: unknown;
    const worker = async () => {
      for (let s = queue.shift(); s; s = queue.shift()) {
        let buf = cacheGet(cacheKey(s.sha));
        const k = buf ? undefined : known.get(s.sha);
        if (k) {
          buf = k;
          cachePut(cacheKey(s.sha), k);
        }
        if (!buf) {
          const blob = await getWithRetry<{ encoding?: string; content?: string }>(
            ref,
            `/repos/${input.owner}/${input.repo}/git/blobs/${s.sha}`,
          );
          if (blob.encoding !== "base64" || typeof blob.content !== "string") {
            throw new StageAbort({ ok: false, reason: "io_error", detail: "fetch: unexpected blob encoding" });
          }
          buf = Buffer.from(blob.content, "base64");
          if (buf.length !== s.size) {
            throw new StageAbort({ ok: false, reason: "io_error", detail: "fetch: blob size mismatch" });
          }
          if (gitBlobSha(buf) !== s.sha) {
            throw new StageAbort({ ok: false, reason: "io_error", detail: "fetch: blob sha mismatch" });
          }
          cachePut(cacheKey(s.sha), buf);
        }
        const target = resolve(root, s.path);
        if (!target.startsWith(root + sep)) {
          throw new StageAbort({ ok: false, reason: "io_error", detail: "stage: path escapes root" });
        }
        // Intermediate dirs one segment at a time, never `recursive: true`:
        // after a deadline the caller removes `root`, and a recursive mkdir
        // would recreate it.
        const segs = s.path.split("/").slice(0, -1);
        let dir = root;
        for (const seg of segs) {
          dir = join(dir, seg);
          if (inner.signal.aborted) throw new StageAbort(abortedFailure(inner.signal));
          await mkdir(dir, { mode: 0o700 }).catch((err: NodeJS.ErrnoException) => {
            if (err.code !== "EEXIST") throw err;
          });
        }
        if (inner.signal.aborted) throw new StageAbort(abortedFailure(inner.signal));
        await writeFile(target, buf, { flag: "wx", mode: 0o600 });
      }
    };
    await Promise.all(
      Array.from({ length: Math.min(BLOB_CONCURRENCY, queue.length) }, () =>
        worker().catch((err) => {
          // The FIRST failure in time is the one reported; siblings then abort.
          if (firstError === undefined) firstError = err;
          inner.abort(err);
        }),
      ),
    );
    if (firstError !== undefined) {
      if (input.signal.aborted) return abortedFailure(input.signal);
      throw firstError;
    }
    return {
      ok: true,
      paths: listed.sources.map((s) => s.path),
      modelSha: listed.modelSha,
      sourceKey: listed.sourceKey,
    };
  } catch (err) {
    if (input.signal.aborted) return abortedFailure(input.signal);
    if (err instanceof StageAbort) return err.failure;
    return { ok: false, reason: "io_error", detail: errorDetail("stage", err) };
  } finally {
    input.signal.removeEventListener("abort", onOuter);
  }
}
