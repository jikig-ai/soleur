/**
 * Tombstone census machinery (#8364) — derives, from git history alone, the
 * set of public URLs that STOPPED being served under `plugins/soleur/docs/`,
 * so a guard can require each to be covered by an edge redirect, re-served by
 * a live page, or explicitly exempted.
 *
 * Event sources (all enumerated via `git log`, never a hand-maintained list):
 *   - `git log --diff-filter=RD -M --name-status` — deletions and renames.
 *   - `git log -p -G'permalink:'` — permalink VALUE removals on files (the
 *     reslug case: the file survives but its old URL dies).
 *
 * URL derivation rules (mirror what the Eleventy build + the deleted
 * meta-refresh machinery actually served):
 *   - blog/YYYY-MM-DD-<slug>.md   -> BOTH families: /blog/<slug> and the dated
 *                                  alias /blog/<YYYY-MM-DD-slug> (3 shapes each)
 *   - blog/<slug>.md (undated)    -> /blog/<slug> family (3 shapes)
 *   - any other page file         -> its `permalink:` frontmatter (dir-style ->
 *                                  3 shapes, file-shaped -> 1 shape), or the
 *                                  Eleventy dir-slug default when absent
 *   - template permalinks ({{)    -> underivable: the event's path must carry
 *                                  a TOMBSTONE_EXEMPT entry instead
 *
 * A derived URL classifies as:
 *   live      — a page at HEAD still emits it (permalink restored, or another
 *               file now serves the path). No redirect needed.
 *   covered   — present in the declared redirect source set (literal list
 *               items + pair expansions + zone-ruleset path literals).
 *   exempt    — the event's path is in the exemption map (issue ref required).
 *   uncovered — RED. The gate prints the URL set and a paste-ready
 *               tombstone_redirect_pairs entry.
 *
 * Sharp-edge notes: git *reports* are input shapes — every `--name-status`
 * output shape (D, R###, D+A below the -M threshold, -G removal) is exercised
 * by the mutation battery in redirect-tombstones.test.ts. HEAD-state
 * assertions are impossible for deleted files by definition, so per-event
 * blobs are read at <commit>^ — the last live version.
 */

import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, type Dirent } from "node:fs";
import { join } from "node:path";

const PAGE_EXTS = new Set([".md", ".njk", ".html"]);
const NON_PAGE_DIRS = new Set([
  "_data",
  "_includes",
  "images",
  "css",
  "js",
  "fonts",
  "screenshots",
  "scripts",
]);
const NON_PAGE_BASENAMES = new Set([
  "CNAME",
  "robots.txt",
  "sitemap.njk",
  "llms.txt.njk",
]);

/** Is `rel` (path under the docs root) a page-emitting Eleventy input? */
export function isPageEmitting(rel: string): boolean {
  const base = rel.split("/").pop()!;
  const dot = base.lastIndexOf(".");
  const ext = dot === -1 ? "" : base.slice(dot);
  if (!PAGE_EXTS.has(ext)) return false;
  if (NON_PAGE_DIRS.has(rel.split("/")[0])) return false;
  if (NON_PAGE_BASENAMES.has(base)) return false;
  if (/^feed.*\.njk$/.test(base)) return false;
  return true;
}

function git(repoDir: string, args: string[]): string {
  return execFileSync("git", args, {
    cwd: repoDir,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

/** Fail loudly (never vacuously) when the census baseline is unreachable —
 *  e.g. a shallow clone or a rewritten history. */
export function assertBaselineReachable(repoDir: string, baseline: string): void {
  try {
    git(repoDir, ["cat-file", "-e", `${baseline}^{commit}`]);
  } catch {
    throw new Error(
      `tombstone baseline ${baseline} is not a commit in this repository — refusing to run a vacuous census (shallow clone? rewritten history?)`,
    );
  }
}

export type FileEvent = {
  commit: string;
  subject: string;
  kind: "D" | "R";
  /** Repo-relative path that lost content (the old side of a rename). */
  oldPath: string;
  /** Repo-relative new path, for renames. */
  newPath?: string;
};

/** Enumerate D/R events under docsPrefix across all of history (or `range`). */
export function enumerateFileEvents(
  repoDir: string,
  docsPrefix: string,
  range?: string,
): FileEvent[] {
  const args = [
    "log",
    "--diff-filter=RD",
    "-M",
    "--name-status",
    "--format=COMMIT%x09%H%x09%s",
  ];
  if (range) args.push(range);
  args.push("--", docsPrefix);
  const out = git(repoDir, args);
  const events: FileEvent[] = [];
  let commit = "";
  let subject = "";
  for (const line of out.split("\n")) {
    const c = line.match(/^COMMIT\t([0-9a-f]+)\t(.*)$/);
    if (c) {
      commit = c[1];
      subject = c[2];
      continue;
    }
    const d = line.match(/^D\t(.+)$/);
    if (d) {
      events.push({ commit, subject, kind: "D", oldPath: d[1] });
      continue;
    }
    const r = line.match(/^R\d+\t(.+)\t(.+)$/);
    if (r) {
      events.push({
        commit,
        subject,
        kind: "R",
        oldPath: r[1],
        newPath: r[2],
      });
    }
  }
  return events;
}

export type PermalinkRemoval = {
  commit: string;
  subject: string;
  path: string;
  value: string;
};

/** Every `-permalink:` line ever removed under docsPrefix (reslug events). */
export function enumeratePermalinkRemovals(
  repoDir: string,
  docsPrefix: string,
  range?: string,
): PermalinkRemoval[] {
  const args = ["log", "-p", "-Gpermalink:", "--format=COMMIT%x09%H%x09%s"];
  if (range) args.push(range);
  args.push("--", docsPrefix);
  const out = git(repoDir, args);
  const removals: PermalinkRemoval[] = [];
  let commit = "";
  let subject = "";
  let path = "";
  for (const line of out.split("\n")) {
    const c = line.match(/^COMMIT\t([0-9a-f]+)\t(.*)$/);
    if (c) {
      commit = c[1];
      subject = c[2];
      continue;
    }
    const d = line.match(/^diff --git a\/.+ b\/(.+)$/);
    if (d) {
      path = d[1];
      continue;
    }
    const p = line.match(/^-permalink:\s*(.+?)\s*$/);
    if (p) {
      let v = p[1];
      if (
        (v.startsWith('"') && v.endsWith('"')) ||
        (v.startsWith("'") && v.endsWith("'"))
      ) {
        v = v.slice(1, -1);
      }
      removals.push({ commit, subject, path, value: v });
    }
  }
  return removals;
}

function blobAt(repoDir: string, rev: string, path: string): string | null {
  try {
    return git(repoDir, ["show", `${rev}:${path}`]);
  } catch {
    return null;
  }
}

/** Frontmatter-scoped permalink read — a `permalink:` line inside a markdown
 *  body is not an override (same convention as validate-blog-links.sh). */
export function frontmatterPermalink(blob: string): string | null {
  if (!blob.startsWith("---")) return null;
  const end = blob.indexOf("\n---", 3);
  const fm = end === -1 ? blob : blob.slice(0, end);
  const m = fm.match(/^permalink:\s*(.+?)\s*$/m);
  if (!m) return null;
  let v = m[1];
  if (
    (v.startsWith('"') && v.endsWith('"')) ||
    (v.startsWith("'") && v.endsWith("'"))
  ) {
    v = v.slice(1, -1);
  }
  return v;
}

/**
 * The URL shapes a permalink value serves. Directory-style (`x/`) and
 * `/index.html`-suffixed permalinks serve three shapes (dir, index.html,
 * bare — Bulk Redirects match full_uri exactly). Other file-shaped
 * permalinks (`x.html`) serve exactly one. Template values (`{{`) are
 * underivable and return null.
 */
export function permalinkUrls(perm: string): string[] | null {
  if (perm.includes("{{") || perm.includes("}}")) return null;
  let p = perm.startsWith("/") ? perm : `/${perm}`;
  if (p === "/index.html") return ["/"];
  const last = p.split("/").pop()!;
  if (last === "index.html") {
    const dir = p.slice(0, -"index.html".length);
    return [dir, `${dir}index.html`, dir.slice(0, -1)];
  }
  if (last.includes(".")) return [p];
  const dir = p.endsWith("/") ? p : `${p}/`;
  return [dir, `${dir}index.html`, dir.slice(0, -1)];
}

function dirShapes(dir: string): string[] {
  return [dir, `${dir}index.html`, dir.slice(0, -1)];
}

const DATED_POST = /^blog\/(\d{4}-\d{2}-\d{2})-(.+)\.md$/;

/**
 * Eleventy default URL for a page file with no permalink override —
 * dir-slug output (`x.md` -> `/x/`, `x/index.njk` -> `/x/`, root `index.*` ->
 * `/`), except `.html` files which serve their literal path.
 */
export function pathDerivedUrls(rel: string): string[] {
  const dated = rel.match(DATED_POST);
  if (dated) {
    return [
      ...dirShapes(`/blog/${dated[2]}/`),
      ...dirShapes(`/blog/${dated[1]}-${dated[2]}/`),
    ];
  }
  const stem = rel.replace(/\.(md|njk|html)$/, "");
  if (stem === "index") return ["/"];
  if (stem.endsWith("/index")) return dirShapes(`/${stem.slice(0, -6)}/`);
  if (rel.endsWith(".html")) return [`/${rel}`];
  return dirShapes(`/${stem}/`);
}

export type Derivation = { urls: string[]; underivable: boolean };

/**
 * The public URL set a file served at `rev`. Blob permalink wins over the
 * filename default; dated blog posts ALWAYS emit the dated-alias family on
 * top (the meta-refresh machinery served it independent of canonical).
 */
export function deriveUrlsAtRev(
  repoDir: string,
  rev: string,
  path: string,
  docsPrefix: string,
): Derivation {
  const rel = path.startsWith(`${docsPrefix}/`)
    ? path.slice(docsPrefix.length + 1)
    : path;
  const blob = blobAt(repoDir, rev, path);
  const perm = blob === null ? null : frontmatterPermalink(blob);
  const urls = new Set<string>();
  if (perm !== null) {
    const derived = permalinkUrls(perm);
    if (derived === null) return { urls: [], underivable: true };
    for (const u of derived) urls.add(u);
  } else {
    for (const u of pathDerivedUrls(rel)) urls.add(u);
  }
  const dated = rel.match(DATED_POST);
  if (dated) {
    for (const u of dirShapes(`/blog/${dated[1]}-${dated[2]}/`)) urls.add(u);
  }
  return { urls: [...urls], underivable: false };
}

/** The URL set the docs tree serves at HEAD (working tree read — the census
 *  only needs "is this URL still emitted", not a full Eleventy build). */
export function liveUrlPaths(repoDir: string, docsPrefix: string): Set<string> {
  const live = new Set<string>();
  const root = join(repoDir, docsPrefix);
  const walk = (dir: string) => {
    let entries: Dirent[];
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const ent of entries) {
      const full = join(dir, ent.name);
      if (ent.isDirectory()) {
        walk(full);
        continue;
      }
      const rel = full.slice(root.length + 1).replaceAll("\\", "/");
      if (!isPageEmitting(rel)) continue;
      let blob: string;
      try {
        blob = readFileSync(full, "utf8");
      } catch {
        continue;
      }
      const perm = frontmatterPermalink(blob);
      const urls = perm === null ? pathDerivedUrls(rel) : permalinkUrls(perm);
      for (const u of urls ?? []) live.add(u);
      const dated = rel.match(DATED_POST);
      if (dated) {
        for (const u of dirShapes(`/blog/${dated[1]}-${dated[2]}/`)) {
          live.add(u);
        }
      }
    }
  };
  walk(root);
  return live;
}

export type UrlNeed = {
  url: string;
  commit: string;
  subject: string;
  kind: "delete" | "rename" | "permalink-removal";
  path: string;
};

export type Census = {
  /** URLs needing an edge redirect or a live emitter, with their origin. */
  needs: UrlNeed[];
  /** Paths whose permalink was a template ({{) — derivation impossible, so
   *  the path MUST carry an exemption entry. */
  underivablePaths: { path: string; commit: string }[];
  /** Raw event counts for diagnostics. */
  fileEvents: number;
  permalinkRemovals: number;
};

/**
 * The full tombstone census: every URL that stopped being served under
 * docsPrefix across `range` (default: all history), with the event that
 * stranded it. Rename events contribute only the shapes the NEW file does
 * not re-serve (a date-only rename of a dated post keeps the canonical but
 * strands the old dated alias).
 */
export function collectNeeds(
  repoDir: string,
  docsPrefix: string,
  range?: string,
): Census {
  const needs = new Map<string, UrlNeed>();
  const underivablePaths: { path: string; commit: string }[] = [];
  const underivableSeen = new Set<string>();
  const pushUnderivable = (path: string, commit: string) => {
    // A template-permalink deletion surfaces twice (the D event AND the
    // -permalink: removal line in its diff) — one entry per path.
    if (underivableSeen.has(path)) return;
    underivableSeen.add(path);
    underivablePaths.push({ path, commit });
  };
  const seen = new Set<string>();

  const addNeed = (n: UrlNeed) => {
    if (!seen.has(n.url)) {
      seen.add(n.url);
      needs.set(n.url, n);
    }
  };

  const fileEvents = enumerateFileEvents(repoDir, docsPrefix, range);
  for (const ev of fileEvents) {
    if (!ev.oldPath.startsWith(`${docsPrefix}/`)) continue;
    const oldRel = ev.oldPath.slice(docsPrefix.length + 1);
    if (!isPageEmitting(oldRel)) continue;
    const parent = `${ev.commit}^`;
    const old = deriveUrlsAtRev(repoDir, parent, ev.oldPath, docsPrefix);
    if (old.underivable) {
      pushUnderivable(ev.oldPath, ev.commit);
      continue;
    }
    let newUrls = new Set<string>();
    if (ev.kind === "R" && ev.newPath) {
      const newRel = ev.newPath.startsWith(`${docsPrefix}/`)
        ? ev.newPath.slice(docsPrefix.length + 1)
        : ev.newPath;
      if (isPageEmitting(newRel)) {
        const nu = deriveUrlsAtRev(repoDir, ev.commit, ev.newPath, docsPrefix);
        newUrls = new Set(nu.urls);
      }
    }
    for (const url of old.urls) {
      if (newUrls.has(url)) continue;
      addNeed({
        url,
        commit: ev.commit,
        subject: ev.subject,
        kind: ev.kind === "D" ? "delete" : "rename",
        path: ev.oldPath,
      });
    }
  }

  const removals = enumeratePermalinkRemovals(repoDir, docsPrefix, range);
  for (const rm of removals) {
    if (!rm.path.startsWith(`${docsPrefix}/`)) continue;
    const rel = rm.path.slice(docsPrefix.length + 1);
    if (!isPageEmitting(rel)) continue;
    const urls = permalinkUrls(rm.value);
    if (urls === null) {
      pushUnderivable(rm.path, rm.commit);
      continue;
    }
    // A removal whose value the file's HEAD frontmatter re-declares is a
    // restore, not a reslug — the URL is live again.
    const headBlob = blobAt(repoDir, "HEAD", rm.path);
    const headPerm = headBlob === null ? null : frontmatterPermalink(headBlob);
    if (headPerm !== null && headPerm === rm.value) continue;
    for (const url of urls) {
      addNeed({
        url,
        commit: rm.commit,
        subject: rm.subject,
        kind: "permalink-removal",
        path: rm.path,
      });
    }
  }

  return {
    needs: [...needs.values()],
    underivablePaths,
    fileEvents: fileEvents.length,
    permalinkRemovals: removals.length,
  };
}

export type Classified = {
  uncovered: UrlNeed[];
  underivableUnexempt: { path: string; commit: string }[];
  /** Exemption keys no event consumed — a stale exemption rots silently. */
  staleExempt: string[];
  counts: { covered: number; live: number; exempt: number; uncovered: number };
};

/**
 * Classify every census need: exempt (path-keyed) -> live (still emitted at
 * HEAD) -> covered (declared redirect source) -> uncovered.
 */
export function classifyCensus(
  census: Census,
  coverage: Set<string>,
  live: Set<string>,
  exempt: Set<string>,
): Classified {
  const uncovered: UrlNeed[] = [];
  const counts = { covered: 0, live: 0, exempt: 0, uncovered: 0 };
  const consumedExempt = new Set<string>();
  for (const need of census.needs) {
    if (exempt.has(need.path)) {
      consumedExempt.add(need.path);
      counts.exempt++;
      continue;
    }
    if (live.has(need.url)) {
      counts.live++;
      continue;
    }
    if (coverage.has(need.url)) {
      counts.covered++;
      continue;
    }
    counts.uncovered++;
    uncovered.push(need);
  }
  const underivableUnexempt = census.underivablePaths.filter((u) => {
    if (exempt.has(u.path)) {
      consumedExempt.add(u.path);
      return false;
    }
    return true;
  });
  const staleExempt = [...exempt].filter((p) => !consumedExempt.has(p));
  return { uncovered, underivableUnexempt, staleExempt, counts };
}

/** Extract the brace-balanced body of `resource "<type>" "<name>"` — the same
 *  technique as the seo-rulesets-noindex.ts precedent, duplicated here
 *  because plugins/soleur/test cannot import apps/web-platform/test/lib. */
export function extractResourceBody(
  tf: string,
  type: string,
  name: string,
): string {
  const open = tf.match(
    new RegExp(`resource\\s+"${type}"\\s+"${name}"\\s*\\{`),
  );
  if (!open || open.index === undefined) {
    throw new Error(`resource "${type}" "${name}" not found`);
  }
  let depth = 0;
  for (let i = open.index + open[0].length - 1; i < tf.length; i++) {
    if (tf[i] === "{") depth++;
    else if (tf[i] === "}") {
      depth--;
      if (depth === 0) return tf.slice(open.index + open[0].length, i);
    }
  }
  throw new Error(`resource "${type}" "${name}" has no closing brace`);
}
